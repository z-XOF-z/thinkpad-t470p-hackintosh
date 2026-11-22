//
//  GraficaT470p: plugin de Lilu que deja la GPU Intel HD 630 (Kaby Lake) SIEMPRE a su frecuencia maxima.
//
//  Basado en el parche "RPS control" de WhateverGreen (kern_igfx_pm.cpp, acidanthera, BSD-3):
//  WhateverGreen pide la frecuencia maxima cada vez que se manda trabajo a la GPU, pero el driver de Apple
//  la vuelve a bajar unos milisegundos despues con un temporizador. Medido en la T470p: entre trabajos la GPU
//  caia a 300-500 MHz y el escritorio se sentia lento (14-20 FPS) hasta que volvia a subir.
//
//  El driver de Apple (AppleIntelKBLGraphics) pide frecuencia en dos lugares (desensamblado en Tahoe 26.7):
//    1) IGHardwareCommandStreamer5::setGTFrequencyMMIO(uint32 valor)
//         escribe `valor` directo en el registro 0xA008 (GEN6_RPNSWREQ). La llaman submitExecList (al mandar
//         trabajo) y handleChangeFrequencyInterrupt (el temporizador que BAJA la frecuencia sin trabajo).
//    2) IGHardwareRingBuffer::patchFrequencyRequest(uint32 posicion, uint32 valor)
//         mete en los comandos de la GPU un MI_LOAD_REGISTER_IMM a 0xA008 con `valor`.
//  Aqui se interceptan las dos y siempre se pide el maximo. El formato del valor es el mismo que usa
//  WhateverGreen: (GEN9_FREQ_SCALER << 23) * RP0, con RP0 en unidades de 50 MHz (registro GEN6_RP_STATE_CAP).
//
//  Boot-args:  -gt470poff      no hace nada (para recuperar si algo falla)
//              gt470pmhz=NNN   frecuencia fija en MHz (por defecto la maxima de fabrica, RP0)
//              -gt470pdbg      mensajes de depuracion (con Lilu DEBUG)
//  En ioreg (clase GraficaT470p): RP0, valor pedido, y cuantas veces el driver quiso bajar la frecuencia.
//

#include <Headers/plugin_start.hpp>
#include <Headers/kern_api.hpp>
#include <Headers/kern_iokit.hpp>
#include <Headers/kern_devinfo.hpp>
#include <IOKit/IOService.h>
#include <IOKit/pci/IOPCIDevice.h>
#include <kern/thread_call.h>

namespace {

constexpr uint32_t GEN9_FREQUENCY_SHIFT = 23;
constexpr uint32_t GEN9_FREQ_SCALER     = 3;
constexpr uint32_t MCHBAR_MIRROR_BASE   = 0x140000;
constexpr uint32_t GEN6_RP_STATE_CAP    = MCHBAR_MIRROR_BASE + 0x5998;
constexpr uint32_t RP0_RESPALDO         = 22;   // 22 x 50 MHz = 1100 MHz (maximo de la HD 630 en el i5-7300HQ)

const char *rutaKBL[] { "/System/Library/Extensions/AppleIntelKBLGraphics.kext/Contents/MacOS/AppleIntelKBLGraphics" };
KernelPatcher::KextInfo kextKBL { "com.apple.driver.AppleIntelKBLGraphics", rutaKBL, arrsize(rutaKBL), {}, {}, KernelPatcher::KextInfo::Unloaded };

// Estado (los contadores se publican en ioreg cada 2 s desde un thread_call, nunca desde los ganchos)
uint32_t rp0 = 0;                  // en unidades de 50 MHz
uint32_t rp0Fuente = 0;            // 0 = aun no, 1 = leido de la GPU, 2 = respaldo, 3 = boot-arg
uint32_t valorMax = 0;             // valor para 0xA008
volatile uint64_t llamadasMMIO = 0, llamadasAnillo = 0, bajadasEvitadas = 0;
volatile uint32_t ultimoPedidoApple = 0;
bool gancho5 = false, gancho4 = false, ganchoAnillo = false;

using SetFreqT = void (*)(void *, uint32_t);
using PatchReqT = void (*)(void *, uint32_t, uint32_t);
mach_vm_address_t orgSetFreq5 = 0, orgSetFreq4 = 0, orgPatchReq = 0;

IOPCIDevice *gpu = nullptr;
IOMemoryMap *mapa = nullptr;
thread_call_t publicador = nullptr;

void calcularValor() {
	valorMax = (GEN9_FREQ_SCALER << GEN9_FREQUENCY_SHIFT) * rp0;
}

// Lee RP0 del registro de la GPU (BAR0 de la IGPU). Se intenta una vez, ya con el driver de Apple cargado.
void leerRP0() {
	if (rp0Fuente != 0) return;
	uint32_t mhz = 0;
	if (PE_parse_boot_argn("gt470pmhz", &mhz, sizeof(mhz)) && mhz >= 300 && mhz <= 1500) {
		rp0 = mhz / 50; rp0Fuente = 3; calcularValor();
		SYSLOG("gt470p", "frecuencia fija por boot-arg: %u MHz", rp0 * 50);
		return;
	}
	if (gpu) {
		if (!mapa) mapa = gpu->mapDeviceMemoryWithRegister(kIOPCIConfigBaseAddress0);
		if (mapa && mapa->getLength() > GEN6_RP_STATE_CAP + 4) {
			auto cap = *reinterpret_cast<volatile uint32_t *>(mapa->getVirtualAddress() + GEN6_RP_STATE_CAP);
			auto v = cap & 0xFF;
			if (v >= 10 && v <= 30) { rp0 = v; rp0Fuente = 1; calcularValor();
				SYSLOG("gt470p", "RP0 leido de la GPU: %u (%u MHz), RP_STATE_CAP=0x%08X", v, v * 50, cap);
				return;
			}
			SYSLOG("gt470p", "RP_STATE_CAP raro (0x%08X), uso respaldo", cap);
		}
	}
	rp0 = RP0_RESPALDO; rp0Fuente = 2; calcularValor();
	SYSLOG("gt470p", "RP0 de respaldo: %u MHz", rp0 * 50);
}

// Los ganchos pueden correr en el temporizador del driver: aqui NO se mapea memoria ni se reserva nada.
// RP0 se lee desde el thread_call `publicar`; mientras tanto se usa el respaldo (1100 MHz).
inline uint32_t pedirMax(uint32_t pedidoApple) {
	ultimoPedidoApple = pedidoApple;
	if ((pedidoApple >> GEN9_FREQUENCY_SHIFT) < (valorMax >> GEN9_FREQUENCY_SHIFT))
		__atomic_add_fetch(&bajadasEvitadas, 1, __ATOMIC_RELAXED);
	return valorMax;
}

void ganchoSetFreq5(void *that, uint32_t v) {
	__atomic_add_fetch(&llamadasMMIO, 1, __ATOMIC_RELAXED);
	FunctionCast(ganchoSetFreq5, orgSetFreq5)(that, pedirMax(v));
}

void ganchoSetFreq4(void *that, uint32_t v) {
	__atomic_add_fetch(&llamadasMMIO, 1, __ATOMIC_RELAXED);
	FunctionCast(ganchoSetFreq4, orgSetFreq4)(that, pedirMax(v));
}

void ganchoPatchReq(void *that, uint32_t posicion, uint32_t v) {
	__atomic_add_fetch(&llamadasAnillo, 1, __ATOMIC_RELAXED);
	FunctionCast(ganchoPatchReq, orgPatchReq)(that, posicion, pedirMax(v));
}

void publicar(thread_call_param_t, thread_call_param_t) {
	static uint32_t intentos = 0;
	if ((rp0Fuente == 0 || rp0Fuente == 2) && intentos < 10) {   // reintentar unas veces si no se pudo leer
		intentos++;
		rp0Fuente = 0;
		leerRP0();
	}
	auto yo = ADDPR(selfInstance);
	if (yo) {
		yo->setProperty("RP0 MHz", rp0 * 50, 32);
		yo->setProperty("RP0 fuente", rp0Fuente == 1 ? "leido de la GPU" : rp0Fuente == 2 ? "respaldo 1100 MHz" : rp0Fuente == 3 ? "boot-arg gt470pmhz" : "aun no");
		yo->setProperty("Valor pedido 0xA008", valorMax, 32);
		yo->setProperty("Ultimo pedido de Apple MHz", (ultimoPedidoApple >> GEN9_FREQUENCY_SHIFT) * 50 / GEN9_FREQ_SCALER, 32);
		yo->setProperty("Llamadas setGTFrequencyMMIO", llamadasMMIO, 64);
		yo->setProperty("Llamadas patchFrequencyRequest", llamadasAnillo, 64);
		yo->setProperty("Bajadas evitadas", bajadasEvitadas, 64);
		yo->setProperty("Ganchos", gancho5 && ganchoAnillo ? "CS5 + anillo" : gancho5 ? "solo CS5" : ganchoAnillo ? "solo anillo" : "NINGUNO");
	}
	if (publicador) thread_call_enter_delayed(publicador, [] { uint64_t d; nanoseconds_to_absolutetime(2000ULL * 1000 * 1000, &d); return mach_absolute_time() + d; }());
}

void alCargarKext(void *, KernelPatcher &patcher, size_t index, mach_vm_address_t address, size_t size) {
	if (!kextKBL.loadIndex || kextKBL.loadIndex != index) return;

	KernelPatcher::RouteRequest req5 { "__ZN26IGHardwareCommandStreamer518setGTFrequencyMMIOEj", ganchoSetFreq5, orgSetFreq5 };
	gancho5 = patcher.routeMultiple(index, &req5, 1, address, size);
	if (!gancho5) { SYSLOG("gt470p", "no pude enganchar CS5::setGTFrequencyMMIO (%d)", patcher.getError()); patcher.clearError(); }

	KernelPatcher::RouteRequest req4 { "__ZN26IGHardwareCommandStreamer418setGTFrequencyMMIOEj", ganchoSetFreq4, orgSetFreq4 };
	gancho4 = patcher.routeMultiple(index, &req4, 1, address, size);
	if (!gancho4) patcher.clearError();   // CS4 es opcional

	KernelPatcher::RouteRequest reqA { "__ZN20IGHardwareRingBuffer21patchFrequencyRequestEjj", ganchoPatchReq, orgPatchReq };
	ganchoAnillo = patcher.routeMultiple(index, &reqA, 1, address, size);
	if (!ganchoAnillo) { SYSLOG("gt470p", "no pude enganchar patchFrequencyRequest (%d)", patcher.getError()); patcher.clearError(); }

	SYSLOG("gt470p", "ganchos: CS5 %d, CS4 %d, anillo %d", gancho5, gancho4, ganchoAnillo);
}

void alArrancarPatcher(void *, KernelPatcher &) {
	auto info = DeviceInfo::create();
	if (info) {
		if (info->videoBuiltin) {
			gpu = OSDynamicCast(IOPCIDevice, info->videoBuiltin);
			if (gpu) gpu->retain();
		}
		DeviceInfo::deleter(info);
	}
	if (!gpu) SYSLOG("gt470p", "no encontre la IGPU; uso RP0 de respaldo");
}

void iniciar() {
	SYSLOG("gt470p", "GraficaT470p: GPU siempre al maximo");
	rp0 = RP0_RESPALDO; calcularValor();   // valor seguro desde el arranque
	lilu.onPatcherLoadForce(alArrancarPatcher);
	lilu.onKextLoadForce(&kextKBL, 1, alCargarKext);
	publicador = thread_call_allocate(publicar, nullptr);
	if (publicador) {
		uint64_t d; nanoseconds_to_absolutetime(5000ULL * 1000 * 1000, &d);
		thread_call_enter_delayed(publicador, mach_absolute_time() + d);
	}
}

const char *argApagar[] { "-gt470poff" };
const char *argDebug[]  { "-gt470pdbg" };
const char *argBeta[]   { "-gt470pbeta" };

} // namespace

PluginConfiguration ADDPR(config) {
	xStringify(PRODUCT_NAME),
	parseModuleVersion(xStringify(MODULE_VERSION)),
	LiluAPI::AllowNormal | LiluAPI::AllowSafeMode,
	argApagar, arrsize(argApagar),
	argDebug, arrsize(argDebug),
	argBeta, arrsize(argBeta),
	KernelVersion::Catalina,
	KernelVersion::Tahoe,
	iniciar
};

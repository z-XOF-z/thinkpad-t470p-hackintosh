// TeclaWindows: si aprietas y sueltas la tecla Windows SOLA, abre Apps (como el menú Inicio).
// Con otra tecla o clic en medio (Win+C, Win+clic...) no hace nada y sigue funcionando como modificador.
// Por el cambio de hidutil (com.andrew.teclas-ctrl) la tecla Windows física llega como Control izquierdo (código 59).
// Necesita permiso de "Monitoreo de entrada" (Ajustes > Privacidad y seguridad).
//
// Tambien: si el brillo del panel ya esta al MINIMO y se aprieta "bajar brillo" otra vez, el panel interno se
// APAGA de verdad (sin la barrita encendida), y con "subir brillo" vuelve. Si no hay otra pantalla conectada,
// en vez de desactivar el panel se duerme la pantalla (pmset displaysleepnow), para nunca quedarse sin imagen.
import Cocoa

let teclaWin: Int64 = 59          // Control izquierdo = tecla Windows física
let tiempoMax: TimeInterval = 0.6 // si la dejas apretada más que esto, no abre nada
let apps = URL(fileURLWithPath: "/System/Applications/Apps.app")

var apretada = false
var otraTecla = false
var inicio = Date()
var tapGlobal: CFMachPort? = nil

// ---------- Brillo: apagar el panel al bajar de minimo ----------
let ds = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
typealias FnBrillo = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
typealias FnActivar = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError
let leerBrillo: FnBrillo? = ds.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: FnBrillo.self) }
let activarPantalla: FnActivar? = (dlsym(UnsafeMutableRawPointer(bitPattern: -2), "SLSConfigureDisplayEnabled")
    ?? dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSConfigureDisplayEnabled")).map { unsafeBitCast($0, to: FnActivar.self) }
let archivoPanel = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/TeclaWindows/panel-apagado").path
var panelApagado: CGDirectDisplayID = 0
var ultimoCambio = Date.distantPast

func pantallasEnLinea() -> [CGDirectDisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 8)
    var n: UInt32 = 0
    CGGetOnlineDisplayList(8, &ids, &n)
    return Array(ids.prefix(Int(n)))
}

func configurarPanel(_ id: CGDirectDisplayID, _ encendido: Bool) -> Bool {
    guard let f = activarPantalla else { return false }
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
    _ = f(cfg, id, encendido)
    return CGCompleteDisplayConfiguration(cfg, .forSession) == .success
}

func encenderPanel() {
    guard panelApagado != 0 else { return }
    _ = configurarPanel(panelApagado, true)
    NSLog("TeclaWindows: panel %u encendido", panelApagado)
    panelApagado = 0
    try? FileManager.default.removeItem(atPath: archivoPanel)
}

func apagarPanelSiMinimo() {
    guard panelApagado == 0, Date().timeIntervalSince(ultimoCambio) > 0.4,
          let interno = pantallasEnLinea().first(where: { CGDisplayIsBuiltin($0) != 0 }), let leer = leerBrillo else { return }
    var b: Float = 1
    guard leer(interno, &b) == 0, b <= 0.02 else { return }     // solo si YA estaba al minimo
    ultimoCambio = Date()
    let otras = pantallasEnLinea().filter { $0 != interno && CGDisplayIsActive($0) != 0 }
    if otras.isEmpty {
        // Sin otra pantalla: dormir la pantalla (se despierta con cualquier tecla)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); p.arguments = ["displaysleepnow"]
        try? p.run()
        return
    }
    if configurarPanel(interno, false) {
        panelApagado = interno
        try? FileManager.default.createDirectory(atPath: (archivoPanel as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? "\(interno)".write(toFile: archivoPanel, atomically: true, encoding: .utf8)
        NSLog("TeclaWindows: panel %u apagado (brillo al minimo)", interno)
    }
}

func teclaBrillo(_ subir: Bool) {
    DispatchQueue.main.async {
        if subir {
            if panelApagado != 0 { ultimoCambio = Date(); encenderPanel() }
        } else {
            apagarPanelSiMinimo()
        }
    }
}

func abrirApps() {
    DispatchQueue.main.async {
        NSWorkspace.shared.openApplication(at: apps, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}

let callback: CGEventTapCallBack = { _, tipo, evento, refcon in
    switch tipo {
    case .flagsChanged:
        let code = evento.getIntegerValueField(.keyboardEventKeycode)
        let ctrl = evento.flags.contains(.maskControl)
        if code == teclaWin {
            if ctrl && !apretada {                      // se apretó
                apretada = true; otraTecla = false; inicio = Date()
            } else if !ctrl && apretada {               // se soltó
                apretada = false
                if !otraTecla && Date().timeIntervalSince(inicio) < tiempoMax { abrirApps() }
            }
        } else if apretada {
            otraTecla = true                            // otro modificador junto (Shift, Alt...)
        }
    case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
        if apretada { otraTecla = true }
        if tipo == .keyDown {
            // teclas de brillo como teclas ADB (BrightnessKeys): 144 = subir, 145 = bajar
            let k = evento.getIntegerValueField(.keyboardEventKeycode)
            if k == 144 { teclaBrillo(true) } else if k == 145 { teclaBrillo(false) }
        }
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let t = tapGlobal { CGEvent.tapEnable(tap: t, enable: true) }
    default:
        // NX_SYSDEFINED (14), subtipo 8 = teclas especiales: 2 = subir brillo, 3 = bajar brillo
        if tipo.rawValue == 14, let e = NSEvent(cgEvent: evento), e.subtype.rawValue == 8 {
            let tecla = (e.data1 & 0xFFFF0000) >> 16
            let abajo = ((e.data1 & 0xFF00) >> 8) == 0xA
            if abajo && tecla == 2 { teclaBrillo(true) } else if abajo && tecla == 3 { teclaBrillo(false) }
        }
    }
    return Unmanaged.passUnretained(evento)
}

let tipos: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
                            CGEventType(rawValue: 14)!]
let mascara = tipos.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

// Pedir permiso de Monitoreo de entrada si no lo tiene, y esperar a que lo den
if !CGPreflightListenEventAccess() {
    _ = CGRequestListenEventAccess()
    NSLog("TeclaWindows: esperando permiso de Monitoreo de entrada; launchd me vuelve a abrir")
    Thread.sleep(forTimeInterval: 20)
    exit(0)
}

guard let tap2 = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                   eventsOfInterest: mascara, callback: callback, userInfo: nil) else {
    NSLog("TeclaWindows: no pude crear el event tap (falta permiso de Monitoreo de entrada)")
    exit(1)
}
tapGlobal = tap2

// Seguridad: si quedo un panel apagado de una ejecucion anterior, encenderlo
if let t = try? String(contentsOfFile: archivoPanel, encoding: .utf8), let id = UInt32(t.trimmingCharacters(in: .whitespacesAndNewlines)) {
    panelApagado = id
    encenderPanel()
}
// Seguridad: si se desconecta la otra pantalla mientras el panel esta apagado, encenderlo
CGDisplayRegisterReconfigurationCallback({ _, _, _ in
    DispatchQueue.main.async {
        if panelApagado != 0 && !pantallasEnLinea().contains(where: { $0 != panelApagado && CGDisplayIsActive($0) != 0 }) {
            encenderPanel()
        }
    }
}, nil)
let fuente = CFMachPortCreateRunLoopSource(nil, tap2, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), fuente, .commonModes)
CGEvent.tapEnable(tap: tap2, enable: true)
NSLog("TeclaWindows: listo")
NSApplication.shared.setActivationPolicy(.prohibited)
CFRunLoopRun()

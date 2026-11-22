# GraficaT470p.kext (experimental)

Plugin de Lilu que deja la GPU Intel HD 630 de la T470p **siempre a su frecuencia máxima** (RP0, 1100 MHz).

## Por qué
- WhateverGreen `rps-control` pide el máximo cada vez que se manda trabajo a la GPU, pero el driver de Apple
  (`AppleIntelKBLGraphics`) la baja con un temporizador (`handleChangeFrequencyInterrupt`) en cuanto se queda unos ms sin trabajo.
- Medido: entre trabajos la GPU caía a 300–500 MHz; el escritorio se sentía lento. Con la GPU arriba, el escritorio va a 60 FPS.
- `GPUDespierta` (pulsos de cálculo) lo logra desde fuera, pero ocupa ~20 % de la GPU. Este kext lo hace sin gastar GPU.

## Cómo
Desensamblado de `AppleIntelKBLGraphics` (Tahoe 26.7): el driver pide frecuencia en dos lugares, los dos escriben el registro
`0xA008` (`GEN6_RPNSWREQ`):

| Función | Llamada desde | Gancho |
|---|---|---|
| `IGHardwareCommandStreamer5::setGTFrequencyMMIO(uint32)` | `submitExecList`, `handleChangeFrequencyInterrupt` | siempre pide RP0 |
| `IGHardwareRingBuffer::patchFrequencyRequest(uint32, uint32)` | `submitExecList` (MI_LOAD_REGISTER_IMM dentro de los comandos) | siempre pide RP0 |

Valor: `(3 << 23) * RP0` (mismo formato que WhateverGreen), RP0 leído de `GEN6_RP_STATE_CAP` (MCHBAR 0x145998) en BAR0 de la IGPU.

## Compilar (sin Xcode)
`GraficaT470p/compilar.sh` — necesita `fuentes/` con Lilu 1.7.2 y MacKernelSDK (acidanthera).

## Probar / instalar
```
sudo bash gpu-kext.sh listar            # USB con OpenCore
sudo bash gpu-kext.sh usb diskXsY       # copia EFI-MAC a la USB + el kext (probar con F12)
sudo bash gpu-kext.sh disco             # instalar en EFI-MAC
sudo bash gpu-kext.sh quitar
```
Verificar: `ioreg -l -w0 -c GraficaT470p` (RP0, ganchos, "Bajadas evitadas") y `rendimiento/rampa-gpu` con GPUDespierta apagado.
Boot-args: `-gt470poff` (desactiva), `gt470pmhz=NNN` (frecuencia fija).

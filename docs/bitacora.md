# Bitácora de cambios hechos desde macOS (Tahoe 26.7.3, T470p)

Es la continuación de `C:\Users\TU_USUARIO\Documents\CODE\hackintosh-dual-boot\RESUMEN.md`.
Desde macOS el disco de Windows (NTFS) solo se puede leer, así que esta bitácora vive en **EFI-MAC** (FAT32, en `\BITACORA-MAC\`).
Hay una copia en macOS, en `~/hackintosh-mac/`.

## Cómo arreglarlo desde Windows si macOS deja de arrancar
1. Monta EFI-MAC con `herramientas\actualizar-efi-disco.ps1` (la busca por tamaño: 1 GB y tipo System).
   También se puede como admin con diskpart: `select disk 0`, `list part`, seleccionar la de **1 GB** y `assign letter=M`.
   `mountvol S: /S` NO sirve, porque monta la EFI de Windows.
2. Cada cambio de abajo dice qué respaldo del config restaurar. Los respaldos están en `M:\EFI\OC\config.antes-*.plist`
   y en `M:\BITACORA-MAC\respaldos\`. Para restaurar, copia el respaldo encima de `M:\EFI\OC\config.plist`.
3. Al terminar, quita la letra (`remove letter=M` en diskpart).
4. Si no hay Windows a la mano: arranca desde la USB de OpenCore (tiene la EFI vieja, que sí funciona).

## Estado al 2026-11-20 (antes de los cambios de hoy)
- Tahoe instalado y funcionando. El WiFi va con itlwm + HeliPort (en los ítems de inicio). **Andrew decidió quedarse con HeliPort.**
  El WiFi nativo en Tahoe necesita forks de la comunidad de AirportItlwm (no probados en la 8265), un root patch de OCLP y apagar más SIP.
- Audio: VoodooHDA 3.3.4 en `/Library/Extensions`. Está apagado en OpenCore; lo carga macOS por la Aux KC, con SIP en csr 0x201.
  El 17/11 se pusieron los `MixerValues` en 90 (el respaldo del Info.plist está en el Escritorio). **Sigue sin sonar** la bocina,
  aunque el driver, el engine y el volumen se ven bien. Pendiente: probar con audífonos y actualizar a VoodooHDA 3.6.8.
- Bluetooth: apagado, porque IntelBTPatcher 2.4 dio un kernel panic al instalar. Pendiente: probar los builds 2.5.x de lshbluesky
  desde la USB, sin tocar EFI-MAC.
- boot-args en el config de EFI-MAC: `-v -ibtcompatbeta debug=0x100`.
- 5 apagados trabados (shutdown stall) el 17/11, en `/Library/Logs/DiagnosticReports/shutdown_stall_*`.

## Cambios

### 2026-11-20 14:31 - Arreglos rápidos
- Respaldo del config antes del cambio: `config.antes-arreglos-20261120-143114.plist`. Está en `EFI\OC\`, en `BITACORA-MAC\respaldos\` y en `~/hackintosh-mac/respaldos/`.
- boot-args: `-v -ibtcompatbeta debug=0x100` → `-ibtcompatbeta`. ocvalidate: sin errores.
  - Para deshacer: restaurar `config.antes-arreglos-20261120-143114.plist` encima de `EFI\OC\config.plist`.
- Suspensión: antes estaba en `standby 1; powernap 0; hibernatemode 3`. Ahora hibernatemode, standby, autopoweroff y powernap están en 0, y se borró el sleepimage.
  - Para deshacer: `sudo pmset -a hibernatemode 3 standby 1` (en macOS; no afecta el arranque).
- Los 5 reportes de apagado trabado se convirtieron a texto en `~/hackintosh-mac/reportes-apagado/` (solo lectura, no se cambió nada).
- **Causa de los apagados trabados:** en los 5 reportes, el primer proceso trabado es `/usr/sbin/BlueTool`.
  Se queda en `sleep` esperando el controlador de Bluetooth, porque los kexts de BT están apagados. No rompe nada, solo hace más lento
  el apagado. Debería quitarse cuando el Bluetooth funcione (BlueToolFixup).
- Bluetooth verificado: la 8265 aparece en USB como `8087:0a2b` (2603). IntelBluetoothFirmware 2.5.3 (lshbluesky) la soporta
  y trae su firmware `ibt-12-16`. Los kexts ya están descargados en `~/hackintosh-mac/kexts-nuevos/`, junto con VoodooHDA 3.6.8.
- Pendiente: probar con audífonos → VoodooHDA 3.6.8. (El Bluetooth al final se hizo directo en EFI-MAC, sin USB; ver abajo.)

### 2026-11-20 14:35 - Activar Bluetooth (directo en EFI-MAC, sin USB)
- Respaldo del config: `config.antes-bluetooth-20261120-143552.plist` (en EFI\OC\, BITACORA-MAC\respaldos\ y ~/hackintosh-mac/respaldos/).
- Respaldo de los kexts de BT anteriores (2.4.0): `BITACORA-MAC\respaldos\kexts-bt-antes-20261120-143552\`.
- Kexts copiados a EFI\OC\Kexts: IntelBluetoothFirmware 2.5.3 e IntelBTPatcher 2.5.3 (de lshbluesky). BlueToolFixup se queda en 2.7.2.
  - Kernel/Add #20 BlueToolFixup.kext: Enabled = true
  - Kernel/Add #21 IntelBluetoothFirmware.kext: Enabled = true
  - Kernel/Add #22 IntelBTPatcher.kext: Enabled = false (a proposito)
- NVRAM (7C436110...): `bluetoothExternalDongleFailed` = 00 y `bluetoothInternalControllerInfo` = 14 bytes en 0 (tambien en NVRAM/Delete).
- boot-args: `-ibtcompatbeta` (sin cambio; -ibtcompatbeta ya estaba).
- ocvalidate: Completed validating /Volumes/EFI-MAC/EFI/OC/config.plist in 2 ms. No issues found.
- **Si da kernel panic o no arranca:** desde Windows restaurar `config.antes-bluetooth-20261120-143552.plist` encima de EFI\OC\config.plist
  (con eso los kexts de BT quedan apagados otra vez; no hace falta regresar los kexts viejos).

### 2026-11-20 14:38 - VoodooHDA 3.3.4 -> 3.6.8 (en /Library/Extensions de macOS)
- Respaldo del kext anterior: `~/hackintosh-mac/respaldos/VoodooHDA-3.3.4-antes-20261120-143846.kext`.
- Instalado VoodooHDA 3.6.8 (CloverHackyColor Release368) con MixerValues en 90 (Volume, Speaker, etc.) y firma ad-hoc.
- kmutil (Aux KC): No variant specified, falling back to release No variant specified, falling back to release Unable to resolve dependencies: 'com.apple.driver.AppleMobileDevice' names a dependency on 'com.apple.kpi.mach', which was not found. 
- **Si da kernel panic o no arranca:** desde Windows, en EFI-MAC, agregar ` -x` a boot-args en EFI\OC\config.plist
  (NVRAM > Add > 7C436110-... > boot-args). Arrancar en modo seguro y correr: `sudo bash ~/hackintosh-mac/restaurar-voodoohda.sh`.
  Luego quitar el `-x`.

### 2026-11-20 14:45 - Revisión después de reiniciar
- Arrancó bien con boot-args `-ibtcompatbeta` (sin `-v`).
- **Bluetooth funciona:** IntelBluetoothFirmware 2.5.3 + BlueToolFixup 2.7.2 cargados (IntelBTPatcher sigue apagado). Controlador encendido (USB, `THIRD_PARTY_DONGLE`), ya ve los AirPods Pro 2 y el iPhone 13 Pro.
- **Audio sigue sin sonar:** el kext en disco es 3.6.8, pero el que está cargado es **VoodooHDA 3.3.4**, porque la Aux KC sigue siendo la del 17/11 (kmutil falló). Siguiente paso: `sudo bash ~/hackintosh-mac/recompilar-aux-voodoohda.sh` y reiniciar.

### 2026-11-20 14:55 - Clic derecho del touchpad
- Antes: clic secundario = clic con dos dedos (`TrackpadRightClick=1`, `TrackpadCornerSecondaryClick=0`), así que apretar el pad del lado derecho daba clic izquierdo.
- Ahora: clic secundario = **esquina inferior derecha** (`TrackpadCornerSecondaryClick=2`, `TrackpadRightClick=0`, `trackpadCornerClickBehavior=1`). Solo son preferencias del usuario, no tocan el arranque.
  - Para deshacer: Ajustes → Trackpad → Clic secundario → "Clic o toque con dos dedos".
- Los botones físicos de arriba del TrackPoint siguen apagados a propósito (parche de VoodooPS2 del 16/11, porque congelaban el puntero).

### 2026-11-20 14:56 - Reconstruir la Aux KC con VoodooHDA 3.6.8
- Despues de reiniciar seguia cargado 3.3.4: la Aux KC (del 17/11) no se habia regenerado por el error de AppleMobileDevice.
- Respaldo de la Aux KC vieja: `~/hackintosh-mac/respaldos/AuxiliaryKernelExtensions-antes-20261120-145625.kc`.
- kmutil create -n aux -x -p VoodooHDA.kext: codigo 34. No variant specified, falling back to release Missing Developer Kit: As of macOS 13.0, you will need to install a KDK matching your build 25G342 to rebuild kernel collections. 
- Fallo; se intenta con kmutil load -p (puede pedir Permitir en Privacidad y seguridad).
- kmutil load: Extension with identifiers org.voodoo.driver.VoodooHDA not approved to load. Please approve using System Settings. 
- Contenido de la Aux KC ahora: (no se pudo leer)
- **Para deshacer:** `sudo cp ~/hackintosh-mac/respaldos/AuxiliaryKernelExtensions-antes-20261120-145625.kc /Library/KernelCollections/AuxiliaryKernelExtensions.kc` y reiniciar.
  Si no arranca: ` -x` en boot-args desde Windows (ver arriba), arrancar en modo seguro y correr eso mismo.

### 2026-11-20 (tarde) - Revisión
- **VoodooHDA 3.6.8 ya está cargado** (kextstat). Ahora salen dos salidas separadas: `Speaker (Analog)` y `Headphones (Black Left)`.
  La salida predeterminada estaba en **Headphones**, por eso podía no sonar la bocina. Pendiente: elegir `Speaker` y probar.
- Mapa USB actual (USBToolBox 1.2.0 + UTBMap, XhciPortLimit = false): 10 puertos, HS01-HS06 y SS01-SS04.
  Internos (255): HS03, HS05, HS06, SS04. USB 3 (tipo 3): HS01, HS02, HS04, SS01, SS02, SS03.
  El mapa se hizo con el UltraDock conectado. Pendiente: re-mapear sin el dock (mejor desde Windows con USBToolBox).

### 2026-11-20 15:10 - Escaneo USB en vivo (sin el UltraDock)
- Con todo conectado a la laptop: HS01 = receptor 2.4G (teclado/mouse), HS02 = USB Receiver, HS04 = memoria Flash Disk. Internos: HS05 = Bluetooth, HS06 = cámara.
- HS03 y SS03 no tienen nada: probablemente eran del dock. No estorban (son 10 puertos, menos de 15).
- Detalle menor: SS04 (el par USB 3 de HS04) está marcado como interno (255) y debería ser 3. No impide que funcione.
- Falta confirmar la velocidad USB 3 con algo que sí sea 3.0 (los tres dispositivos conectados son USB 2).
- Script de escaneo: `~/hackintosh-mac/escanear-usb.sh [segundos]` (guarda en `salida-escaneo-usb.txt`).

### 2026-11-20 15:15 - Parche del HDMI (framebuffer)
- Respaldo del config: `config.antes-hdmi-20261120-151516.plist` (en EFI\OC\, BITACORA-MAC\respaldos\ y ~/hackintosh-mac/respaldos/).
- Antes: con1 = puerto C HDMI, con2 = puerto D DP (lo de fabrica de 0x591B0000). El HDMI no detectaba nada.
- DeviceProperties > IGPU: `framebuffer-con1-enable` = 01000000
  y `framebuffer-con1-alldata` = 01050A00 00080000 87010000 02040A00 00080000 87010000 (puertos B y C como HDMI).
- ocvalidate: Completed validating /Volumes/EFI-MAC/EFI/OC/config.plist in 9 ms. No issues found.
- **Si la pantalla se queda negra o no arranca:** desde Windows restaurar `config.antes-hdmi-20261120-151516.plist` encima de EFI\OC\config.plist.

### 2026-11-20 (noche) - HDMI confirmado y prueba de bocina
- **El HDMI funciona** con el parche de las 15:15 (con1 en HDMI). macOS ve la tele como `LCDTV` a 1360x768 @ 60 Hz, aparte de la pantalla interna.
  El config bueno es el actual; el respaldo `config.antes-hdmi-20261120-151516.plist` ya solo sirve para regresar a como estaba antes.
- Audio: VoodooHDA 3.6.8 cargado, volumen 100, sin silencio. La salida predeterminada **seguía en Headphones (Black Left)**.
  Se cambió a `Speaker (Analog)` con `swift ~/hackintosh-mac/salida-audio.swift Speaker` (sin argumento, lista las salidas) y se reprodujeron Glass y Ping.
- El códec aparece como "Realtek (Unknown)" (el de la T470p es ALC298). HDAS es `8086:a171`, con subsistema `17aa:505d` y `layout-id` = 0x12 en DeviceProperties.
- Esta entrada se escribió solo en `~/hackintosh-mac/` porque EFI-MAC no estaba montada: hay que copiarla a `EFI-MAC\BITACORA-MAC\`.
- Resultado: **con Speaker tampoco suena** (Andrew no oyó Glass ni Ping). Falta probar con audífonos.
- **Ubicación no funciona:** es por el WiFi con itlwm. macOS lo ve como `Ethernet` (en1) y no como AirPort, así que locationd no puede escanear redes WiFi para ubicarse.
  Es una limitación conocida de itlwm + HeliPort, no es un error nuevo. Solo se arregla con AirportItlwm (WiFi nativo), que en Tahoe se había descartado.
  Mientras tanto: Ajustes → General → Fecha y hora → elegir la zona horaria a mano.

### 2026-11-20 (noche) - Revisión para cambiar a AppleALC
- Ethernet (en0, IntelMausi): el driver carga, pero no detecta cable (IOLinkStatus = 1, sin enlace). El internet sale por en1 (WiFi itlwm). Pendiente: revisar el cable o el puerto.
- Códec confirmado en el registro de Windows: `HDAUDIO\FUNC_01&VEN_10EC&DEV_0298&SUBSYS_17AA505D` (**ALC298**).
- **En Tahoe no existe AppleHDA.kext** (Apple lo quitó, como confirma `/System/Library/Extensions`). AppleALC solo, sin AppleHDA, no da sonido analógico.
  Para usar AppleALC hay que reinyectar AppleHDA con un root patch (forks de OCLP o el método de perez987). Ese mismo root patch es el que hace falta para el WiFi nativo.
- Ojo: en config, `layout-id` de HDAS (PciRoot(0x0)/Pci(0x1F,0x3)) es 1 byte (`12`). Si se usa AppleALC, ponerlo en 4 bytes (`xx000000`).
- AppleALC 1.9.7 (el de la T470s) está en `hackintosh-dual-boot\kexts-quitados\`.
- No se tocó nada; falta que Andrew decida el camino.
- Investigación del root patch (2026-11-20):
  - **OCLP-Mod** (laobamac): es el único que dice tener parche para WiFi **Intel** y de sonido en Tahoe. Última versión: 3.1.9 (15 abr). **Archivado el 13-14 jun 2026**; dice que las versiones que ya salieron siguen sirviendo. No menciona 26.7.
  - **OCLP-Plus** (YBronst): trae "Modern Audio" (AppleHDA), pero **no soporta WiFi Intel** (solo Broadcom). Congelado el 28 jun 2026. Dice "26.0 – 26.4.1 and later".
  - Requisitos típicos: csr-active-config `03080000`, SecureBootModel `Disabled`, AMFIPass.kext (+ `-amfipassbeta` si falla), KDK que coincida (25G342) y Reset NVRAM.
  - Ninguno está probado en 26.7.3 (25G342), así que el riesgo es real. Para deshacer: botón "Revert Root Patches" o `sudo bless --mount / --last-sealed-snapshot`.

### 2026-11-20 19:15 - Paso 1: AppleALC + AMFIPass + SIP para el root patch
- Respaldo del config: `config.antes-applealc-20261120-191545.plist` (en EFI\OC\, BITACORA-MAC\respaldos\ y ~/hackintosh-mac/respaldos/).
- Lilu ya era 1.7.2.
- Kernel/Add: #3 AMFIPass.kext 1.4.1 y #4 AppleALC.kext 1.9.8 (justo despues de Lilu). VoodooHDA en OpenCore sigue apagado.
- DeviceProperties > HDAS: `layout-id` 12 (1 byte, layout 18) -> 2F000000 (**layout 47**, "Daliansky - ALC298 ThinkPad T470p"). Otros que se pueden probar: 29 (X270), 3, 13.
- csr-active-config: 01020000 (0x201) -> 030A0000 (0xA03 = 0x803 que pide OCLP + 0x200 que ya estaba). Ya estaba en NVRAM/Delete.
- SecureBootModel: ya estaba en Disabled (sin cambio).
- boot-args: `-ibtcompatbeta` -> `-ibtcompatbeta -amfipassbeta`.
- ocvalidate: Completed validating /Volumes/EFI-MAC/EFI/OC/config.plist in 7 ms. No issues found.
- VoodooHDA 3.6.8 quitado de /Library/Extensions (respaldo: ~/hackintosh-mac/respaldos/VoodooHDA-3.6.8-antes-20261120-191545.kext).
- **Si no arranca o hay kernel panic:** desde Windows restaurar `config.antes-applealc-20261120-191545.plist` encima de EFI\OC\config.plist.
  Para regresar VoodooHDA: `sudo bash ~/hackintosh-mac/restaurar-voodoohda.sh`.
- Siguiente: reiniciar, hacer **Reset NVRAM** en el menu de OpenCore (para que tome el SIP nuevo) y luego revisar con `csrutil status`.

### 2026-11-20 (después del Reset NVRAM) - Revisión del Paso 1
- Arrancó bien. SIP tomó el valor nuevo: `csr-active-config` = 030A0000 (Kext Signing y Filesystem Protections apagados). boot-args: `-ibtcompatbeta -amfipassbeta`.
- Cargados: Lilu 1.7.2, AMFIPass 1.4.1, AppleALC 1.9.8 (`alc-layout-id` = 2F000000, layout 47). VoodooHDA ya no carga.
- Audio: **sin dispositivos**, como se esperaba: falta AppleHDA (no existe en Tahoe). Siguiente: Paso 2, root patch con OCLP-Mod (necesita KDK 25G342).

### 2026-11-20 20:04 - Paso 2a: KDK y OCLP-Mod instalados (sin parchar todavia)
- KDK 26.7.3 (25G342) de dortania/KdkSupportPkg, SHA256 verificado. Instalado en: /Library/Developer/KDKs/KDK_26.7.3_25G342.kdk
- OCLP-Mod 3.1.9 (laobamac, firmado y notarizado). App: /Applications/OCLP-Mod.app
- Todavia no se aplico ningun root patch; el sistema sigue sellado igual que antes.
- Para quitar: borrar el KDK de /Library/Developer/KDKs/ y correr OCLP-Mod-Uninstaller.pkg (no afectan el arranque).

### 2026-11-20 20:10 - Paso 2b: qué ofrece OCLP-Mod (安装驱动补丁 / Root patch)
- OCLP-Mod detecta el equipo como MacBookPro16,2 (es solo el modelo que usa de referencia, no cambia la EFI).
- Parches disponibles: **WiFi: Intel inalámbrico** (网卡: Intel无线网卡) y **Varios: parche de audio** (杂项: 音频补丁). No ofrece parches de gráficas.
- **No deja instalar:** "文件保险箱已开启" = **FileVault está activado** (`fdesetup status`: FileVault is On). El botón "开始安装驱动补丁" está gris.
- Siguiente: apagar FileVault (Ajustes → Privacidad y seguridad → FileVault → Desactivar), esperar a que termine de desencriptar y volver a abrir OCLP-Mod.
- 2026-11-20 20:36 FileVault quedó apagado (desencriptado al 100 %). Ya se puede aplicar el root patch.

### 2026-11-20 20:51 - Paso 2b: root patch de OCLP-Mod aplicado
- FileVault se apagó (desencriptado terminado a las 20:36). Después OCLP-Mod ya dejó aplicar los parches.
- Registro de OCLP-Mod (resumen):
  - Unió el KDK 26.7.3 (25G342) con el volumen del sistema sin errores.
  - **WiFi Intel:** reemplazó `wifip2pd` en /usr/libexec e instaló IO80211.framework y WiFiPeerToPeer.framework en /System/Library/PrivateFrameworks.
  - **Audio:** instaló **AppleHDA.kext** en /System/Library/Extensions.
  - Saltó RSRMonitor porque no aplica. Instaló los LaunchAgents/Daemons `com.laobamac.oclp-mod.auto-patch`, `macos-update` y `os-caching`.
  - Reconstruyó la colección de kexts de arranque y del sistema y desmontó el volumen raíz.
  - Mensaje final: "驱动补丁操作成功!" (parches aplicados con éxito). Pide reiniciar.
- Ojo: el WiFi sigue con itlwm + HeliPort. Para el WiFi nativo hay que cambiarlo después por AirportItlwm (versión para Tahoe) en la EFI. Eso queda para otro paso.
- **Si no arranca después de reiniciar:** en OpenCore entrar a Recovery, abrir Terminal y correr
  `bless --mount /Volumes/Macintosh --last-sealed-snapshot` (el volumen se llama "Macintosh"), y luego reiniciar.
  Si sí arranca pero algo falla: en OCLP-Mod → 安装驱动补丁 → 删除已安装的补丁 (quitar los parches instalados).

### 2026-11-20 20:57 - Revisión después de reiniciar con el root patch
- Arrancó bien con macOS 26.7.3 (25G342). El sistema arranca desde el snapshot nuevo de OCLP-Mod (`com.apple.bless...`); Authenticated Root apagado, como se esperaba.
- Cargados: Lilu 1.7.2, AMFIPass 1.4.1, AppleALC 1.9.8, **AppleHDA 600.2**, AppleHDAController y AppleHDAHardwareConfigDriver.
- **Audio ya aparece:** "Built-in Output" (Internal Speakers) y "Built-in Input" (Internal Microphone), con layout 47.
- Volumen en 81, sin silencio. Se reprodujeron Glass y Ping: falta que Andrew confirme si se oyeron.
- WiFi: sigue con itlwm (en1 como Ethernet, IP 192.168.2.80). El parche de WiFi Intel ya está en el sistema, pero falta cambiar a AirportItlwm en la EFI.
- 21:05 Andrew no oyó nada. Diagnóstico: el códec ALC298 (10ec0298) se detecta con layout 47; el motor de salida corre al reproducir (IOAudioEngineState = 1), salida IntSpeakers, volumen 127, sin mute, jack sin nada conectado.
  macOS sí manda el sonido, pero el layout 47 no llega a la bocina de esta T470p. Se hizo `cambiar-layout.sh` para probar otros layouts (29, 3, 13, 21, 28).

### 2026-11-20 21:16 - Cambio de layout-id a 29
- Respaldo del config: `config.antes-layout29-20261120-211644.plist` (en EFI\OC\, BITACORA-MAC\respaldos\ y ~/hackintosh-mac/respaldos/).
- DeviceProperties > HDAS: `layout-id` 2f000000 -> 1D000000 (**layout 29**). Con layout 47, macOS sí mandaba sonido (motor activo, IntSpeakers, volumen 127) pero la bocina no sonaba.
- ocvalidate: Completed validating /Volumes/EFI-MAC/EFI/OC/config.plist in 8 ms. No issues found.
- **Si no arranca:** desde Windows restaurar `config.antes-layout29-20261120-211644.plist` encima de EFI\OC\config.plist.
- Siguiente: reiniciar (no hace falta Reset NVRAM) y probar bocina y audífonos.

### 2026-11-20 21:23 - Revisión después de reiniciar con layout 29
- Arrancó bien (21:20). Cargados: Lilu 1.7.2, AMFIPass 1.4.1, AppleALC 1.9.8 (`alc-layout-id` = 1D000000, **layout 29**), AppleHDA 600.2.
- Audio: Built-in Output (Internal Speakers), Built-in Microphone y ahora también **Built-in Line Input**. Volumen 81, sin silencio.
- Se reprodujeron Glass, Ping y una voz ("Prueba de sonido"): falta que Andrew confirme si se oyó.
- 21:30 **Andrew confirmó que la bocina ya suena con layout 29.** Ese es el layout bueno; el respaldo `config.antes-layout29-...` solo sirve para regresar al 47.
- Apple Music no suena: las canciones se quedan en 0:00 aunque Music dice "playing". No es problema del audio, sino del DRM (FairPlay -15842). Se hizo `arreglar-drm-music.sh` (agrega `unfairgva=1` a boot-args).

### 2026-11-20 21:47 - boot-args para el DRM de Apple Music
- Motivo: la bocina ya suena con layout 29, pero Apple Music se queda en 0:00. En el registro de Music: FairPlay "Failed to create content key request data" (-15842), TimeoutReadyToPlay (5410).
- Respaldo del config: `config.antes-unfairgva-20261120-214724.plist` (en EFI\OC\, BITACORA-MAC\respaldos\ y ~/hackintosh-mac/respaldos/).
- boot-args: `-ibtcompatbeta -amfipassbeta` -> `-ibtcompatbeta -amfipassbeta unfairgva=1`.
- ocvalidate: Completed validating /Volumes/EFI-MAC/EFI/OC/config.plist in 7 ms. No issues found.
- **Si no arranca:** desde Windows restaurar `config.antes-unfairgva-20261120-214724.plist` encima de EFI\OC\config.plist (unfairgva no deberia impedir el arranque).
- Siguiente: reiniciar (no hace falta Reset NVRAM) y probar una cancion de Apple Music.

### 2026-11-20 22:07 - boot-args para el DRM de Apple Music
- Motivo: la bocina ya suena con layout 29, pero Apple Music se queda en 0:00. En el registro de Music: FairPlay "Failed to create content key request data" (-15842), TimeoutReadyToPlay (5410).
- Respaldo del config: `config.antes-unfairgva-20261120-220708.plist` (en EFI\OC\, BITACORA-MAC\respaldos\ y ~/hackintosh-mac/respaldos/).
- boot-args: `-ibtcompatbeta -amfipassbeta unfairgva=1` -> `-ibtcompatbeta -amfipassbeta unfairgva=7`.
- ocvalidate: Completed validating /Volumes/EFI-MAC/EFI/OC/config.plist in 9 ms. No issues found.
- **Si no arranca:** desde Windows restaurar `config.antes-unfairgva-20261120-220708.plist` encima de EFI\OC\config.plist (unfairgva no deberia impedir el arranque).
- Siguiente: reiniciar (no hace falta Reset NVRAM) y probar una cancion de Apple Music.

### 2026-11-20 22:19 - Apple Music funciona
- Arrancó bien (22:10) con boot-args `-ibtcompatbeta -amfipassbeta unfairgva=7` (en NVRAM). Cargados: Lilu 1.7.2, AppleALC 1.9.8 (layout 29), AppleHDA 600.2.
- **Andrew confirmó que Apple Music ya reproduce y se oye.** `unfairgva=1` no bastaba; con `unfairgva=7` sí. Este es el config bueno.
  Los respaldos `config.antes-unfairgva-*` solo sirven para regresar a como estaba antes.
- Esta entrada se escribió solo en `~/hackintosh-mac/` (EFI-MAC no estaba montada): hay que copiar la bitácora a `EFI-MAC\BITACORA-MAC\`.
- Pendientes que quedan:
  - WiFi nativo: cambiar itlwm + HeliPort por AirportItlwm (versión Tahoe) en la EFI. El parche de WiFi Intel de OCLP-Mod ya está en el sistema. Con eso también funcionaría Ubicación.
  - ~~Probar los audífonos~~ 22:25 Andrew confirmó que los audífonos también suenan con layout 29. **El audio quedó completo.**
  - Ethernet (en0) sin enlace: revisar el cable o el puerto.
  - Detalle menor de USB: SS04 marcado como interno (255) en vez de 3; confirmar USB 3 con un dispositivo 3.0.
  - Ojo con las actualizaciones de macOS: el root patch se pierde al actualizar. Hay que volver a aplicarlo con OCLP-Mod (y conseguir el KDK que coincida).

### 2026-11-20 22:44 - WiFi nativo: itlwm -> AirportItlwm (Tahoe)
- Kext: AirportItlwm-Tahoe v2.4.0-alpha RELEASE (laobamac/itlwm, 7204c69). Trae la 8265 (0x24fd) y el firmware iwm-8265-36. Depende de IO80211Family e IOSkywalkFamily (los del sistema, con el root patch de OCLP-Mod).
- Respaldo del config: `config.antes-wifi-activar-20261120-224444.plist` (en EFI\OC\, BITACORA-MAC\respaldos\ y ~/hackintosh-mac/respaldos/).
- Kernel/Add #2 AirportItlwm.kext agregado: Enabled = true (MinKernel 25.0.0)
- Kernel/Add #1 itlwm.kext: Enabled = false (el kext se queda en la carpeta)
- ocvalidate: Completed validating /Volumes/EFI-MAC/EFI/OC/config.plist in 8 ms. No issues found.
- **Si no hay WiFi o no arranca:** `sudo bash ~/hackintosh-mac/cambiar-wifi-nativo.sh revertir` (no necesita internet) y reiniciar.
  Desde Windows: restaurar `config.antes-wifi-activar-20261120-224444.plist` encima de EFI\OC\config.plist.
- Siguiente: reiniciar (no hace falta Reset NVRAM), conectarse desde el icono de WiFi de macOS y probar Ubicacion. HeliPort ya no hace falta.

### 2026-11-20 23:00 - Revisión del WiFi nativo (AirportItlwm) después de reiniciar
- Arrancó bien (22:45). Cargados: AirportItlwm 2.4.0 (fw 36.ca7b901d.0, IOModel iwm-8265-36), IO80211Family 1200.13.1 e IOSkywalkFamily (del root patch).
- macOS ya ve el adaptador como WiFi de verdad (en1, CoreWLAN dice encendido), pero **no aparece ninguna red**: el escaneo con CoreWLAN devuelve 0 redes, aun apagando y prendiendo el WiFi.
- En el registro: IO80211 sí manda los escaneos al driver ("Scan type to FW 1/2/3"), pero no regresa ningún resultado. Muchas llamadas fallan con `isDriverAvailable=<0>`, y el código de país se queda en `ZZ`.
- Mientras tanto, Andrew tiene internet por el iPhone conectado por USB (en2).
- Ojo para revisar registros: en zsh, `log` es un comando interno; hay que usar `/usr/bin/log show ...`.
- Opciones: (a) regresar a itlwm + HeliPort con `sudo bash ~/hackintosh-mac/cambiar-wifi-nativo.sh revertir` y reiniciar (HeliPort sigue en /Applications); (b) seguir probando AirportItlwm (otro build u otra versión del fork).

### 2026-11-20 23:14 - Quitar solo el parche de WiFi de OCLP-Mod (el audio se queda)
- Causa: el parche Intel de OCLP-Mod es el "Modern Wireless" de OCLP: mete wifip2pd, IO80211.framework (con IO80211Old.dylib) y WiFiPeerToPeer.framework de macOS 13.7.2.
  Eso es para el AirportItlwm viejo. El AirportItlwm-Tahoe usa el IO80211Family nativo y con esos frameworks viejos salían "Invalid ioctl", isDriverAvailable=0 y 0 redes.
- Se copiaron los originales desde el snapshot sellado `com.apple.os.update-C504F81773F7A187617F0EB9D360502DFCCF5E5D36F4E346E233F63C9099A00C` a: /usr/libexec/wifip2pd, IO80211.framework y WiFiPeerToPeer.framework.
- Respaldo de los archivos del parche: `/Users/TU_USUARIO/hackintosh-mac/respaldos/wifi-oclp-20261120-231449`.
- bless --create-snapshot: código 0.
- AppleHDA (audio) no se tocó.
- **Si no arranca:** Recovery → Terminal → `bless --mount /Volumes/Macintosh --last-sealed-snapshot` (regresa a Tahoe original; después hay que volver a parchar el audio con OCLP-Mod).
- Ojo: si se vuelve a aplicar el root patch con OCLP-Mod, vuelve a meter estos archivos y el WiFi nativo deja de escanear. Hay que correr este script otra vez.
- Siguiente: reiniciar y buscar redes desde el icono de WiFi.

### 2026-11-21 00:24 - WiFi nativo funciona (después de quitar el parche de WiFi de OCLP-Mod)
- Arrancó bien (00:16). Cargados: AirportItlwm 2.4.0 (fw 36.ca7b901d.0), IO80211Family 1200.13.1, IOSkywalkFamily, AppleALC 1.9.8 + AppleHDA 600.2, IntelBluetoothFirmware 2.5.3.
- **El WiFi nativo ya escanea y conecta:** macOS ve la tarjeta como Wi-Fi (en1), salen las redes de alrededor (2.4 y 5 GHz) y está conectado (IP 192.168.1.186, LinkStatusActive, ruta por defecto en en1, ping 0 % de pérdida). HeliPort ya no corre.
- Con quitar los frameworks viejos (wifip2pd, IO80211.framework, WiFiPeerToPeer.framework de 13.7.2) bastó. El config bueno es el actual.
- Audio sigue bien (Built-in Output predeterminado) y Bluetooth encendido.
- Detalles: el código de país sigue en `ZZ` (Locale Unknown); no impide conectar. `networksetup -getairportnetwork` dice "not associated" aunque sí lo está (le falta permiso de ubicación a la Terminal para ver el SSID).
- Pendientes:
  - Probar Ubicación (Ajustes → Privacidad y seguridad → Localización), que ya debería funcionar con el WiFi nativo.
  - Quitar HeliPort de los ítems de inicio (ya no hace falta).
  - Copiar esta bitácora a `EFI-MAC\BITACORA-MAC\`.
  - Ethernet (en0) sin enlace; SS04 marcado como interno.
  - Si se vuelve a aplicar el root patch con OCLP-Mod (por ejemplo tras actualizar macOS), correr otra vez `quitar-parche-wifi-oclp.sh`.

### 2026-11-21 00:45 - Teclado, trackpad, HeliPort y región (solo ajustes de macOS, no tocan el arranque)
- **HeliPort** quitado de los ítems de inicio (la app sigue en /Applications, por si se regresa a itlwm).
- **Ubicación:** Andrew confirmó que ya funciona con el WiFi nativo.
- **Teclas como en Windows:** Ctrl ↔ Comando (izquierdo y derecho) con `hidutil`, cargado al iniciar sesión por `~/Library/LaunchAgents/com.andrew.teclas-ctrl.plist`.
  Ctrl+C/V/Z/T/W funcionan como en Windows; la tecla Windows ahora es Control. Aplica a todos los teclados (también el USB).
  - Para deshacer: `launchctl bootout gui/$(id -u)/com.andrew.teclas-ctrl; rm ~/Library/LaunchAgents/com.andrew.teclas-ctrl.plist; hidutil property --set '{"UserKeyMapping":[]}'`
- **Trackpad estilo Windows:** tocar = clic; clic derecho con **dos dedos** (tocar o apretar) **y también** en la esquina inferior derecha; doble toque y arrastrar (`Dragging = 1`).
  El tamaño de la zona de la esquina no se puede cambiar (lo decide macOS), por eso se activaron los dos dedos.
  - Para deshacer: Ajustes → Trackpad.
- Los parches del TrackPoint (Kernel/Patch de PS2Trackpad) **siguen activos**; no se tocaron.
- **Región:** ya estaba en México (es-MX). El `ZZ` del WiFi es del driver AirportItlwm, que no deja elegir país. No impide conectarse (ve 2.4 y 5 GHz).
- Apagados: el último reporte (00:15) ya no es BlueTool; ahora solo esperan `findmydeviced` y `duetexpertd` unos segundos. No hace daño.

### 2026-11-21 00:55 - Teclas de ThinkPad, Inicio/Fin y VS Code (ajustes de macOS, no tocan el arranque)
- **YogaSMCNC 1.5.3** (app de zhen-zen, igual que el kext YogaSMC 1.5.3 que ya cargaba con ThinkVPC) en /Applications, con inicio automático (`StartAtLogin`). El panel YogaSMCPane está en ~/Library/PreferencePanes.
  Maneja las teclas de arriba: F7 proyectar (pantalla espejo), F8 WiFi, F9 Ajustes, F10 Bluetooth, F11 teclado, Fn+Espacio luz del teclado (la maneja el EC; YogaSMC muestra el aviso).
  - **Tecla estrella (F12) → abre Visual Studio Code** (`Events > 1311` en `org.zhen.YogaSMC`, acción launchbundle `com.microsoft.VSCode`).
  - EC Capability = Basic: no deja controlar el ventilador (es normal).
  - Para quitar: borrar /Applications/YogaSMCNC.app y `defaults delete org.zhen.YogaSMC`.
- **Inicio/Fin como en Windows:** `~/Library/KeyBindings/DefaultKeyBinding.dict` (Inicio/Fin = inicio/fin de línea; con Shift selecciona; con Ctrl va al inicio/fin del documento). Aplica a las apps que se abran después; algunas apps (Terminal, VS Code) usan sus propias teclas.
  - Para deshacer: borrar ese archivo.
- **Visual Studio Code 1.147.0** en /Applications (firmado y notarizado por Microsoft). Comando `code` en ~/.local/bin (agregado al PATH en ~/.zshrc).
- El script `mejoras-cpu-estabilidad.sh` (todavía sin correr) ahora también pone el menú de OpenCore en **Timeout 0** (espera a que elijas), marca **SS04 como USB 3** en UTBMap y revisa (solo lectura) de dónde sale la entrada "EFI".

### 2026-11-21 01:05 - AirDrop solo de ida, lector SD y escribir en el disco de Windows
- **AirDrop:** Andrew reporta que **de la laptop al iPhone sí manda**, pero **del iPhone a la laptop no**: el iPhone no ve la Mac.
  - Revisado: AirDrop está en "Todos" (`DiscoverableMode = Everyone`), pero **no existe la interfaz `awdl0`**. AWDL es el WiFi directo que usa AirDrop para que otros te encuentren.
    AirportItlwm (Intel) no lo implementa, así que la Mac no puede anunciarse por AWDL. Que sí mande hacia el iPhone es una suerte: no hay que depender de eso.
  - Bluetooth Intel (THIRD_PARTY_DONGLE) también limita Handoff, Continuidad y Desbloqueo con el Watch.
  - **Única solución completa:** cambiar la tarjeta WiFi/BT por una Broadcom (BCM94360NG, M.2 2230 A+E, la misma ranura de la 8265). Necesita el parche "Modern Wireless" de OCLP-Mod y quitar AirportItlwm/IntelBluetoothFirmware. Queda como idea, no se hizo nada.
  - **Mientras tanto:** se instaló **LocalSend 1.18.2** (gratis, de código abierto, notarizado) en /Applications. Hay que instalarlo también en el iPhone (App Store); manda archivos en los dos sentidos por la misma red WiFi.
- **Lector SD:** es un **Realtek RTS522A** (PCI `10ec:522a`) y no tenía driver. El script `mejoras-cpu-estabilidad.sh` (todavía sin correr) ahora también agrega RealtekCardReader 0.9.8 + RealtekCardReaderFriend 1.0.5 (0xFireWolf; la 0.9.8 salió el 18/11/2026 con soporte para Tahoe). Kexts en `~/hackintosh-mac/descargas/sd/x/`.
- **Disco de Windows (NTFS):** macOS lo monta **solo lectura** (driver FSKit de Apple). Tiene 58 GB libres. No hay `hiberfil.sys`, así que el inicio rápido de Windows está apagado (bien: es requisito para escribir sin dañarlo).
  Opciones para escribir: (a) macFUSE + ntfs-3g (gratis, más pasos); (b) Paragon NTFS for Mac (de pago, el más estable); (c) una partición exFAT compartida que lean y escriban los dos sistemas sin nada extra. Falta que Andrew decida.

### 2026-11-21 01:30 - Micrófono, ventilador, NTFS con escritura, Encontrar mi Mac y Ethernet
- **Micrófono interno funciona:** con `swift ~/hackintosh-mac/microfono.swift` captó una voz de prueba a -12.7 dBFS (pico 0.23).
  La entrada predeterminada estaba en la bocina Bluetooth "PIONER ROOM" (eso baja el audio a calidad de llamada, 8 kHz); se cambió a **Built-in Microphone**.
- **Ventilador al máximo:** YogaSMC solo podía leer el EC (`EC Capability = Basic`). Se hizo `~/hackintosh-mac/acpi-nuevo/SSDT-ECRW.aml` (métodos RE1B/RECB/WE1B/WECB en `\_SB.PCI0.LPCB.EC`; el DSDT no los tenía; el ventilador es HFSP, 0x2F).
  Compilado con iasl 20260930 (ACPICA oficial, compilado aquí; queda en `descargas/acpica/bin/iasl`). Se agrega con `mejoras-cpu-estabilidad.sh`.
  YogaSMCNC quedó con `SaveFanLevel = 1` y `FanLevel = 71` (0x47 = "Full"). Al arrancar con el SSDT, el menú de YogaSMCNC muestra el ventilador con botones Auto / Full.
  - Para regresar a automático: en el menú de YogaSMCNC elegir "Auto", o `defaults write org.zhen.YogaSMC FanLevel -int 132`.
- **Escribir en Windows (NTFS):** Andrew eligió macFUSE + ntfs-3g.
  - macFUSE 5.5.0 (firmado y notarizado, SHA-256 verificado) y ntfs-3g 2026.9.28 (código de tuxera.com, SHA-256 `350d9415...`, compilado aquí en estático contra macFUSE) en `descargas/ntfs/`.
  - `montar-windows.sh` (se instala en /usr/local/sbin): quita el montaje de solo lectura y monta con ntfs-3g usando **backend FSKit** (sin kext). Si falla, prueba el kext de macFUSE; si eso también falla, regresa a solo lectura. Apaga Spotlight en ese disco. Registro: `salida-montar-windows.txt`.
  - Un LaunchDaemon (`com.andrew.montar-windows`) lo corre al arrancar. Todo se instala con `mejoras-cpu-estabilidad.sh`.
  - Paso manual una sola vez: Ajustes → General → Ítems de inicio y extensiones → Extensiones del sistema de archivos → activar **macFUSE**.
  - Ojo: ntfs-3g se niega a escribir si Windows quedó hibernado o con inicio rápido. Siempre apagar Windows con "Apagar" normal.
- **Encontrar mi Mac:** todavía no está activado (no hay `fmm-computer-name` en NVRAM), pero cumple los requisitos: iCloud con sesión iniciada, SMBIOS con serie de 12 y MLB de 17 caracteres, ROM = MAC de en0 (XX:XX:XX:XX:XX:XX), en0 marcado como interno (IOBuiltin) y NVRAM nativa con escritura.
- **Ethernet (en0, I219-V5, IntelMausi 1.0.8):** el driver carga bien (IOBuiltin = Yes, MAC XX:XX:XX:XX:XX:XX), pero `status: inactive` y `IOLinkSpeed = 0`: no detecta cable. Falta probar con un cable conectado.
- **AirDrop:** no hay forma de que funcione de ida y vuelta con la Intel 8265: su firmware no tiene AWDL y AirportItlwm no lo implementa. Solo se arregla con una tarjeta Broadcom.
- **Limpieza:** se borraron los temporales de compilación (macfuse.dmg, la extracción del pkg y el código de ACPICA). Se dejaron el instalador del KDK (1.1 GB) y el pkg de OCLP-Mod (730 MB): hacen falta para volver a parchar si macOS se actualiza.
  No hay apps que no sirvan: HeliPort se deja por si se regresa a itlwm. Los kexts HighPoint de /Library/Extensions vienen con macOS; no se tocan.

### 2026-11-21 01:40 - Distribución de teclado Latinoamericana (como en Windows)
- Antes estaba "Spanish - ISO" (la de España: el @ sale con Opción+2). El teclado de Andrew es latinoamericano.
- Se hizo una distribución a la medida: `~/Library/Keyboard Layouts/Latinoamericano (Windows).keylayout`, generada con `~/hackintosh-mac/teclado/generar-latam.py` y activada con `swift ~/hackintosh-mac/teclado/activar-latam.swift`.
  - AltGr (Alt derecho) = Opción. **AltGr+Q = @**, AltGr+' = \, AltGr++ = ~, AltGr+{ = ^, AltGr+} = `, AltGr+| = ¬.
  - Ñ en su lugar; ´ y ¨ son teclas muertas (´+a = á, ¨+u = ü); ¿ ¡ ' ? { [ } ] + * < > - _ como en Windows.
  - Con Comando (Ctrl físico, por el cambio de teclas), los atajos usan las letras normales: Ctrl+C/V/Z siguen igual.
  - Probado con UCKeyTranslate: todas las teclas de prueba dan el carácter correcto.
- "Spanish - ISO" se dejó activada como respaldo (se cambia desde el menú de teclado de la barra).
- Si la tecla de debajo de Esc (| °) y la de junto a la Z (< >) salen cambiadas, es por cómo VoodooPS2 reporta el teclado ISO; se arregla intercambiando los códigos 10 y 50 en el script.
- Para quitarla: borrar el archivo de ~/Library/Keyboard Layouts y cerrar sesión.

### 2026-11-21 01:42 - Tecla Windows sola abre Apps
- Programa propio **TeclaWindows** (`~/hackintosh-mac/tecla-windows/main.swift`, compilado con swiftc y firmado ad-hoc) en /Applications/TeclaWindows.app, sin icono.
  Escucha (solo lectura) la tecla Windows física (llega como Control izquierdo, código 59, por el cambio de hidutil). Si la aprietas y sueltas **sola** en menos de 0.6 s, abre **/System/Applications/Apps.app**.
  Con otra tecla, otro modificador o un clic en medio no hace nada, así que la tecla sigue sirviendo de modificador.
- Arranca con `~/Library/LaunchAgents/com.andrew.teclawindows.plist` (KeepAlive). Necesita permiso de **Monitoreo de entrada** (Ajustes → Privacidad y seguridad).
- Para quitarlo: `launchctl bootout gui/$(id -u)/com.andrew.teclawindows; rm ~/Library/LaunchAgents/com.andrew.teclawindows.plist; rm -rf /Applications/TeclaWindows.app`

### 2026-11-21 01:44 - CPU en modo rendimiento (CPUFriend) y estabilidad
- Revisado antes: la gráfica HD 630 ya tiene aceleración (Metal 3, AppleIntelKBLGraphics, 1536 MB). La NVIDIA 940MX no tiene driver en macOS (no se puede usar).
- CPU: XCPM activo (plugin-type 1, X86PlatformPlugin) y sin limitación térmica. El perfil del MacBookPro16,2 traía EPP 0x80 (ahorro).
  Se agregó CPUFriend 1.3.0 + CPUFriendDataProvider (perfil Mac-5F9802EFE386AA28 con EPP 0x20 en los dos vectores): sube a turbo más rápido. Gasta un poco más de batería.
- Lector SD (Realtek RTS522A, 10ec:522a): RealtekCardReader 0.9.8 + RealtekCardReaderFriend 1.0.5 (0xFireWolf, con soporte para Tahoe). Ojo: si la laptop se suspende con la tarjeta puesta, al despertar hay que sacarla y volver a meterla.
- Respaldo del config: `config.antes-cpufriend-aplicar-20261121-014352.plist` (en EFI\OC\, BITACORA-MAC\respaldos\ y ~/hackintosh-mac/respaldos/).
- Kernel/Add #26 CPUFriend.kext agregado: Enabled = true (al final, despues de Lilu)
- Kernel/Add #27 CPUFriendDataProvider.kext agregado: Enabled = true (al final, despues de Lilu)
- Kernel/Add #28 RealtekCardReader.kext agregado: Enabled = true (al final, despues de Lilu)
- Kernel/Add #29 RealtekCardReaderFriend.kext agregado: Enabled = true (al final, despues de Lilu)
- ACPI/Add #4 SSDT-ECRW.aml agregado: Enabled = true (YogaSMC puede escribir en el EC: control del ventilador)
- Misc/Boot/Timeout: 5 -> 0 (el menu de OpenCore espera hasta que elijas; ya no arranca solo)
- Parches del TrackPoint (Kernel/Patch, PS2Trackpad): 2 encontrados, todos activos (no se tocaron)
- ocvalidate: Completed validating /Volumes/EFI-MAC/EFI/OC/config.plist in 2 ms. No issues found.
- Actualizaciones de macOS: AutomaticallyInstallMacOSUpdates = 0, AutomaticDownload = 0 (las de seguridad siguen igual). Así una actualización no borra el root patch del audio sin avisar.
- UTBMap: SS04 UsbConnector 255 -> 3 (USB 3) en 1 entrada(s). Respaldo: UTBMap-antes-20261121-014352
- macFUSE 5.5.0: instalado. ntfs-3g 2026.9.28 (compilado aqui, estatico, SHA-256 del codigo verificado) en /usr/local/bin. LaunchDaemon com.andrew.montar-windows monta Windows con escritura al arrancar.
  Para quitarlo: `sudo rm /Library/LaunchDaemons/com.andrew.montar-windows.plist` y `sudo bash /usr/local/sbin/montar-windows.sh solo-leer`; macFUSE se quita con su Uninstaller.
- Ventilador: SSDT-ECRW.aml (EC en \_SB.PCI0.LPCB.EC, compilado con iasl 20260930). YogaSMCNC guarda el nivel Full (0x47) y lo aplica al iniciar.
- Entrada "EFI" del menú (diagnóstico, no se cambió nada): EFI-MAC \EFI\BOOT: .contentFlavour BOOTx64.efi  | EFI de Windows (disk0s5) \EFI: APPLE Boot Microsoft | \EFI\BOOT: BOOTIA32.EFI (747681 bytes) bootx64.efi (949424 bytes) fbia32.efi (70360 bytes) fbx64.efi (87816 bytes) 
- **Si no arranca o hay kernel panic:** desde Windows restaurar `config.antes-cpufriend-aplicar-20261121-014352.plist` encima de EFI\OC\config.plist.
  Desde macOS: `sudo bash ~/hackintosh-mac/mejoras-cpu-estabilidad.sh revertir` y reiniciar.
- Siguiente: reiniciar (no hace falta Reset NVRAM) y revisar con `kextstat | grep -i cpufriend`.

### 2026-11-21 01:55 - Revisión después de correr mejoras-cpu-estabilidad.sh y reiniciar
- El script corrió a las 01:43 (ocvalidate sin errores) y arrancó bien a las 01:45.
- **CPUFriend 1.3.0** cargado; `cf-frequency-data` presente en los 4 CPU (EPP 0x20).
- **Lector SD:** RealtekCardReader 0.9.8 y Friend 1.0.5 cargados; el registro muestra `RealtekRTS522AController` y `RealtekPCISDXCSlot`. Falta probarlo con una tarjeta.
- **Ventilador:** `EC Capability` pasó de Basic a **RW** (el SSDT-ECRW funciona). YogaSMCNC no se había abierto sola (`StartAtLogin` no basta en Tahoe): se agregó como **ítem de inicio** y aplicó "Set Fan Level to 47" (Full).
- **USB:** SS04 ya sale como UsbConnector = 3.
- WiFi nativo, Bluetooth y audio bien. El cambio de teclas Ctrl↔Comando y TeclaWindows siguen activos (TeclaWindows ya tiene el permiso de Monitoreo de entrada).
- **Distribución de teclado:** al reiniciar macOS regresó a "Spanish - ISO". Se volvió a seleccionar "Latinoamericano (Windows)" y se desactivó Spanish - ISO (`swift ~/hackintosh-mac/teclado/quitar-espana.swift`) para que no se regrese.
- **Disco de Windows:** al arrancar, ntfs-3g sí abrió el disco con escritura ("Mounted /dev/disk0s2 (Read-Write)"), pero el montaje FSKit no terminó porque macFUSE todavía no estaba activado en Ajustes. El disco quedó desmontado. Andrew ya activó macFUSE.
  `montar-windows.sh` se mejoró: espera máximo 45 s por cada backend (ya no se puede quedar atorado) y no usa `tee` cuando lo corre launchd. Hay que volver a instalarlo en /usr/local/sbin.
- **Entrada "EFI" del menú de OpenCore:** viene de la EFI de Windows (disk0s5): en `\EFI\BOOT` hay `bootx64.efi` (949 KB) + `fbx64.efi` + `BOOTIA32.EFI` + `fbia32.efi`. Eso es **shim de Linux**, que quedó de las distros que se probaron.
  Al elegirlo busca GRUB, que ya no existe, y regresa (por eso "se mini reinicia"). Windows arranca por `\EFI\Microsoft`, así que no depende de eso. Para esconderla habría que poner un archivo `.contentVisibility` en esa carpeta (falta que Andrew autorice tocar la EFI de Windows).
- Ethernet sigue sin enlace (`status: inactive`); falta probar con cable.

### 2026-11-21 02:05 - Antes de reiniciar: Windows, red y Ethernet
- `montar-windows.sh` (versión nueva) corrió a mano: FSKit y VFS no montaron y regresó solo a solo lectura (como debía). Andrew dice que macOS pidió reiniciar para las extensiones nuevas de macFUSE; se reinicia y el LaunchDaemon lo vuelve a intentar.
- Red: el servicio del WiFi (en1) se llamaba "Ethernet 2" (quedó de cuando era itlwm). Se renombró a **"Wi-Fi"** con `networksetup -renamenetworkservice`.
- Ethernet: Andrew confirma que **el cable sí está conectado** al módem y aun así no hay enlace. Chip: Intel I219-V5 (8086:15d6, subsistema 17aa:505d), soportado por IntelMausi 1.0.8. `IOLinkStatus = 1` (sin enlace), `IOLinkSpeed = 0`.
  Sospecha: Windows deja apagado el PHY al apagarse (Wake on LAN / ahorro de energía). Siguientes pruebas: ver si funciona en Windows; apagar en frío (quitar el cargador 30 s) y arrancar directo a macOS.
- Se hizo `arreglar-hdmi-arranque.sh`: agrega `igfxonln=1` a boot-args para que el HDMI se detecte al arrancar sin desconectarlo.

### 2026-11-21 01:59 - HDMI detectado al arrancar (igfxonln=1)
- Motivo: después de cada reinicio había que desconectar y volver a conectar el HDMI para que lo detectara.
- Respaldo del config: `config.antes-igfxonln-aplicar-20261121-015920.plist` (en EFI\OC\, BITACORA-MAC\respaldos\ y ~/hackintosh-mac/respaldos/).
- boot-args: `-ibtcompatbeta -amfipassbeta unfairgva=7` -> `-ibtcompatbeta -amfipassbeta unfairgva=7 igfxonln=1`
- ocvalidate: Completed validating /Volumes/EFI-MAC/EFI/OC/config.plist in 7 ms. No issues found.
- **Si la pantalla se queda negra o no arranca:** desde Windows restaurar `config.antes-igfxonln-aplicar-20261121-015920.plist` encima de EFI\OC\config.plist, o `sudo bash ~/hackintosh-mac/arreglar-hdmi-arranque.sh revertir`.

### 2026-11-21 02:10 - Widgets (Stats), hora entre Windows y macOS, y fondo en vivo
- **Stats 3.1.0** (exelban, gratis, código abierto, notarizado) en /Applications y en ítems de inicio. Muestra en la barra de arriba y como widgets: CPU, GPU, RAM, disco, red, temperaturas y batería.
  Lee los sensores de VirtualSMC (SMCProcessor, SMCSuperIO) y SMCBatteryManager. El ventilador se sigue controlando desde el menú de YogaSMCNC (Auto / Full).
- Batería: 6151/6600 mAh (93 %), 215 ciclos, cargador reportado de 60 W. La carga rápida de Lenovo (Rapid Charge) la maneja el EC/BIOS y no depende del sistema; necesita un cargador Lenovo de 65 W o más.
- **Hora:** el registro de Windows **no tiene `RealTimeIsUniversal`** (revisado en `Windows\System32\config\SYSTEM`, solo lectura). Por eso, al cambiar de sistema, la hora se mueve unas 7 horas hasta que se sincroniza.
  Se preparó `~/hackintosh-mac/para-windows/hora-UTC-como-macOS.reg` (RealTimeIsUniversal = 1, QWORD). Se pasa al escritorio de Windows cuando el disco tenga escritura y se le da doble clic en Windows.
- Andrew quiere ver datos en vivo (temperatura, etc.) en el menú de OpenCore. OpenCanopy solo dibuja imágenes fijas. Opción: una herramienta UEFI propia como entrada aparte del menú. Queda para después del reinicio.

### 2026-11-21 02:20 - Batería, carga rápida y Mensajes (solo revisión)
- **Batería en macOS:** System Information ya la reporta completa: SANYO 45N1777, 6151 mAh de carga completa, 215 ciclos, estado "Normal", carga en %. El "60 W" del cargador (AdapterDetails) es un valor fijo de SMCBatteryManager, no el real.
- **Carga rápida (Lenovo Rapid Charge):** la maneja el EC de la laptop y funciona igual en cualquier sistema; macOS no la puede activar. YogaSMC 1.5.3 (ThinkVPC) no expone umbrales de carga ni Rapid Charge.
  Requisito: cargador Lenovo de 65 W o más (revisar la etiqueta del cargador). En Windows, Lenovo Vantage tiene el interruptor "Carga rápida" si el modelo lo soporta, y se queda guardado en el EC.
- **Mensajes:** identityservicesd recibe mensajes de iMessage (validación BlastDoor OK), así que el registro de iMessage sí funciona. Los "Failed entitlement check" de apsd son normales.
  Si "no se envió" pasa con contactos de SMS (burbuja verde), falta activar Reenvío de mensajes de texto en el iPhone para esta Mac. Falta que Andrew diga con quién falla.
- Menú de OpenCore con datos en vivo en la misma pantalla: posible modificando OpenCanopy (compilar OpenCorePkg). Plan: probarlo primero en la USB de OpenCore, sin tocar EFI-MAC.

### 2026-11-21 02:17 - Menú de OpenCore: fondo ThinkPad y entrada "EFI" (aplicar)
- Fondo: Background.icns (1172970 bytes, PNG 1920x1080 en registro ic07) copiado a EFI\OC\Resources\Image\Acidanthera\GoldenGate\.
  El fondo se hace con `swift ~/hackintosh-mac/menu-arranque/fondo.swift` (logo ThinkPad con el punto rojo, T470p y panel con CPU, GPU, RAM, SSD, pantalla y red; el centro queda libre para los iconos).
- Entrada "EFI": se creó \EFI\BOOT\.contentVisibility = Disabled en la EFI de Windows (disk0s5). Contenido de esa carpeta: .contentVisibility BOOTIA32.EFI bootx64.efi fbia32.efi fbx64.efi 
  Es el shim de Linux (bootx64.efi + fbx64.efi + BOOTIA32.EFI) que quedó de las distros que se probaron; Windows arranca por \EFI\Microsoft y no lo usa.
- Para deshacer: `sudo bash ~/hackintosh-mac/menu-arranque/aplicar-menu.sh revertir`. Desde Windows: borrar Background.icns del tema y \EFI\BOOT\.contentVisibility de la EFI de Windows.
- No se tocó config.plist (el fondo es opcional para OpenCanopy: si falla al cargarlo, solo se ve el fondo negro de siempre).

### 2026-11-21 02:25 - Revisión después del reinicio (fondo, HDMI, macFUSE)
- **Fondo ThinkPad del menú de OpenCore:** se ve bien (Andrew: "me encantó"). La entrada "EFI" ya no aparece.
- **HDMI:** con `igfxonln=1` (boot-args: `-ibtcompatbeta -amfipassbeta unfairgva=7 igfxonln=1`) ya se detecta al arrancar sin desconectarlo. Confirmado por Andrew.
- **macFUSE:** el kext `io.macfuse.filesystems.macfuse.25` (5.5.0) ya carga desde la Aux KC. En la pantalla de bloqueo pidió permiso y Andrew lo dio.
  Lo que pasó al arrancar: FSKit falló a los 22 s. Luego el backend VFS (kext) se quedó esperando ese permiso más de 45 s; el script se rindió y montó el solo lectura de Apple, y después ntfs-3g montó **debajo** (dos montajes encimados en /Volumes/Windows). No se escribió nada.
  Arreglo en `montar-windows.sh`: primero VFS (kext, ya aprobado), luego FSKit; espera hasta 2 min; si encuentra montajes encimados, los quita y monta limpio; si falla, mata ntfs-3g antes de volver a solo lectura. Hay que reinstalarlo en /usr/local/sbin.
- Ethernet: Andrew va a revisar el cable en el módem.
- Menú con datos en vivo: se bajó OpenCorePkg 1.0.8 en `~/hackintosh-mac/opencanopy-vivo/` para modificar OpenCanopy. Se prueba primero en la USB.

### 2026-11-21 02:40 - Icono de batería y menú EN VIVO (en desarrollo)
- **Icono de batería de macOS** ocultado (`NSStatusItem VisibleCC Battery` = false y `-currentHost Battery = 8` en com.apple.controlcenter; se reinició ControlCenter). La batería se ve con Stats.
  Para regresarlo: Ajustes → Centro de control → Batería → Mostrar en la barra de menús.
- **Disco de Windows:** el comando nuevo (`install ... montar-windows.sh` y montar) todavía no se ha corrido; siguen los dos montajes encimados (solo lectura de Apple + macfuse).
- **Menú EN VIVO (OpenCanopy modificado):** en `~/hackintosh-mac/opencanopy-vivo/OpenCorePkg` (OpenCore 1.0.8).
  - Archivo nuevo `Platform/OpenCanopy/Views/LiveStats.c` (+ .h): panel abajo a la izquierda (660×224) con "EN VIVO" (punto rojo que parpadea), reloj (RTC en UTC − 7 h) y tres tarjetas con valor grande y gráfica de 60 s:
    temperatura del CPU (MSR 0x1B1/0x19C con TjMax de 0x1A2), frecuencia real (APERF/MPERF × TSC) y consumo del paquete (RAPL 0x606/0x611).
    Cada MSR se lee solo si CPUID dice que existe (RAPL solo en modelos Intel Core conocidos; la T470p es 06_9E). Si algo falta, la tarjeta muestra "--".
    Se actualiza cada 30 cuadros (0.5 s) con una animación de OpenCanopy; solo se activa a escala 1 y en pantallas de 1280×720 o más.
  - Cambios en BootPicker.c: el panel se agrega a la vista y se inicia y libera junto con ella. En OpenCanopy.inf: el archivo nuevo + OcCpuLib, PrintLib, UefiRuntimeServicesTableLib.
  - Herramientas sin sudo en `opencanopy-vivo/tools/bin`: mtoc 1.0.3 (acidanthera/ocmtoc), nasm 2.15.05 (ocbuild/external) e iasl 20260930.
  - Compilación: `build_oc.tool` con ARCHS=X64, TARGETS=RELEASE, TOOLCHAINS=XCODE5 y BUILD_ARGUMENTS="-m OpenCanopy.inf" (solo ese módulo). Registro: `opencanopy-vivo/build.log`.
  - Plan de prueba: copiar el OpenCanopy.efi nuevo **solo a la USB de OpenCore** y arrancar desde ella. EFI-MAC no se toca hasta que funcione.

### 2026-11-21 02:55 - Corrección: la T470p de Andrew NO tiene NVIDIA
- En entradas anteriores (CPUFriend y el fondo del menú) se escribió que había una "NVIDIA GeForce 940MX" sin driver. **Es un error**: el hardware revisado desde Windows (`RESUMEN.md`, 16 nov) dice "HD 630 (8086:591B), **sin NVIDIA**". La única gráfica es la Intel HD 630, y va con aceleración completa.
- `menu-arranque/fondo.swift` corregido: la fila GPU dice "Intel HD Graphics 630 · Metal 3 · 1.5 GB". Para que se vea en el menú hay que volver a correr `sudo bash ~/hackintosh-mac/menu-arranque/aplicar-menu.sh`.
- **Disco de Windows:** Andrew corrió el comando nuevo y quedó **montado con escritura** (un solo montaje macfuse, prueba de escritura OK).
- Se instaló GitHub CLI 2.105.0 (checksum verificado) en ~/.local/bin para subir el proyecto a GitHub (repo público `thinkpad-t470p-hackintosh`, sin datos únicos).

### 2026-11-21 02:40 - Repo de GitHub, Obsidian y menú EN VIVO compilado
- **OpenCanopy con panel EN VIVO compilado sin errores:** `opencanopy-vivo/OpenCorePkg/UDK/Build/OpenCorePkg/RELEASE_XCODE5/X64/OpenCanopy.efi` (118 784 bytes; tiene los textos "EN VIVO", "TEMPERATURA CPU" y "CONSUMO CPU").
  El "rc=1" del final de build.log es solo del empaquetado (busca OpenCore.efi, que no se compiló a propósito). Falta probarlo en la USB.
- **Repo** `~/hackintosh-mac/repo` (público, `thinkpad-t470p-hackintosh`):
  - README con la portada, `instalar.py` (baja OpenCore 1.0.8, genera SMBIOS propio con macserial, baja Tahoe con macrecovery `Mac-CFF7D910A743CAAF`; probado con `--sin-macos`) y `docs/instalacion.md`, `docs/bitacora.md`, `docs/windows.md`.
  - Además scripts/macos, extras (SSDT-ECRW, fondo, teclado, TeclaWindows, .reg de la hora) y licencia MIT para lo propio.
  - Se arma con `python3 ~/hackintosh-mac/armar-repo.py`: copia todo y quita la MAC/ROM, las rutas con el usuario, el correo y el GUID de bcdedit; en la EFI deja serie, MLB, UUID y ROM en blanco. Al final revisa que no quede nada privado.
  - Falta la EFI: `sudo bash ~/hackintosh-mac/exportar-efi.sh` (solo lee EFI-MAC) y luego login de GitHub (`gh auth login --web`).
- **Hora de Windows:** `hora-UTC-como-macOS.reg` copiado al Escritorio de Windows. Falta darle doble clic desde Windows.
- **Obsidian (bóveda XOF en CODE):** nota nueva `proyectos/hackintosh-t470p.md` (plantilla de proyecto) y fila en la tabla de proyectos de `inicio.md`.

### 2026-11-21 03:08 - GitHub publicado, USB al día y panel EN VIVO v2
- **GitHub:** sesión iniciada como `z-XOF-z`. Repo público https://github.com/z-XOF-z/thinkpad-t470p-hackintosh (commits b33e2dd y a535b8c), con temas hackintosh/opencore/thinkpad/t470p/macos-tahoe.
  Commits con el correo noreply de GitHub. El instalador se probó desde GitHub (`curl ... | python3 - --sin-macos`): bajó la EFI del repo y generó un SMBIOS nuevo.
  Clonado en Windows: `CODE/thinkpad-t470p-hackintosh` (core.fileMode false). Enlace agregado a la nota de Obsidian.
- **USB OPENCORE (disk6s1):** tenía la EFI vieja del 17/11 (sin AMFIPass ni el SIP nuevo; arrancar macOS con ella podía fallar). Respaldo en `respaldos/usb-EFI-antes-20261121-030102/`.
  Se reemplazó por la EFI actual de EFI-MAC + el fondo corregido + el OpenCanopy con panel EN VIVO. ocvalidate sin errores; Timeout 0.
- **Panel EN VIVO v2** (`LiveStats.c`): 6 tarjetas en una fila centrada (1302×224, y 668–892 en 1080p), entre los iconos (terminan en ~659) y los botones de apagar/reiniciar (empiezan en 900).
  Se agregaron **batería** (%, cargando/en uso y watts), **ventilador** (RPM) y **temperatura de la placa**, leídos del EC por los puertos 0x62/0x66 con tiempo límite (20 ms por paso). Offsets del DSDT: HB0S 0x38, TMP0 0x78, HIID 0x81 (se pone 0 = BAT0, como _BST), HSPD 0x84, SBRC 0xA0, SBFC 0xA2, SBAC 0xA8, SBVO 0xAA.
  Arriba: RAM total (suma del mapa de memoria de UEFI) y reloj. Si el panel no cabe sin tapar los iconos, no se muestra. Copia de la v1 en `opencanopy-vivo/LiveStats.c.v1`.
- **Para probar:** reiniciar → F12 → la USB. Si el menú se traba o se ve mal: apagar con el botón y arrancar normal (EFI-MAC no se tocó).

### 2026-11-21 03:20 - Herramienta propia "Diagnostico" (DiagT470p.efi) en la USB
- App UEFI propia, `opencanopy-vivo/OpenCorePkg/Application/DiagT470p/` (Comun.c, Main.c, Sistema.c, Ram.c, Disco.c), compilada con EDK2 (XCODE5, RELEASE): `DiagT470p.efi`, 77 824 bytes, sin errores.
  Agregada a OpenCorePkg.dsc. Usa la consola de texto de OpenCore (OcConsoleControlEntryModeGenericLib) + GOP para gráficas.
- **Todo es de solo lectura** (no escribe en discos). Menú:
  1. Resumen: CPU (CPUID, microcódigo MSR 0x8B), firmware, GOP, reloj y mapa de memoria UEFI (por tipo + barra física coloreada).
  2. Prueba de RAM: toda la memoria libre en bloques de 16 MB (AllocatePages AllocateAddress → 4 patrones: 0x55, 0xAA, dirección en dirección, aleatorio xorshift → FreePages).
     Mapa de 96×20 cuadros (gris pendiente / amarillo / verde / rojo / negro en uso), barras de MB/s, lista de errores y pasadas continuas hasta Esc.
  3. Discos: info y S.M.A.R.T. por EFI_ATA_PASS_THRU: IDENTIFY 0xEC, SMART READ DATA (0xB0/0xD0), THRESHOLDS (0xD1) y RETURN STATUS (0xDA).
     Tabla de atributos con nombres en español, barras y veredicto (BUENA / REVISAR / MALA), horas, temperatura y vida restante del SSD.
  4. Escaneo de superficie (estilo Victoria): BlockIo ReadBlocks de 256 sectores; cada lectura se clasifica <5, <20, <50, <150, <500, ≥500 ms o error.
     Mapa de 150×26 cuadros (cada cuadro = su peor lectura), contadores, MB/s con gráfica y lista de LBA con error. Elige el disco (interno/extraíble).
  5. Teclado: teclado latinoamericano de la T470p en pantalla. El firmware lo lee como EE.UU. (la Ñ llega como `;`), por eso la tabla usa el carácter de EE.UU. de cada tecla. Esc 3 veces para salir.
  6. Pantalla: 8 colores sólidos, degradado y tablero fino.
  7. Batería (EC): %, cargando/en uso, mWh o mAh (bit 15 de SBBM), voltaje, corriente, watts, salud (SBFC/SBDC), ciclos (SBCC), fecha de fabricación (SBMD), historial en barras, TMP0 y RPM.
- En la USB: `EFI/OC/Tools/DiagT470p.efi` + entrada en Misc/Tools ("Diagnostico", Flavour `Diagnostico:Tool`, Auxiliary false: se ve sin apretar Espacio). ocvalidate sin errores. Respaldo del config de la USB en `respaldos/usb-config.antes-diag-*`.
- Siguiente etapa (no hecha): reparación estilo HDAT2/Victoria solo para discos externos, con confirmaciones. Lectura/verificación + reasignación (escribir el sector malo) + borrado seguro ATA. El disco interno quedaría bloqueado.
- No se hizo ingeniería inversa de HDAT2 ni de Victoria: todo sale de los estándares públicos ATA/ACS y UEFI. No hay desfragmentador (en SSD no conviene y requiere entender NTFS/APFS).

### 2026-11-21 03:32 - Prueba en la laptop: funciona. Arreglos de calidad y de limpieza
- **Andrew probó la USB:** el panel EN VIVO y el Diagnóstico funcionan.
- Problema 1: el panel se veía "de baja calidad". Causa: los números grandes eran la fuente de 12 px de OpenCanopy agrandada ×3 pixel por pixel.
  Arreglo: fuente propia **suavizada** (alfa de 8 bits) generada con `opencanopy-vivo/generar-fuente.swift` (Helvetica Neue) → `Views/LiveFont.h`, en tres tamaños: Grande 48 px (valores), Mediano 23 px (EN VIVO, reloj, unidades), Chico 17 px (títulos, RAM). El reloj ahora se alinea a la derecha midiendo el texto. OpenCanopy.efi: 176 128 bytes.
- Problema 2: en el Diagnóstico, al cambiar de sección quedaban las gráficas de la anterior (por ejemplo, la RAM debajo del disco). Causa: `ClearScreen` de OpenCore solo borra el texto. Arreglo: `Limpiar()` ahora también pinta toda la pantalla de negro por GOP.
- Ambos recompilados sin errores y copiados a la USB.

### 2026-11-21 03:40 - Correcciones por las fotos y modo de reparación (estilo HDAT2/Victoria)
- **Fotos de Andrew (primera versión):** todo funciona. Panel: 52 °C, 3.09 GHz, 6.4 W, batería 100 %, 2158 RPM, placa 52 °C. RAM a ~3.4 GB/s sin errores.
  S.M.A.R.T. del Kingston SA400S37480G (firmware SBFKK1C3): salud BUENA, 3384 h, 2154 encendidos, 39 °C, vida 94 %. Teclado 75/75. Escaneo: ~250 MB/s, sin errores. Batería: 93.2 %, 215 ciclos, diseño 71 280 mWh a 10.8 V.
- **Errores corregidos en DiagT470p:**
  - Decía "8 núcleos / 16 hilos": CPUID 1/4 dan el máximo del APIC. Ahora usa CPUID 0x0B (topología real: 4/4).
  - "RAM 17.0 GB": eran 16 GiB en decimal. La RAM ahora se muestra en binario (TamanoBin) y solo cuenta tipos de memoria estándar.
  - Temperatura del S.M.A.R.T. con crudo 81608966183: solo se usa el byte bajo (los otros son mínimo y máximo).
  - Barras del S.M.A.R.T. escaladas a 100 (o 253) y la de vida restante en verde/amarillo/rojo.
  - "Fabricada 1980-00-16": se prueba SBMD y SBOM (página 2) y la fecha solo se muestra si el año está entre 2010 y 2035.
- **Opción 5 nueva: "Discos: reparación"** (DiagT470p.efi 86 016 bytes):
  1. Remap: lee todo; el sector que no se lee en 3 intentos se escribe en ceros (el disco lo reasigna) y se verifica.
  2. Refrescar: los bloques de 150 ms o más se reescriben con sus mismos datos.
  3. Borrar todo con ceros (hay que escribir `BORRAR`).
  - **Candados:** solo discos con nodo USB en la ruta, que no sean la USB de arranque (`EsDiscoDeArranque` compara con el LoadedImage; si no sabe, bloquea) y que no sean de solo lectura. Doble confirmación para 1 y 2. `Escanear()` vuelve a revisar el candado antes de escribir. El disco interno SATA nunca aparece.
- Copiado a la USB.

### 2026-11-21 03:46 - Diagnóstico con 9 métodos de disco (estilo HDAT2/Victoria) y franjas en la interfaz
- `Disco.c` reescrito con un solo motor (`Ejecutar`) y 9 métodos:
  - **Solo leen (cualquier disco):** 1 Lectura lineal · 2 Verificar con **ATA READ VERIFY SECTORS EXT (0x42)**, sin transferir datos (solo SATA con EFI_ATA_PASS_THRU; el disco se enlaza con su puerto por el nodo `Sata()` de la ruta y LocateDevicePath; si no hay ATA usa lectura) · 3 Mariposa (alterna inicio y final) · 4 Acceso aleatorio (4096 lecturas: tiempo mínimo, promedio y máximo).
  - **Escriben (solo USB externos que no sean de arranque):** 5 Reparar (remap) · 6 Refrescar lentos (≥150 ms) · 7 Leer-escribir-leer (reescribe igual y compara, no destructivo) · 8 Escribir patrón y verificar (xorshift distinto por LBA, destructivo) · 9 Borrar con ceros.
  - Confirmaciones: los no destructivos que escriben piden doble S; los destructivos piden escribir `BORRAR`. El candado (`PuedeEscribir`) se revisa en el menú y otra vez dentro de `Ejecutar`.
  - Mapa de 150×26 que guarda la **peor** operación de cada zona (sirve para métodos que saltan). Gráfica de velocidad con líneas guía y brillo en cada barra.
- Menú principal: "Discos: pruebas" (cualquier disco, solo los métodos de lectura) y "Discos: reparación" (solo USB, los 9 métodos).
- Encabezado con 6 franjas diagonales rojas, cada vez más oscuras ("rayitos").
- DiagT470p.efi 90 112 bytes, compilado sin errores, copiado a la USB.
- Para pasar todo a EFI-MAC cuando Andrew lo apruebe: `sudo bash ~/hackintosh-mac/menu-arranque/instalar-en-efi.sh` (respalda OpenCanopy.efi, config.plist y fondo; `revertir` los regresa).

### 2026-11-21 03:48 - Diagnóstico: pantalla "BIOS y ThinkPad" (opción 9)
- Pregunta de Andrew: ¿se puede controlar la BIOS desde el menú? Decisión: **no se edita la configuración de la BIOS desde UEFI** (variable Setup de Lenovo): un valor mal puesto puede dejar la ThinkPad sin arrancar.
  La vía segura para cambiar opciones de la BIOS es la interfaz WMI oficial de Lenovo en Windows (ofrecida como herramienta aparte, no hecha).
- Opción 9 nueva en DiagT470p (94 208 bytes, sin errores, en la USB):
  - Firmware (proveedor, revisión, UEFI), Secure Boot y SetupMode, y la lista BootOrder/Boot#### con la entrada desde la que se arrancó (BootCurrent).
    El SMBIOS no sirve aquí: OpenCore lo reemplaza con el de Mac (`UpdateSMBIOS` = true, modo `Create`).
  - **Reiniciar a la BIOS** con la tecla B (bit EFI_OS_INDICATIONS_BOOT_TO_FW_UI en OsIndications + ResetSystem), solo si OsIndicationsSupported lo ofrece. Pide confirmación.
  - **Ventilador** por el EC (HFSP 0x2F): A = automático (0x80), F = full (0x40), 1–7 = nivel fijo, con RPM en vivo (HSPD 0x84) y barra. Dura hasta que arranca el sistema.

### 2026-11-21 03:53 - Menú EN VIVO y Diagnóstico grabados en EFI-MAC
- OpenCanopy.efi con panel EN VIVO (176128 bytes), Tools/DiagT470p.efi (94208 bytes) con entrada "Diagnostico" en Misc/Tools y fondo corregido.
- Respaldo de lo anterior: `BITACORA-MAC/respaldos/menu-vivo-antes-20261121-035318/` (OpenCanopy.efi, config.plist, Background.icns) y en ~/hackintosh-mac/respaldos/.
- ocvalidate: Completed validating /Volumes/EFI-MAC/EFI/OC/config.plist in 8 ms. No issues found.
- **Si el menú se traba o no arranca:** F12 → USB de OpenCore, y desde macOS `sudo bash ~/hackintosh-mac/menu-arranque/instalar-en-efi.sh revertir`.
  Desde Windows: copiar `menu-vivo-antes-20261121-035318/OpenCanopy.efi` a EFI\OC\Drivers\ y su config.plist a EFI\OC\.

### 2026-11-21 03:58 - Menú EN VIVO grabado en EFI-MAC; arreglo del aviso de macFUSE al arrancar
- Andrew corrió `instalar-en-efi.sh`: el menú EN VIVO y el Diagnóstico ya arrancan desde el disco. "Se ve excelente".
- **Aviso de "activa la extensión" en la pantalla de bloqueo:** el registro de las 03:51 muestra que ntfs-3g montó con escritura a las 03:51:55, pero el kext de macFUSE apenas se cargó a las 03:51:56 y el montaje se cayó solo (03:51:57).
  Luego el script probó FSKit, que es el que pide activar la extensión del sistema de archivos. No era que estuviera apagado: el LaunchDaemon corre antes de que macOS cargue el kext.
- `montar-windows.sh` cambiado:
  - Primero carga el kext (`macfuse.fs/Contents/Resources/load_macfuse`) y espera hasta 2 min a verlo en kextstat.
  - Luego monta solo con el kext: hasta 5 intentos, cada uno espera 60 s y entre intentos hay 10 s.
  - **Se quitó el respaldo FSKit** (era el que sacaba el aviso).
- Hay que reinstalarlo en /usr/local/sbin (necesita sudo).

### 2026-11-21 04:05 - Windows montado sin avisos; GitHub y Obsidian al día
- `montar-windows.sh` nuevo instalado: "LISTO … montado con escritura (ntfs-3g, intento 1)".
- GitHub (commit bcdcfe8): EFI del repo con OpenCanopy EN VIVO + DiagT470p (entrada en Misc/Tools) + fondo corregido, ocvalidate sin errores.
  `extras/opencore/`: código de LiveStats/LiveFont, generar-fuente.swift, DiagT470p y el parche de OpenCorePkg 1.0.8. README con las secciones del panel y del Diagnóstico.
  Copia de Windows (`CODE/thinkpad-t470p-hackintosh`) actualizada con git pull.
- Nota de Obsidian `proyectos/hackintosh-t470p.md` actualizada: decisiones del 21/11 y pendientes.

### 2026-11-21 04:05 - Luz del teclado que "respira" (4.º estado de Fn + Espacio) y dudas del panel de YogaSMC
- **Prueba:** la luz del teclado se puede cambiar desde macOS escribiendo la propiedad `BacklightLevel` del servicio ThinkVPC (YogaSMC → método `MLCS` del DSDT → `KBLS`). Niveles 0/1/2 OK; YogaSMCNC no recibió eventos de esos cambios.
- **LuzTeclado** (`~/hackintosh-mac/luz-teclado/main.swift` → `~/.local/bin/LuzTeclado`, firmado ad-hoc):
  - `ciclo`: lo llama YogaSMCNC con el evento 0x1012 (Fn + Espacio). Si estaba respirando, la detiene y apaga la luz. Si el EC acaba de pasar de alta a apagada, arranca `respirar` en segundo plano.
  - `respirar`: repite 0,1,2,2,1,0,0 cada 360 ms (unos 2.5 s por respiro); guarda su PID en `~/Library/Application Support/LuzTeclado/`.
  - `parar`: detiene la respiración y apaga la luz.
  - Ciclo resultante: apagada → baja → alta → **respirando** → apagada.
- YogaSMCNC: `Events > 1012 > 0` = acción `script` con `do shell script "~/.local/bin/LuzTeclado ciclo &"` (antes mostraba el aviso de nivel). La estrella (1311) sigue abriendo VS Code.
  - Para deshacer: borrar `Events > 1012` en `org.zhen.YogaSMC` (o poner la acción `backlight`) y reiniciar YogaSMCNC.
- **Dudas del panel de YogaSMC:**
  - Quiet / Balanced / Performance y "DYTC Revision" = Lenovo Dynamic Thermal Control (perfiles térmicos de la BIOS). El DSDT de la T470p **no tiene método DYTC** (llegó en ThinkPads de 2018+), por eso la revisión sale en 0 y el control está gris.
    El equivalente aquí es CPUFriend (rendimiento) + el ventilador.
  - LED Control: el método `LED` del DSDT escribe en el EC (0x0C) y controla los LEDs físicos (botón de encendido, standby, el punto rojo de la "i" de la tapa) en apagado / prendido / parpadeo. "Mute LED fixup" sincroniza el LED de F1 con el silencio de macOS.
  - El DSDT **sí** tiene BCTG/BCCS/BCSS: se pueden poner **umbrales de carga** (por ejemplo, cargar solo hasta 80 %) desde el panel de YogaSMC.

### 2026-11-21 04:12 - Icono "BateriaT470p": límite de carga y luz que respira
- App de barra de menús propia (`~/hackintosh-mac/limite-bateria/main.swift` → /Applications/BateriaT470p.app, firmada ad-hoc, en ítems de inicio).
  - Opciones: cargar hasta 60 / 80 / 90 % o normal (100 %). Usa las propiedades `Battery`=1 (BAT0), `setCMstop` (BCSS) y `setCMstart` (BCCS = tope − 5) del driver ThinkVPC.
  - El icono muestra el tope actual (lee BAT_PRIMARY.BCSG). El límite lo guarda el EC: se respeta en Windows y con la laptop apagada.
  - También trae un interruptor "Luz del teclado que respira" (llama a LuzTeclado respirar/parar).
- Probado: BCSG 0x300 → 0x350 (80 %), BCTG → 0x34B (75 %), y de regreso a 0x300/0x300 (normal). Se dejó en **normal**; Andrew decide si lo activa.
- Para quitarlo: elegir "Carga normal", salir de la app y borrar /Applications/BateriaT470p.app y su ítem de inicio.

### 2026-11-21 04:20 - Ethernet funciona y más funciones de la BIOS en el menú de la batería
- **Ethernet (en0, I219-V5):** ya tiene enlace: `status: active`, 192.168.2.67, la ruta por defecto sale por en0. Negoció **100baseTX full-duplex** (100 Mbps), no gigabit.
  Si el módem es gigabit, lo más probable es el cable (Cat5 viejo o con un par dañado) o el puerto del módem.
- **Métodos del DSDT (HKEY) revisados:** BCTG/BCCS/BCSG/BCSS (umbrales), BICG/BICS (pausar carga), BDSG/BDSS (descarga forzada), PSSG/PSSS (peak shift), GMKS/SMKS (Fn Lock), GSKL/SSKL (idioma del teclado), MLCG/MLCS (luz del teclado), LED (LEDs), GBDC/SBDC (Bluetooth), GWAN/SWAN (WWAN), SAUM/SSMS/SHDA (audio y LEDs de silencio).
  Además está la interfaz WMI de configuración de la BIOS de Lenovo (WMA1…WMAC/WQAx); se usa desde Windows.
- **Pruebas con YogaSMC (todo se regresó como estaba):**
  - Fn Lock (`FnlockMode`): OK.
  - Pausar carga (`setCMInhibitCharge`): OK, BICG 0x70 → 0x171 → 0x170.
  - Descarga forzada (`setCMForceDischarge`): **no aplica** en esta BIOS (BDSG se queda en 0x700).
  - Pitidos: la propiedad no existe en este modelo.
- **BateriaT470p** ahora también tiene: "Pausar la carga (aunque esté conectada)", "Fn Lock" y "Punto rojo de la tapa" (prendido 0x8A / apagado 0x0A / parpadeando 0xCA, método LED vía YogaSMC).

### 2026-11-21 04:35 - Arreglo de las "luces locas": respiración desconectada de Fn + Espacio
- **Problema:** había **15 copias** de `LuzTeclado respirar` corriendo al mismo tiempo. Cada cambio de luz por software (MLCS) hace que la BIOS mande el mismo aviso 0x1012 que Fn + Espacio, y YogaSMC no los distingue: solo marca con 0x10 los cambios de su propio temporizador (`backlightStimulation`).
  Así se formó un bucle: cambio → aviso → `ciclo` → otra respiración. La prueba de antes no lo mostró porque todavía no estaba conectado al evento.
- **Arreglo:**
  - Fn + Espacio regresa a lo normal (`Events > 1012` = acción `backlight`, `display` = false para que no salga el aviso en pantalla mientras respira).
  - LuzTeclado nuevo: `rapido` (160 ms), `medio` (380 ms), `lento` (750 ms) y `parar`. Al arrancar mata cualquier otra copia; solo cuenta procesos cuyo **programa** es LuzTeclado, nunca un `parar` ni una terminal que lo mencione.
  - Se corrigió un bloqueo: la lista de `ps` se leía después de esperarlo y se trababa.
  - Probado: rápido → medio → lento deja siempre 1 proceso; `parar` deja 0.
- BateriaT470p: submenú "Luz del teclado" con Normal / Respirar rápido / medio / lento, con palomita en el modo activo.

### 2026-11-21 04:50 - Panel a 75 Hz (preparado), apagar el panel con el brillo y GitHub
- **Panel:** BOE NV140FHM-N46, **14"** (no 15.6; se corrigió el fondo del menú). EDID: modo 1 = 60 Hz (141.40 MHz, 2142×1100 total); modo 2 = 48 Hz (113.12 MHz).
  6 bits por color por DisplayPort, así que a 75 Hz (176.72 MHz) le sobra ancho de banda.
- `pantalla/pantalla-hz.sh N` (sudo): override en `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-9e5/DisplayProductID-6b3`. Cambia el 2.º descriptor (48 Hz) por N Hz con el mismo blanking y corrige el checksum; 60 Hz sigue de principal. `quitar` lo borra. Probado sin instalar: 75.00 Hz exactos.
- **PantallaHz** (`~/.local/bin/PantallaHz`): pone el modo de más Hz del panel y abre una ventana de confirmación con cuenta regresiva de 30 s **en todas las pantallas**; si no se confirma, regresa al modo anterior. `PantallaHz 60` regresa sin preguntar. Sin el override hoy ve 48 y 60 Hz.
- **TeclaWindows:** si el brillo ya está al mínimo (DisplayServicesGetBrightness ≤ 0.02) y se aprieta bajar brillo, desactiva el panel interno (SLSConfigureDisplayEnabled, solo esta sesión) si hay otra pantalla; si no la hay, `pmset displaysleepnow`. Subir brillo lo prende.
  - Seguridades: al arrancar prende un panel que haya quedado apagado; si se desconecta la otra pantalla, prende el panel.
  - Escucha NX_SYSDEFINED (subtipo 8, teclas 2/3) y las teclas ADB 144/145.
  - Al recompilarla (firma ad-hoc nueva) macOS le quitó el permiso de Monitoreo de entrada: hay que volver a darlo.
- GitHub commit 471f0e4 (BateriaT470p, LuzTeclado, PantallaHz, TeclaWindows, fondo 14"). Copia de Windows actualizada.

### 2026-11-21 04:25 - Override de pantalla a 75 Hz
- `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-9e5/DisplayProductID-6b3` con el 2o descriptor del EDID cambiado a 75 Hz (antes 48 Hz). 60 Hz sigue de principal.
- Probar con `PantallaHz` (confirma en 30 s o regresa a 60). Quitar: `sudo bash ~/hackintosh-mac/pantalla/pantalla-hz.sh quitar` y reiniciar.

### 2026-11-21 04:25 - Menú EN VIVO y Diagnóstico grabados en EFI-MAC
- OpenCanopy.efi con panel EN VIVO (176128 bytes), Tools/DiagT470p.efi (94208 bytes) con entrada "Diagnostico" en Misc/Tools y fondo corregido.
- Respaldo de lo anterior: `BITACORA-MAC/respaldos/menu-vivo-antes-20261121-042511/` (OpenCanopy.efi, config.plist, Background.icns) y en ~/hackintosh-mac/respaldos/.
- ocvalidate: Completed validating /Volumes/EFI-MAC/EFI/OC/config.plist in 2 ms. No issues found.
- **Si el menú se traba o no arranca:** F12 → USB de OpenCore, y desde macOS `sudo bash ~/hackintosh-mac/menu-arranque/instalar-en-efi.sh revertir`.
  Desde Windows: copiar `menu-vivo-antes-20261121-042511/OpenCanopy.efi` a EFI\OC\Drivers\ y su config.plist a EFI\OC\.

### 2026-11-21 05:00 - Panel confirmado a 75 Hz; preparado lo de la TV
- **Panel a 75 Hz:** el override instalado expone 60 y 75 Hz y Andrew confirmó en la ventana de PantallaHz ("Confirmado: el panel se queda a 75 Hz").
  Un error mío regresó el panel a 60 Hz un momento; se volvió a poner con la confirmación de 30 s.
- **TV (HDMI):** Insignia/Best Buy "LCDTV" 2016, VendorID 0x859, ProductID 0x19. Nativa 1360×768 a 60.02 Hz (85.50 MHz). Acepta hasta 1080p60 (lo reduce).
  Declara 55–76 Hz verticales, 30–80 kHz horizontales y 170 MHz de reloj máximo. La extensión CEA anuncia YCbCr 4:4:4/4:2:2 (byte 3 = 0x73), y por eso macOS manda YCbCr (texto borroso, colores deslavados).
- `pantalla/tv-pantalla.sh rgb|N|quitar` (sudo): override `DisplayVendorID-859/DisplayProductID-19`. Quita YCbCr (0x73 → 0x43) para forzar RGB y, con N, pone 1360×768 a N Hz en el 2.º descriptor (75 Hz = 106.85 MHz, 59.6 kHz, dentro de los límites).
  Corrige los dos checksums. No hace falta reiniciar: basta con reconectar el HDMI. Probado sin instalar.
- PantallaHz: `PantallaHz tv` y `PantallaHz tv 60` hacen lo mismo con la pantalla externa.
- Límite del panel: el "margen de 15 Hz" es un promedio, no una regla. Se puede seguir probando 80/85 Hz con reinicio + confirmación, revisando que no se salte cuadros (testufo.com/frameskipping).

### 2026-11-21 04:35 - Override de la TV (75)
- `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-859/DisplayProductID-19`: sin YCbCr en el EDID (macOS manda RGB) + 1360x768 a 75 Hz como 2o modo.
- Quitar: `sudo bash ~/hackintosh-mac/pantalla/tv-pantalla.sh quitar` y reconectar el HDMI.

### 2026-11-21 05:15 - Las dos pantallas a 75 Hz, Arduino IDE con ESP32-S3 y eqMac
- **Pantallas:** laptop 1920×1080 a 75 Hz y TV 1360×768 a 75 Hz (con override RGB), confirmadas por Andrew.
  macOS las guardó en `~/Library/Preferences/ByHost/com.apple.windowserver.<UUID>.plist` (RefreshRate 75), así que se quedan al reiniciar. Andrew decide dejarlas en 75 (no subir más).
- **Arduino IDE 2.3.11** (notarizado por Arduino SA) en /Applications. `arduino-cli` 1.6.0 del IDE enlazado en `~/.local/bin`, con configuración en `~/.arduinoIDE/arduino-cli.yaml` (URL de Espressif; datos en ~/Library/Arduino15, sketches en ~/Documents/Arduino).
  - Núcleos: arduino:avr 1.8.8 (Uno) y esp32:esp32 4.0.0.
  - Librerías (sacadas de las notas de Obsidian): LiquidCrystal I2C, DHT sensor library + Adafruit Unified Sensor, OneWire, DallasTemperature, Adafruit Motor Shield (V1 = AFMotor y V2), RTClib, TinyGPSPlus, Adafruit NeoPixel y Adafruit BusIO.
  - Probado: compila un sketch para `esp32:esp32:esp32s3:PartitionScheme=app3M_fat9M_16MB,FlashSize=16M,PSRAM=opi,CDCOnBoot=cdc` (ESP32-S3 N16R8) y otro para `arduino:avr:uno`.
- **eqMac 1.9.2** (notarizado por Bitgapp) en /Applications: ecualizador para todo el sistema. El Atmos/Audio Espacial real solo funciona con AirPods.

### 2026-11-21 05:25 - Apps instaladas
- The Unarchiver (MacPaw, dl.devmate.com), IINA 1.5.1, AltTab 11.10.2, Hidden Bar 1.13.2 (consolelabs/dwarvesf) y AppCleaner 3.7. Todas notarizadas (verificado con spctl), en /Applications.
- AltTab: atajo Opción+Tab, que en esta laptop es Alt+Tab físico (por el cambio de Ctrl/Comando, Alt sigue siendo Opción). Pide permisos de Accesibilidad y Grabación de pantalla.

### 2026-11-21 12:10 - Suspensión con la tapa: funciona; ventilador en automático al dormir
- Prueba en vivo (monitor de AppleClamshellState + pmset log), sin la TV: 12:03:06 tapa cerrada → ~12:03:22 suspensión → 12:03:41 "Wake from Normal Sleep … power-button". **La suspensión funciona.**
  En la prueba anterior no se suspendió porque la TV estaba conectada con el cargador: macOS se queda en modo clamshell a propósito.
- Al abrir la tapa no despierta sola: hay que apretar una tecla o el botón de encendido (DriverReason XHC / power-button).
- Suspensión por inactividad: pmset `displaysleep 10`, `sleep 1`. Sin música ni descargas (aserciones PreventUserIdleSystemSleep), la pantalla se apaga a los 10 min y el sistema se suspende un momento después.
- **BateriaT470p:**
  - Al suspender pone el ventilador en automático (`FanSpeed` = 0x84, lo maneja el EC); 3 s después de despertar regresa al nivel guardado de YogaSMCNC (`FanLevel` 71 = 0x47 = Full).
  - Opción nueva "Suspender al cerrar la tapa aunque esté la TV" (apagada por defecto): si la tapa está cerrada y hay pantalla externa, hace `pmset sleepnow`.

### 2026-11-21 16:50 - Rendimiento: CPU medido, GPU, fluidez y contador de FPS
- **CPU medido** con prueba propia (`rendimiento/ghz`, cadena de sumas = 1 ciclo cada una): **2.9 GHz con 1 núcleo y 2.75 GHz con los 4**,
  cuando el i5-7300HQ da 3.5 / 3.1. macOS permite hasta 3.5 (`machdep.xcpm.hard_plimit_max_100mhz_ratio: 35`, CPUFriend cargado, sin aviso
  térmico en `pmset -g therm`), así que el freno viene de BIOS/EC (límite de watts PL1/PL2 o PROCHOT). Para saber cuál:
  `sudo bash ~/hackintosh-mac/rendimiento/medir-cpu.sh` (deja el resultado en `rendimiento/medicion-cpu.txt`).
- **GPU:** `rendimiento/gpu-efi.sh` (sudo) agrega a la IGPU `rps-control` = 1 y `framebuffer-unifiedmem` = 2048 MB. Respaldo y `revertir` incluidos. PENDIENTE de correr.
- **Fluidez** (sin sudo, `rendimiento/fluidez.sh`, con `revertir`): Reducir transparencia (quita el vidrio de Tahoe, aplica al cerrar sesión),
  `NSWindowResizeTime` 0.001, Mission Control 0.15 s, sin rebote del Dock. Valores de antes en `rendimiento/valores-antes.txt` (todos venían sin valor).
- **MedidorFPS** (`fps/main.swift` → `/Applications/MedidorFPS.app`): cuadrito en la esquina inferior izquierda de cada pantalla con FPS reales
  (ScreenCaptureKit cuenta los cuadros que WindowServer dibuja), uso de GPU (IOAccelerator) y CPU. Verde = fluido, amarillo = a medias, rojo = trabado, gris = nada se mueve.
  - ScreenCaptureKit nunca pasa de **60 cuadros/s** aunque el panel esté a 75 Hz (CVDisplayLink confirma **75.0 vsync/s**). Por eso al tope muestra "60+".
    CGDisplayStream ya no entrega cuadros en Tahoe y `SLSGetPerformanceData` no regresa datos.
  - Cuesta ~20 % de un núcleo de WindowServer cuando la pantalla se mueve (igual a 16 px que a 128 px). Se prende/apaga en BateriaT470p → "Mostrar FPS, GPU y CPU".
  - Necesita permiso de Grabación de pantalla (Ajustes → Privacidad y seguridad).
- **Procesos revisados:** RAM sobrada (sin swap, 85 % libre). WindowServer 16–38 % en reposo (vidrio + Tahoe en HD 630). VS Code ~30–60 % mientras Claude Code trabaja.
  iCloud (`bird`, `cloudd`, `fileproviderd`) escribió 2 GB cada uno en la sincronización inicial de anoche; ya está en 0 %. `bluetoothd` se reinició solo 2 veces hoy (SIGABRT, Intel BT en Tahoe).

### 2026-11-21 17:25 - Se veía feo y lento: contador de FPS apagado y transparencia de regreso
- Con MedidorFPS capturando + Safari (WebKit GPU 63 %) WindowServer llegó a 78 % y la carga a 13: la Mac casi no respondía.
- MedidorFPS apagado (`MostrarFPS` = false en BateriaT470p) y `reduceTransparency` borrado (no gustó cómo se ve). Se quedan las animaciones rápidas.
- El cambio de la GPU (`gpu-efi.sh`) NO se había aplicado; no tuvo que ver.

### 2026-11-21 17:25 - GPU HD 630: rps-control y 2 GB de memoria de video
- DeviceProperties de la IGPU: `rps-control` = 1 (WhateverGreen sube la GPU a su máximo con carga) y `framebuffer-unifiedmem` = 2048 MB (antes 1536).
- Respaldo: `BITACORA-MAC/respaldos/gpu-antes-20261121-172541/config.plist` y en ~/hackintosh-mac/respaldos/.
- ocvalidate: Completed validating /Volumes/EFI-MAC/EFI/OC/config.plist in 71 ms. No issues found.
- **Si la imagen falla:** `sudo bash ~/hackintosh-mac/rendimiento/gpu-efi.sh revertir`, o desde Windows copiar ese config.plist a EFI\OC\.

### 2026-11-21 17:35 - CORRECCIÓN: el CPU SÍ va al máximo
- `medir-cpu.sh` (powermetrics) con los 4 núcleos a tope: **3100 MHz en los 4**, limitado por `MAX_TURBO_LIMIT` (= el turbo máximo de fábrica
  del i5-7300HQ con 4 núcleos), 68 °C, 19 W, presión térmica Nominal. No hay freno de BIOS/EC.
- Mi prueba `ghz` estaba mal para esto: mide con el reloj de pared, y si otros procesos (Safari, WindowServer, powermetrics) le quitan turnos,
  sale más bajo (1.1 GHz aquí). Lo correcto es lo de powermetrics.
- GPU: `gpu-efi.sh` aplicado (ocvalidate sin problemas, respaldo `gpu-antes-20261121-172541`). Falta reiniciar.

### 2026-11-21 17:35 - Panel interno: imagen partida y "fantasma" → regresado a 60 Hz
- Mientras la laptop estaba sola (antes de aplicar gpu-efi.sh), la pantalla se apagó por inactividad y al despertar el panel quedó con la
  imagen partida en dos/repetida y con rayas (señal de 75 Hz que el panel no aguantó al reconectar).
- Después de reiniciar, el escritorio de macOS se seguía viendo "fantasma" encima del menú de OpenCore (que es firmware, sin drivers de macOS):
  retención de imagen en el LCD.
- Panel regresado a **60 Hz** con `PantallaHz 60`. Falta quitar el override: `sudo bash ~/hackintosh-mac/pantalla/pantalla-hz.sh quitar`.
  La TV se queda a 75 Hz (es otro aparato y no ha fallado).
- Para que se borre la retención: apagar por completo (no reiniciar) 30-60 min.
- Lección: el panel BOE de 14" no aguanta 75 Hz de forma confiable (sobre todo al despertar). Se queda en 60.

### 2026-11-21 17:32 - Override de pantalla quitado
- Se borró `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-9e5/DisplayProductID-6b3`.

### 2026-11-21 18:15 - Panel: sigue un poco de parpadeo y fantasma en el centro
- Después de 1 h apagada y sin batería, el centro del panel todavía parpadea un poco y deja algo de fantasma.
- Nueva herramienta `LimpiarPantalla [minutos]` (`pantalla/limpiar/main.swift` → `~/.local/bin/`): colores sólidos en pantalla completa,
  cambio suave cada 10 s (sin estrobo), evita que se apague la pantalla. Sirve para ver el defecto y para lavar la retención (brillo alto, 1-2 h).
- Pendiente: `sudo bash ~/hackintosh-mac/pantalla/pantalla-hz.sh quitar` (el override 9e5 de 75 Hz sigue instalado aunque el panel está a 60).

### 2026-11-21 18:13 - Override de pantalla quitado
- Se borró `/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-9e5/DisplayProductID-6b3`.

### 2026-11-21 19:50 - Todo al máximo: CPU EPP 0x00, panel fijo a 60 Hz
- Panel interno: override de 75 Hz borrado (copia en respaldos/override-panel-75hz-20261121-195041.plist). Se queda en 60 Hz. La TV sigue a 75 Hz.
- CPU: CPUFriendDataProvider con EPP **0x00** (máximo rendimiento, antes 0x20). Respaldo: `BITACORA-MAC/respaldos/cpu-epp-antes-20261121-195041/`.
- GPU: rps-control y 2 GB siguen en la EFI. `pmset -a lowpowermode 0`.
- ocvalidate: Completed validating /Volumes/EFI-MAC/EFI/OC/config.plist in 76 ms. No issues found.
- Deshacer CPU: `sudo bash ~/hackintosh-mac/rendimiento/todo-al-maximo.sh revertir`.

### 2026-11-21 19:00 - Medido: CPU y GPU al máximo
- Aplicado `todo-al-maximo.sh` y reiniciado. Verificado: EPP cargado = **0x00** (ioreg cf-frequency-data), panel a 60 Hz sin override (solo queda el de la TV, 859), VRAM 2048 MB.
- `powermetrics` NO sirve para la GPU en hackintosh (siempre "350 MHz / HW 0 %"). Medición propia `rendimiento/ghz-gpu` (FMA/s ÷ 192 FMA por ciclo de la HD 630):
  **180 G FMA/s ≈ 940 MHz mínimo real** (~1.05–1.1 GHz quitando el costo del ciclo), igual con el CPU al 100 %. A 350 MHz daría 67 G FMA/s → rps-control funciona.
- `rendimiento/ghz` corregido: ahora mide con el tiempo de CPU del hilo (antes reloj de pared, salía bajo si otros procesos le quitaban turnos).
  **3.0 GHz en los 4 núcleos**, igual con la GPU al 100 % (máximo de fábrica 3.1).
- `medir-todo.sh` estaba mal hecho (la carga de CPU terminaba antes de que midiera powermetrics); usar `ghz 4` y `ghz-gpu` en su lugar.
- Panel recuperado con `LimpiarPantalla` (el gris era lo que más se notaba).

### 2026-11-21 19:20 - GPU fija a 1.1 GHz: medido, no se puede sin kext propio
- `rendimiento/rampa-gpu`: después de 3 s sin trabajo, lotes cortos de ~3-5 ms. La GPU sube a ~900 MHz en 3-14 ms, pero entre lotes
  (cuando se queda unos ms sin trabajo) baja otra vez a 300-500 MHz. Con carga continua se queda en ~940+ (ver ghz-gpu).
- La frecuencia mínima la decide el driver de Apple (RPS). No hay opción en WhateverGreen, BIOS ni macOS para fijarla.
- Mantenerla arriba con una carga de fondo no sirve: el RPS solo sube si la GPU está ~85-95 % ocupada, así que la carga le quitaría la GPU a lo demás.
- Única vía: kext propio que escriba el registro de frecuencia mínima de la GPU (RP min, MMIO 0xA014 / softlimit). Experimental, riesgo de congelar la GPU; probar en USB.

### 2026-11-21 19:40 - GPU siempre al máximo: GPUDespierta
- Andrew notó que con la GPU a 1.1 GHz (durante las pruebas) el escritorio pasó de ~14-20 FPS a 60 al mover el mouse: con la GPU a 350 MHz el escritorio se siente lento.
- `rendimiento/gpu-despierta.swift` → `~/.local/bin/GPUDespierta 1.5 6`: pulsos de cálculo de 1.5 ms cada 6 ms (~20 % de la GPU, 2.9 % de un núcleo de CPU).
  Medido con su propio pulso: continuo = 647 MHz-equivalente (tope de ese cálculo); pausa 2 ms = 97 %, 4 ms = 93 %, 8 ms = 92 %, 16 ms = 87 % del tope.
- LaunchAgent `~/Library/LaunchAgents/com.andrew.gpudespierta.plist` (RunAtLoad + KeepAlive). Interruptor en BateriaT470p → "GPU siempre al máximo (1.1 GHz)"
  (apagar = `launchctl bootout` + `disable`, no vuelve al iniciar sesión).

### 2026-11-21 20:00 - FPS que "bajaban a 21": no era trabazón
- Medido con `rendimiento/fpslog` y `rendimiento/fps-mouse` (ignorando VS Code, moviendo el mouse por código):
  moviendo el mouse **60-61 parejo**; quieto 52-57; animación constante 60 con o sin GPUDespierta.
- Dos capturas de pantalla a la vez (MedidorFPS + otra medición) se reparten los cuadros: cada una ve ~30. Medir siempre con una sola.
- El contador mide cuadros NUEVOS: si nada cambia, macOS no dibuja y el número baja aunque todo vaya fluido.
- MedidorFPS ahora muestra **"reposo"** en gris si no hubo teclado/mouse en el último segundo y los FPS están bajos. Rojo/amarillo solo cuenta mientras se usa.

### 2026-11-21 20:50 - YouTube 1080p en Safari: "Se produjo un error" → VP9 apagado en Safari
- Reproducido con `rendimiento/prueba-youtube` (WebKit, el motor de Safari, con YouTube real): 480p = H.264 (`avc1`, formato 135) funciona;
  al subir a 1080p YouTube cambia a **VP9** (`vp09.00.51.08`, formato 303) → 0 cuadros → error y regresa a 480p.
- Causa: con el SMBIOS MacBookPro16,2 (Ice Lake) macOS dice que hay VP9 por hardware (`VTIsHardwareDecodeSupported(VP9)` = true),
  pero la HD 630 con el driver de Apple no lo decodifica. H.264 y HEVC sí van por hardware.
- Arreglo: VP9 apagado en Safari → YouTube manda 1080p60 en H.264 (`avc1.64002A`, formato 299).
  `defaults write com.apple.Safari "WebKitPreferences.vp9DecoderEnabled" -bool false` (= Ajustes → Avanzado → Feature Flags → "VP9 decoder").
  Medido: 1080p60 sin error, **6 cuadros perdidos de 1065**, GPU al 37 %. Se pierde 1440p/4K en YouTube (solo hay VP9/AV1).
- Con MedidorFPS prendido el mismo video perdía ~30 % de cuadros (la captura de pantalla compite): apagarlo para ver videos.
- Deshacer: `defaults delete com.apple.Safari "WebKitPreferences.vp9DecoderEnabled"`.

### 2026-11-21 21:30 - GraficaT470p.kext: kext propio para la GPU (experimental, sin instalar)
- Base: parche RPS control de WhateverGreen 1.7.1 (`kern_igfx_pm.cpp`). Fuentes en `kext-gpu/fuentes/` (WhateverGreen 1.7.1, Lilu 1.7.2, MacKernelSDK).
- Desensamblado `AppleIntelKBLGraphics` (OCLP-Mod, Tahoe): la frecuencia se escribe en 0xA008 desde `CS5::setGTFrequencyMMIO`
  (la llaman `submitExecList` y el temporizador `handleChangeFrequencyInterrupt`, que es el que la baja) y desde
  `IGHardwareRingBuffer::patchFrequencyRequest` (MI_LOAD_REGISTER_IMM en los comandos). El kext intercepta las dos y siempre pide RP0.
- Compilado sin Xcode (`kext-gpu/GraficaT470p/compilar.sh`, clang + MacKernelSDK + libkmodc++ + cc_kext). `kmutil libraries`: 295 símbolos
  del kernel 25.6 resueltos; los 12 de Lilu están exportados por el Lilu 1.7.2 de la EFI. ocvalidate OK con el kext después de WhateverGreen.
- Probar: `sudo bash ~/hackintosh-mac/kext-gpu/gpu-kext.sh listar` y luego `usb diskXsY` (copia EFI-MAC a la USB + kext). F12 → USB.
- Apagar si algo falla: boot-arg `-gt470poff`, o arrancar normal desde el disco (EFI-MAC no se toca hasta `gpu-kext.sh disco`).

### 2026-11-21 22:00 - GraficaT470p 1.1.0: también sin RC6 y con frecuencia real en ioreg
- Encontrado en el driver de Apple: opción interna `forceDisableRC6` (bit 25 de las banderas en IntelAccelerator+0x1148), que
  `IGTelemetryManager::operation` activa llamando `IntelAccelerator::SafeForceWake(true)` (referencia contada de "despierto").
- El kext ahora toma esa referencia cuando el acelerador ya publica `PerformanceStatistics`, la suelta en `kIOMessageSystemWillSleep`
  y la retoma al despertar (≤ 2 s). Así la GPU no se apaga entre trabajos ni tiene que volver a subir de frecuencia.
- ioreg `GraficaT470p`: "Frecuencia actual MHz" (RPSTAT1), "Estado GT" (0x138060), "Tiempo dormida % (RC6)" (0x138108), RC6, ganchos y bajadas evitadas.
- Boot-arg nuevo `-gt470prc6` (deja el RC6 como Apple). Sigue sin instalar: probar en USB con `kext-gpu/gpu-kext.sh`.

### 2026-11-21 22:15 - GraficaT470p revisado antes de la USB
- Mejoras de la revisión: candado (IOLock) entre tomar/soltar la referencia de despierto; también se suelta al **apagar y reiniciar**
  (no solo al dormir) para no causar shutdown stalls; al despertar espera 3 s antes de retomarla; chequeo de índice del kext igual que WhateverGreen.
- Verificado: clase `IntelAccelerator` registrada con `PerformanceStatistics`; `SafeForceWake(bool)` = `SafeForceWake(bool, 7)` (los 3 dominios);
  317 símbolos, 0 faltantes (kernel 25.6 + Lilu 1.7.2).
- USB `disk6s1` (OPENCORE, 15.9 GB): respaldo completo de su EFI en `respaldos/usb-OPENCORE-completa-20261121-210430/`.

### 2026-11-21 21:14 - GraficaT470p.kext en la USB para probar
- USB disk6s1 = copia de EFI-MAC + GraficaT470p (después de WhateverGreen). Respaldo de la USB: `respaldos/usb-OC-antes-gpu-kext-20261121-211232`.

### 2026-11-21 21:30 - GraficaT470p 1.1.0 PROBADO desde la USB: funciona
- Arrancado con F12 → USB (EFI-MAC + GraficaT470p). `kextstat`: com.andrew.GraficaT470p (1.1.0) cargado después de WhateverGreen.
- ioreg: Ganchos "CS5 + anillo", RC6 "APAGADO", Estado GT RC0, **Tiempo dormida 0 %**, **Frecuencia actual 1000 MHz** fija en todas las lecturas.
- **Corrección:** RP0 leído del chip = 20 → **1000 MHz**. La HD 630 del i5-7300HQ llega a 1.0 GHz (el i7-7700HQ a 1.1). Ya está en su máximo absoluto.
- "Bajadas evitadas" = 0 y "Último pedido de Apple" = 1000: con `rps-control` Apple ya pedía el máximo; lo que la bajaba era el **RC6** (se dormía entre trabajos).
- GPUDespierta apagado y deshabilitado (`launchctl disable`): ya no hace falta. FPS moviendo el mouse: 60 parejo, incluso con MedidorFPS + otra captura (antes 30).
- `rampa-gpu` no sirve para esto (lotes de 3 ms compiten con WindowServer); la medida buena es el registro RPSTAT1 que publica el kext.
- Falta: probar suspensión desde la USB y luego `sudo bash ~/hackintosh-mac/kext-gpu/gpu-kext.sh disco`.

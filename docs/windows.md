# Lo que se hizo desde Windows (14–17 nov 2026)

Notas originales de la parte de Windows: particiones, USB, mapa USB, parche del TrackPoint y la instalación de Tahoe. La guía limpia está en [instalacion.md](instalacion.md).


Resumen de la sesión del 14 y 15 de noviembre de 2026 (antes estaba abierta en `C:\`).

## El equipo
- **Lenovo ThinkPad 20J7 (T470p)**, i5-7300HQ (Kaby Lake), Intel HD 630, 16 GB de RAM.
- WiFi Intel AC 8265, Ethernet Intel I219-V, audio Realtek, touchpad Synaptics.
- SSD **Kingston SA400 de 480 GB** (Windows lo ve como 447 GB), en **GPT**.

## Cómo está el disco
| # | Partición | Tamaño | Qué es |
|---|---|---|---|
| 1 | MSR | 16 MB | Reservada de Windows |
| 2 | C: Windows | 447 GB | Sistema (unos 130 GB libres después de la limpieza) |
| 3 | SYSTEM FAT32 | 100 MB | **EFI de Windows. NO borrarla ni anexarla** |

La partición de 100 MB no es basura del dual boot de antes: es de donde arranca Windows.

## Por qué Windows no dejaba encoger C:
Lo bloquea **`pagefile.sys`** (el archivo de paginación), porque queda cerca del final del disco. Sin tocar nada, se le pueden quitar unos **75 GB** a C:.

## Plan (PENDIENTE: Andrew avisa cuándo)
1. Desactivar el pagefile y **reiniciar**.
2. Encoger C: lo necesario para:
   - **EFI nueva de 1 GB (FAT32) solo para macOS/OpenCore.** La de Windows no se toca.
   - **macOS de 60 GB** (lo que recomiendo) u 80 GB (para eso hay que liberar más espacio en C:).
3. **Volver a activar el pagefile automático** en cuanto termine. La vez pasada se olvidó y causó problemas.

Así quedaría: `[MSR][C: Windows][EFI mac 1GB][macOS][EFI Win 100MB]`

Ojo: el instalador de macOS a veces se queja porque la EFI de Windows mide menos de 200 MB. Si pasa, el plan B es agrandar esa EFI.

## Configuración del Hackintosh
- **macOS Monterey (12)**: el último que soporta Kaby Lake de forma nativa.
- **SMBIOS:** `MacBookPro14,3`
- **Guía:** Dortania OpenCore, sección "Laptop Kaby Lake". Usar de base una EFI de GitHub ("T470p OpenCore").
- **Kexts:** Lilu, VirtualSMC, WhateverGreen (HD 630), AppleALC (probar layout-id), IntelMausi, itlwm + HeliPort (o AirportItlwm), IntelBluetoothFirmware + BlueToolFixup, VoodooPS2/VoodooRMI.
- **No funciona:** el lector de huella.
- **BIOS:** apagar Secure Boot, SGX y la detección de cambios de hardware; VT-d apagado (o DisableIoMapper); arranque en UEFI only.

## Otras cosas que se vieron en la sesión
- **Pagefile:** tras el reinicio se volvió a activar en automático (unos 19 GB). Todo bien.
- **Proxy de headroom:** Claude Code manda todo por `http://127.0.0.1:8787` (configurado en `~/.claude/settings.json`). Si el proxy no arranca, Claude no abre y se queda reintentando. Cómo arreglarlo: correr `headroom proxy --port 8787` o quitar `ANTHROPIC_BASE_URL` del settings.
- **VS Code gastando ~6 GB de RAM y mucho CPU:**
  - Pylance (1.2 GB, ~22% de CPU) estaba escaneando **todo `C:\`**, porque la carpeta abierta era `C:\`. **Solución: abrir solo carpetas de proyecto** (por eso existe esta carpeta).
  - El Extension Host (3 GB) carga 43 extensiones. Conviene usar perfiles o deshabilitarlas por workspace (LaTeX, Arduino, C++, etc.).
  - Las conversaciones de Claude muy largas también suman. Abrir una sesión nueva de vez en cuando.

## Cambio de plan (15 nov 2026): Tahoe con la EFI del hermano
- Base: EFI de Tahoe de `hfoky/ThinkPad-T470s-OpenCore-configuration` (release Native-Wi-Fi-Sequoia, OC 1.0.7). Es de **T470s**; el hermano la usa con Tahoe.
- Original sin tocar en `efi-tahoe/extraido/`; la **corregida para T470p** está en `efi-t470p/EFI/`.
- Cambios hechos: ig-platform-id `0x591B0000` (HD 630) sin los parches de con1 de la T470s; AppleALC y USBMap (de la T470s) apagados; `alcid=3` quitado (en Tahoe el audio va con VoodooHDA); rename `_OSI→XOSI` apagado (no traía SSDT-XOSI); ROM = MAC del Ethernet `XX:XX:XX:XX:XX:XX`; borrada la carpeta EFI/APPLE.
- SMBIOS `MacBookPro16,2`.
- Pendiente: serial/MLB/UUID propios (GenSMBIOS), mapa USB con USBToolBox desde Windows, USB del instalador, particiones.
- 15 nov: SMBIOS propio generado con GenSMBIOS (ya en el config). Mapa USB hecho con USBToolBox: 10 puertos (HS 1,2,3,4,7,8 y SS 17-20; sin el 6 = huella). En la EFI: `USBToolBox.kext` 1.2.0 RELEASE + `UTBMap.kext`, cargados justo después de Lilu. USBMap y AppleALC de la T470s movidos a `kexts-quitados/`. Los SS 17-19 se emparejaron por suposición (no había memoria USB 3.0); si un puerto no va a 3.0 en macOS, revisar eso.
- 15 nov: USB instalador lista (Generic Flash Disk 16 GB, letra D:, FAT32 "OPENCORE", quedó en MBR porque Clear-Disk necesita admin; para UEFI da igual). Contiene `EFI/` (copia exacta de `efi-t470p/EFI`) + `com.apple.recovery.boot/` (Tahoe, `macrecovery -b Mac-CFF7D910A743CAAF -os latest`, verificada). Se borró el Hiren's que tenía.
- 15 nov: **Botones del TrackPoint** (en Sequoia: clic izq. y medio no iban, el derecho se quedaba pegado). Causa: touchpad Synaptics por **SMBus** (LEN2045, "Synaptics SMBus Driver" en Windows); VoodooPS2 solo no maneja bien los botones. Arreglo: **VoodooRMI 1.4.2 + VoodooSMBus 3.0** (el zip 1.4.3 trae VoodooSMBus vacío, roto), cargados después de VoodooPS2 en el orden del README; VoodooInput de VoodooPS2 apagado (se usa el de VoodooRMI, ambos 1.1.6). Respaldo previo: `herramientas/config.antes-voodoormi.plist`. USB D: actualizada.
- 16 nov: **Prueba de la USB OK**: OpenCore arranca, entra a la recuperación de macOS 26.6.2 (25G83), Utilidad de Discos ve el SSD (Windows, SYSTEM) y la USB. Touchpad y sus clics funcionan. **Sigue el bug del TrackPoint con VoodooRMI**: el botón izquierdo de arriba congela todo el puntero (incluso el ratón USB) y el medio y el derecho no hacen nada. Pendiente: diagnóstico desde la Terminal de la recuperación.
- Dato de Andrew: el mismo fallo de los botones del TrackPoint le pasa en **todas las distros de Linux** que probó (Ubuntu, Fedora, Arch, Pop!_OS); solo en Windows funcionan. O sea, no es de la EFI: es como manda los botones este touchpad/TrackPoint (o un detalle de hardware), y solo el driver de Synaptics para Windows lo resuelve.
- 16 nov: **Parche para que los botones del TrackPoint no congelen**. VoodooRMI no lo arregló, así que se apagó (VoodooRMI, VoodooSMBus, RMISMBus y su VoodooInput quedan en la carpeta pero desactivados) y se regresó a VoodooPS2 solo, con su VoodooInput. Causa en el código de VoodooPS2 2.3.7: `_lastPassthruButtons` (offset 0x658) se suma a cada reporte del touchpad, así que si nunca llega el "soltar", el clic izquierdo se queda pegado. Dos `Kernel > Patch` (Identifier `as.acidanthera.voodoo.driver.PS2Trackpad`): (1) `83e007`→`83e000` en synaptics_parse_passthru (botones del passthrough = 0; la bolita sigue moviendo el puntero); (2) `jb`→`jmp`, que se salta synaptics_parse_ext_btns. Probado con capstone sobre el binario. **Si se actualiza VoodooPS2, hay que revisar que los patrones sigan siendo los mismos.** Respaldo: `herramientas/config.antes-parche-trackpoint.plist`.
- 16 nov: **Parche del TrackPoint probado, funciona**: los botones de arriba ya no congelan nada y el touchpad va completo.
- Hardware confirmado desde Windows: i5-7300HQ, HD 630 (8086:591B), **sin NVIDIA**, audio Realtek **ALC298** (10EC:0298), SATA AHCI (sin NVMe), lector de tarjetas Realtek RTS522A (10EC:522A), WiFi AC 8265 (8086:24FD), I219-V, BIOS R0FET61W 1.41.
- Mejoras agregadas: Bluetooth (BlueToolFixup 2.7.2 con MinKernel 21, IntelBluetoothFirmware + IntelBTPatcher 2.4.0; en Tahoe es experimental), menú de arranque gráfico (OcBinaryData: Image, Font y Label; PickerVariant Acidanthera\GoldenGate). Respaldo: `herramientas/config.antes-bt-gui.plist`. USB sincronizada.
- AirDrop/Handoff: imposible con tarjetas Intel. Necesita una Broadcom (BCM94360NG, M.2 2230 A+E) + parche de OCLP; en Sequoia está probado, en Tahoe no se sabe.
- Cuando ya esté instalado: quitar `-v debug=0x100`, CPUFriend (con los datos generados en macOS), probar HDMI y el audio de VoodooHDA, y pensar en el lector SD.
- 16 nov: **Repaso general de la EFI**. OpenCore pasó a **1.0.8** (OpenCore.efi, BOOTx64, OpenRuntime, OpenCanopy, ResetNvramEntry, OpenShell; HfsPlus de OcBinaryData), WhateverGreen a **1.7.1** y VirtualSMC con sus plugins a **1.3.8**. Al config del hermano le faltaban 43 llaves y tenía errores (el parche de NVMe estaba mal armado, `Stratergy` mal escrito): se completó con el Sample 1.0.8 y **ocvalidate 1.0.8 ya no marca nada**. Además: `LauncherOption=Full` (para que Windows no se adueñe del arranque), `HideAuxiliary=true` (la recuperación y demás aparecen con Espacio), el bloqueo de IOSkywalkFamily apagado (solo sirve para Broadcom con OCLP; si algún día se pone Broadcom, volver a prenderlo) y VoodooRMI/VoodooSMBus fuera de la EFI. Respaldo completo de antes: `herramientas/EFI-respaldo-antes-oc108/`.
- Pendiente para Windows: hora en UTC (`RealTimeIsUniversal=1`, necesita admin) para que no se desfase el reloj con macOS.
- 16 nov: DSDT sacado del registro de Windows (`acpi/DSDT.aml`, LENOVO SKL). Lo que se vio: EC en `\_SB.PCI0.LPCB.EC` (los SSDT que lo usan están bien), GFX0 sí existe (sirve SSDT-PNLF), solo hay **BAT0, no hay BAT1**. **SSDT-BATC apagado**: es de la T470s (dos baterías) y llama a BAT1 sin `CondRefOf`, lo que daría errores de ACPI y dejaría sin batería. SSDT-EC-USBX solo crea el EC falso si no existe uno real, así que no choca. Hay 28 usos de GPRW: si se despierta solo al dormirlo, toca SSDT-GPRW.
- 17 nov: Pasos del disco y la instalación escritos en `PASOS-DISCO-E-INSTALACION.txt` (copias en el Escritorio y en la USB). Plan: encoger 81 GB (EFI-MAC de 1 GB + MACOS exFAT de 80 GB con diskpart), copiar la EFI con robocopy, entrada de arranque con bcdedit (path \EFI\OC\OpenCore.efi), volver a activar el pagefile y dejar la hibernación apagada.
- 17 nov 00:52: **PAGEFILE APAGADO** (AutomaticManagedPagefile=False, sin PageFileSetting) y **hibernación apagada** (`powercfg /h off`, a propósito, se queda así). Falta reiniciar. **Hay que volver a activarlo** después de crear las particiones: `REACTIVAR-PAGEFILE.bat` en el Escritorio (pide admin y reinicia).
- 17 nov 01:03: **PARTICIONES HECHAS** (script `herramientas/particionar.ps1`, registro en `particionar.log`). Disco ahora: `#1 MSR 16MB | #2 C: 365.9 GB | #4 EFI-MAC 1 GB (ESP, FAT32, sin letra, con la EFI copiada: 530 archivos) | #5 MACOS 80 GB exFAT | #3 SYSTEM 100 MB (Windows, sin tocar)`. Entrada de firmware "OpenCore" `{CODIGO-DE-BCDEDIT}` → `\EFI\OC\OpenCore.efi`, puesta primero en el displayorder. **Pagefile automático reactivado (True)**; hibernación apagada a propósito. Sigue: reiniciar e instalar Tahoe en MACOS (paso 6 del TXT).
- 17 nov 01:30: Primer arranque del instalador desde el OpenCore del disco → **kernel panic por IntelBTPatcher 2.4** (`com.zxystd.IntelBTPatcher` en el backtrace, proceso bluetoothd, Tahoe 25G83). Se **apagaron los 3 kexts de Bluetooth** (IntelBTPatcher, IntelBluetoothFirmware, BlueToolFixup) → igual que la prueba anterior que sí arrancó. Actualizado en la USB y en EFI-MAC. OJO: después de reiniciar, Windows **cambió la numeración**: ahora EFI-MAC es la **#3** y MACOS la **#4**; la de Windows de 100 MB es la #5. Para montar EFI-MAC, buscarla por tamaño (1 GB y tipo System), no por número: `herramientas/actualizar-efi-disco.ps1`.
- 17 nov: **macOS Tahoe INSTALADO** en MACOS (80 GB). Cuenta de usuario creada e inició sesión con su Apple ID (con el serial propio de GenSMBIOS). OpenCore sigue primero en el arranque (y LauncherOption=Full agregó su propia entrada "OpenCore"). En la BIOS quedan entradas viejas de Fedora y Kali (de antes, no estorban). Pendientes en macOS: quitar `-v debug=0x100`, HeliPort para el WiFi, probar sleep, HDMI, audio, brillo y batería, CPUFriend, y montar la EFI en macOS.


---

## Pasos originales (texto plano)

```text
=====================================================================
  HACKINTOSH T470p - PASOS: DISCO + INSTALAR macOS TAHOE
  (hecho el 17 nov 2026, con tu EFI ya probada)
=====================================================================

COMO ESTA HOY TU DISCO (Kingston 480 GB):
  [MSR 16MB][ C: Windows 447 GB, 141 GB libres ][ SYSTEM 100 MB = EFI de Windows ]

COMO VA A QUEDAR:
  [MSR][ C: Windows ~366 GB ][ EFI-MAC 1 GB ][ macOS 80 GB ][ SYSTEM 100 MB ]

REGLAS DE ORO
  * La particion SYSTEM de 100 MB (EFI de Windows) NO SE TOCA. Nunca.
  * En el instalador de macOS NUNCA borres el disco completo "KINGSTON",
    solo la particion que se llame MACOS.
  * Respalda antes lo que no quieras perder (fotos, tareas) en otro lado.
  * La USB "OPENCORE" no la borres: es tu llave para arrancar macOS
    y tu salvavidas si algo falla.


---------------------------------------------------------------------
PASO 1 - APAGAR PAGEFILE E HIBERNACION (Windows)
---------------------------------------------------------------------
Estos dos archivos se quedan "pegados" al final de C: y no dejan encogerla.

 1. Tecla Windows + R  ->  escribe  sysdm.cpl  -> Enter
 2. Pestana "Opciones avanzadas" -> en Rendimiento, boton "Configuracion"
 3. Pestana "Opciones avanzadas" -> en Memoria virtual, boton "Cambiar"
 4. QUITA la palomita de "Administrar automaticamente el tamano..."
 5. Selecciona C:, marca "Sin archivo de paginacion" -> boton "Establecer"
    -> "Si" al aviso -> Aceptar -> Aceptar -> Aceptar.
 6. Abre CMD como administrador
    (Inicio -> escribe cmd -> clic derecho -> Ejecutar como administrador)
    y escribe:

        powercfg /h off

    (Apaga la hibernacion y el "Inicio rapido". Para el dual boot es MEJOR
     dejarlo apagado para siempre: si no, Windows deja el disco "trabado".)
 7. REINICIA la compu.

 OJO: sin pagefile pueden salir errores de "memoria insuficiente" en
 programas pesados (por eso Claude no abre). Es normal y temporal.
 No abras nada pesado hasta el PASO 5.


---------------------------------------------------------------------
PASO 2 - ENCOGER C: (Windows)
---------------------------------------------------------------------
 1. Windows + R  ->  diskmgmt.msc  -> Enter
 2. Clic derecho en "Windows (C:)" -> "Reducir volumen..."
 3. En "Tamano del espacio que desea reducir, en MB" escribe:

        82944        (= 1 GB para EFI-MAC + 80 GB para macOS)

    Si NO te deja tanto (el maximo que te ofrece es menor), pon:

        62464        (= 1 GB + 60 GB, lo minimo recomendable)

    Si ni eso te deja: apaga "Proteccion del sistema" para C:
    (sysdm.cpl -> Proteccion del sistema -> Configurar -> Desactivar),
    reinicia y vuelve a intentar.
 4. Clic en "Reducir". Te queda un bloque negro "No asignado" despues de C:.
    NO le hagas nada desde aqui.


---------------------------------------------------------------------
PASO 3 - CREAR EFI-MAC (1 GB) Y LA PARTICION MACOS (Windows)
---------------------------------------------------------------------
 1. Abre CMD como administrador y escribe, UNA linea a la vez:

        diskpart
        list disk

    -> Fijate cual es el KINGSTON (~447 GB). Casi seguro es "Disco 0".

        select disk 0
        list partition

    -> Debes ver: Reservado (MSR), Principal (C:, el grande), Sistema (100 MB).
       Si no ves eso, ESCRIBE  exit  Y PARA AQUI.

        create partition efi size=1024
        format quick fs=fat32 label="EFI-MAC"
        assign letter=S
        create partition primary
        format quick fs=exfat label="MACOS"
        list partition
        exit

    -> Ahora debe haber: MSR, C:, Sistema 1024 MB (nueva), Principal ~80 GB
       (MACOS, nueva) y Sistema 100 MB (la de Windows, intacta).

 NO cierres la ventana de CMD (admin), la usas en el paso 4.


---------------------------------------------------------------------
PASO 4 - COPIAR TU EFI AL DISCO Y PONER OPENCORE DE ARRANQUE
---------------------------------------------------------------------
 (La USB OPENCORE conectada. Revisa en "Este equipo" que siga siendo D:.
  Si tiene otra letra, cambia la D: de abajo por la que tenga.)

 1. En el CMD de administrador:

        robocopy D:\EFI S:\EFI /E

    Al final debe decir "Copiados" con ~530 archivos y 0 "ERROR".

 2. Crear la entrada de OpenCore en la BIOS (en el mismo CMD admin):

        bcdedit /copy {bootmgr} /d "OpenCore"

    -> Te responde algo como:
       "La entrada se copio correctamente en {xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}"
       COPIA ese codigo con todo y llaves { }. Abajo lo llamo {CODIGO}.

        bcdedit /set {CODIGO} path \EFI\OC\OpenCore.efi
        bcdedit /set {CODIGO} device partition=S:
        bcdedit /set {fwbootmgr} displayorder {CODIGO} /addfirst

    Asi la compu prende primero en OpenCore, y ahi eliges Windows o macOS.
    Si algun dia OpenCore no arranca: F12 al prender -> "Windows Boot Manager".

 3. Quitarle la letra S: (para que Windows no la vea ni la toque):

        diskpart
        select volume S
        remove letter=S
        exit


---------------------------------------------------------------------
PASO 5 - REACTIVAR EL PAGEFILE (IMPORTANTE, NO LO OLVIDES)
---------------------------------------------------------------------
 1. Windows + R -> sysdm.cpl -> Opciones avanzadas -> Rendimiento
    "Configuracion" -> Opciones avanzadas -> Memoria virtual "Cambiar"
 2. PON la palomita en "Administrar automaticamente el tamano del archivo
    de paginacion para todas las unidades".
 3. Aceptar -> Aceptar -> Aceptar -> REINICIA.
 (La hibernacion la dejamos apagada a proposito.)

 Extra recomendado (para que el reloj no se desfase 6 horas con macOS),
 en CMD como administrador:

        reg add HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation /v RealTimeIsUniversal /t REG_DWORD /d 1 /f

 Despues de reiniciar ya deberias poder abrir Claude otra vez.
 -> Si puedes, AVISAME AQUI antes de instalar macOS y reviso que el disco
    haya quedado bien. Si no puedes, sigue con el paso 6.


---------------------------------------------------------------------
PASO 6 - INSTALAR macOS TAHOE
---------------------------------------------------------------------
 ANTES: conecta el CABLE DE RED (Ethernet) al dock o a la laptop.
 El instalador baja macOS de internet y el WiFi NO funciona en el
 instalador (solo despues, con HeliPort). Sin cable no va a poder.

 1. Reinicia. Ya deberia salir el menu de OpenCore (el bonito, con iconos).
    Para arrancar desde la USB: F12 al prender -> la USB.
 2. En el menu de OpenCore: si NO ves el instalador, aprieta la BARRA
    ESPACIADORA para mostrar las opciones ocultas. Elige el de "(dmg)" /
    "macOS Base System".
 3. Espera la pantalla de "Utilidades de macOS" (el texto blanco es normal).

 4. FORMATEAR LA PARTICION (con cuidado):
    - Abre "Utilidad de Discos".
    - Menu de arriba: Visualizacion -> "Mostrar todos los dispositivos".
    - En la lista de la izquierda, dentro del KINGSTON, selecciona
      la particion "MACOS" (~80 GB, exFAT).
        X  NO el disco "KINGSTON..." de hasta arriba
        X  NO "Windows", NO "EFI-MAC", NO "SYSTEM"
    - Boton "Borrar":
        Nombre:   Macintosh HD
        Formato:  APFS
      -> "Borrar". Al terminar, cierra Utilidad de Discos.
    - Si sale error de "MediaKit" o de espacio en la EFI: NO insistas,
      toma foto y para. (Es por la EFI de Windows de 100 MB; tiene arreglo.)

 5. "Reinstalar macOS Tahoe" -> Continuar -> acepta -> elige "Macintosh HD".
    Tarda 30-90 min y se REINICIA varias veces.

 6. En CADA reinicio: si no sale el menu de OpenCore, F12 -> la USB.
    En el menu elige:
      - "macOS Installer" (o algo parecido) mientras se este instalando,
      - y al final "Macintosh HD".
    Si te deja elegir y te da duda: el que NO diga Windows ni dmg.

 7. Configuracion inicial de macOS: pais, idioma, usuario.
    - Apple ID / iCloud: SALTALO por ahora ("Configurar despues").
      Lo hacemos juntos despues de revisar que todo este bien.

 Si algo se traba mas de 10 min o sale un "panic": FOTO a la pantalla
 completa y me la mandas.


---------------------------------------------------------------------
PASO 7 - YA CON macOS ARRIBA
---------------------------------------------------------------------
 1. Prueba que arranque SIN la USB: quitala, reinicia, deberia salir
    OpenCore desde el disco (por el paso 4). Si no sale, F12 y elige
    "OpenCore". Si tampoco, con la USB funciona igual: me avisas.
 2. WiFi: baja HeliPort (github.com/OpenIntelWireless/HeliPort -> Releases),
    abrelo y conectate a tu red desde su icono en la barra de arriba.
 3. Abre Claude (o me escribes desde Windows) y seguimos con:
      - quitar el texto blanco del arranque (-v),
      - sleep, HDMI, bateria (CPUFriend), teclas Cmd/Alt,
      - iCloud con tu serial propio.


---------------------------------------------------------------------
SI ALGO SALE MAL - COMO REGRESAR A WINDOWS
---------------------------------------------------------------------
 * F12 al prender -> "Windows Boot Manager". Siempre debe estar ahi.
 * Nada de estos pasos toca la particion de Windows ni su EFI de 100 MB,
   asi que Windows debe seguir arrancando pase lo que pase.
 * Si OpenCore arranca primero y no te gusta: en la BIOS (F1) ->
   Startup -> Boot, sube "Windows Boot Manager" hasta arriba.
=====================================================================

```

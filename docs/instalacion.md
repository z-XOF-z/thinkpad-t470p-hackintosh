# Guía de instalación — ThinkPad T470p · macOS Tahoe · dual boot con Windows

> Probado el 17–21 nov 2026 con macOS Tahoe 26.7.3 (25G342) y OpenCore 1.0.8.
> Respalda tus datos antes de tocar particiones.

## 0. Lo que necesitas
- Una T470p con Windows ya instalado (GPT/UEFI).
- Una USB de 16 GB.
- Internet: **cable de red** o **iPhone conectado por USB** (Compartir Internet). El WiFi también puede funcionar en el instalador, pero no lo des por hecho.
- La carpeta que arma [`instalar.py`](../instalar.py): `EFI/` + `com.apple.recovery.boot/`.

## 1. BIOS (F1 al prender)
| Opción | Valor |
|---|---|
| Security → Secure Boot | **Disabled** |
| Security → Intel SGX | **Disabled** |
| Security → Device Guard | **Disabled** |
| Security → Virtualization → VT-d | da igual (`DisableIoMapper` ya está) |
| Config → "Detect hardware change" | Off |
| Startup → UEFI/Legacy Boot | **UEFI Only**, CSM off |

## 2. Hacer espacio desde Windows
**Reglas de oro**
- La partición **SYSTEM de 100 MB** (EFI de Windows) **no se toca nunca**.
- En el instalador de macOS **nunca** borres el disco completo, solo la partición MACOS.

1. Apaga el pagefile y la hibernación (si no, Windows no deja encoger `C:`):
   - `sysdm.cpl` → Opciones avanzadas → Rendimiento → Configuración → Opciones avanzadas → Memoria virtual → Cambiar → quitar "Administrar automáticamente" → `C:` "Sin archivo de paginación" → Establecer.
   - CMD como administrador: `powercfg /h off` (apaga también el *Inicio rápido*; **déjalo apagado para siempre**, es requisito para escribir en NTFS desde macOS).
   - Reinicia.
2. `diskmgmt.msc` → clic derecho en `C:` → **Reducir volumen** → `82944` MB (1 GB EFI + 80 GB macOS). Mínimo razonable: `62464`.
3. CMD como administrador:
   ```
   diskpart
   list disk
   select disk 0
   list partition
   create partition efi size=1024
   format quick fs=fat32 label="EFI-MAC"
   assign letter=S
   create partition primary
   format quick fs=exfat label="MACOS"
   exit
   ```
4. Copia la EFI y crea la entrada de arranque de OpenCore (USB en `D:`):
   ```
   robocopy D:\EFI S:\EFI /E
   bcdedit /copy {bootmgr} /d "OpenCore"
   bcdedit /set {CODIGO} path \EFI\OC\OpenCore.efi
   bcdedit /set {CODIGO} device partition=S:
   bcdedit /set {fwbootmgr} displayorder {CODIGO} /addfirst
   ```
   (`{CODIGO}` es lo que te devuelve el `bcdedit /copy`.) Luego quita la letra: `diskpart` → `select volume S` → `remove letter=S`.
5. Vuelve a activar el pagefile automático y reinicia. **No vuelvas a prender la hibernación.**
6. Hora igual en los dos sistemas (CMD admin):
   ```
   reg add HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation /v RealTimeIsUniversal /t REG_QWORD /d 1 /f
   ```

> Si OpenCore algún día no arranca: **F12** → *Windows Boot Manager*. Nada de esto toca Windows.

## 3. Instalar macOS
1. F12 → la USB. En el menú de OpenCore aprieta **Espacio** para ver las opciones ocultas y elige *macOS Base System (dmg)*.
2. Utilidad de Discos → Visualización → **Mostrar todos los dispositivos** → selecciona **solo** la partición `MACOS` → Borrar → nombre `Macintosh HD`, formato **APFS**.
3. Reinstalar macOS Tahoe → `Macintosh HD`. Tarda 30–90 min y reinicia varias veces: en cada reinicio elige *macOS Installer* y al final *Macintosh HD*.
4. Configura tu usuario. Inicia sesión con tu Apple ID **solo si generaste tu propio SMBIOS** (lo hace `instalar.py`).

## 4. Post-instalación (en este orden)

### 4.1 Audio: root patch con OCLP-Mod
Tahoe ya no trae `AppleHDA.kext`; sin él, AppleALC no da sonido. La EFI ya trae lo necesario (`AMFIPass`, `csr-active-config 030A0000`, `-amfipassbeta`, `SecureBootModel Disabled`).
1. En el menú de OpenCore haz **Reset NVRAM** una vez (para que tome el SIP de la EFI). Comprueba con `csrutil status`.
2. Apaga **FileVault** (Ajustes → Privacidad y seguridad) y espera a que termine de desencriptar.
3. Instala el **KDK** que coincida con tu versión exacta (por ejemplo 25G342) de [dortania/KdkSupportPkg](https://github.com/dortania/KdkSupportPkg/releases).
4. Instala [OCLP-Mod](https://github.com/laobamac/OCLP-Mod) 3.1.9 → *Root patch* → aplica los parches → reinicia.
5. **Importante:** OCLP-Mod también mete un parche de WiFi Intel viejo (frameworks de macOS 13) que **rompe** el WiFi nativo de AirportItlwm Tahoe (0 redes, `isDriverAvailable=0`). Quítalo y deja solo el audio:
   ```
   sudo bash scripts/macos/quitar-parche-wifi-oclp.sh
   ```
   Reinicia. Vuelve a hacerlo cada vez que apliques el root patch.
6. Audio con **layout-id 29** (`1D000000`, ya en la EFI). Con el 47 macOS "suena" pero la bocina no.
7. Al **actualizar macOS** el root patch se pierde: necesitas el KDK nuevo, repetir el paso 4 y el script del paso 5. Por eso conviene apagar las actualizaciones automáticas.

### 4.2 WiFi y Bluetooth
- WiFi nativo con **AirportItlwm Tahoe 2.4.0** (ya activo en la EFI; `itlwm.kext` queda apagado). Te conectas desde el icono normal de WiFi y funciona Ubicación.
- Si renombraste el servicio, el WiFi puede llamarse "Ethernet 2": `networksetup -renamenetworkservice "Ethernet 2" "Wi-Fi"`.
- Bluetooth: IntelBluetoothFirmware 2.5.3 + BlueToolFixup. **IntelBTPatcher se queda apagado** (con la 2.4 daba kernel panic).
- AirDrop solo funciona de Mac → iPhone; al revés no (la Intel 8265 no tiene AWDL). Alternativa: [LocalSend](https://localsend.org).

### 4.3 Apple Music / TV (DRM)
`unfairgva=7` en boot-args (ya en la EFI). Con `=1` las canciones se quedan en 0:00.

### 4.4 HDMI
Parche de framebuffer `con1` como HDMI (ya en la EFI) + `igfxonln=1` para que la pantalla se detecte al arrancar sin desconectarla.

### 4.5 Teclas Fn y ventilador (YogaSMC)
1. Instala la app [YogaSMCNC 1.5.3](https://github.com/zhen-zen/YogaSMC/releases) (la del kext que ya está en la EFI) y agrégala a los ítems de inicio (su opción "Start at login" no basta en Tahoe).
2. `SSDT-ECRW.aml` (ya en la EFI) deja que YogaSMC escriba en el EC (`EC Capability = RW`): el menú de YogaSMCNC muestra el ventilador con **Auto / Full**.
3. Para que la tecla ⭐ abra una app: `defaults write org.zhen.YogaSMC Events -dict ...` (ejemplo completo en `docs/bitacora.md`).

### 4.6 CPU y energía
- CPUFriend + `CPUFriendDataProvider.kext` (perfil del MacBookPro16,2 con EPP `0x20`): sube a turbo más rápido. Ya en la EFI.
- `sudo pmset -a hibernatemode 0 standby 0 autopoweroff 0 powernap 0` y borra `/var/vm/sleepimage`.

### 4.7 Lector SD
RealtekCardReader 0.9.8 + RealtekCardReaderFriend 1.0.5 (ya en la EFI). Si suspendes con la tarjeta puesta, sácala y vuelve a meterla al despertar.

### 4.8 Escribir en el disco de Windows (NTFS)
1. Instala [macFUSE 5.5](https://github.com/macfuse/macfuse/releases) y da permiso al kext en Privacidad y seguridad (pide reiniciar).
2. Compila ntfs-3g (ver `scripts/macos/README.md`) o usa el binario de tu preferencia en `/usr/local/bin/ntfs-3g`.
3. `scripts/macos/montar-windows.sh` monta `/Volumes/Windows` con escritura (primero el kext, luego FSKit) y nunca deja dos montajes encimados. Un LaunchDaemon lo corre al arrancar.
4. ntfs-3g **se niega a escribir** si Windows quedó hibernado: apaga Windows siempre con *Apagar*.

### 4.9 Comodidad
- Ctrl como en Windows: `hidutil` (Ctrl ↔ Comando) en un LaunchAgent — ver `extras/teclado/`.
- Distribución **Latinoamericana (Windows)** con AltGr+Q = @: `extras/teclado/generar-latam.py`.
- Tecla Windows sola = abrir Apps: `extras/tecla-windows/`.
- Inicio/Fin como en Windows: `~/Library/KeyBindings/DefaultKeyBinding.dict` (en `extras/teclado/`).
- Monitor en la barra: [Stats](https://github.com/exelban/stats).

## 5. Si algo sale mal
- **No arranca después de un cambio en la EFI:** desde Windows, monta EFI-MAC (`diskpart`, la partición de 1 GB) y restaura el `config.antes-*.plist` que corresponda (cada cambio de la bitácora dice cuál).
- **No arranca después del root patch:** Recovery → Terminal → `bless --mount /Volumes/Macintosh\ HD --last-sealed-snapshot`.
- **Kernel panic al arrancar:** agrega `-v` a boot-args para ver dónde se detiene; agrega `-x` para modo seguro.
- Siempre puedes entrar a Windows con **F12 → Windows Boot Manager**.

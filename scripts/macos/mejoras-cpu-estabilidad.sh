#!/bin/bash
# 1) CPUFriend 1.3.0 + CPUFriendDataProvider (perfil MacBookPro16,2 con EPP 0x80 -> 0x20: el CPU sube rapido a turbo).
# 2) Apaga la instalacion automatica de actualizaciones de macOS (una actualizacion borra el root patch del audio).
# 3) Revisa que los parches del TrackPoint sigan activos (no los toca).
# 4) Menu de OpenCore: Timeout 0 (espera a que elijas). USB: SS04 como USB 3 en UTBMap.
# 5) Revisa (solo lectura) de donde sale la entrada "EFI" del menu. 6) Copia la BITACORA a EFI-MAC.
# Uso: sudo bash ~/hackintosh-mac/mejoras-cpu-estabilidad.sh            (aplica)
#      sudo bash ~/hackintosh-mac/mejoras-cpu-estabilidad.sh revertir   (apaga CPUFriend y el lector SD en el config)
# Tambien: lector SD Realtek RTS522A (RealtekCardReader 0.9.8 + RealtekCardReaderFriend 1.0.5).
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo con sudo"; exit 1; }
MODO="${1:-aplicar}"
[[ "$MODO" = aplicar || "$MODO" = revertir ]] || { echo "Uso: sudo bash $0 [revertir]"; exit 1; }
YO=/Users/TU_USUARIO
LOC="$YO/hackintosh-mac"
BIT="$LOC/BITACORA.md"
CF="$LOC/descargas/cpufriend"
SD="$LOC/descargas/sd/x"
STAMP=$(date +%Y%m%d-%H%M%S)
log(){ echo "$*"; echo "$*" >> "$BIT"; }

# --- Montar EFI-MAC (por nombre, nunca la de Windows) ---
DEV=""
for d in $(diskutil list disk0 | awk '/EFI/ {print $NF}'); do
  name=$(diskutil info "$d" | awk -F': *' '/Volume Name/ {print $2}')
  [ "$name" = "EFI-MAC" ] && DEV=$d
done
[ -n "$DEV" ] || { echo "No encontre EFI-MAC. No toco nada."; exit 1; }
diskutil mount "$DEV" >/dev/null
MP=$(diskutil info "$DEV" | awk -F': *' '/Mount Point/ {print $2}')
OC="$MP/EFI/OC"; CFG="$OC/config.plist"
[ -f "$CFG" ] || { echo "No hay config.plist en $MP"; exit 1; }
if [ "$MODO" = aplicar ]; then
  [ -d "$CF/zip/CPUFriend.kext" ] && [ -f "$CF/CPUFriendDataProvider.kext/Contents/Info.plist" ] || { echo "Faltan los kexts en $CF"; exit 1; }
  [ -d "$SD/RealtekCardReader.kext" ] && [ -d "$SD/RealtekCardReaderFriend.kext" ] || { echo "Faltan los kexts del lector SD en $SD"; exit 1; }
  [ -f "$LOC/acpi-nuevo/SSDT-ECRW.aml" ] || { echo "Falta $LOC/acpi-nuevo/SSDT-ECRW.aml"; exit 1; }
  [ -f "$LOC/descargas/ntfs/macFUSE-5.5.0.pkg" ] && [ -x "$LOC/descargas/ntfs/bin/ntfs-3g" ] || { echo "Faltan macFUSE o ntfs-3g en $LOC/descargas/ntfs"; exit 1; }
fi

# --- Respaldo ---
BK="config.antes-cpufriend-$MODO-$STAMP.plist"
mkdir -p "$MP/BITACORA-MAC/respaldos" "$LOC/respaldos"
cp "$CFG" "$OC/$BK"; cp "$CFG" "$MP/BITACORA-MAC/respaldos/$BK"; cp "$CFG" "$LOC/respaldos/$BK"

# --- Copiar kexts ---
if [ "$MODO" = aplicar ]; then
  for k in CPUFriend.kext CPUFriendDataProvider.kext RealtekCardReader.kext RealtekCardReaderFriend.kext; do
    if [ -d "$OC/Kexts/$k" ]; then
      mkdir -p "$MP/BITACORA-MAC/respaldos/kexts-cpufriend-antes-$STAMP"
      mv "$OC/Kexts/$k" "$MP/BITACORA-MAC/respaldos/kexts-cpufriend-antes-$STAMP/"
    fi
  done
  cp -R "$CF/zip/CPUFriend.kext" "$OC/Kexts/"
  cp -R "$CF/CPUFriendDataProvider.kext" "$OC/Kexts/"
  cp -R "$SD/RealtekCardReader.kext" "$SD/RealtekCardReaderFriend.kext" "$OC/Kexts/"
  cp "$LOC/acpi-nuevo/SSDT-ECRW.aml" "$OC/ACPI/"
fi

# --- Editar Kernel/Add y revisar los parches del TrackPoint ---
CAMBIOS=$(/usr/bin/python3 -I - "$CFG" "$MODO" <<'PY'
import plistlib, sys
cfg, modo = sys.argv[1], sys.argv[2]
with open(cfg, 'rb') as f: p = plistlib.load(f)
add = p['Kernel']['Add']; out = []
def idx(n):
    for i, k in enumerate(add):
        if k.get('BundlePath') == n: return i
    return None
ent = {
 'CPUFriend.kext': {'Arch':'x86_64','BundlePath':'CPUFriend.kext','Comment':'CPUFriend 1.3.0 (acidanthera)','Enabled':True,
   'ExecutablePath':'Contents/MacOS/CPUFriend','MaxKernel':'','MinKernel':'','PlistPath':'Contents/Info.plist'},
 'CPUFriendDataProvider.kext': {'Arch':'x86_64','BundlePath':'CPUFriendDataProvider.kext','Comment':'Perfil MBP16,2 con EPP 0x20 (rendimiento)',
   'Enabled':True,'ExecutablePath':'','MaxKernel':'','MinKernel':'','PlistPath':'Contents/Info.plist'},
 'RealtekCardReader.kext': {'Arch':'x86_64','BundlePath':'RealtekCardReader.kext','Comment':'Lector SD RTS522A (0xFireWolf 0.9.8)','Enabled':True,
   'ExecutablePath':'Contents/MacOS/RealtekCardReader','MaxKernel':'','MinKernel':'','PlistPath':'Contents/Info.plist'},
 'RealtekCardReaderFriend.kext': {'Arch':'x86_64','BundlePath':'RealtekCardReaderFriend.kext','Comment':'Lector SD como interno (0xFireWolf 1.0.5)','Enabled':True,
   'ExecutablePath':'Contents/MacOS/RealtekCardReaderFriend','MaxKernel':'','MinKernel':'','PlistPath':'Contents/Info.plist'},
}
for n in ['CPUFriend.kext', 'CPUFriendDataProvider.kext', 'RealtekCardReader.kext', 'RealtekCardReaderFriend.kext']:
    i = idx(n)
    if modo == 'aplicar':
        if i is None:
            add.append(ent[n]); out.append(f'Kernel/Add #{len(add)-1} {n} agregado: Enabled = true (al final, despues de Lilu)')
        else:
            add[i]['Enabled'] = True; out.append(f'Kernel/Add #{i} {n}: Enabled = true')
    elif i is not None:
        add[i]['Enabled'] = False; out.append(f'Kernel/Add #{i} {n}: Enabled = false')
acpi = p['ACPI']['Add']
ia = next((i for i, a in enumerate(acpi) if a.get('Path') == 'SSDT-ECRW.aml'), None)
if modo == 'aplicar':
    if ia is None:
        acpi.append({'Comment': 'EC lectura/escritura para YogaSMC (ventilador)', 'Enabled': True, 'Path': 'SSDT-ECRW.aml'})
        out.append(f'ACPI/Add #{len(acpi)-1} SSDT-ECRW.aml agregado: Enabled = true (YogaSMC puede escribir en el EC: control del ventilador)')
    else:
        acpi[ia]['Enabled'] = True; out.append(f'ACPI/Add #{ia} SSDT-ECRW.aml: Enabled = true')
elif ia is not None:
    acpi[ia]['Enabled'] = False; out.append(f'ACPI/Add #{ia} SSDT-ECRW.aml: Enabled = false')
if modo == 'aplicar':
    b = p['Misc']['Boot']
    if b.get('Timeout') != 0:
        out.append(f"Misc/Boot/Timeout: {b.get('Timeout')} -> 0 (el menu de OpenCore espera hasta que elijas; ya no arranca solo)")
        b['Timeout'] = 0
tp = [x for x in p['Kernel']['Patch'] if x.get('Identifier') == 'as.acidanthera.voodoo.driver.PS2Trackpad']
ok = all(x.get('Enabled') for x in tp)
out.append(f"Parches del TrackPoint (Kernel/Patch, PS2Trackpad): {len(tp)} encontrados, {'todos activos (no se tocaron)' if ok and tp else 'OJO: alguno esta apagado o falta'}")
with open(cfg, 'wb') as f: plistlib.dump(p, f, sort_keys=False)
print('\n'.join(out))
PY
)
plutil -lint "$CFG" >/dev/null
OCV=/Volumes/Windows/Users/TU_USUARIO_WINDOWS/Documents/CODE/hackintosh-dual-boot/herramientas/oc108/Utilities/ocvalidate/ocvalidate
VAL=$([ -x "$OCV" ] && "$OCV" "$CFG" | tail -1 || echo "(ocvalidate no disponible)")

# --- USB: SS04 (par USB 3 del puerto HS04) marcado como interno (255) -> USB 3 (3) ---
USBNOTA=""
UTB="$OC/Kexts/UTBMap.kext/Contents/Info.plist"
if [ "$MODO" = aplicar ] && [ -f "$UTB" ]; then
  mkdir -p "$MP/BITACORA-MAC/respaldos/UTBMap-antes-$STAMP" "$LOC/respaldos/UTBMap-antes-$STAMP"
  cp -R "$OC/Kexts/UTBMap.kext" "$MP/BITACORA-MAC/respaldos/UTBMap-antes-$STAMP/"
  cp -R "$OC/Kexts/UTBMap.kext" "$LOC/respaldos/UTBMap-antes-$STAMP/"
  USBNOTA=$(/usr/bin/python3 -I - "$UTB" <<'PY'
import plistlib, sys
f = sys.argv[1]
with open(f, 'rb') as h: p = plistlib.load(h)
n = 0
for pers in p.get('IOKitPersonalities', {}).values():
    ss = pers.get('IOProviderMergeProperties', {}).get('ports', {}).get('SS04')
    if ss and ss.get('UsbConnector') == 255:
        ss['UsbConnector'] = 3; n += 1
if n:
    with open(f, 'wb') as h: plistlib.dump(p, h, sort_keys=False)
    print(f'UTBMap: SS04 UsbConnector 255 -> 3 (USB 3) en {n} entrada(s). Respaldo: UTBMap-antes-STAMP')
else:
    print('UTBMap: SS04 no estaba en 255, no se cambio nada')
PY
)
  USBNOTA="${USBNOTA/STAMP/$STAMP}"
  plutil -lint "$UTB" >/dev/null
fi

# --- Diagnostico de la entrada "EFI" del menu (solo lectura; la EFI de Windows NO se modifica) ---
ESPNOTA=""
WDEV=""
for d in $(diskutil list disk0 | awk '/EFI/ {print $NF}'); do
  [ "$d" = "$DEV" ] || WDEV=$d
done
ESPNOTA="EFI-MAC \\EFI\\BOOT: $(ls "$MP/EFI/BOOT" 2>/dev/null | tr '\n' ' ')"
if [ -n "$WDEV" ]; then
  WMP_ANTES=$(diskutil info "$WDEV" | awk -F': *' '/Mount Point/ {print $2}')
  [ -n "$WMP_ANTES" ] || diskutil mount readOnly "$WDEV" >/dev/null 2>&1 || true
  WMP=$(diskutil info "$WDEV" | awk -F': *' '/Mount Point/ {print $2}')
  if [ -n "$WMP" ]; then
    ESPNOTA="$ESPNOTA | EFI de Windows ($WDEV) \\EFI: $(ls "$WMP/EFI" 2>/dev/null | tr '\n' ' ')| \\EFI\\BOOT: $(ls -l "$WMP/EFI/BOOT" 2>/dev/null | awk 'NR>1 {print $NF" ("$5" bytes)"}' | tr '\n' ' ')"
    [ -n "$WMP_ANTES" ] || diskutil unmount "$WDEV" >/dev/null 2>&1 || true
  fi
fi

# --- macFUSE + ntfs-3g (escribir en el disco de Windows) ---
NTFSNOTA=""
if [ "$MODO" = aplicar ]; then
  if installer -pkg "$LOC/descargas/ntfs/macFUSE-5.5.0.pkg" -target / >/dev/null 2>&1; then MFOK="instalado"; else MFOK="FALLO la instalacion"; fi
  mkdir -p /usr/local/bin
  install -m 755 "$LOC/descargas/ntfs/bin/ntfs-3g" "$LOC/descargas/ntfs/bin/ntfsfix" "$LOC/descargas/ntfs/bin/ntfslabel" /usr/local/bin/
  mkdir -p /usr/local/sbin
  install -o root -g wheel -m 755 "$LOC/montar-windows.sh" /usr/local/sbin/montar-windows.sh
  cat > /Library/LaunchDaemons/com.andrew.montar-windows.plist <<'LD'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.andrew.montar-windows</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>/usr/local/sbin/montar-windows.sh</string>
  </array>
  <key>RunAtLoad</key><true/>
</dict></plist>
LD
  chown root:wheel /Library/LaunchDaemons/com.andrew.montar-windows.plist; chmod 644 /Library/LaunchDaemons/com.andrew.montar-windows.plist
  NTFSNOTA="macFUSE 5.5.0: $MFOK. ntfs-3g 2026.9.28 (compilado aqui, estatico, SHA-256 del codigo verificado) en /usr/local/bin. LaunchDaemon com.andrew.montar-windows monta Windows con escritura al arrancar."
fi

# --- Actualizaciones automaticas de macOS ---
if [ "$MODO" = aplicar ]; then
  SU=/Library/Preferences/com.apple.SoftwareUpdate
  defaults write $SU AutomaticallyInstallMacOSUpdates -bool false
  defaults write $SU AutomaticDownload -bool false
  UPD="AutomaticallyInstallMacOSUpdates = $(defaults read $SU AutomaticallyInstallMacOSUpdates), AutomaticDownload = $(defaults read $SU AutomaticDownload) (las de seguridad siguen igual)"
fi

log ""
if [ "$MODO" = aplicar ]; then
  log "### $(date '+%Y-%m-%d %H:%M') - CPU en modo rendimiento (CPUFriend) y estabilidad"
  log "- Revisado antes: la gráfica HD 630 ya tiene aceleración (Metal 3, AppleIntelKBLGraphics, 1536 MB). La NVIDIA 940MX no tiene driver en macOS (no se puede usar)."
  log "- CPU: XCPM activo (plugin-type 1, X86PlatformPlugin) y sin limitación térmica. El perfil del MacBookPro16,2 traía EPP 0x80 (ahorro)."
  log "  Se agregó CPUFriend 1.3.0 + CPUFriendDataProvider (perfil Mac-5F9802EFE386AA28 con EPP 0x20 en los dos vectores): sube a turbo más rápido. Gasta un poco más de batería."
  log "- Lector SD (Realtek RTS522A, 10ec:522a): RealtekCardReader 0.9.8 + RealtekCardReaderFriend 1.0.5 (0xFireWolf, con soporte para Tahoe). Ojo: si la laptop se suspende con la tarjeta puesta, al despertar hay que sacarla y volver a meterla."
  log "- Respaldo del config: \`$BK\` (en EFI\\OC\\, BITACORA-MAC\\respaldos\\ y ~/hackintosh-mac/respaldos/)."
else
  log "### $(date '+%Y-%m-%d %H:%M') - CPUFriend apagado"
  log "- Respaldo del config: \`$BK\`."
fi
while IFS= read -r l; do [ -n "$l" ] && log "- $l"; done <<< "$CAMBIOS"
log "- ocvalidate: $VAL"
if [ "$MODO" = aplicar ]; then
  log "- Actualizaciones de macOS: $UPD. Así una actualización no borra el root patch del audio sin avisar."
  [ -n "$USBNOTA" ] && log "- $USBNOTA"
  log "- $NTFSNOTA"
  log "  Para quitarlo: \`sudo rm /Library/LaunchDaemons/com.andrew.montar-windows.plist\` y \`sudo bash /usr/local/sbin/montar-windows.sh solo-leer\`; macFUSE se quita con su Uninstaller."
  log "- Ventilador: SSDT-ECRW.aml (EC en \\_SB.PCI0.LPCB.EC, compilado con iasl 20260930). YogaSMCNC guarda el nivel Full (0x47) y lo aplica al iniciar."
  log "- Entrada \"EFI\" del menú (diagnóstico, no se cambió nada): $ESPNOTA"
  log "- **Si no arranca o hay kernel panic:** desde Windows restaurar \`$BK\` encima de EFI\\OC\\config.plist."
  log "  Desde macOS: \`sudo bash ~/hackintosh-mac/mejoras-cpu-estabilidad.sh revertir\` y reiniciar."
  log "- Siguiente: reiniciar (no hace falta Reset NVRAM) y revisar con \`kextstat | grep -i cpufriend\`."
fi

chown -R TU_USUARIO:staff "$LOC"
cp "$BIT" "$MP/BITACORA-MAC/BITACORA.md"
sync
diskutil unmount "$DEV" >/dev/null || true
echo "LISTO ($MODO). La bitácora ya quedó copiada en EFI-MAC. Reinicia."

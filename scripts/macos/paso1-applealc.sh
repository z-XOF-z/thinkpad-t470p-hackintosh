#!/bin/bash
# Paso 1 hacia el audio con AppleALC y el root patch (OCLP-Mod) en Tahoe.
# - EFI-MAC: agrega AMFIPass 1.4.1 y AppleALC 1.9.8 despues de Lilu, actualiza Lilu a 1.7.2 si es viejo,
#   layout-id = 47 (ThinkPad T470p), csr-active-config = 0xA03 (030A0000), boot-args + -amfipassbeta.
# - macOS: quita VoodooHDA de /Library/Extensions (queda respaldado).
# Respalda todo y lo anota en la BITACORA. Uso: sudo bash ~/hackintosh-mac/paso1-applealc.sh
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo con sudo"; exit 1; }
YO=/Users/TU_USUARIO
LOC="$YO/hackintosh-mac"
BIT="$LOC/BITACORA.md"
NUE="$LOC/kexts-nuevos/alc"
STAMP=$(date +%Y%m%d-%H%M%S)
log(){ echo "$*"; echo "$*" >> "$BIT"; }
PB=/usr/libexec/PlistBuddy
HDAS='PciRoot(0x0)/Pci(0x1F,0x3)'
NV='7C436110-AB2A-4BBB-A880-FE41995C9F82'

for k in AppleALC-1.9.8-RELEASE/AppleALC.kext AMFIPass-v1.4.1-RELEASE/AMFIPass.kext Lilu-1.7.2-RELEASE/Lilu.kext; do
  [ -d "$NUE/$k" ] || { echo "Falta $NUE/$k. No toco nada."; exit 1; }
done

# --- Montar EFI-MAC (por nombre, nunca la de Windows) ---
DEV=""
for d in $(diskutil list disk0 | awk '/EFI/ {print $NF}'); do
  name=$(diskutil info "$d" | awk -F': *' '/Volume Name/ {print $2}')
  [ "$name" = "EFI-MAC" ] && DEV=$d
done
[ -n "$DEV" ] || { echo "No encontre EFI-MAC. No toco nada."; exit 1; }
diskutil mount "$DEV" >/dev/null
MP=$(diskutil info "$DEV" | awk -F': *' '/Mount Point/ {print $2}')
OC="$MP/EFI/OC"; CFG="$OC/config.plist"; KX="$OC/Kexts"
[ -f "$CFG" ] || { echo "No hay config.plist en $MP"; exit 1; }
[ "$($PB -c 'Print :Kernel:Add:2:BundlePath' "$CFG")" = "Lilu.kext" ] || { echo "Lilu no esta en Kernel/Add #2. No toco nada."; exit 1; }
if $PB -c 'Print :Kernel:Add' "$CFG" | grep -q -e 'AppleALC.kext' -e 'AMFIPass.kext'; then
  echo "AppleALC o AMFIPass ya estan en el config. No toco nada."; exit 1
fi

# --- Respaldos ---
BK="config.antes-applealc-$STAMP.plist"
mkdir -p "$MP/BITACORA-MAC/respaldos" "$LOC/respaldos"
cp "$CFG" "$OC/$BK"; cp "$CFG" "$MP/BITACORA-MAC/respaldos/$BK"; cp "$CFG" "$LOC/respaldos/$BK"
LILU_V=$($PB -c 'Print :CFBundleShortVersionString' "$KX/Lilu.kext/Contents/Info.plist")

log ""
log "### $(date '+%Y-%m-%d %H:%M') - Paso 1: AppleALC + AMFIPass + SIP para el root patch"
log "- Respaldo del config: \`$BK\` (en EFI\\OC\\, BITACORA-MAC\\respaldos\\ y ~/hackintosh-mac/respaldos/)."

# --- Kexts en EFI-MAC ---
if [ "$LILU_V" != "1.7.2" ]; then
  cp -R "$KX/Lilu.kext" "$MP/BITACORA-MAC/respaldos/Lilu-$LILU_V-antes-$STAMP.kext"
  rm -rf "$KX/Lilu.kext"; cp -R "$NUE/Lilu-1.7.2-RELEASE/Lilu.kext" "$KX/"
  log "- Lilu $LILU_V -> 1.7.2 (respaldo del viejo en BITACORA-MAC\\respaldos\\Lilu-$LILU_V-antes-$STAMP.kext)."
else
  log "- Lilu ya era 1.7.2."
fi
rm -rf "$KX/AppleALC.kext" "$KX/AMFIPass.kext"
cp -R "$NUE/AppleALC-1.9.8-RELEASE/AppleALC.kext" "$KX/"
cp -R "$NUE/AMFIPass-v1.4.1-RELEASE/AMFIPass.kext" "$KX/"

add_kext(){ # indice nombre
  $PB -c "Add :Kernel:Add:$1 dict" \
      -c "Add :Kernel:Add:$1:Arch string Any" \
      -c "Add :Kernel:Add:$1:BundlePath string $2.kext" \
      -c "Add :Kernel:Add:$1:Comment string $2.kext" \
      -c "Add :Kernel:Add:$1:Enabled bool true" \
      -c "Add :Kernel:Add:$1:ExecutablePath string Contents/MacOS/$2" \
      -c "Add :Kernel:Add:$1:MaxKernel string" \
      -c "Add :Kernel:Add:$1:MinKernel string" \
      -c "Add :Kernel:Add:$1:PlistPath string Contents/Info.plist" "$CFG"
}
add_kext 3 AMFIPass
add_kext 4 AppleALC
log "- Kernel/Add: #3 AMFIPass.kext 1.4.1 y #4 AppleALC.kext 1.9.8 (justo despues de Lilu). VoodooHDA en OpenCore sigue apagado."

# --- layout-id 47 (0x2F) en 4 bytes ---
plutil -replace "DeviceProperties.Add.$HDAS.layout-id" -data "$(printf '\x2f\x00\x00\x00' | base64)" "$CFG"
log "- DeviceProperties > HDAS: \`layout-id\` 12 (1 byte, layout 18) -> 2F000000 (**layout 47**, \"Daliansky - ALC298 ThinkPad T470p\"). Otros que se pueden probar: 29 (X270), 3, 13."

# --- SIP 0x201 -> 0xA03 ---
plutil -replace "NVRAM.Add.$NV.csr-active-config" -data "$(printf '\x03\x0a\x00\x00' | base64)" "$CFG"
log "- csr-active-config: 01020000 (0x201) -> 030A0000 (0xA03 = 0x803 que pide OCLP + 0x200 que ya estaba). Ya estaba en NVRAM/Delete."
log "- SecureBootModel: ya estaba en Disabled (sin cambio)."

# --- boot-args ---
BA=$($PB -c "Print :NVRAM:Add:$NV:boot-args" "$CFG")
case " $BA " in *" -amfipassbeta "*) ;; *) $PB -c "Set :NVRAM:Add:$NV:boot-args $BA -amfipassbeta" "$CFG";; esac
log "- boot-args: \`$BA\` -> \`$($PB -c "Print :NVRAM:Add:$NV:boot-args" "$CFG")\`."

plutil -lint "$CFG" >/dev/null
OCV=/Volumes/Windows/Users/TU_USUARIO_WINDOWS/Documents/CODE/hackintosh-dual-boot/herramientas/oc108/Utilities/ocvalidate/ocvalidate
VAL=$([ -x "$OCV" ] && "$OCV" "$CFG" | tail -1 || echo "(ocvalidate no disponible)")
log "- ocvalidate: $VAL"

# --- VoodooHDA fuera de macOS ---
LE=/Library/Extensions/VoodooHDA.kext
if [ -d "$LE" ]; then
  VV=$($PB -c 'Print :CFBundleShortVersionString' "$LE/Contents/Info.plist")
  mv "$LE" "$LOC/respaldos/VoodooHDA-$VV-antes-$STAMP.kext"
  touch /Library/Extensions
  log "- VoodooHDA $VV quitado de /Library/Extensions (respaldo: ~/hackintosh-mac/respaldos/VoodooHDA-$VV-antes-$STAMP.kext)."
fi

log "- **Si no arranca o hay kernel panic:** desde Windows restaurar \`$BK\` encima de EFI\\OC\\config.plist."
log "  Para regresar VoodooHDA: \`sudo bash ~/hackintosh-mac/restaurar-voodoohda.sh\`."
log "- Siguiente: reiniciar, hacer **Reset NVRAM** en el menu de OpenCore (para que tome el SIP nuevo) y luego revisar con \`csrutil status\`."

chown -R TU_USUARIO:staff "$LOC"
cp "$BIT" "$MP/BITACORA-MAC/BITACORA.md"
sync
diskutil unmount "$DEV" >/dev/null || true
echo "LISTO. Reinicia y en el menu de OpenCore elige Reset NVRAM (espacio para ver las opciones ocultas)."

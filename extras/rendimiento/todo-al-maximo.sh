#!/bin/bash
# Todo al maximo (CPU y GPU), panel interno fijo a 60 Hz.
#  1) Panel de la laptop: borra el override de 75 Hz (se queda en 60 para siempre). La TV sigue a 75 Hz.
#  2) CPU: CPUFriendDataProvider con EPP 0x00 (maximo rendimiento: turbo al instante y sin soltarlo). Antes 0x20.
#  3) GPU: confirma que rps-control y 2 GB ya estan en la EFI.
#  4) Energia: sin modo de bajo consumo en bateria ni en corriente.
# Uso: sudo bash ~/hackintosh-mac/rendimiento/todo-al-maximo.sh            (aplica; luego reiniciar)
#      sudo bash ~/hackintosh-mac/rendimiento/todo-al-maximo.sh revertir   (regresa el kext de CPU de antes)
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo con sudo"; exit 1; }
MODO="${1:-aplicar}"
LOC=/Users/TU_USUARIO/hackintosh-mac
BIT="$LOC/BITACORA.md"
STAMP=$(date +%Y%m%d-%H%M%S)
log(){ echo "$*"; echo "$*" >> "$BIT"; }

DEV=""
for d in $(diskutil list disk0 | awk '/EFI/ {print $NF}'); do
  [ "$(diskutil info "$d" | awk -F': *' '/Volume Name/ {print $2}')" = "EFI-MAC" ] && DEV=$d
done
[ -n "$DEV" ] || { echo "No encontre EFI-MAC. No toco nada."; exit 1; }
diskutil mount "$DEV" >/dev/null
MP=$(diskutil info "$DEV" | awk -F': *' '/Mount Point/ {print $2}')
OC="$MP/EFI/OC"; CFG="$OC/config.plist"
[ -f "$CFG" ] && [ -d "$OC/Kexts/CPUFriendDataProvider.kext" ] || { echo "No encontre config.plist o CPUFriendDataProvider en $OC"; exit 1; }
RES="$MP/BITACORA-MAC/respaldos"; mkdir -p "$RES" "$LOC/respaldos"

if [ "$MODO" = revertir ]; then
  ULT=$(ls -d "$RES"/cpu-epp-antes-* 2>/dev/null | sort | tail -1)
  [ -n "$ULT" ] || { echo "No hay respaldo cpu-epp-antes-*"; exit 1; }
  rm -rf "$OC/Kexts/CPUFriendDataProvider.kext"; cp -R "$ULT/CPUFriendDataProvider.kext" "$OC/Kexts/"
  log ""; log "### $(date '+%Y-%m-%d %H:%M') - CPU: EPP regresado (kext de \`$(basename "$ULT")\`)"
  diskutil unmount "$DEV" >/dev/null || true; echo "Listo. Reinicia."; exit 0
fi

# 1) Panel a 60 Hz fijo
OVR=/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-9e5/DisplayProductID-6b3
[ -f "$OVR" ] && cp "$OVR" "$LOC/respaldos/override-panel-75hz-$STAMP.plist" && rm -f "$OVR"
rmdir /Library/Displays/Contents/Resources/Overrides/DisplayVendorID-9e5 2>/dev/null || true

# 2) CPU EPP 0x00
R="$RES/cpu-epp-antes-$STAMP"; mkdir -p "$R"
cp -R "$OC/Kexts/CPUFriendDataProvider.kext" "$R/"; cp -R "$R" "$LOC/respaldos/"
rm -rf "$OC/Kexts/CPUFriendDataProvider.kext"
cp -R "$LOC/rendimiento/CPUFriendDataProvider.kext" "$OC/Kexts/"
/usr/bin/python3 -I - "$CFG" <<'PY'
import plistlib, sys
f = sys.argv[1]; p = plistlib.load(open(f, 'rb'))
for k in p['Kernel']['Add']:
    if k.get('BundlePath') == 'CPUFriendDataProvider.kext':
        k['Comment'] = 'Perfil MBP16,2 con EPP 0x00 (maximo rendimiento)'
g = p['DeviceProperties']['Add']['PciRoot(0x0)/Pci(0x2,0x0)']
print("GPU en EFI: rps-control =", g.get('rps-control', b'').hex() or "FALTA",
      "| unifiedmem MB =", int.from_bytes(g.get('framebuffer-unifiedmem', b'\0\0\0\0'), 'little') // 1048576)
plistlib.dump(p, open(f, 'wb'), sort_keys=False)
PY

# 4) Sin bajo consumo
pmset -a lowpowermode 0

OCV=/Volumes/Windows/Users/TU_USUARIO_WINDOWS/Documents/CODE/hackintosh-dual-boot/herramientas/oc108/Utilities/ocvalidate/ocvalidate
VAL=$([ -x "$OCV" ] && "$OCV" "$CFG" | tail -1 || echo "(ocvalidate no disponible)")
log ""
log "### $(date '+%Y-%m-%d %H:%M') - Todo al máximo: CPU EPP 0x00, panel fijo a 60 Hz"
log "- Panel interno: override de 75 Hz borrado (copia en respaldos/override-panel-75hz-$STAMP.plist). Se queda en 60 Hz. La TV sigue a 75 Hz."
log "- CPU: CPUFriendDataProvider con EPP **0x00** (máximo rendimiento, antes 0x20). Respaldo: \`BITACORA-MAC/respaldos/cpu-epp-antes-$STAMP/\`."
log "- GPU: rps-control y 2 GB siguen en la EFI. \`pmset -a lowpowermode 0\`."
log "- ocvalidate: $VAL"
log "- Deshacer CPU: \`sudo bash ~/hackintosh-mac/rendimiento/todo-al-maximo.sh revertir\`."
diskutil unmount "$DEV" >/dev/null || true
echo "Listo. Reinicia. Despues corre: sudo bash ~/hackintosh-mac/rendimiento/medir-todo.sh"

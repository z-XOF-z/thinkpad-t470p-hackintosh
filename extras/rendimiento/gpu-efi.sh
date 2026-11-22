#!/bin/bash
# GPU Intel HD 630 a todo lo que da (en EFI-MAC, config.plist -> DeviceProperties de PciRoot(0x0)/Pci(0x2,0x0)):
#   - rps-control = 1        : WhateverGreen deja que la GPU suba sola a su frecuencia maxima (1.1 GHz) cuando hay carga
#                               (sin esto macOS la sube lento y se queda abajo). Mismo efecto que igfxrpsc=1.
#   - framebuffer-unifiedmem = 2048 MB : memoria de video que macOS reporta y deja usar (antes 1536 MB).
# Uso: sudo bash ~/hackintosh-mac/rendimiento/gpu-efi.sh            (aplica)
#      sudo bash ~/hackintosh-mac/rendimiento/gpu-efi.sh revertir   (regresa el config.plist de antes)
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo con sudo"; exit 1; }
MODO="${1:-instalar}"
[[ "$MODO" = instalar || "$MODO" = revertir ]] || { echo "Uso: sudo bash $0 [revertir]"; exit 1; }
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
CFG="$MP/EFI/OC/config.plist"
[ -f "$CFG" ] || { echo "No hay config.plist en $MP"; exit 1; }
RES="$MP/BITACORA-MAC/respaldos"; mkdir -p "$RES" "$LOC/respaldos"

if [ "$MODO" = revertir ]; then
  ULT=$(ls -d "$RES"/gpu-antes-* 2>/dev/null | sort | tail -1)
  [ -n "$ULT" ] || { echo "No hay respaldo gpu-antes-* en $RES"; exit 1; }
  cp "$ULT/config.plist" "$CFG"
  log ""
  log "### $(date '+%Y-%m-%d %H:%M') - GPU: se quitaron rps-control y unifiedmem"
  log "- config.plist restaurado de \`$(basename "$ULT")\`. Reinicia para que aplique."
else
  R="$RES/gpu-antes-$STAMP"; mkdir -p "$R"; cp "$CFG" "$R/"; cp -R "$R" "$LOC/respaldos/"
  /usr/bin/python3 -I - "$CFG" <<'PY'
import plistlib, sys
f = sys.argv[1]
p = plistlib.load(open(f, 'rb'))
g = p['DeviceProperties']['Add']['PciRoot(0x0)/Pci(0x2,0x0)']
g['rps-control'] = (1).to_bytes(4, 'little')
g['framebuffer-unifiedmem'] = (2048 * 1024 * 1024).to_bytes(4, 'little')
g['framebuffer-patch-enable'] = (1).to_bytes(4, 'little')
plistlib.dump(p, open(f, 'wb'), sort_keys=False)
print("config.plist: rps-control=1, framebuffer-unifiedmem=2048 MB")
PY
  OCV=/Volumes/Windows/Users/TU_USUARIO_WINDOWS/Documents/CODE/hackintosh-dual-boot/herramientas/oc108/Utilities/ocvalidate/ocvalidate
  VAL=$([ -x "$OCV" ] && "$OCV" "$CFG" | tail -1 || echo "(ocvalidate no disponible)")
  log ""
  log "### $(date '+%Y-%m-%d %H:%M') - GPU HD 630: rps-control y 2 GB de memoria de video"
  log "- DeviceProperties de la IGPU: \`rps-control\` = 1 (WhateverGreen sube la GPU a su máximo con carga) y \`framebuffer-unifiedmem\` = 2048 MB (antes 1536)."
  log "- Respaldo: \`BITACORA-MAC/respaldos/gpu-antes-$STAMP/config.plist\` y en ~/hackintosh-mac/respaldos/."
  log "- ocvalidate: $VAL"
  log "- **Si la imagen falla:** \`sudo bash ~/hackintosh-mac/rendimiento/gpu-efi.sh revertir\`, o desde Windows copiar ese config.plist a EFI\\OC\\."
fi
diskutil unmount "$DEV" >/dev/null || true
echo "Listo. Reinicia para que aplique."

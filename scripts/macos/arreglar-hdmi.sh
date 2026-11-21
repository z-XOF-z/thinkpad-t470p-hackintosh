#!/bin/bash
# Parche de framebuffer para el HDMI de la T470p (iGPU HD 630, ig-platform-id 0x591B0000).
# Pone con1 = puerto B (busid 5) como HDMI y con2 = puerto C (busid 4) como HDMI.
# Uno de los dos es el HDMI de la laptop. Todo queda en la BITACORA. Correr como root.
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo como root"; exit 1; }
YO=/Users/TU_USUARIO
LOC="$YO/hackintosh-mac"
BIT="$LOC/BITACORA.md"
STAMP=$(date +%Y%m%d-%H%M%S)
log(){ echo "$*"; echo "$*" >> "$BIT"; }
IG='PciRoot(0x0)/Pci(0x2,0x0)'

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
ID=$(plutil -extract "DeviceProperties.Add.$IG.AAPL,ig-platform-id" raw -o - "$CFG" | base64 -d | xxd -p)
[ "$ID" = "00001b59" ] || { echo "ig-platform-id inesperado ($ID). No toco nada."; exit 1; }

# --- Respaldo ---
BK="config.antes-hdmi-$STAMP.plist"
mkdir -p "$MP/BITACORA-MAC/respaldos"
cp "$CFG" "$OC/$BK"; cp "$CFG" "$MP/BITACORA-MAC/respaldos/$BK"; cp "$CFG" "$LOC/respaldos/$BK"

log ""
log "### $(date '+%Y-%m-%d %H:%M') - Parche del HDMI (framebuffer)"
log "- Respaldo del config: \`$BK\` (en EFI\\OC\\, BITACORA-MAC\\respaldos\\ y ~/hackintosh-mac/respaldos/)."
log "- Antes: con1 = puerto C HDMI, con2 = puerto D DP (lo de fabrica de 0x591B0000). El HDMI no detectaba nada."

# con1 y con2 (24 bytes): 01050A00 00080000 87010000 | 02040A00 00080000 87010000
ALL=$(echo 01050A000008000087010000 02040A000008000087010000 | xxd -r -p | base64)
plutil -replace "DeviceProperties.Add.$IG.framebuffer-con1-enable" -data AQAAAA== "$CFG"
plutil -replace "DeviceProperties.Add.$IG.framebuffer-con1-alldata" -data "$ALL" "$CFG"
log "- DeviceProperties > IGPU: \`framebuffer-con1-enable\` = 01000000"
log "  y \`framebuffer-con1-alldata\` = 01050A00 00080000 87010000 02040A00 00080000 87010000 (puertos B y C como HDMI)."

plutil -lint "$CFG" >/dev/null
OCV=/Volumes/Windows/Users/TU_USUARIO_WINDOWS/Documents/CODE/hackintosh-dual-boot/herramientas/oc108/Utilities/ocvalidate/ocvalidate
VAL=$([ -x "$OCV" ] && "$OCV" "$CFG" | tail -1 || echo "(ocvalidate no disponible)")
log "- ocvalidate: $VAL"
log "- **Si la pantalla se queda negra o no arranca:** desde Windows restaurar \`$BK\` encima de EFI\\OC\\config.plist."

chown -R TU_USUARIO:staff "$LOC"
cp "$BIT" "$MP/BITACORA-MAC/BITACORA.md"
sync
diskutil unmount "$DEV" >/dev/null || true
echo "LISTO"

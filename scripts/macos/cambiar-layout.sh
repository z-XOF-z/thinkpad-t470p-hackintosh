#!/bin/bash
# Cambia el layout-id de AppleALC (HDAS) en la EFI-MAC, con respaldo y nota en la BITACORA.
# Uso: sudo bash ~/hackintosh-mac/cambiar-layout.sh 29
# Layouts del ALC298 para probar: 29 (X270), 3, 13, 21, 28, 47 (el actual).
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo con sudo"; exit 1; }
N="$1"
[[ "$N" =~ ^[0-9]+$ ]] && [ "$N" -ge 1 ] && [ "$N" -le 255 ] || { echo "Uso: sudo bash $0 <numero de layout, ej. 29>"; exit 1; }
YO=/Users/TU_USUARIO
LOC="$YO/hackintosh-mac"
BIT="$LOC/BITACORA.md"
PB=/usr/libexec/PlistBuddy
HDAS='PciRoot(0x0)/Pci(0x1F,0x3)'
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

ANTES=$($PB -c "Print :DeviceProperties:Add:$HDAS:layout-id" "$CFG" | xxd -p | head -c 8)

# --- Respaldo ---
BK="config.antes-layout$N-$STAMP.plist"
mkdir -p "$MP/BITACORA-MAC/respaldos" "$LOC/respaldos"
cp "$CFG" "$OC/$BK"; cp "$CFG" "$MP/BITACORA-MAC/respaldos/$BK"; cp "$CFG" "$LOC/respaldos/$BK"

# --- layout-id en 4 bytes (little endian) ---
HEX=$(printf '%02x000000' "$N")
plutil -replace "DeviceProperties.Add.$HDAS.layout-id" -data "$(echo "$HEX" | xxd -r -p | base64)" "$CFG"
plutil -lint "$CFG" >/dev/null
OCV=/Volumes/Windows/Users/TU_USUARIO_WINDOWS/Documents/CODE/hackintosh-dual-boot/herramientas/oc108/Utilities/ocvalidate/ocvalidate
VAL=$([ -x "$OCV" ] && "$OCV" "$CFG" | tail -1 || echo "(ocvalidate no disponible)")

log ""
log "### $(date '+%Y-%m-%d %H:%M') - Cambio de layout-id a $N"
log "- Respaldo del config: \`$BK\` (en EFI\\OC\\, BITACORA-MAC\\respaldos\\ y ~/hackintosh-mac/respaldos/)."
log "- DeviceProperties > HDAS: \`layout-id\` $ANTES -> $(echo "$HEX" | tr a-f A-F) (**layout $N**). Con layout 47, macOS sí mandaba sonido (motor activo, IntSpeakers, volumen 127) pero la bocina no sonaba."
log "- ocvalidate: $VAL"
log "- **Si no arranca:** desde Windows restaurar \`$BK\` encima de EFI\\OC\\config.plist."
log "- Siguiente: reiniciar (no hace falta Reset NVRAM) y probar bocina y audífonos."

chown -R TU_USUARIO:staff "$LOC"
cp "$BIT" "$MP/BITACORA-MAC/BITACORA.md"
sync
diskutil unmount "$DEV" >/dev/null || true
echo "LISTO. Reinicia y prueba el sonido."

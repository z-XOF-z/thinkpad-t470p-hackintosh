#!/bin/bash
# Agrega unfairgva=N a boot-args en la EFI-MAC (DRM de FairPlay para Apple Music / TV), con respaldo y nota en la BITACORA.
# Motivo: Apple Music se queda en 0:00. Error en Music: "Failed to create content key request data" (OSStatus -15842).
# Uso: sudo bash ~/hackintosh-mac/arreglar-drm-music.sh        (pone unfairgva=1)
#      sudo bash ~/hackintosh-mac/arreglar-drm-music.sh 7      (si con 1 no basta)
#      sudo bash ~/hackintosh-mac/arreglar-drm-music.sh quitar (lo quita)
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo con sudo"; exit 1; }
N="${1:-1}"
[[ "$N" =~ ^[1-7]$ || "$N" = quitar ]] || { echo "Uso: sudo bash $0 [1-7|quitar]"; exit 1; }
YO=/Users/TU_USUARIO
LOC="$YO/hackintosh-mac"
BIT="$LOC/BITACORA.md"
PB=/usr/libexec/PlistBuddy
NV='7C436110-AB2A-4BBB-A880-FE41995C9F82'
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

ANTES=$($PB -c "Print :NVRAM:Add:$NV:boot-args" "$CFG")

# --- Respaldo ---
BK="config.antes-unfairgva-$STAMP.plist"
mkdir -p "$MP/BITACORA-MAC/respaldos" "$LOC/respaldos"
cp "$CFG" "$OC/$BK"; cp "$CFG" "$MP/BITACORA-MAC/respaldos/$BK"; cp "$CFG" "$LOC/respaldos/$BK"

# --- Quitar cualquier unfairgva anterior y agregar el nuevo ---
NUEVO=$(echo "$ANTES" | tr ' ' '\n' | grep -v '^unfairgva=' | grep -v '^$' | tr '\n' ' ' | sed 's/ $//')
[ "$N" = quitar ] || NUEVO="$NUEVO unfairgva=$N"
$PB -c "Set :NVRAM:Add:$NV:boot-args $NUEVO" "$CFG"
plutil -lint "$CFG" >/dev/null
OCV=/Volumes/Windows/Users/TU_USUARIO_WINDOWS/Documents/CODE/hackintosh-dual-boot/herramientas/oc108/Utilities/ocvalidate/ocvalidate
VAL=$([ -x "$OCV" ] && "$OCV" "$CFG" | tail -1 || echo "(ocvalidate no disponible)")

log ""
log "### $(date '+%Y-%m-%d %H:%M') - boot-args para el DRM de Apple Music"
log "- Motivo: la bocina ya suena con layout 29, pero Apple Music se queda en 0:00. En el registro de Music: FairPlay \"Failed to create content key request data\" (-15842), TimeoutReadyToPlay (5410)."
log "- Respaldo del config: \`$BK\` (en EFI\\OC\\, BITACORA-MAC\\respaldos\\ y ~/hackintosh-mac/respaldos/)."
log "- boot-args: \`$ANTES\` -> \`$NUEVO\`."
log "- ocvalidate: $VAL"
log "- **Si no arranca:** desde Windows restaurar \`$BK\` encima de EFI\\OC\\config.plist (unfairgva no deberia impedir el arranque)."
log "- Siguiente: reiniciar (no hace falta Reset NVRAM) y probar una cancion de Apple Music."

chown -R TU_USUARIO:staff "$LOC"
cp "$BIT" "$MP/BITACORA-MAC/BITACORA.md"
sync
diskutil unmount "$DEV" >/dev/null || true
echo "LISTO. boot-args ahora: $NUEVO"
echo "Reinicia y prueba Apple Music."

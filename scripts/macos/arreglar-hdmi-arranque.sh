#!/bin/bash
# Agrega igfxonln=1 a boot-args (WhateverGreen: fuerza "en linea" las pantallas externas al arrancar y al despertar,
# para no tener que desconectar y conectar el HDMI). Con respaldo y nota en la BITACORA.
# Uso: sudo bash ~/hackintosh-mac/arreglar-hdmi-arranque.sh            (agrega)
#      sudo bash ~/hackintosh-mac/arreglar-hdmi-arranque.sh revertir   (lo quita)
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo con sudo"; exit 1; }
MODO="${1:-aplicar}"
[[ "$MODO" = aplicar || "$MODO" = revertir ]] || { echo "Uso: sudo bash $0 [revertir]"; exit 1; }
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
[ -f "$CFG" ] || { echo "No hay config.plist en $MP"; exit 1; }

BK="config.antes-igfxonln-$MODO-$STAMP.plist"
mkdir -p "$MP/BITACORA-MAC/respaldos" "$LOC/respaldos"
cp "$CFG" "$OC/$BK"; cp "$CFG" "$MP/BITACORA-MAC/respaldos/$BK"; cp "$CFG" "$LOC/respaldos/$BK"

CAMBIO=$(/usr/bin/python3 -I - "$CFG" "$MODO" <<'PY'
import plistlib, sys
cfg, modo = sys.argv[1], sys.argv[2]
with open(cfg, 'rb') as f: p = plistlib.load(f)
g = p['NVRAM']['Add']['7C436110-AB2A-4BBB-A880-FE41995C9F82']
antes = g.get('boot-args', '')
args = [a for a in antes.split() if not a.startswith('igfxonln=')]
if modo == 'aplicar': args.append('igfxonln=1')
g['boot-args'] = ' '.join(args)
with open(cfg, 'wb') as f: plistlib.dump(p, f, sort_keys=False)
print(f"boot-args: `{antes}` -> `{g['boot-args']}`")
PY
)
plutil -lint "$CFG" >/dev/null
OCV=/Volumes/Windows/Users/TU_USUARIO_WINDOWS/Documents/CODE/hackintosh-dual-boot/herramientas/oc108/Utilities/ocvalidate/ocvalidate
VAL=$([ -x "$OCV" ] && "$OCV" "$CFG" | tail -1 || echo "(ocvalidate no disponible)")

log ""
log "### $(date '+%Y-%m-%d %H:%M') - HDMI detectado al arrancar (igfxonln=1)"
log "- Motivo: después de cada reinicio había que desconectar y volver a conectar el HDMI para que lo detectara."
log "- Respaldo del config: \`$BK\` (en EFI\\OC\\, BITACORA-MAC\\respaldos\\ y ~/hackintosh-mac/respaldos/)."
log "- $CAMBIO"
log "- ocvalidate: $VAL"
log "- **Si la pantalla se queda negra o no arranca:** desde Windows restaurar \`$BK\` encima de EFI\\OC\\config.plist, o \`sudo bash ~/hackintosh-mac/arreglar-hdmi-arranque.sh revertir\`."
chown -R TU_USUARIO:staff "$LOC"
cp "$BIT" "$MP/BITACORA-MAC/BITACORA.md"
sync
diskutil unmount "$DEV" >/dev/null || true
echo "LISTO ($MODO). Reinicia."

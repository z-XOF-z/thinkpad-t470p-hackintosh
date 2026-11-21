#!/bin/bash
# Cambia el WiFi de itlwm + HeliPort a AirportItlwm (WiFi nativo de Tahoe), con respaldo y nota en la BITACORA.
# Kext: laobamac/itlwm v2.4.0-alpha, AirportItlwm-Tahoe RELEASE (7204c69). Trae la 8265 (0x24fd) y su firmware iwm-8265-36.
# Necesita el root patch de WiFi Intel de OCLP-Mod (ya aplicado el 2026-11-20 20:51). Usa IOSkywalkFamily, asi que NO se bloquea.
# Uso: sudo bash ~/hackintosh-mac/cambiar-wifi-nativo.sh            (activa AirportItlwm y apaga itlwm)
#      sudo bash ~/hackintosh-mac/cambiar-wifi-nativo.sh revertir   (regresa a itlwm; no necesita internet)
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo con sudo"; exit 1; }
MODO="${1:-activar}"
[[ "$MODO" = activar || "$MODO" = revertir ]] || { echo "Uso: sudo bash $0 [revertir]"; exit 1; }
YO=/Users/TU_USUARIO
LOC="$YO/hackintosh-mac"
BIT="$LOC/BITACORA.md"
KEXT_NUEVO="$LOC/descargas/airportitlwm/AirportItlwm.kext"
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
[ "$MODO" = revertir ] || [ -d "$KEXT_NUEVO" ] || { echo "No encuentro $KEXT_NUEVO"; exit 1; }

# --- Respaldo ---
BK="config.antes-wifi-$MODO-$STAMP.plist"
mkdir -p "$MP/BITACORA-MAC/respaldos" "$LOC/respaldos"
cp "$CFG" "$OC/$BK"; cp "$CFG" "$MP/BITACORA-MAC/respaldos/$BK"; cp "$CFG" "$LOC/respaldos/$BK"

# --- Copiar el kext (guardando el que hubiera) ---
if [ "$MODO" = activar ]; then
  if [ -d "$OC/Kexts/AirportItlwm.kext" ]; then
    mkdir -p "$MP/BITACORA-MAC/respaldos/AirportItlwm-antes-$STAMP"
    mv "$OC/Kexts/AirportItlwm.kext" "$MP/BITACORA-MAC/respaldos/AirportItlwm-antes-$STAMP/"
  fi
  cp -R "$KEXT_NUEVO" "$OC/Kexts/"
fi

# --- Editar Kernel/Add (y revisar Kernel/Block) ---
CAMBIOS=$(/usr/bin/python3 - "$CFG" "$MODO" <<'PY'
import plistlib, sys
cfg, modo = sys.argv[1], sys.argv[2]
with open(cfg, 'rb') as f: p = plistlib.load(f)
add = p['Kernel']['Add']
out = []
def idx(nombre):
    for i, k in enumerate(add):
        if k.get('BundlePath') == nombre: return i
    return None
i_itl = idx('itlwm.kext'); i_air = idx('AirportItlwm.kext')
if modo == 'activar':
    if i_air is None:
        pos = (i_itl + 1) if i_itl is not None else len(add)
        add.insert(pos, {'Arch': 'x86_64', 'BundlePath': 'AirportItlwm.kext',
            'Comment': 'AirportItlwm Tahoe 2.4.0-alpha (laobamac) - WiFi nativo',
            'Enabled': True, 'ExecutablePath': 'Contents/MacOS/AirportItlwm',
            'MaxKernel': '', 'MinKernel': '25.0.0', 'PlistPath': 'Contents/Info.plist'})
        out.append(f'Kernel/Add #{pos} AirportItlwm.kext agregado: Enabled = true (MinKernel 25.0.0)')
    else:
        add[i_air]['Enabled'] = True
        out.append(f'Kernel/Add #{i_air} AirportItlwm.kext: Enabled = true')
    i_itl = idx('itlwm.kext')
    if i_itl is not None:
        add[i_itl]['Enabled'] = False
        out.append(f'Kernel/Add #{i_itl} itlwm.kext: Enabled = false (el kext se queda en la carpeta)')
else:
    if i_air is not None:
        add[i_air]['Enabled'] = False
        out.append(f'Kernel/Add #{i_air} AirportItlwm.kext: Enabled = false')
    if i_itl is not None:
        add[i_itl]['Enabled'] = True
        out.append(f'Kernel/Add #{i_itl} itlwm.kext: Enabled = true')
for b in p['Kernel'].get('Block', []):
    if 'Skywalk' in b.get('Identifier', '') and b.get('Enabled'):
        b['Enabled'] = False
        out.append('Kernel/Block IOSkywalkFamily: estaba activado -> Enabled = false (AirportItlwm Tahoe lo necesita)')
with open(cfg, 'wb') as f: plistlib.dump(p, f, sort_keys=False)
print('\n'.join(out))
PY
)
plutil -lint "$CFG" >/dev/null
OCV=/Volumes/Windows/Users/TU_USUARIO_WINDOWS/Documents/CODE/hackintosh-dual-boot/herramientas/oc108/Utilities/ocvalidate/ocvalidate
VAL=$([ -x "$OCV" ] && "$OCV" "$CFG" | tail -1 || echo "(ocvalidate no disponible)")

log ""
if [ "$MODO" = activar ]; then
  log "### $(date '+%Y-%m-%d %H:%M') - WiFi nativo: itlwm -> AirportItlwm (Tahoe)"
  log "- Kext: AirportItlwm-Tahoe v2.4.0-alpha RELEASE (laobamac/itlwm, 7204c69). Trae la 8265 (0x24fd) y el firmware iwm-8265-36. Depende de IO80211Family e IOSkywalkFamily (los del sistema, con el root patch de OCLP-Mod)."
else
  log "### $(date '+%Y-%m-%d %H:%M') - WiFi: regresar a itlwm + HeliPort"
fi
log "- Respaldo del config: \`$BK\` (en EFI\\OC\\, BITACORA-MAC\\respaldos\\ y ~/hackintosh-mac/respaldos/)."
while IFS= read -r l; do [ -n "$l" ] && log "- $l"; done <<< "$CAMBIOS"
log "- ocvalidate: $VAL"
if [ "$MODO" = activar ]; then
  log "- **Si no hay WiFi o no arranca:** \`sudo bash ~/hackintosh-mac/cambiar-wifi-nativo.sh revertir\` (no necesita internet) y reiniciar."
  log "  Desde Windows: restaurar \`$BK\` encima de EFI\\OC\\config.plist."
  log "- Siguiente: reiniciar (no hace falta Reset NVRAM), conectarse desde el icono de WiFi de macOS y probar Ubicacion. HeliPort ya no hace falta."
fi

chown -R TU_USUARIO:staff "$LOC"
cp "$BIT" "$MP/BITACORA-MAC/BITACORA.md"
sync
diskutil unmount "$DEV" >/dev/null || true
echo "LISTO ($MODO). Reinicia."

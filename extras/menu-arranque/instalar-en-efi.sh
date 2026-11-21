#!/bin/bash
# Pasa a EFI-MAC (el disco) lo que ya se probo en la USB:
#   - OpenCanopy.efi con el panel EN VIVO (LiveStats + fuente suavizada)
#   - Herramienta "Diagnostico" (DiagT470p.efi) + su entrada en Misc/Tools
#   - Fondo ThinkPad corregido (Background.icns)
# Uso: sudo bash ~/hackintosh-mac/menu-arranque/instalar-en-efi.sh            (instala)
#      sudo bash ~/hackintosh-mac/menu-arranque/instalar-en-efi.sh revertir   (regresa OpenCanopy y config de antes)
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo con sudo"; exit 1; }
MODO="${1:-instalar}"
[[ "$MODO" = instalar || "$MODO" = revertir ]] || { echo "Uso: sudo bash $0 [revertir]"; exit 1; }
LOC=/Users/TU_USUARIO/hackintosh-mac
BIT="$LOC/BITACORA.md"
B="$LOC/opencanopy-vivo/OpenCorePkg/UDK/Build/OpenCorePkg/RELEASE_XCODE5/X64"
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
RES="$MP/BITACORA-MAC/respaldos"
mkdir -p "$RES" "$LOC/respaldos"

if [ "$MODO" = revertir ]; then
  ULT=$(ls -d "$RES"/menu-vivo-antes-* 2>/dev/null | sort | tail -1)
  [ -n "$ULT" ] || { echo "No hay respaldo menu-vivo-antes-* en $RES"; exit 1; }
  cp "$ULT/OpenCanopy.efi" "$OC/Drivers/OpenCanopy.efi"
  cp "$ULT/config.plist" "$CFG"
  rm -f "$OC/Tools/DiagT470p.efi"
  log ""
  log "### $(date '+%Y-%m-%d %H:%M') - Menú EN VIVO y Diagnóstico quitados de EFI-MAC"
  log "- Se restauraron OpenCanopy.efi y config.plist de \`$(basename "$ULT")\`."
else
  for f in OpenCanopy.efi DiagT470p.efi; do [ -f "$B/$f" ] || { echo "Falta $B/$f"; exit 1; }; done
  # Respaldo completo de lo que se va a cambiar
  R="$RES/menu-vivo-antes-$STAMP"; mkdir -p "$R"
  cp "$OC/Drivers/OpenCanopy.efi" "$CFG" "$R/"
  [ -f "$OC/Resources/Image/Acidanthera/GoldenGate/Background.icns" ] && cp "$OC/Resources/Image/Acidanthera/GoldenGate/Background.icns" "$R/"
  cp -R "$R" "$LOC/respaldos/"

  cp "$B/OpenCanopy.efi" "$OC/Drivers/OpenCanopy.efi"
  mkdir -p "$OC/Tools"
  cp "$B/DiagT470p.efi" "$OC/Tools/DiagT470p.efi"
  cp "$LOC/menu-arranque/Background.icns" "$OC/Resources/Image/Acidanthera/GoldenGate/Background.icns"
  /usr/bin/python3 -I - "$CFG" <<'PY'
import plistlib, sys
f = sys.argv[1]
p = plistlib.load(open(f, 'rb'))
t = [x for x in p['Misc']['Tools'] if x.get('Path') != 'DiagT470p.efi']
t.append({'Arguments': '', 'Auxiliary': False, 'Comment': 'Diagnostico propio: RAM, discos, teclado, pantalla, bateria',
          'Enabled': True, 'Flavour': 'Diagnostico:Tool', 'FullNvramAccess': False, 'Name': 'Diagnostico',
          'Path': 'DiagT470p.efi', 'RealPath': False, 'TextMode': False})
p['Misc']['Tools'] = t
plistlib.dump(p, open(f, 'wb'), sort_keys=False)
PY
  plutil -lint "$CFG" >/dev/null
  OCV=/Volumes/Windows/Users/TU_USUARIO_WINDOWS/Documents/CODE/hackintosh-dual-boot/herramientas/oc108/Utilities/ocvalidate/ocvalidate
  VAL=$([ -x "$OCV" ] && "$OCV" "$CFG" | tail -1 || echo "(ocvalidate no disponible)")
  log ""
  log "### $(date '+%Y-%m-%d %H:%M') - Menú EN VIVO y Diagnóstico grabados en EFI-MAC"
  log "- OpenCanopy.efi con panel EN VIVO ($(stat -f %z "$OC/Drivers/OpenCanopy.efi") bytes), Tools/DiagT470p.efi ($(stat -f %z "$OC/Tools/DiagT470p.efi") bytes) con entrada \"Diagnostico\" en Misc/Tools y fondo corregido."
  log "- Respaldo de lo anterior: \`BITACORA-MAC/respaldos/menu-vivo-antes-$STAMP/\` (OpenCanopy.efi, config.plist, Background.icns) y en ~/hackintosh-mac/respaldos/."
  log "- ocvalidate: $VAL"
  log "- **Si el menú se traba o no arranca:** F12 → USB de OpenCore, y desde macOS \`sudo bash ~/hackintosh-mac/menu-arranque/instalar-en-efi.sh revertir\`."
  log "  Desde Windows: copiar \`menu-vivo-antes-$STAMP/OpenCanopy.efi\` a EFI\\OC\\Drivers\\ y su config.plist a EFI\\OC\\."
fi

chown -R TU_USUARIO:staff "$LOC"
cp "$BIT" "$MP/BITACORA-MAC/BITACORA.md"
sync
diskutil unmount "$DEV" >/dev/null || true
echo "LISTO ($MODO). Reinicia para verlo."

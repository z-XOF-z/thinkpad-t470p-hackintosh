#!/bin/bash
# Quick fixes for the Hackintosh (T470p, Tahoe). Run as root.
#  1. Removes -v and debug=0x100 from boot-args (OpenCore config in EFI-MAC)
#  2. Hibernation/standby off
#  3. Converts the shutdown-stall reports to text
# Everything is recorded in BITACORA.md (local + EFI-MAC:\BITACORA-MAC\)
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo como root"; exit 1; }
GUID=7C436110-AB2A-4BBB-A880-FE41995C9F82
YO=/Users/TU_USUARIO
LOC="$YO/hackintosh-mac"
BIT="$LOC/BITACORA.md"
STAMP=$(date +%Y%m%d-%H%M%S)
log(){ echo "$*"; echo "$*" >> "$BIT"; }

# --- Mount EFI-MAC (by name, never Windows' EFI) ---
DEV=""
for d in $(diskutil list disk0 | awk '/EFI/ {print $NF}'); do
  name=$(diskutil info "$d" | awk -F': *' '/Volume Name/ {print $2}')
  [ "$name" = "EFI-MAC" ] && DEV=$d
done
[ -n "$DEV" ] || { echo "No encontre EFI-MAC. No toco nada."; exit 1; }
diskutil mount "$DEV" >/dev/null
MP=$(diskutil info "$DEV" | awk -F': *' '/Mount Point/ {print $2}')
CFG="$MP/EFI/OC/config.plist"
[ -f "$CFG" ] || { echo "No hay config.plist en $MP"; exit 1; }
mkdir -p "$MP/BITACORA-MAC/respaldos" "$LOC/respaldos"

# --- Backup ---
BK="config.antes-arreglos-$STAMP.plist"
cp "$CFG" "$MP/EFI/OC/$BK"
cp "$CFG" "$MP/BITACORA-MAC/respaldos/$BK"
cp "$CFG" "$LOC/respaldos/$BK"

log ""
log "### $(date '+%Y-%m-%d %H:%M') - Quick fixes"
log "- Backup of the config before the change: \`$BK\` (in EFI\\OC\\, in BITACORA-MAC\\respaldos\\ and in ~/hackintosh-mac/respaldos/)."

# --- 1. boot-args ---
OLD=$(/usr/libexec/PlistBuddy -c "Print :NVRAM:Add:$GUID:boot-args" "$CFG")
NEW=$(echo "$OLD" | tr ' ' '\n' | grep -vxE -- '-v|debug=0x100' | grep -v '^$' | tr '\n' ' ' | sed 's/ *$//')
/usr/libexec/PlistBuddy -c "Set :NVRAM:Add:$GUID:boot-args $NEW" "$CFG"
plutil -lint "$CFG" >/dev/null
OCV=/Volumes/Windows/Users/TU_USUARIO_WINDOWS/Documents/CODE/hackintosh-dual-boot/herramientas/oc108/Utilities/ocvalidate/ocvalidate
VAL=$([ -x "$OCV" ] && "$OCV" "$CFG" | tail -1 || echo "(ocvalidate no disponible)")
log "- boot-args: \`$OLD\` -> \`$NEW\`. ocvalidate: $VAL"
log "  - To undo: restore \`$BK\` over EFI\\OC\\config.plist."

# --- 2. Sleep ---
BEFORE=$(pmset -g | grep -E '^ (hibernatemode|standby|autopoweroff|powernap) ' | tr -s ' ' | tr '\n' ';')
pmset -a hibernatemode 0 standby 0 autopoweroff 0 powernap 0
rm -f /var/vm/sleepimage
log "- Sleep: before \`$BEFORE\` -> hibernatemode/standby/autopoweroff/powernap = 0, sleepimage deleted."
log "  - To undo: \`sudo pmset -a hibernatemode 3 standby 1\` (in macOS; does not affect boot)."

# --- 3. Shutdown-stall reports ---
OUT="$LOC/reportes-apagado"; mkdir -p "$OUT"
n=0
for f in /Library/Logs/DiagnosticReports/shutdown_stall_*.shutdownStall; do
  [ -f "$f" ] || continue
  spindump -i "$f" -o "$OUT/$(basename "$f" .shutdownStall).txt" >/dev/null 2>&1 && n=$((n+1)) || true
done
log "- $n shutdown-stall reports converted to text in ~/hackintosh-mac/reportes-apagado/ (read only, nothing changed)."

# --- Copy log to EFI-MAC and unmount ---
chown -R TU_USUARIO:staff "$LOC"
cp "$BIT" "$MP/BITACORA-MAC/BITACORA.md"
sync
diskutil unmount "$DEV" >/dev/null || true
echo "LISTO"

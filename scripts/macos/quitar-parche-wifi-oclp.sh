#!/bin/bash
# Quita SOLO la parte de WiFi del root patch de OCLP-Mod y deja el audio (AppleHDA) como está.
#
# Motivo: el parche "Intel无线网卡" de OCLP-Mod es el "Modern Wireless" de OCLP. Mete wifip2pd, IO80211.framework
# (con IO80211Old.dylib) y WiFiPeerToPeer.framework de macOS 13.7.2 (Ventura). Eso sirve para el AirportItlwm
# viejo (el de Sonoma con IO80211FamilyLegacy). El AirportItlwm-Tahoe de laobamac usa el IO80211Family NATIVO
# de Tahoe, y con los frameworks viejos airportd le habla con ioctls viejos: "Invalid ioctl",
# isDriverAvailable=0 y escaneos sin resultados.
#
# Qué hace: copia los originales desde el snapshot sellado de Tahoe (solo lectura) encima del volumen del sistema,
# respalda los del parche y crea un snapshot nuevo para arrancar.
#
# Uso:   sudo bash ~/hackintosh-mac/quitar-parche-wifi-oclp.sh
# Si después no arranca: en OpenCore entra a Recovery → Terminal →
#        bless --mount /Volumes/Macintosh --last-sealed-snapshot
#        (regresa a Tahoe original; el audio se tendría que volver a parchar con OCLP-Mod).
set -euo pipefail

[ "$(id -u)" = 0 ] || { echo "Córrelo con sudo: sudo bash $0"; exit 1; }

LOC=/Users/TU_USUARIO/hackintosh-mac
TS=$(date +%Y%m%d-%H%M%S)
RESP="$LOC/respaldos/wifi-oclp-$TS"
BIT="$LOC/BITACORA.md"
ORIG=/private/var/tmp/tahoe-original
MNT=/System/Volumes/Update/mnt1
ITEMS=(
  "usr/libexec/wifip2pd"
  "System/Library/PrivateFrameworks/IO80211.framework"
  "System/Library/PrivateFrameworks/WiFiPeerToPeer.framework"
)

log() { echo "$1" | tee -a "$BIT"; }

# Volumen del sistema: "/" es /dev/diskXsYs1 (snapshot); el volumen es /dev/diskXsY
SNAPDEV=$(mount | awk '$3=="/" {print $1}')
DEV=${SNAPDEV%s[0-9]*}
SNAP=$(diskutil apfs listSnapshots / | awk '/Name:/ && /com.apple.os.update-/ {print $NF; exit}')
[ -n "$SNAP" ] || { echo "No encuentro el snapshot sellado original (com.apple.os.update-...)"; exit 1; }
echo "Volumen del sistema: $DEV"
echo "Snapshot original:   $SNAP"

limpiar() {
  umount "$ORIG" 2>/dev/null || true
  umount "$MNT" 2>/dev/null || true
}
trap limpiar EXIT

mkdir -p "$ORIG" "$MNT"
umount "$ORIG" 2>/dev/null || true
mount_apfs -o rdonly -s "$SNAP" "$DEV" "$ORIG"

echo
echo "== Comparación (original de Tahoe vs. lo que dejó OCLP-Mod) =="
for i in "${ITEMS[@]}"; do
  if [ -e "$ORIG/$i" ]; then o="existe"; else o="NO existe"; fi
  echo "- /$i: en el original $o"
  if [ -d "/$i" ]; then
    diff <(cd "$ORIG/$i" 2>/dev/null && find . | sort) <(cd "/$i" && find . | sort) | sed 's/^/    /' || true
  fi
done
echo
read -r -p "¿Regreso estos 3 a como vienen en Tahoe? (el audio no se toca) [s/N] " R
[ "$R" = s ] || [ "$R" = S ] || { echo "No se cambió nada."; exit 0; }

umount "$MNT" 2>/dev/null || true
mount -o nobrowse -t apfs "$DEV" "$MNT"

mkdir -p "$RESP"
for i in "${ITEMS[@]}"; do
  if [ -e "$MNT/$i" ]; then
    mkdir -p "$RESP/$(dirname "$i")"
    ditto "$MNT/$i" "$RESP/$i"
  fi
  rm -rf "$MNT/$i"
  if [ -e "$ORIG/$i" ]; then
    ditto "$ORIG/$i" "$MNT/$i"
  fi
done

if bless --folder "$MNT/System/Library/CoreServices" --bootefi --create-snapshot; then RES=0; else RES=$?; fi

log ""
log "### $(date '+%Y-%m-%d %H:%M') - Quitar solo el parche de WiFi de OCLP-Mod (el audio se queda)"
log "- Causa: el parche Intel de OCLP-Mod es el \"Modern Wireless\" de OCLP: mete wifip2pd, IO80211.framework (con IO80211Old.dylib) y WiFiPeerToPeer.framework de macOS 13.7.2."
log "  Eso es para el AirportItlwm viejo. El AirportItlwm-Tahoe usa el IO80211Family nativo y con esos frameworks viejos salían \"Invalid ioctl\", isDriverAvailable=0 y 0 redes."
log "- Se copiaron los originales desde el snapshot sellado \`$SNAP\` a: /usr/libexec/wifip2pd, IO80211.framework y WiFiPeerToPeer.framework."
log "- Respaldo de los archivos del parche: \`$RESP\`."
log "- bless --create-snapshot: código $RES."
log "- AppleHDA (audio) no se tocó."
log "- **Si no arranca:** Recovery → Terminal → \`bless --mount /Volumes/Macintosh --last-sealed-snapshot\` (regresa a Tahoe original; después hay que volver a parchar el audio con OCLP-Mod)."
log "- Ojo: si se vuelve a aplicar el root patch con OCLP-Mod, vuelve a meter estos archivos y el WiFi nativo deja de escanear. Hay que correr este script otra vez."
log "- Siguiente: reiniciar y buscar redes desde el icono de WiFi."

echo
echo "Listo. Reinicia y busca redes desde el icono de WiFi."

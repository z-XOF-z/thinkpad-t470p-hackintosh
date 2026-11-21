#!/bin/bash
# Copia la EFI que funciona (EFI-MAC) a ~/hackintosh-mac/efi-exportada/ para armar el repo de GitHub.
# Solo lee EFI-MAC; no cambia nada. Los datos unicos (serie, MLB, UUID, ROM) se quitan despues, al armar el repo.
# Uso: sudo bash ~/hackintosh-mac/exportar-efi.sh
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo con sudo"; exit 1; }
DST=/Users/TU_USUARIO/hackintosh-mac/efi-exportada
DEV=""
for d in $(diskutil list disk0 | awk '/EFI/ {print $NF}'); do
  [ "$(diskutil info "$d" | awk -F': *' '/Volume Name/ {print $2}')" = "EFI-MAC" ] && DEV=$d
done
[ -n "$DEV" ] || { echo "No encontre EFI-MAC"; exit 1; }
ANTES=$(diskutil info "$DEV" | awk -F': *' '/Mount Point/ {print $2}')
[ -n "$ANTES" ] || diskutil mount readOnly "$DEV" >/dev/null
MP=$(diskutil info "$DEV" | awk -F': *' '/Mount Point/ {print $2}')
rm -rf "$DST"; mkdir -p "$DST"
# Solo la EFI de OpenCore (sin los respaldos config.antes-* ni la bitacora)
rsync -a --exclude 'config.antes-*' --exclude '.Trashes' --exclude '.fseventsd' --exclude '._*' "$MP/EFI" "$DST/"
chown -R TU_USUARIO:staff "$DST"
[ -n "$ANTES" ] || diskutil unmount "$DEV" >/dev/null || true
echo "LISTO: EFI copiada a $DST ($(du -sh "$DST" | cut -f1))."

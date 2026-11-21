#!/bin/bash
# Activa el Bluetooth (Intel 8265) en EFI-MAC: IntelBluetoothFirmware 2.5.3 + BlueToolFixup 2.7.2.
# IntelBTPatcher se actualiza a 2.5.3 pero se deja APAGADO (la 2.4 dio kernel panic).
# Todo queda en la BITACORA (local + EFI-MAC:\BITACORA-MAC\). Correr como root.
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo como root"; exit 1; }
GUID=7C436110-AB2A-4BBB-A880-FE41995C9F82
YO=/Users/TU_USUARIO
LOC="$YO/hackintosh-mac"
BIT="$LOC/BITACORA.md"
NUEVOS="$LOC/kexts-nuevos/dl/ibt"
STAMP=$(date +%Y%m%d-%H%M%S)
log(){ echo "$*"; echo "$*" >> "$BIT"; }

for k in IntelBluetoothFirmware IntelBTPatcher; do
  [ -d "$NUEVOS/$k.kext" ] || { echo "Falta $NUEVOS/$k.kext. No toco nada."; exit 1; }
done

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
[ -d "$OC/Kexts/BlueToolFixup.kext" ] || { echo "No esta BlueToolFixup.kext en la EFI. No toco nada."; exit 1; }

# --- Respaldos: config + kexts de Bluetooth viejos ---
BK="config.antes-bluetooth-$STAMP.plist"
KBK="kexts-bt-antes-$STAMP"
mkdir -p "$MP/BITACORA-MAC/respaldos/$KBK" "$LOC/respaldos/$KBK"
cp "$CFG" "$OC/$BK"; cp "$CFG" "$MP/BITACORA-MAC/respaldos/$BK"; cp "$CFG" "$LOC/respaldos/$BK"
for k in IntelBluetoothFirmware IntelBTPatcher; do
  [ -d "$OC/Kexts/$k.kext" ] && cp -R "$OC/Kexts/$k.kext" "$MP/BITACORA-MAC/respaldos/$KBK/" && cp -R "$OC/Kexts/$k.kext" "$LOC/respaldos/$KBK/"
done

log ""
log "### $(date '+%Y-%m-%d %H:%M') - Activar Bluetooth (directo en EFI-MAC, sin USB)"
log "- Respaldo del config: \`$BK\` (en EFI\\OC\\, BITACORA-MAC\\respaldos\\ y ~/hackintosh-mac/respaldos/)."
log "- Respaldo de los kexts de BT anteriores (2.4.0): \`BITACORA-MAC\\respaldos\\$KBK\\\`."

# --- Copiar kexts nuevos ---
for k in IntelBluetoothFirmware IntelBTPatcher; do
  rm -rf "$OC/Kexts/$k.kext"
  cp -R "$NUEVOS/$k.kext" "$OC/Kexts/"
done
log "- Kexts copiados a EFI\\OC\\Kexts: IntelBluetoothFirmware 2.5.3 e IntelBTPatcher 2.5.3 (de lshbluesky). BlueToolFixup se queda en 2.7.2."

# --- Kernel > Add: prender BlueToolFixup e IntelBluetoothFirmware; IntelBTPatcher apagado ---
i=0
while bp=$(/usr/libexec/PlistBuddy -c "Print :Kernel:Add:$i:BundlePath" "$CFG" 2>/dev/null); do
  case "$bp" in
    BlueToolFixup.kext|IntelBluetoothFirmware.kext)
      /usr/libexec/PlistBuddy -c "Set :Kernel:Add:$i:Enabled true" "$CFG"; log "  - Kernel/Add #$i $bp: Enabled = true";;
    IntelBTPatcher.kext)
      /usr/libexec/PlistBuddy -c "Set :Kernel:Add:$i:Enabled false" "$CFG"; log "  - Kernel/Add #$i $bp: Enabled = false (a proposito)";;
  esac
  i=$((i+1))
done

# --- NVRAM que pide Tahoe para BT Intel ---
setdata(){ # $1 llave, $2 base64
  plutil -replace "NVRAM.Add.$GUID.$1" -data "$2" "$CFG"
  /usr/libexec/PlistBuddy -c "Print :NVRAM:Delete:$GUID" "$CFG" | grep -q "$1" || \
    /usr/libexec/PlistBuddy -c "Add :NVRAM:Delete:$GUID: string $1" "$CFG"
}
setdata bluetoothExternalDongleFailed AA==
setdata bluetoothInternalControllerInfo AAAAAAAAAAAAAAAAAAA=
log "- NVRAM (7C436110...): \`bluetoothExternalDongleFailed\` = 00 y \`bluetoothInternalControllerInfo\` = 14 bytes en 0 (tambien en NVRAM/Delete)."
log "- boot-args: \`$(/usr/libexec/PlistBuddy -c "Print :NVRAM:Add:$GUID:boot-args" "$CFG")\` (sin cambio; -ibtcompatbeta ya estaba)."

plutil -lint "$CFG" >/dev/null
OCV=/Volumes/Windows/Users/TU_USUARIO_WINDOWS/Documents/CODE/hackintosh-dual-boot/herramientas/oc108/Utilities/ocvalidate/ocvalidate
VAL=$([ -x "$OCV" ] && "$OCV" "$CFG" | tail -1 || echo "(ocvalidate no disponible)")
log "- ocvalidate: $VAL"
log "- **Si da kernel panic o no arranca:** desde Windows restaurar \`$BK\` encima de EFI\\OC\\config.plist"
log "  (con eso los kexts de BT quedan apagados otra vez; no hace falta regresar los kexts viejos)."

chown -R TU_USUARIO:staff "$LOC"
cp "$BIT" "$MP/BITACORA-MAC/BITACORA.md"
sync
diskutil unmount "$DEV" >/dev/null || true
echo "LISTO"

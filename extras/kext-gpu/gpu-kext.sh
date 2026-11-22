#!/bin/bash
# GraficaT470p.kext: probar en USB y luego instalar en EFI-MAC.
#   sudo bash ~/hackintosh-mac/kext-gpu/gpu-kext.sh listar          -> muestra las USB con OpenCore
#   sudo bash ~/hackintosh-mac/kext-gpu/gpu-kext.sh usb disk4s1     -> copia la EFI de disco a esa USB + GraficaT470p (para probar con F12)
#   sudo bash ~/hackintosh-mac/kext-gpu/gpu-kext.sh disco           -> lo instala en EFI-MAC (despues de probar en USB)
#   sudo bash ~/hackintosh-mac/kext-gpu/gpu-kext.sh quitar          -> lo quita de EFI-MAC (regresa el config de antes)
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo con sudo"; exit 1; }
LOC=/Users/TU_USUARIO/hackintosh-mac
KX="$LOC/kext-gpu/GraficaT470p/build/GraficaT470p.kext"
BIT="$LOC/BITACORA.md"
OCV=/Volumes/Windows/Users/TU_USUARIO_WINDOWS/Documents/CODE/hackintosh-dual-boot/herramientas/oc108/Utilities/ocvalidate/ocvalidate
STAMP=$(date +%Y%m%d-%H%M%S)
log(){ echo "$*"; echo "$*" >> "$BIT"; }
MODO="$1"

montar_efi_mac() {
  DEV=""
  for d in $(diskutil list disk0 | awk '/EFI/ {print $NF}'); do
    [ "$(diskutil info "$d" | awk -F': *' '/Volume Name/ {print $2}')" = "EFI-MAC" ] && DEV=$d
  done
  [ -n "$DEV" ] || { echo "No encontre EFI-MAC"; exit 1; }
  diskutil mount "$DEV" >/dev/null
  MPMAC=$(diskutil info "$DEV" | awk -F': *' '/Mount Point/ {print $2}')
}

agregar_kext() {   # $1 = carpeta EFI/OC
  local OC="$1"
  rm -rf "$OC/Kexts/GraficaT470p.kext"; cp -R "$KX" "$OC/Kexts/"
  /usr/bin/python3 -I - "$OC/config.plist" <<'PY'
import plistlib, sys
f = sys.argv[1]; p = plistlib.load(open(f, 'rb'))
k = [x for x in p['Kernel']['Add'] if x.get('BundlePath') != 'GraficaT470p.kext']
i = next((n for n, x in enumerate(k) if x.get('BundlePath') == 'WhateverGreen.kext'), None)
assert i is not None, "no hay WhateverGreen en el config"
k.insert(i + 1, {'Arch': 'x86_64', 'BundlePath': 'GraficaT470p.kext', 'Comment': 'GPU HD 630 siempre al maximo (propio, plugin de Lilu)',
                 'Enabled': True, 'ExecutablePath': 'Contents/MacOS/GraficaT470p', 'MaxKernel': '', 'MinKernel': '19.0.0', 'PlistPath': 'Contents/Info.plist'})
p['Kernel']['Add'] = k
plistlib.dump(p, open(f, 'wb'), sort_keys=False)
print("config.plist: GraficaT470p agregado despues de WhateverGreen")
PY
  [ -x "$OCV" ] && "$OCV" "$OC/config.plist" | tail -1 || true
}

case "$MODO" in
listar)
  for d in $(diskutil list external physical | awk '/^\/dev\//{print $1}'); do
    for p in $(diskutil list "$d" | awk '/EFI|Microsoft Basic Data|DOS_FAT|Windows_FAT/ {print $NF}'); do
      diskutil mount "$p" >/dev/null 2>&1 || continue
      M=$(diskutil info "$p" | awk -F': *' '/Mount Point/ {print $2}')
      [ -f "$M/EFI/OC/config.plist" ] && echo "USB con OpenCore: $p  ($(diskutil info "$p" | awk -F': *' '/Volume Name/ {print $2}'), $M)"
    done
  done
  echo "Usa: sudo bash $0 usb <identificador>";;
usb)
  P="$2"; [ -n "$P" ] || { echo "Falta el identificador (corre primero: listar)"; exit 1; }
  diskutil info "$P" | grep -qE 'Device Location: *External|Removable Media: *Removable|Protocol: *USB' || { echo "$P no parece una USB externa. No toco nada."; exit 1; }
  diskutil mount "$P" >/dev/null; MU=$(diskutil info "$P" | awk -F': *' '/Mount Point/ {print $2}')
  [ -d "$MU/EFI" ] || { echo "No hay carpeta EFI en $MU"; exit 1; }
  montar_efi_mac
  R="$LOC/respaldos/usb-OC-antes-gpu-kext-$STAMP"; mkdir -p "$R"
  [ -d "$MU/EFI/OC" ] && cp -R "$MU/EFI/OC" "$R/" && echo "Respaldo de la USB: $R"
  rm -rf "$MU/EFI/OC"; cp -R "$MPMAC/EFI/OC" "$MU/EFI/OC"
  mkdir -p "$MU/EFI/BOOT"; cp "$MPMAC/EFI/BOOT/BOOTx64.efi" "$MU/EFI/BOOT/BOOTx64.efi"
  agregar_kext "$MU/EFI/OC"
  diskutil unmount "$P" >/dev/null || true
  log ""; log "### $(date '+%Y-%m-%d %H:%M') - GraficaT470p.kext en la USB para probar"
  log "- USB $P = copia de EFI-MAC + GraficaT470p (después de WhateverGreen). Respaldo de la USB: \`respaldos/$(basename "$R")\`."
  echo "Listo. Reinicia, F12, elige la USB y arranca macOS.";;
disco)
  montar_efi_mac; OC="$MPMAC/EFI/OC"
  R="$MPMAC/BITACORA-MAC/respaldos/gpu-kext-antes-$STAMP"; mkdir -p "$R"; cp "$OC/config.plist" "$R/"; cp -R "$R" "$LOC/respaldos/"
  agregar_kext "$OC"
  log ""; log "### $(date '+%Y-%m-%d %H:%M') - GraficaT470p.kext instalado en EFI-MAC"
  log "- Respaldo: \`BITACORA-MAC/respaldos/gpu-kext-antes-$STAMP/config.plist\`. Quitar: \`sudo bash ~/hackintosh-mac/kext-gpu/gpu-kext.sh quitar\`."
  log "- Si no arranca: boot-arg \`-gt470poff\` o arrancar con la USB y correr quitar."
  diskutil unmount "$DEV" >/dev/null || true; echo "Listo. Reinicia.";;
quitar)
  montar_efi_mac; OC="$MPMAC/EFI/OC"
  # Se quita la entrada directo del config (no se depende de un respaldo: si se instalo dos veces, el ultimo ya la traia)
  cp "$OC/config.plist" "$LOC/respaldos/config-antes-de-quitar-gpu-kext-$STAMP.plist"
  /usr/bin/python3 -I - "$OC/config.plist" <<'PY2'
import plistlib, sys
f = sys.argv[1]; p = plistlib.load(open(f, 'rb'))
antes = len(p['Kernel']['Add'])
p['Kernel']['Add'] = [x for x in p['Kernel']['Add'] if x.get('BundlePath') != 'GraficaT470p.kext']
plistlib.dump(p, open(f, 'wb'), sort_keys=False)
print("entradas quitadas:", antes - len(p['Kernel']['Add']))
PY2
  rm -rf "$OC/Kexts/GraficaT470p.kext"
  [ -x "$OCV" ] && "$OCV" "$OC/config.plist" | tail -1 || true
  log ""; log "### $(date '+%Y-%m-%d %H:%M') - GraficaT470p.kext quitado de EFI-MAC (entrada borrada del config; copia en respaldos/config-antes-de-quitar-gpu-kext-$STAMP.plist)"
  diskutil unmount "$DEV" >/dev/null || true; echo "Listo. Reinicia.";;
*) sed -n 2,6p "$0";;
esac

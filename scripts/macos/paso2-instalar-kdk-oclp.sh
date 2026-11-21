#!/bin/bash
# Paso 2a: instalar KDK 25G342 y OCLP-Mod 3.1.9 (no aplica ningun parche todavia)
set -e
D=/Users/TU_USUARIO/hackintosh-mac/descargas
LOG=/Users/TU_USUARIO/hackintosh-mac/BITACORA.md
[ "$(id -u)" = 0 ] || { echo "Correr con sudo"; exit 1; }

MNT=$(hdiutil attach -nobrowse -readonly "$D/kdk/Kernel_Debug_Kit_26.7.3_build_25G342.dmg" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
PKG=$(ls "$MNT"/*.pkg | head -1)
echo "Instalando KDK: $PKG"
installer -pkg "$PKG" -target / 2>&1 | tee /tmp/kdk-install.txt
hdiutil detach "$MNT" >/dev/null || true
KDK=$(ls -d /Library/Developer/KDKs/*25G342* 2>/dev/null | head -1)

echo "Instalando OCLP-Mod"
installer -pkg "$D/oclp-mod/OCLP-Mod.pkg" -target / 2>&1 | tee /tmp/oclp-install.txt
APP=$(ls -d /Applications/OCLP-Mod*.app /Applications/OpenCore-Patcher*.app 2>/dev/null | head -1)

cat >> "$LOG" <<EOF

### $(date '+%Y-%m-%d %H:%M') - Paso 2a: KDK y OCLP-Mod instalados (sin parchar todavia)
- KDK 26.7.3 (25G342) de dortania/KdkSupportPkg, SHA256 verificado. Instalado en: ${KDK:-NO SE ENCONTRO}
- OCLP-Mod 3.1.9 (laobamac, firmado y notarizado). App: ${APP:-NO SE ENCONTRO}
- Todavia no se aplico ningun root patch; el sistema sigue sellado igual que antes.
- Para quitar: borrar el KDK de /Library/Developer/KDKs/ y correr OCLP-Mod-Uninstaller.pkg (no afectan el arranque).
EOF
echo
echo "KDK: ${KDK:-NO SE ENCONTRO}"
echo "App: ${APP:-NO SE ENCONTRO}"
echo LISTO

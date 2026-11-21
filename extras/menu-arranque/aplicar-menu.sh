#!/bin/bash
# 1) Pone el fondo ThinkPad (Background.icns) en el tema GoldenGate de OpenCanopy (EFI-MAC).
# 2) Esconde la entrada "EFI" del menu: es el shim de Linux que quedo en la EFI de Windows (\EFI\BOOT\bootx64.efi).
#    Solo se agrega el archivo de texto \EFI\BOOT\.contentVisibility con "Disabled" (OpenCore lo lee; Windows no lo usa).
#    No se borra ni se cambia nada mas de la EFI de Windows.
# Uso: sudo bash ~/hackintosh-mac/menu-arranque/aplicar-menu.sh            (aplica)
#      sudo bash ~/hackintosh-mac/menu-arranque/aplicar-menu.sh revertir   (quita el fondo y vuelve a mostrar "EFI")
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo con sudo"; exit 1; }
MODO="${1:-aplicar}"
[[ "$MODO" = aplicar || "$MODO" = revertir ]] || { echo "Uso: sudo bash $0 [revertir]"; exit 1; }
LOC=/Users/TU_USUARIO/hackintosh-mac
BIT="$LOC/BITACORA.md"
FONDO="$LOC/menu-arranque/Background.icns"
STAMP=$(date +%Y%m%d-%H%M%S)
log(){ echo "$*"; echo "$*" >> "$BIT"; }

nombre(){ diskutil info "$1" | awk -F': *' '/Volume Name/ {print $2}'; }
punto(){ diskutil info "$1" | awk -F': *' '/Mount Point/ {print $2}'; }
MAC=""; WIN=""
for d in $(diskutil list disk0 | awk '/EFI/ {print $NF}'); do
  case "$(nombre "$d")" in EFI-MAC) MAC=$d;; SYSTEM) WIN=$d;; esac
done
[ -n "$MAC" ] || { echo "No encontre EFI-MAC. No toco nada."; exit 1; }
[ -n "$WIN" ] || { echo "No encontre la EFI de Windows (SYSTEM). No toco nada."; exit 1; }

# --- Fondo en EFI-MAC ---
diskutil mount "$MAC" >/dev/null
MP=$(punto "$MAC")
TEMA="$MP/EFI/OC/Resources/Image/Acidanthera/GoldenGate"
[ -d "$TEMA" ] || { echo "No encontre el tema GoldenGate en $MP"; exit 1; }
if [ "$MODO" = aplicar ]; then
  [ -f "$FONDO" ] || { echo "Falta $FONDO"; exit 1; }
  if [ -f "$TEMA/Background.icns" ]; then
    mkdir -p "$MP/BITACORA-MAC/respaldos"; cp "$TEMA/Background.icns" "$MP/BITACORA-MAC/respaldos/Background-antes-$STAMP.icns"
  fi
  cp "$FONDO" "$TEMA/Background.icns"
  F1="Fondo: Background.icns ($(stat -f %z "$TEMA/Background.icns") bytes, PNG 1920x1080 en registro ic07) copiado a EFI\\OC\\Resources\\Image\\Acidanthera\\GoldenGate\\."
else
  rm -f "$TEMA/Background.icns"; F1="Fondo: Background.icns quitado (vuelve el fondo negro normal)."
fi

# --- .contentVisibility en la EFI de Windows ---
WMP_ANTES=$(punto "$WIN")
[ -n "$WMP_ANTES" ] || diskutil mount "$WIN" >/dev/null
WMP=$(punto "$WIN")
[ -d "$WMP/EFI/BOOT" ] || { echo "No hay \\EFI\\BOOT en la EFI de Windows; no hago nada ahi."; WMP=""; }
if [ -n "$WMP" ]; then
  if [ "$MODO" = aplicar ]; then
    printf 'Disabled' > "$WMP/EFI/BOOT/.contentVisibility"
    F2="Entrada \"EFI\": se creó \\EFI\\BOOT\\.contentVisibility = Disabled en la EFI de Windows ($WIN). Contenido de esa carpeta: $(ls -A "$WMP/EFI/BOOT" | tr '\n' ' ')"
  else
    rm -f "$WMP/EFI/BOOT/.contentVisibility"; F2="Entrada \"EFI\": se borró \\EFI\\BOOT\\.contentVisibility de la EFI de Windows (vuelve a aparecer)."
  fi
  sync
  [ -n "$WMP_ANTES" ] || diskutil unmount "$WIN" >/dev/null || true
fi

log ""
log "### $(date '+%Y-%m-%d %H:%M') - Menú de OpenCore: fondo ThinkPad y entrada \"EFI\" ($MODO)"
log "- $F1"
log "  El fondo se hace con \`swift ~/hackintosh-mac/menu-arranque/fondo.swift\` (logo ThinkPad con el punto rojo, T470p y panel con CPU, GPU, RAM, SSD, pantalla y red; el centro queda libre para los iconos)."
log "- $F2"
log "  Es el shim de Linux (bootx64.efi + fbx64.efi + BOOTIA32.EFI) que quedó de las distros que se probaron; Windows arranca por \\EFI\\Microsoft y no lo usa."
log "- Para deshacer: \`sudo bash ~/hackintosh-mac/menu-arranque/aplicar-menu.sh revertir\`. Desde Windows: borrar Background.icns del tema y \\EFI\\BOOT\\.contentVisibility de la EFI de Windows."
log "- No se tocó config.plist (el fondo es opcional para OpenCanopy: si falla al cargarlo, solo se ve el fondo negro de siempre)."
chown -R TU_USUARIO:staff "$LOC"
cp "$BIT" "$MP/BITACORA-MAC/BITACORA.md"
sync
diskutil unmount "$MAC" >/dev/null || true
echo "LISTO ($MODO). Se ve en el siguiente reinicio."

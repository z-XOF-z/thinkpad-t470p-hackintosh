#!/bin/bash
# Ajustes de fluidez del escritorio (sin sudo). Uso: bash fluidez.sh   |   bash fluidez.sh revertir
if [ "$1" = revertir ]; then
  defaults delete com.apple.universalaccess reduceTransparency 2>/dev/null
  defaults delete -g NSWindowResizeTime 2>/dev/null
  defaults delete com.apple.dock expose-animation-duration 2>/dev/null
  defaults delete com.apple.dock launchanim 2>/dev/null
  echo "Regresado a como venia macOS (la transparencia vuelve al cerrar sesion o reiniciar)."
else
  defaults write com.apple.universalaccess reduceTransparency -bool true   # sin vidrio: WindowServer y GPU trabajan mucho menos
  defaults write -g NSWindowResizeTime -float 0.001                        # ventanas y hojas de dialogo sin animacion lenta
  defaults write com.apple.dock expose-animation-duration -float 0.15      # Mission Control mas rapido
  defaults write com.apple.dock launchanim -bool false                     # sin rebote al abrir apps
  echo "Listo. La transparencia se quita al cerrar sesion o reiniciar."
fi
killall Dock

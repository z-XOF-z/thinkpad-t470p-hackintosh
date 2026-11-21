#!/bin/bash
# Agrega un modo de mas Hz al panel interno (BOE NV140FHM-N46, 1920x1080) con un "override" de pantalla de macOS.
# Se reemplaza el 2o modo del EDID (48 Hz de ahorro) por uno de N Hz con los mismos margenes; el de 60 Hz sigue
# siendo el principal, asi que la laptop SIEMPRE arranca a 60 Hz. El modo nuevo solo se usa con "PantallaHz"
# (que pide confirmar en 30 s y si no, regresa a 60 Hz).
# Uso: sudo bash ~/hackintosh-mac/pantalla/pantalla-hz.sh 75      (agrega 75 Hz; luego reiniciar)
#      sudo bash ~/hackintosh-mac/pantalla/pantalla-hz.sh quitar  (borra el override; luego reiniciar)
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo con sudo"; exit 1; }
ARG="${1:-75}"
LOC=/Users/TU_USUARIO/hackintosh-mac
BIT="$LOC/BITACORA.md"
DIR="/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-9e5"
ARCH="$DIR/DisplayProductID-6b3"

if [ "$ARG" = quitar ]; then
  rm -f "$ARCH"
  echo "Override quitado. Reinicia para volver al EDID original (60/48 Hz)."
  printf '\n### %s - Override de pantalla quitado\n- Se borró `%s`.\n' "$(date '+%Y-%m-%d %H:%M')" "$ARCH" >> "$BIT"
  exit 0
fi

HZ="$ARG"
[[ "$HZ" =~ ^[0-9]+$ ]] && [ "$HZ" -ge 50 ] && [ "$HZ" -le 120 ] || { echo "Hz invalido (50-120)"; exit 1; }
mkdir -p "$DIR"
[ -f "$ARCH" ] && cp "$ARCH" "$LOC/respaldos/override-pantalla-antes-$(date +%Y%m%d-%H%M%S).plist"

/usr/bin/python3 -I - "$HZ" "$ARCH" <<'PY'
import plistlib, sys, subprocess, re
hz, dst = int(sys.argv[1]), sys.argv[2]
# EDID original del panel (leido del registro; si ya hay override, ioreg muestra el original en IODisplayEDIDOriginal)
out = subprocess.run(["ioreg", "-l", "-w0", "-r", "-c", "AppleBacklightDisplay"], capture_output=True, text=True).stdout
m = re.search(r'"IODisplayEDIDOriginal" = <([0-9a-f]+)>', out) or re.search(r'"IODisplayEDID" = <([0-9a-f]+)>', out)
edid = bytearray(bytes.fromhex(m.group(1)))
assert edid[8:12] == bytes.fromhex("09e5b306"), "no es el panel BOE NV140FHM-N46 esperado"
d1 = edid[54:72]
pclk = d1[0] | (d1[1] << 8)                                  # en 10 kHz
ha = d1[2] | ((d1[4] & 0xF0) << 4); hb = d1[3] | ((d1[4] & 0x0F) << 8)
va = d1[5] | ((d1[7] & 0xF0) << 4); vb = d1[6] | ((d1[7] & 0x0F) << 8)
nuevo = round(pclk * hz / (pclk * 10000 / ((ha + hb) * (va + vb))))   # mismo blanking, mas reloj
d2 = bytearray(d1); d2[0] = nuevo & 0xFF; d2[1] = nuevo >> 8
edid[72:90] = d2                                             # el 2o descriptor (antes 48 Hz)
edid[127] = (256 - sum(edid[:127]) % 256) % 256              # checksum
real = nuevo * 10000 / ((ha + hb) * (va + vb))
plistlib.dump({"DisplayProductName": f"Panel ThinkPad ({hz} Hz)", "DisplayVendorID": 0x9E5, "DisplayProductID": 0x6B3,
               "IODisplayEDID": bytes(edid)}, open(dst, "wb"))
print(f"{ha}x{va}: 60 Hz = {pclk/100:.2f} MHz -> {hz} Hz = {nuevo/100:.2f} MHz (real {real:.2f} Hz)")
PY
chmod 644 "$ARCH"
printf '\n### %s - Override de pantalla a %s Hz\n- `%s` con el 2o descriptor del EDID cambiado a %s Hz (antes 48 Hz). 60 Hz sigue de principal.\n- Probar con `PantallaHz` (confirma en 30 s o regresa a 60). Quitar: `sudo bash ~/hackintosh-mac/pantalla/pantalla-hz.sh quitar` y reiniciar.\n' \
  "$(date '+%Y-%m-%d %H:%M')" "$HZ" "$ARCH" "$HZ" >> "$BIT"
echo "LISTO. Reinicia y luego corre PantallaHz para probar $HZ Hz."

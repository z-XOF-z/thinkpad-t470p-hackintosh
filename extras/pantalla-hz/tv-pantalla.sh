#!/bin/bash
# Override para la TV por HDMI (Insignia/Best Buy "LCDTV", 2016, nativa 1360x768):
#   - Fuerza RGB: quita del EDID el aviso de YCbCr 4:4:4/4:2:2 (bits 4-5 del byte 3 de la extension CEA).
#     Asi macOS manda RGB completo: texto mas nitido y colores correctos (con YCbCr se ve borroso y deslavado).
#   - Opcional: cambia el 2o modo del EDID (1280x768 a 60 Hz) por 1360x768 a N Hz (la TV declara 55-76 Hz, 170 MHz).
# No hace falta reiniciar: desconecta y vuelve a conectar el HDMI.
# Uso: sudo bash ~/hackintosh-mac/pantalla/tv-pantalla.sh rgb      (solo RGB)
#      sudo bash ~/hackintosh-mac/pantalla/tv-pantalla.sh 75       (RGB + 1360x768 a 75 Hz)
#      sudo bash ~/hackintosh-mac/pantalla/tv-pantalla.sh quitar   (regresa al EDID original)
set -e
[ "$(id -u)" = 0 ] || { echo "Correlo con sudo"; exit 1; }
ARG="${1:-rgb}"
LOC=/Users/TU_USUARIO/hackintosh-mac
BIT="$LOC/BITACORA.md"
DIR="/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-859"
ARCH="$DIR/DisplayProductID-19"

if [ "$ARG" = quitar ]; then
  rm -f "$ARCH"
  echo "Override de la TV quitado. Desconecta y vuelve a conectar el HDMI."
  printf '\n### %s - Override de la TV quitado\n' "$(date '+%Y-%m-%d %H:%M')" >> "$BIT"
  exit 0
fi
if [ "$ARG" != rgb ]; then
  [[ "$ARG" =~ ^[0-9]+$ ]] && [ "$ARG" -ge 50 ] && [ "$ARG" -le 76 ] || { echo "Hz invalido: la TV declara 55-76 Hz"; exit 1; }
fi
mkdir -p "$DIR"
[ -f "$ARCH" ] && cp "$ARCH" "$LOC/respaldos/override-tv-antes-$(date +%Y%m%d-%H%M%S).plist"

/usr/bin/python3 -I - "$ARG" "$ARCH" <<'PY'
import plistlib, sys, subprocess, re
arg, dst = sys.argv[1], sys.argv[2]
out = subprocess.run(["ioreg", "-l", "-w0"], capture_output=True, text=True).stdout
# EDID de la TV (original si ya hay override)
cands = re.findall(r'"IODisplayEDID(?:Original)?" = <(00ffffffffffff000859[0-9a-f]+)>', out)
orig = re.findall(r'"IODisplayEDIDOriginal" = <(00ffffffffffff000859[0-9a-f]+)>', out)
edid = bytearray(bytes.fromhex((orig or cands)[0]))
assert len(edid) == 256 and edid[128] == 2, "se esperaba EDID con extension CEA"
cambios = []
# 1) Forzar RGB: quitar YCbCr 4:4:4 (bit 5) y 4:2:2 (bit 4) del byte 3 de la extension
antes = edid[131]; edid[131] &= ~0x30
cambios.append(f"CEA byte 3: 0x{antes:02x} -> 0x{edid[131]:02x} (sin YCbCr, solo RGB)")
# 2) Opcional: 1360x768 a N Hz en el 2o descriptor (antes 1280x768 a 60 Hz)
if arg != "rgb":
    hz = int(arg)
    d1 = edid[54:72]
    pclk = d1[0] | (d1[1] << 8)
    ha = d1[2] | ((d1[4] & 0xF0) << 4); hb = d1[3] | ((d1[4] & 0x0F) << 8)
    va = d1[5] | ((d1[7] & 0xF0) << 4); vb = d1[6] | ((d1[7] & 0x0F) << 8)
    tot = (ha + hb) * (va + vb)
    nuevo = round(hz * tot / 10000)
    assert nuevo * 10 <= 170000, "pasa el reloj maximo de la TV (170 MHz)"
    assert nuevo * 10000 / (ha + hb) <= 80000, "pasa la frecuencia horizontal maxima (80 kHz)"
    d2 = bytearray(d1); d2[0] = nuevo & 0xFF; d2[1] = nuevo >> 8
    edid[72:90] = d2
    cambios.append(f"Modo 2: {ha}x{va} a {nuevo*10000/tot:.2f} Hz ({nuevo/100:.2f} MHz, {nuevo*10/(ha+hb):.1f} kHz)")
edid[127] = (256 - sum(edid[:127]) % 256) % 256
edid[255] = (256 - sum(edid[128:255]) % 256) % 256
plistlib.dump({"DisplayProductName": "TV (RGB)" + ("" if arg == "rgb" else f" {arg} Hz"),
               "DisplayVendorID": 0x859, "DisplayProductID": 0x19, "IODisplayEDID": bytes(edid)}, open(dst, "wb"))
print("\n".join(cambios))
PY
chmod 644 "$ARCH"
printf '\n### %s - Override de la TV (%s)\n- `%s`: sin YCbCr en el EDID (macOS manda RGB)%s.\n- Quitar: `sudo bash ~/hackintosh-mac/pantalla/tv-pantalla.sh quitar` y reconectar el HDMI.\n' \
  "$(date '+%Y-%m-%d %H:%M')" "$ARG" "$ARCH" "$([ "$ARG" = rgb ] || echo " + 1360x768 a $ARG Hz como 2o modo")" >> "$BIT"
echo "LISTO. Desconecta y vuelve a conectar el HDMI de la TV."

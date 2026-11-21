#!/bin/bash
# Escaneo USB en vivo: anota cada vez que un dispositivo aparece o desaparece y en que puerto (HSxx/SSxx).
OUT=/Users/TU_USUARIO/hackintosh-mac/salida-escaneo-usb.txt
estado(){ ioreg -p IOService -w0 -l -r -c IOUSBHostDevice 2>/dev/null | awk '
  /\+-o / {name=$0; sub(/^.*\+-o /,"",name); sub(/@.*/,"",name)}
  /"locationID" =/ {printf "%s|%x\n", name, $NF}
  ' | sort -u; }
puerto(){ # locationID -> nombre de puerto segun el arbol
  ioreg -p IOService -w0 | grep -B3 "$1" >/dev/null; }
echo "Escaneo iniciado $(date '+%H:%M:%S')" > "$OUT"
echo "Puertos con dispositivo al inicio:" >> "$OUT"
ioreg -p IOService -w0 | grep -E "(HS|SS|USR)[0-9]+@" -A1 | grep -E "(HS|SS)[0-9]+@|IOUSBHostDevice" | sed 's/<class.*//' >> "$OUT"
prev=$(estado)
end=$((SECONDS+${1:-420}))
while [ $SECONDS -lt $end ]; do
  cur=$(estado)
  if [ "$cur" != "$prev" ]; then
    echo "--- $(date '+%H:%M:%S')" >> "$OUT"
    comm -13 <(echo "$prev") <(echo "$cur") | sed 's/^/CONECTADO: /' >> "$OUT"
    comm -23 <(echo "$prev") <(echo "$cur") | sed 's/^/QUITADO:   /' >> "$OUT"
    ioreg -p IOService -w0 | awk '/(HS|SS)[0-9]+@/ {p=$0; sub(/^.*-o /,"",p); sub(/  <.*/,"",p)} /IOUSBHostDevice/ && p {d=$0; sub(/^.*-o /,"",d); sub(/  <.*/,"",d); print "   " p " -> " d; p=""}' >> "$OUT"
    prev=$cur
  fi
  sleep 1
done
echo "Escaneo terminado $(date '+%H:%M:%S')" >> "$OUT"

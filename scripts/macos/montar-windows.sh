#!/bin/bash
# Monta el disco de Windows (NTFS) con LECTURA Y ESCRITURA usando ntfs-3g + macFUSE (backend FSKit, sin kext).
# Uso: sudo bash /usr/local/sbin/montar-windows.sh            (monta con escritura)
#      sudo bash /usr/local/sbin/montar-windows.sh solo-leer  (regresa al modo normal de macOS, solo lectura)
# Seguridad: ntfs-3g se niega a escribir si Windows quedó hibernado o con "inicio rápido". En ese caso
# arranca Windows y apágalo con Inicio > Apagar (o Shift + Apagar), no lo fuerces con remove_hiberfile.
[ "$(id -u)" = 0 ] || { echo "Correlo con sudo"; exit 1; }
MODO="${1:-escribir}"
NTFS3G=/usr/local/bin/ntfs-3g
MP=/Volumes/Windows
LOG=/Users/TU_USUARIO/hackintosh-mac/salida-montar-windows.txt
# Si lo corres a mano se ve en pantalla y tambien se guarda; desde launchd solo va al archivo
if [ -t 1 ]; then exec > >(tee -a "$LOG") 2>&1; else exec >>"$LOG" 2>&1; fi
echo "=== $(date '+%Y-%m-%d %H:%M:%S') montar-windows.sh $MODO"

# Buscar la particion NTFS llamada Windows en el disco interno (esperar hasta 60 s al arrancar)
DEV=""
for i in $(seq 1 30); do
  for d in $(diskutil list disk0 | awk '/Microsoft Basic Data/ {print $NF}'); do
    [ "$(diskutil info "$d" | awk -F': *' '/Volume Name/ {print $2}')" = "Windows" ] && DEV=$d
  done
  [ -n "$DEV" ] && break; sleep 2
done
[ -n "$DEV" ] || { echo "No encontré la partición Windows"; exit 1; }
echo "Partición: /dev/$DEV"

if [ "$MODO" = solo-leer ]; then
  umount "$MP" 2>/dev/null || diskutil unmount force "$DEV" >/dev/null 2>&1
  diskutil mount "$DEV" && echo "Montado otra vez solo lectura (driver de Apple)."
  exit 0
fi

[ -x "$NTFS3G" ] || { echo "No está $NTFS3G"; exit 1; }
[ -d /Library/Filesystems/macfuse.fs ] || { echo "macFUSE no está instalado"; exit 1; }
# Montado por ntfs-3g = cualquier montaje en $MP que no sea el NTFS de Apple "(ntfs,"
montado_fuse(){ mount | grep " on $MP (" | grep -vq "(ntfs,"; }
if montado_fuse; then
  if mount | grep " on $MP (" | grep -q "(ntfs,"; then
    echo "Hay dos montajes encimados (solo lectura de Apple + ntfs-3g). Los quito y vuelvo a montar limpio."
    while mount | grep -q " on $MP ("; do umount "$MP" 2>/dev/null || diskutil unmount force "$MP" >/dev/null 2>&1 || break; done
    pkill -f "ntfs-3g /dev/$DEV" 2>/dev/null; sleep 2
  else
    echo "Ya estaba montado con ntfs-3g."; exit 0
  fi
fi

# Quitar el montaje de solo lectura de macOS
diskutil unmount "$DEV" >/dev/null 2>&1 || diskutil unmount force "$DEV" >/dev/null 2>&1
mkdir -p "$MP"

OPTS="volname=Windows,uid=501,gid=20,umask=022,windows_names,big_writes"
for BACKEND in vfs fskit; do   # vfs = kext de macFUSE (ya aprobado, mas rapido); fskit de respaldo
  if [ "$BACKEND" = fskit ]; then O="$OPTS,backend=fskit"; else O="$OPTS,local,allow_other,auto_xattr"; fi
  echo "Probando backend $BACKEND ..."
  "$NTFS3G" "/dev/$DEV" "$MP" -o "$O" &
  PID=$!
  OK=0
  for i in $(seq 1 120); do     # esperar hasta 2 min (al arrancar el kext puede tardar)
    if montado_fuse; then OK=1; break; fi
    kill -0 $PID 2>/dev/null || { wait $PID; montado_fuse && OK=1; break; }
    sleep 1
  done
  if [ $OK = 0 ]; then
    echo "El backend $BACKEND no montó (se tardó o falló)."
    kill $PID 2>/dev/null; pkill -f "ntfs-3g /dev/$DEV" 2>/dev/null; sleep 1; umount "$MP" 2>/dev/null
  fi
  if [ $OK = 1 ]; then
    sleep 1
    if touch "$MP/.prueba-escritura-mac" 2>/dev/null && rm -f "$MP/.prueba-escritura-mac"; then
      mdutil -i off "$MP" >/dev/null 2>&1 || true   # que Spotlight no indexe ni escriba en el disco de Windows
      echo "LISTO: $MP montado con escritura (ntfs-3g, backend $BACKEND)."
      exit 0
    fi
    echo "Montó pero no deja escribir; lo desmonto."
    umount "$MP" 2>/dev/null
  fi
done

echo "No se pudo montar con escritura. Regreso al modo solo lectura."
# Nunca dejar ntfs-3g vivo debajo del montaje de solo lectura
pkill -f "ntfs-3g /dev/$DEV" 2>/dev/null; sleep 1
while mount | grep -q " on $MP ("; do umount "$MP" 2>/dev/null || break; done
echo "Causas típicas: Windows hibernado o con inicio rápido (apágalo bien desde Windows),"
echo "o falta activar macFUSE en Ajustes > General > Ítems de inicio y extensiones > Extensiones del sistema de archivos."
diskutil mount "$DEV" >/dev/null 2>&1
exit 1

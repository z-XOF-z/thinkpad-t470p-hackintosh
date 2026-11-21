#!/usr/bin/env python3
"""
Instalador de la USB de macOS Tahoe para la Lenovo ThinkPad T470p (OpenCore 1.0.8).

Qué hace (no formatea nada por su cuenta):
  1. Consigue la EFI de este repo (si corres el script suelto, baja el repo de GitHub).
  2. Baja OpenCore 1.0.8 oficial para usar sus herramientas (macserial y macrecovery).
  3. Genera TU propio SMBIOS (MacBookPro16,2): número de serie, MLB, UUID y ROM.
     Nunca uses el de otra persona: rompe iMessage/FaceTime y puede bloquear la cuenta.
  4. Baja la recuperación de macOS Tahoe directo de los servidores de Apple.
  5. Deja todo listo en la carpeta "USB-T470p/" para copiarlo a una memoria USB en FAT32.

Uso:
  macOS / Linux:  curl -fsSL https://raw.githubusercontent.com/z-XOF-z/thinkpad-t470p-hackintosh/main/instalar.py | python3 -
  Windows:        irm https://raw.githubusercontent.com/z-XOF-z/thinkpad-t470p-hackintosh/main/instalar.py -OutFile instalar.py; py instalar.py
  Opciones:       --sin-macos   (solo arma la EFI)      --mac AA:BB:CC:DD:EE:FF  (ROM = MAC de tu Ethernet)
                  --salida CARPETA                        --si  (no preguntar)
"""
import argparse
import io
import os
import platform
import plistlib
import random
import shutil
import stat
import subprocess
import sys
import urllib.request
import uuid
import zipfile

REPO = "z-XOF-z/thinkpad-t470p-hackintosh"  # usuario/thinkpad-t470p-hackintosh (se llena al publicar)
OC_VERSION = "1.0.8"
OC_ZIP = f"https://github.com/acidanthera/OpenCorePkg/releases/download/{OC_VERSION}/OpenCore-{OC_VERSION}-RELEASE.zip"
SMBIOS = "MacBookPro16,2"
TAHOE_BOARD = "Mac-CFF7D910A743CAAF"  # recovery_urls.txt de OpenCore: Tahoe
UA = "t470p-hackintosh-instalador"

ROJO, VERDE, AMARILLO, NEGRITA, FIN = "\033[31m", "\033[32m", "\033[33m", "\033[1m", "\033[0m"
if os.name == "nt":
    os.system("")  # activa colores ANSI en la consola de Windows


def paso(n, texto):
    print(f"\n{ROJO}●{FIN} {NEGRITA}[{n}/5] {texto}{FIN}")


def bajar(url, destino=None):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as r:
        total = int(r.headers.get("Content-Length") or 0)
        datos = bytearray()
        while True:
            trozo = r.read(1 << 16)
            if not trozo:
                break
            datos += trozo
            if total:
                print(f"\r    {len(datos) * 100 // total:3d}%  {len(datos) >> 20} de {total >> 20} MB", end="", flush=True)
        if total:
            print()
    if destino:
        with open(destino, "wb") as f:
            f.write(datos)
    return bytes(datos)


def preguntar(texto, auto):
    if auto:
        return True
    try:
        return input(f"{AMARILLO}{texto} [s/N]: {FIN}").strip().lower() in ("s", "si", "sí", "y", "yes")
    except EOFError:  # corriendo con "| python3 -": no hay teclado, se sigue
        return True


def conseguir_efi(trabajo):
    aqui = os.path.dirname(os.path.abspath(sys.argv[0])) if sys.argv and sys.argv[0] not in ("-", "") else os.getcwd()
    local = os.path.join(aqui, "EFI", "OC", "config.plist")
    if os.path.isfile(local):
        print(f"    Uso la EFI del repo: {os.path.join(aqui, 'EFI')}")
        return os.path.join(aqui, "EFI")
    if "/" not in REPO:
        sys.exit(f"{ROJO}No encontré la carpeta EFI junto al script. Clona el repo y córrelo desde ahí.{FIN}")
    print(f"    Bajando el repo {REPO} ...")
    z = zipfile.ZipFile(io.BytesIO(bajar(f"https://github.com/{REPO}/archive/refs/heads/main.zip")))
    z.extractall(trabajo)
    raiz = os.path.join(trabajo, z.namelist()[0].split("/")[0])
    return os.path.join(raiz, "EFI")


def herramientas_oc(trabajo):
    zpath = os.path.join(trabajo, f"OpenCore-{OC_VERSION}.zip")
    if not os.path.isfile(zpath):
        print(f"    Bajando OpenCore {OC_VERSION} (acidanthera) ...")
        bajar(OC_ZIP, zpath)
    z = zipfile.ZipFile(zpath)
    z.extractall(os.path.join(trabajo, "oc"))
    util = os.path.join(trabajo, "oc", "Utilities")
    sistema = platform.system()
    if sistema == "Windows":
        macserial = os.path.join(util, "macserial", "macserial.exe")
    elif sistema == "Darwin":
        macserial = os.path.join(util, "macserial", "macserial")
    else:
        macserial = os.path.join(util, "macserial", "macserial.linux")
    if os.path.isfile(macserial) and sistema != "Windows":
        os.chmod(macserial, os.stat(macserial).st_mode | stat.S_IEXEC)
    return macserial, os.path.join(util, "macrecovery", "macrecovery.py")


def generar_smbios(macserial, mac):
    salida = subprocess.run([macserial, "-m", SMBIOS, "-g", "-n", "1"], capture_output=True, text=True, check=True).stdout
    linea = [l for l in salida.splitlines() if "|" in l][0]
    serie, mlb = [p.strip() for p in linea.split("|")]
    if mac:
        rom = bytes.fromhex(mac.replace(":", "").replace("-", ""))
        if len(rom) != 6:
            sys.exit(f"{ROJO}La MAC debe tener 6 bytes (AA:BB:CC:DD:EE:FF).{FIN}")
    else:
        rom = bytearray(random.randrange(256) for _ in range(6))
        rom[0] = (rom[0] & 0xFC) | 0x02   # MAC unicast y "administrada localmente" (válida, no choca con fabricantes)
        rom = bytes(rom)
    return serie, mlb, str(uuid.uuid4()).upper(), rom


def armar_efi(efi_origen, destino, serie, mlb, uid, rom):
    if os.path.exists(destino):
        shutil.rmtree(destino)
    shutil.copytree(efi_origen, destino)
    cfg = os.path.join(destino, "OC", "config.plist")
    with open(cfg, "rb") as f:
        p = plistlib.load(f)
    g = p["PlatformInfo"]["Generic"]
    g["SystemProductName"] = SMBIOS
    g["SystemSerialNumber"] = serie
    g["MLB"] = mlb
    g["SystemUUID"] = uid
    g["ROM"] = rom
    with open(cfg, "wb") as f:
        plistlib.dump(p, f)


def bajar_macos(macrecovery, destino):
    os.makedirs(destino, exist_ok=True)
    cmd = [sys.executable, macrecovery, "-b", TAHOE_BOARD, "-m", "00000000000000000", "-os", "latest", "-o", destino, "download"]
    print(f"    {' '.join(cmd[1:])}")
    subprocess.run(cmd, check=True)


def main():
    ap = argparse.ArgumentParser(description="USB de macOS Tahoe para ThinkPad T470p")
    ap.add_argument("--salida", default="USB-T470p")
    ap.add_argument("--sin-macos", action="store_true", help="no bajar la recuperación de macOS")
    ap.add_argument("--mac", help="MAC de tu Ethernet para la ROM (recomendado)")
    ap.add_argument("--si", action="store_true", help="no preguntar")
    a = ap.parse_args()

    print(f"""
{ROJO}  ThinkPad{FIN}  T470p  ·  macOS Tahoe  ·  OpenCore {OC_VERSION}
  Esto arma la carpeta "{a.salida}/" con la EFI y el instalador de macOS.
  No formatea ni toca tus discos.""")
    if not preguntar("¿Seguimos?", a.si):
        return

    salida = os.path.abspath(a.salida)
    trabajo = os.path.join(salida, ".trabajo")
    os.makedirs(trabajo, exist_ok=True)

    paso(1, "EFI de la T470p")
    efi = conseguir_efi(trabajo)

    paso(2, f"Herramientas de OpenCore {OC_VERSION}")
    macserial, macrecovery = herramientas_oc(trabajo)

    paso(3, f"Tu SMBIOS propio ({SMBIOS})")
    serie, mlb, uid, rom = generar_smbios(macserial, a.mac)
    armar_efi(efi, os.path.join(salida, "EFI"), serie, mlb, uid, rom)
    print(f"    Serie {serie} · MLB {mlb} · ROM {rom.hex(':')}")
    print(f"    {AMARILLO}Guarda estos datos: son tuyos y no se comparten.{FIN}")
    with open(os.path.join(salida, "MI-SMBIOS.txt"), "w", encoding="utf-8") as f:
        f.write(f"Modelo: {SMBIOS}\nSerie: {serie}\nMLB: {mlb}\nUUID: {uid}\nROM: {rom.hex(':')}\n")

    if a.sin_macos:
        paso(4, "Recuperación de macOS: omitida (--sin-macos)")
    else:
        paso(4, "Recuperación de macOS Tahoe (servidores de Apple)")
        bajar_macos(macrecovery, os.path.join(salida, "com.apple.recovery.boot"))

    shutil.rmtree(trabajo, ignore_errors=True)
    paso(5, "Listo")
    print(f"""
  {VERDE}Carpeta lista:{FIN} {salida}
  1. Formatea una USB de 16 GB en {NEGRITA}FAT32{FIN} con el nombre OPENCORE (GPT o MBR).
  2. Copia a la raíz de la USB:  EFI/  y  com.apple.recovery.boot/
  3. BIOS de la T470p (F1): Secure Boot OFF, Intel SGX OFF, Device Guard OFF,
     "Detect hardware change" OFF, arranque UEFI only. VT-d puede quedar (DisableIoMapper ya está).
  4. Arranca con F12, elige la USB y sigue la guía:  docs/instalacion.md
""")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nCancelado.")
    except subprocess.CalledProcessError as e:
        sys.exit(f"{ROJO}Falló: {' '.join(map(str, e.cmd))}{FIN}")

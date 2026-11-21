# Scripts de macOS

Son los scripts que se usaron en la T470p, tal cual (con el usuario cambiado a `TU_USUARIO`).
Cada uno explica arriba qué hace, hace respaldo antes de cambiar algo y anota el cambio en una `BITACORA.md`.
Los que tocan la EFI la buscan por el nombre `EFI-MAC`; ajústalo si la tuya se llama distinto.

| Script | Para qué |
|---|---|
| `quitar-parche-wifi-oclp.sh` | Quita el parche de WiFi viejo de OCLP-Mod (deja el audio). Correr después de cada root patch. |
| `cambiar-wifi-nativo.sh` | itlwm + HeliPort ↔ AirportItlwm (WiFi nativo). `revertir` regresa a itlwm. |
| `cambiar-layout.sh` | Cambia el `layout-id` de AppleALC (el bueno es 29). |
| `arreglar-drm-music.sh` | `unfairgva` para Apple Music. |
| `arreglar-hdmi.sh` / `arreglar-hdmi-arranque.sh` | Parche del conector HDMI y `igfxonln=1`. |
| `mejoras-cpu-estabilidad.sh` | CPUFriend, lector SD, SSDT-ECRW, menú sin tiempo límite, USB SS04, macFUSE + ntfs-3g. |
| `montar-windows.sh` | Monta el disco de Windows con escritura (ntfs-3g). |
| `paso1-applealc.sh` / `paso2-instalar-kdk-oclp.sh` | Preparación para el root patch del audio. |
| `microfono.swift` / `salida-audio.swift` | Elegir entrada/salida de audio y medir el micrófono. |
| `escanear-usb.sh` | Ver qué puerto USB usa cada dispositivo. |
| `exportar-efi.sh` | Copia la EFI de EFI-MAC para respaldarla o subirla. |

## Compilar ntfs-3g contra macFUSE
```bash
curl -LO https://tuxera.com/opensource/ntfs-3g_ntfsprogs-2026.9.28.tgz   # SHA-256 350d9415c59f7c3f...
tar xzf ntfs-3g_ntfsprogs-2026.9.28.tgz && cd ntfs-3g-2026.9.28
# macFUSE ya instalado (trae /usr/local/include/fuse y /usr/local/lib/libfuse.2.dylib)
./configure --prefix=/usr/local --with-fuse=external --disable-ldconfig --disable-crypto \
            --disable-mtab --disable-shared --enable-static
make -j4 && sudo install -m 755 src/ntfs-3g /usr/local/bin/
```
Si no tienes `pkg-config`, crea uno mínimo que responda `--cflags` con `-I/usr/local/include/fuse -D_FILE_OFFSET_BITS=64`
y `--libs` con `-L/usr/local/lib -lfuse -pthread`, y pásalo con `PKG_CONFIG=...`.

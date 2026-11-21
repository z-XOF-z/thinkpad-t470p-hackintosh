/** @file
  DiagT470p: herramienta de diagnostico propia para el menu de OpenCore (ThinkPad T470p).
  Encabezado comun: pantalla (GOP + consola de texto de OpenCore), colores, teclado y utilidades.
  SPDX-License-Identifier: BSD-3-Clause
**/
#ifndef DIAG_COMUN_H_
#define DIAG_COMUN_H_

#include <Uefi.h>
#include <Protocol/GraphicsOutput.h>
#include <Protocol/SimpleTextInEx.h>
#include <Protocol/BlockIo.h>
#include <Protocol/AtaPassThru.h>
#include <Protocol/DevicePath.h>
#include <Protocol/LoadedImage.h>
#include <Guid/GlobalVariable.h>
#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/DebugLib.h>
#include <Library/DevicePathLib.h>
#include <Library/IoLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/PrintLib.h>
#include <Library/TimerLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/UefiRuntimeServicesTableLib.h>
#include <Library/UefiLib.h>

//
// Colores (B, G, R, 0)
//
extern CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  cNegro, cFondo, cPanel, cBorde, cRojo, cRojoOsc, cBlanco, cGris,
                                            cGrisOsc, cVerde, cAmarillo, cNaranja, cAzul, cCian;

extern EFI_GRAPHICS_OUTPUT_PROTOCOL  *gGop;
extern UINT32                        gAncho, gAlto;     // pixeles
extern UINTN                         gCols, gFilas;     // celdas de texto
extern UINT32                        gCeldaW, gCeldaH;  // pixeles por celda
extern UINT64                        gTscHz;

// Atributos de texto (consola UEFI)
#define T_NORMAL   EFI_TEXT_ATTR (EFI_LIGHTGRAY, EFI_BLACK)
#define T_BLANCO   EFI_TEXT_ATTR (EFI_WHITE, EFI_BLACK)
#define T_GRIS     EFI_TEXT_ATTR (EFI_DARKGRAY, EFI_BLACK)
#define T_ROJO     EFI_TEXT_ATTR (EFI_LIGHTRED, EFI_BLACK)
#define T_VERDE    EFI_TEXT_ATTR (EFI_LIGHTGREEN, EFI_BLACK)
#define T_AMARILLO EFI_TEXT_ATTR (EFI_YELLOW, EFI_BLACK)
#define T_CIAN     EFI_TEXT_ATTR (EFI_LIGHTCYAN, EFI_BLACK)
#define T_SELEC    EFI_TEXT_ATTR (EFI_WHITE, EFI_RED)

// --- Pantalla ---
VOID   PantallaIniciar (VOID);
VOID   Limpiar (VOID);
VOID   Rect (IN UINT32 X, IN UINT32 Y, IN UINT32 W, IN UINT32 H, IN CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL *C);
VOID   Marco (IN UINT32 X, IN UINT32 Y, IN UINT32 W, IN UINT32 H, IN CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL *C);
VOID   Texto (IN UINTN Col, IN UINTN Fila, IN UINTN Attr, IN CONST CHAR16 *Fmt, ...);
VOID   Encabezado (IN CONST CHAR16 *Titulo, IN CONST CHAR16 *Ayuda);
VOID   BarraProgreso (IN UINT32 X, IN UINT32 Y, IN UINT32 W, IN UINT32 H, IN UINT64 Hecho, IN UINT64 Total);
UINT32 ColX (IN UINTN Col);
UINT32 FilaY (IN UINTN Fila);

// --- Teclado ---
EFI_INPUT_KEY  EsperarTecla (VOID);
BOOLEAN        TeclaDisponible (OUT EFI_INPUT_KEY *Tecla);
BOOLEAN        Confirmar (IN UINTN Fila, IN CONST CHAR16 *Pregunta);

// --- Tiempo ---
UINT64 Microsegundos (IN UINT64 TscDelta);

// --- EC de la ThinkPad (puertos 0x62/0x66) ---
BOOLEAN EcLee (IN UINT8 Dir, OUT UINT8 *Valor);
BOOLEAN EcLee16 (IN UINT8 Dir, OUT UINT16 *Valor);
BOOLEAN EcEscribe (IN UINT8 Dir, IN UINT8 Valor);

// --- Pantallas del menu ---
VOID DiagResumen (VOID);
VOID DiagRam (VOID);
VOID DiagDiscoInfo (VOID);
VOID DiagDiscoSuperficie (VOID);
VOID DiagDiscoReparar (VOID);
VOID DiagTeclado (VOID);
VOID DiagPantalla (VOID);
VOID DiagBateria (VOID);
VOID DiagBios (VOID);

// Utilidad: texto de tamano con unidades
VOID Tamano (OUT CHAR16 *Buf, IN UINTN BufSize, IN UINT64 Bytes);      // decimal (discos)
VOID TamanoBin (OUT CHAR16 *Buf, IN UINTN BufSize, IN UINT64 Bytes);   // binario (RAM)

#endif // DIAG_COMUN_H_

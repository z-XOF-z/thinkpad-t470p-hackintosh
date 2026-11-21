/** @file
  DiagT470p: pantalla, texto, teclado, tiempo y EC.
  SPDX-License-Identifier: BSD-3-Clause
**/
#include "Comun.h"

CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  cNegro    = { 0x00, 0x00, 0x00, 0 };
CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  cFondo    = { 0x0E, 0x0C, 0x0C, 0 };
CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  cPanel    = { 0x1C, 0x19, 0x19, 0 };
CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  cBorde    = { 0x3A, 0x36, 0x36, 0 };
CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  cRojo     = { 0x21, 0x12, 0xE3, 0 };
CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  cRojoOsc  = { 0x18, 0x0C, 0x6A, 0 };
CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  cBlanco   = { 0xF0, 0xF0, 0xF0, 0 };
CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  cGris     = { 0x90, 0x90, 0x90, 0 };
CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  cGrisOsc  = { 0x48, 0x48, 0x48, 0 };
CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  cVerde    = { 0x4C, 0xC8, 0x3C, 0 };
CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  cAmarillo = { 0x30, 0xD0, 0xF0, 0 };
CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  cNaranja  = { 0x20, 0x80, 0xF0, 0 };
CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  cAzul     = { 0xE0, 0x80, 0x30, 0 };
CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  cCian     = { 0xE0, 0xD0, 0x40, 0 };

EFI_GRAPHICS_OUTPUT_PROTOCOL  *gGop   = NULL;
UINT32                        gAncho  = 0, gAlto = 0;
UINTN                         gCols   = 80, gFilas = 25;
UINT32                        gCeldaW = 8, gCeldaH = 16;
UINT64                        gTscHz  = 0;

VOID
PantallaIniciar (
  VOID
  )
{
  UINT64  T0, T1;

  gBS->HandleProtocol (gST->ConsoleOutHandle, &gEfiGraphicsOutputProtocolGuid, (VOID **)&gGop);
  if (gGop == NULL) {
    gBS->LocateProtocol (&gEfiGraphicsOutputProtocolGuid, NULL, (VOID **)&gGop);
  }

  if (gGop != NULL) {
    gAncho = gGop->Mode->Info->HorizontalResolution;
    gAlto  = gGop->Mode->Info->VerticalResolution;
  }

  gST->ConOut->QueryMode (gST->ConOut, gST->ConOut->Mode->Mode, &gCols, &gFilas);
  if ((gCols > 0) && (gFilas > 0) && (gAncho > 0)) {
    gCeldaW = (UINT32)(gAncho / gCols);
    gCeldaH = (UINT32)(gAlto / gFilas);
  }

  gST->ConOut->EnableCursor (gST->ConOut, FALSE);

  // Frecuencia del TSC: medir 50 ms
  T0 = AsmReadTsc ();
  gBS->Stall (50000);
  T1     = AsmReadTsc ();
  gTscHz = MultU64x32 (T1 - T0, 20);
}

UINT64
Microsegundos (
  IN UINT64  TscDelta
  )
{
  if (gTscHz == 0) {
    return 0;
  }

  return DivU64x64Remainder (MultU64x32 (TscDelta, 1000000), gTscHz, NULL);
}

UINT32
ColX (
  IN UINTN  Col
  )
{
  return (UINT32)(Col * gCeldaW);
}

UINT32
FilaY (
  IN UINTN  Fila
  )
{
  return (UINT32)(Fila * gCeldaH);
}

VOID
Rect (
  IN UINT32                               X,
  IN UINT32                               Y,
  IN UINT32                               W,
  IN UINT32                               H,
  IN CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  *C
  )
{
  EFI_GRAPHICS_OUTPUT_BLT_PIXEL  P;

  if ((gGop == NULL) || (W == 0) || (H == 0) || (X >= gAncho) || (Y >= gAlto)) {
    return;
  }

  W = MIN (W, gAncho - X);
  H = MIN (H, gAlto - Y);
  P = *C;
  gGop->Blt (gGop, &P, EfiBltVideoFill, 0, 0, X, Y, W, H, 0);
}

VOID
Marco (
  IN UINT32                               X,
  IN UINT32                               Y,
  IN UINT32                               W,
  IN UINT32                               H,
  IN CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  *C
  )
{
  Rect (X, Y, W, 1, C);
  Rect (X, Y + H - 1, W, 1, C);
  Rect (X, Y, 1, H, C);
  Rect (X + W - 1, Y, 1, H, C);
}

VOID
Limpiar (
  VOID
  )
{
  gST->ConOut->SetAttribute (gST->ConOut, T_NORMAL);
  gST->ConOut->ClearScreen (gST->ConOut);
  // ClearScreen de OpenCore solo borra el texto: las graficas (GOP) se borran aparte
  Rect (0, 0, gAncho, gAlto, &cNegro);
}

VOID
Texto (
  IN UINTN         Col,
  IN UINTN         Fila,
  IN UINTN         Attr,
  IN CONST CHAR16  *Fmt,
  ...
  )
{
  VA_LIST  Args;
  CHAR16   Buf[256];

  VA_START (Args, Fmt);
  UnicodeVSPrint (Buf, sizeof (Buf), Fmt, Args);
  VA_END (Args);

  if ((Col >= gCols) || (Fila >= gFilas)) {
    return;
  }

  // No escribir en la ultima celda (haria scroll)
  if ((Fila == gFilas - 1) && (Col + StrLen (Buf) >= gCols)) {
    Buf[gCols - Col - 1] = L'\0';
  }

  gST->ConOut->SetAttribute (gST->ConOut, Attr);
  gST->ConOut->SetCursorPosition (gST->ConOut, Col, Fila);
  gST->ConOut->OutputString (gST->ConOut, Buf);
}

VOID
Encabezado (
  IN CONST CHAR16  *Titulo,
  IN CONST CHAR16  *Ayuda
  )
{
  Limpiar ();
  Rect (0, FilaY (3), gAncho, 3, &cRojo);
  Rect (ColX (1), FilaY (1), 6, gCeldaH, &cRojo);
  // "Rayitos": franjas diagonales rojas a la derecha del encabezado, cada vez mas oscuras
  {
    STATIC CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  Tonos[] = {
      { 0x21, 0x12, 0xE3, 0 }, { 0x1D, 0x10, 0xC0, 0 }, { 0x1A, 0x0E, 0x9A, 0 },
      { 0x16, 0x0C, 0x76, 0 }, { 0x12, 0x0A, 0x55, 0 }, { 0x0E, 0x08, 0x38, 0 }
    };
    UINT32  Alto = FilaY (3) - 6, F, J, X0;

    for (F = 0; F < ARRAY_SIZE (Tonos); ++F) {
      X0 = gAncho - ColX (4) - F * 34;
      for (J = 0; J < Alto; J += 2) {
        Rect (X0 - J / 2, FilaY (3) - 3 - J, 18, 2, &Tonos[F]);
      }
    }
  }
  Texto (3, 1, EFI_TEXT_ATTR (EFI_WHITE, EFI_BLACK), L"DIAGNOSTICO T470p");
  Texto (24, 1, T_ROJO, L"|");
  Texto (27, 1, T_BLANCO, L"%s", Titulo);
  if (Ayuda != NULL) {
    Texto (3, gFilas - 2, T_GRIS, L"%s", Ayuda);
  }
}

VOID
BarraProgreso (
  IN UINT32  X,
  IN UINT32  Y,
  IN UINT32  W,
  IN UINT32  H,
  IN UINT64  Hecho,
  IN UINT64  Total
  )
{
  UINT32  Lleno;

  Rect (X, Y, W, H, &cGrisOsc);
  if (Total == 0) {
    return;
  }

  Lleno = (UINT32)DivU64x64Remainder (MultU64x32 (MIN (Hecho, Total), W), Total, NULL);
  Rect (X, Y, Lleno, H, &cRojo);
}

EFI_INPUT_KEY
EsperarTecla (
  VOID
  )
{
  EFI_INPUT_KEY  Tecla;
  UINTN          Indice;

  ZeroMem (&Tecla, sizeof (Tecla));
  while (TRUE) {
    gBS->WaitForEvent (1, &gST->ConIn->WaitForKey, &Indice);
    if (!EFI_ERROR (gST->ConIn->ReadKeyStroke (gST->ConIn, &Tecla))) {
      return Tecla;
    }
  }
}

BOOLEAN
TeclaDisponible (
  OUT EFI_INPUT_KEY  *Tecla
  )
{
  return !EFI_ERROR (gST->ConIn->ReadKeyStroke (gST->ConIn, Tecla));
}

BOOLEAN
Confirmar (
  IN UINTN         Fila,
  IN CONST CHAR16  *Pregunta
  )
{
  EFI_INPUT_KEY  T;

  Texto (3, Fila, T_AMARILLO, L"%s  [S = si / cualquier otra = no]", Pregunta);
  T = EsperarTecla ();
  Texto (3, Fila, T_NORMAL, L"%-*s", gCols - 6, L"");
  return (T.UnicodeChar == L's') || (T.UnicodeChar == L'S');
}

VOID
Tamano (
  OUT CHAR16  *Buf,
  IN  UINTN   BufSize,
  IN  UINT64  Bytes
  )
{
  if (Bytes >= 1000000000ULL) {
    UnicodeSPrint (Buf, BufSize, L"%lu.%lu GB", DivU64x32 (Bytes, 1000000000), DivU64x32 (Bytes, 100000000) % 10);
  } else if (Bytes >= 1000000ULL) {
    UnicodeSPrint (Buf, BufSize, L"%lu MB", DivU64x32 (Bytes, 1000000));
  } else {
    UnicodeSPrint (Buf, BufSize, L"%lu KB", DivU64x32 (Bytes, 1000));
  }
}

VOID
TamanoBin (
  OUT CHAR16  *Buf,
  IN  UINTN   BufSize,
  IN  UINT64  Bytes
  )
{
  if (Bytes >= SIZE_1GB) {
    UnicodeSPrint (Buf, BufSize, L"%lu.%lu GB", RShiftU64 (Bytes, 30), (UINTN)DivU64x32 (MultU64x32 (Bytes & (SIZE_1GB - 1), 10), SIZE_1GB));
  } else if (Bytes >= SIZE_1MB) {
    UnicodeSPrint (Buf, BufSize, L"%lu MB", RShiftU64 (Bytes, 20));
  } else {
    UnicodeSPrint (Buf, BufSize, L"%lu KB", RShiftU64 (Bytes, 10));
  }
}

//
// EC de la ThinkPad: puertos ACPI estandar, con tiempos limite.
//
STATIC
BOOLEAN
EcEspera (
  IN UINT8    Mascara,
  IN BOOLEAN  Prendido
  )
{
  UINTN  I;

  for (I = 0; I < 2000; ++I) {
    if (((IoRead8 (0x66) & Mascara) != 0) == Prendido) {
      return TRUE;
    }

    MicroSecondDelay (10);
  }

  return FALSE;
}

BOOLEAN
EcLee (
  IN  UINT8  Dir,
  OUT UINT8  *Valor
  )
{
  if (IoRead8 (0x66) == 0xFF) {
    return FALSE;
  }

  if ((IoRead8 (0x66) & BIT0) != 0) {
    (VOID)IoRead8 (0x62);
  }

  if (!EcEspera (BIT1, FALSE)) { return FALSE; }
  IoWrite8 (0x66, 0x80);
  if (!EcEspera (BIT1, FALSE)) { return FALSE; }
  IoWrite8 (0x62, Dir);
  if (!EcEspera (BIT0, TRUE)) { return FALSE; }
  *Valor = IoRead8 (0x62);
  return TRUE;
}

BOOLEAN
EcLee16 (
  IN  UINT8   Dir,
  OUT UINT16  *Valor
  )
{
  UINT8  Lo, Hi;

  if (!EcLee (Dir, &Lo) || !EcLee ((UINT8)(Dir + 1), &Hi)) {
    return FALSE;
  }

  *Valor = (UINT16)(Lo | (Hi << 8));
  return TRUE;
}

BOOLEAN
EcEscribe (
  IN UINT8  Dir,
  IN UINT8  Valor
  )
{
  if (IoRead8 (0x66) == 0xFF) {
    return FALSE;
  }

  if (!EcEspera (BIT1, FALSE)) { return FALSE; }
  IoWrite8 (0x66, 0x81);
  if (!EcEspera (BIT1, FALSE)) { return FALSE; }
  IoWrite8 (0x62, Dir);
  if (!EcEspera (BIT1, FALSE)) { return FALSE; }
  IoWrite8 (0x62, Valor);
  return EcEspera (BIT1, FALSE);
}

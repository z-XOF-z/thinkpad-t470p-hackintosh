/** @file
  DiagT470p: resumen del sistema, bateria, teclado y pantalla.
  SPDX-License-Identifier: BSD-3-Clause
**/
#include "Comun.h"

//
// ================= RESUMEN =================
//
STATIC
VOID
MarcaCpu (
  OUT CHAR8  *Marca   // 49 bytes
  )
{
  UINT32  Regs[12];
  UINT32  Max;
  UINTN   I;
  CHAR8   *P;

  ZeroMem (Marca, 49);
  AsmCpuid (0x80000000, &Max, NULL, NULL, NULL);
  if (Max < 0x80000004) {
    AsciiStrCpyS (Marca, 49, "CPU desconocido");
    return;
  }

  for (I = 0; I < 3; ++I) {
    AsmCpuid (0x80000002 + (UINT32)I, &Regs[I * 4], &Regs[I * 4 + 1], &Regs[I * 4 + 2], &Regs[I * 4 + 3]);
  }

  CopyMem (Marca, Regs, 48);
  P = Marca;
  while (*P == ' ') {
    ++P;
  }

  if (P != Marca) {
    CopyMem (Marca, P, AsciiStrLen (P) + 1);
  }
}

STATIC CONST CHAR16  *mTipoMem[] = {
  L"Reservada", L"Cargador (codigo)", L"Cargador (datos)", L"Boot (codigo)", L"Boot (datos)",
  L"Runtime (codigo)", L"Runtime (datos)", L"Libre", L"Inutilizable", L"ACPI recuperable",
  L"ACPI NVS", L"MMIO", L"MMIO puertos", L"PAL", L"Persistente"
};

STATIC
CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL *
ColorTipo (
  IN UINT32  Tipo
  )
{
  switch (Tipo) {
    case EfiConventionalMemory:                         return &cVerde;
    case EfiBootServicesCode: case EfiBootServicesData: return &cCian;
    case EfiLoaderCode: case EfiLoaderData:             return &cAzul;
    case EfiRuntimeServicesCode: case EfiRuntimeServicesData: return &cNaranja;
    case EfiACPIReclaimMemory: case EfiACPIMemoryNVS:   return &cAmarillo;
    case EfiUnusableMemory:                             return &cRojo;
    default:                                            return &cGrisOsc;
  }
}

VOID
DiagResumen (
  VOID
  )
{
  CHAR8                  Marca[49];
  CHAR16                 B1[32], B2[32];
  UINT32                 Eax, Ebx, Ecx, Edx, Familia, Modelo, Step, Nucleos = 0, Hilos;
  UINT64                 Micro;
  UINTN                  Tam = 0, Llave, TamDesc, I, N;
  UINT32                 VerDesc;
  EFI_MEMORY_DESCRIPTOR  *Mapa = NULL, *D;
  UINT64                 PorTipo[EfiMaxMemoryType];
  UINT64                 Total = 0, Max = 0, Bytes;
  EFI_TIME               Ahora;
  UINT32                 X, Y, W, H, X0;
  UINTN                  Fila;

  Encabezado (L"Resumen del sistema", L"Cualquier tecla: regresar");

  // --- CPU ---
  MarcaCpu (Marca);
  AsmCpuid (1, &Eax, &Ebx, &Ecx, &Edx);
  Familia = (Eax >> 8) & 0xF;
  Modelo  = ((Eax >> 4) & 0xF) | (((Eax >> 16) & 0xF) << 4);
  Step    = Eax & 0xF;
  // Topologia real con CPUID 0x0B (nivel 0 = hilos por nucleo, nivel 1 = hilos del paquete).
  // (CPUID 1 y 4 dan el maximo que cabe en el APIC, no lo que hay: en la T470p decian 16/8.)
  {
    UINT32  PorNucleo = 1, Max0;
    AsmCpuid (0, &Max0, NULL, NULL, NULL);
    Hilos = (Ebx >> 16) & 0xFF;
    if (Max0 >= 0x0B) {
      AsmCpuidEx (0x0B, 0, NULL, &Ebx, NULL, NULL);
      PorNucleo = MAX (1, Ebx & 0xFFFF);
      AsmCpuidEx (0x0B, 1, NULL, &Ebx, NULL, NULL);
      Hilos = MAX (1, Ebx & 0xFFFF);
    }

    Nucleos = Hilos / PorNucleo;
  }
  AsmWriteMsr64 (0x8B, 0);
  AsmCpuid (1, NULL, NULL, NULL, NULL);
  Micro = RShiftU64 (AsmReadMsr64 (0x8B), 32);

  Texto (3, 5, T_ROJO, L"PROCESADOR");
  Texto (3, 6, T_BLANCO, L"%a", Marca);
  Texto (3, 7, T_NORMAL, L"Familia %d  Modelo 0x%02X  Stepping %d  Microcodigo 0x%lX", Familia, Modelo, Step, Micro);
  Texto (3, 8, T_NORMAL, L"%d nucleos / %d hilos   TSC %lu MHz", Nucleos, Hilos, DivU64x32 (gTscHz, 1000000));

  // --- Firmware y pantalla ---
  Texto (3, 10, T_ROJO, L"FIRMWARE Y PANTALLA");
  Texto (3, 11, T_NORMAL, L"%s  rev 0x%08X   UEFI %d.%d", gST->FirmwareVendor, gST->FirmwareRevision,
    gST->Hdr.Revision >> 16, (gST->Hdr.Revision & 0xFFFF) / 10);
  Texto (3, 12, T_NORMAL, L"GOP %d x %d   consola %d x %d celdas", gAncho, gAlto, gCols, gFilas);
  if (!EFI_ERROR (gRT->GetTime (&Ahora, NULL))) {
    Texto (3, 13, T_NORMAL, L"Reloj (RTC): %04d-%02d-%02d %02d:%02d:%02d", Ahora.Year, Ahora.Month, Ahora.Day,
      Ahora.Hour, Ahora.Minute, Ahora.Second);
  }

  // --- Mapa de memoria ---
  ZeroMem (PorTipo, sizeof (PorTipo));
  if (gBS->GetMemoryMap (&Tam, NULL, &Llave, &TamDesc, &VerDesc) == EFI_BUFFER_TOO_SMALL) {
    Tam += 16 * TamDesc;
    Mapa = AllocatePool (Tam);
    if ((Mapa != NULL) && EFI_ERROR (gBS->GetMemoryMap (&Tam, Mapa, &Llave, &TamDesc, &VerDesc))) {
      FreePool (Mapa);
      Mapa = NULL;
    }
  }

  Texto (3, 15, T_ROJO, L"MEMORIA (mapa de UEFI)");
  if (Mapa != NULL) {
    N = Tam / TamDesc;
    for (I = 0; I < N; ++I) {
      D     = (EFI_MEMORY_DESCRIPTOR *)((UINT8 *)Mapa + I * TamDesc);
      Bytes = LShiftU64 (D->NumberOfPages, 12);
      if (D->Type < EfiMaxMemoryType) {
        PorTipo[D->Type] += Bytes;
      }

      if ((D->Type < EfiMaxMemoryType) && (D->Type != EfiMemoryMappedIO) && (D->Type != EfiMemoryMappedIOPortSpace)
          && (D->Type != EfiReservedMemoryType) && (D->Type != EfiUnusableMemory) && (D->Type != EfiPalCode))
      {
        Total += Bytes;
      }

      if ((D->Type != EfiMemoryMappedIO) && (D->Type != EfiMemoryMappedIOPortSpace)) {
        Max = MAX (Max, D->PhysicalStart + Bytes);
      }
    }

    TamanoBin (B1, sizeof (B1), Total);
    TamanoBin (B2, sizeof (B2), PorTipo[EfiConventionalMemory]);
    Texto (3, 16, T_BLANCO, L"RAM utilizable: %s    libre ahora: %s    %d regiones", B1, B2, N);

    Fila = 18;
    for (I = 0; I < EfiMaxMemoryType && I < ARRAY_SIZE (mTipoMem); ++I) {
      if ((PorTipo[I] == 0) || (I == EfiMemoryMappedIO) || (I == EfiMemoryMappedIOPortSpace)) {
        continue;
      }

      TamanoBin (B1, sizeof (B1), PorTipo[I]);
      Rect (ColX (3), FilaY (Fila) + 3, gCeldaW * 2, gCeldaH - 6, ColorTipo ((UINT32)I));
      Texto (7, Fila, T_NORMAL, L"%-20s %10s", mTipoMem[I], B1);
      ++Fila;
    }

    // Barra horizontal: toda la memoria fisica por direccion, coloreada por tipo
    X0 = ColX (3);
    W  = gAncho - ColX (6);
    Y  = FilaY (Fila + 2);
    H  = gCeldaH * 3;
    Texto (3, Fila + 1, T_GRIS, L"Mapa fisico de 0 a %lu MB (cada color es un tipo de memoria):", RShiftU64 (Max, 20));
    Rect (X0, Y, W, H, &cGrisOsc);
    if (Max > 0) {
      for (I = 0; I < N; ++I) {
        D = (EFI_MEMORY_DESCRIPTOR *)((UINT8 *)Mapa + I * TamDesc);
        if ((D->Type == EfiMemoryMappedIO) || (D->Type == EfiMemoryMappedIOPortSpace) || (D->PhysicalStart >= Max)) {
          continue;
        }

        X = X0 + (UINT32)DivU64x64Remainder (MultU64x32 (D->PhysicalStart, W), Max, NULL);
        Bytes = LShiftU64 (D->NumberOfPages, 12);
        Rect (X, Y, MAX (1, (UINT32)DivU64x64Remainder (MultU64x32 (Bytes, W), Max, NULL)), H, ColorTipo (D->Type));
      }
    }

    FreePool (Mapa);
  }

  EsperarTecla ();
}

//
// ================= BATERIA (EC de la ThinkPad) =================
//
VOID
DiagBateria (
  VOID
  )
{
  UINT16         Rc = 0, Fc = 0, Ac = 0, Vo = 0, Bm = 0, Cc = 0, Dc = 0, Dv = 0, Md = 0, Om = 0, Rpm = 0, Fecha;
  UINT8          Estado = 0, Tmp = 0;
  BOOLEAN        Ok, Mwh;
  INT32          Ma;
  UINT32         Pct, Salud, X, Y, W, H, I;
  EFI_INPUT_KEY  T;
  UINT32         Historia[120];
  UINT32         NHist = 0;

  ZeroMem (Historia, sizeof (Historia));
  Encabezado (L"Bateria y sensores del EC", L"Esc: regresar   (se actualiza cada segundo)");

  while (TRUE) {
    Ok = EcEscribe (0x81, 0x01) && EcLee16 (0xA0, &Bm) && EcLee16 (0xA4, &Cc) && EcLee16 (0xA2, &Md)
         && EcEscribe (0x81, 0x02) && EcLee16 (0xA0, &Dc) && EcLee16 (0xA2, &Dv) && EcLee16 (0xA4, &Om)
         && EcEscribe (0x81, 0x00) && EcLee16 (0xA0, &Rc) && EcLee16 (0xA2, &Fc)
         && EcLee16 (0xA8, &Ac) && EcLee16 (0xAA, &Vo) && EcLee (0x38, &Estado);
    EcLee (0x78, &Tmp);
    EcLee16 (0x84, &Rpm);

    if (!Ok || (Fc == 0) || (Fc == 0xFFFF)) {
      Texto (3, 6, T_ROJO, L"No se pudo leer la bateria del EC (o no hay bateria).");
    } else {
      Mwh   = (Bm & 0x8000) != 0;
      Pct   = MIN (100U, ((UINT32)Rc * 100U + Fc / 2) / Fc);
      Salud = (Dc != 0) ? MIN (999U, ((UINT32)Fc * 1000U) / Dc) : 0;
      Ma    = (INT16)Ac;

      Texto (3, 5, T_ROJO, L"CARGA");
      Texto (3, 6, T_BLANCO, L"%3d %%   %s   ", Pct,
        ((Estado & 0x20) != 0) ? L"cargando  " : (((Estado & 0x40) != 0) ? L"en uso    " : L"conectada "));
      Texto (3, 7, T_NORMAL, L"Restante %5d %s   Completa %5d %s   ", Mwh ? Rc * 10 : Rc, Mwh ? L"mWh" : L"mAh",
        Mwh ? Fc * 10 : Fc, Mwh ? L"mWh" : L"mAh");
      Texto (3, 8, T_NORMAL, L"Voltaje %d.%03d V   Corriente %d mA   Potencia %d.%d W     ", Vo / 1000, Vo % 1000, Ma,
        (UINT32)(((UINT64)(Ma < 0 ? -Ma : Ma) * Vo) / 1000000U), (UINT32)((((UINT64)(Ma < 0 ? -Ma : Ma) * Vo) / 100000U) % 10));

      Texto (3, 10, T_ROJO, L"SALUD");
      Texto (3, 11, T_BLANCO, L"%d.%d %% de la capacidad de fabrica   ", Salud / 10, Salud % 10);
      Texto (3, 12, T_NORMAL, L"Diseno %d %s a %d.%03d V   Ciclos %d   ",
        Mwh ? Dc * 10 : Dc, Mwh ? L"mWh" : L"mAh", Dv / 1000, Dv % 1000, Cc);
      // Fecha de fabricacion (formato Smart Battery: dia | mes<<5 | (ano-1980)<<9). No se sabe en que
      // registro la deja el EC de la T470p: se prueba SBMD y SBOM y solo se muestra si tiene sentido.
      Fecha = (((Om >> 9) + 1980 >= 2010) && ((Om >> 9) + 1980 <= 2035)) ? Om : Md;
      if (((Fecha >> 9) + 1980 >= 2010) && ((Fecha >> 9) + 1980 <= 2035) && (((Fecha >> 5) & 0xF) >= 1) && (((Fecha >> 5) & 0xF) <= 12)) {
        Texto (60, 12, T_NORMAL, L"Fabricada %04d-%02d-%02d", 1980 + (Fecha >> 9), (Fecha >> 5) & 0xF, Fecha & 0x1F);
      }

      // Barra grande de carga
      X = ColX (3); Y = FilaY (14); W = ColX (60); H = gCeldaH * 2;
      Marco (X - 2, Y - 2, W + 4, H + 4, &cBorde);
      Rect (X, Y, W, H, &cGrisOsc);
      Rect (X, Y, (W * Pct) / 100, H, (Pct <= 15) ? &cRojo : ((Pct <= 35) ? &cAmarillo : &cVerde));

      // Historial (como el de macOS): barras verticales de la carga, 1 por segundo
      if (NHist < ARRAY_SIZE (Historia)) {
        Historia[NHist++] = Pct;
      } else {
        CopyMem (Historia, Historia + 1, sizeof (Historia) - sizeof (Historia[0]));
        Historia[ARRAY_SIZE (Historia) - 1] = Pct;
      }

      Texto (3, 18, T_GRIS, L"Historial (ultimos 2 minutos)");
      X = ColX (3); Y = FilaY (19); W = 8; H = gCeldaH * 8;
      Rect (X, Y, ARRAY_SIZE (Historia) * (W + 2), H, &cFondo);
      for (I = 0; I < NHist; ++I) {
        UINT32  Alto = (H * Historia[I]) / 100;
        Rect (X + I * (W + 2), Y + H - Alto, W, Alto, (Historia[I] <= 15) ? &cRojo : &cVerde);
      }
    }

    Texto (3, 29, T_ROJO, L"SENSORES");
    Texto (3, 30, T_NORMAL, L"Temperatura de la placa (TMP0): %d C     Ventilador: %d RPM     ", Tmp, Rpm);

    gBS->Stall (1000000);
    if (TeclaDisponible (&T) && ((T.ScanCode == SCAN_ESC) || (T.UnicodeChar == L'q'))) {
      break;
    }
  }
}

//
// ================= PANTALLA =================
//
VOID
DiagPantalla (
  VOID
  )
{
  STATIC CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  Solidos[] = {
    { 0, 0, 0xFF, 0 }, { 0, 0xFF, 0, 0 }, { 0xFF, 0, 0, 0 }, { 0xFF, 0xFF, 0xFF, 0 }, { 0, 0, 0, 0 },
    { 0x80, 0x80, 0x80, 0 }, { 0, 0xFF, 0xFF, 0 }, { 0xFF, 0, 0xFF, 0 }
  };
  UINTN                          I;
  UINT32                         X, Y;
  EFI_GRAPHICS_OUTPUT_BLT_PIXEL  C;
  EFI_INPUT_KEY                  T;

  for (I = 0; I < ARRAY_SIZE (Solidos) + 2; ++I) {
    Limpiar ();
    if (I < ARRAY_SIZE (Solidos)) {
      Rect (0, 0, gAncho, gAlto, &Solidos[I]);
    } else if (I == ARRAY_SIZE (Solidos)) {
      // degradado horizontal de grises
      for (X = 0; X < gAncho; X += 4) {
        C.Red = C.Green = C.Blue = (UINT8)((X * 255) / gAncho);
        C.Reserved = 0;
        Rect (X, 0, 4, gAlto, &C);
      }
    } else {
      // tablero de ajedrez fino (enfoque y escalado)
      for (Y = 0; Y < gAlto; Y += 8) {
        for (X = 0; X < gAncho; X += 8) {
          Rect (X, Y, 8, 8, (((X + Y) / 8) % 2) ? &cBlanco : &cNegro);
        }
      }
    }

    T = EsperarTecla ();
    if (T.ScanCode == SCAN_ESC) {
      break;
    }
  }
}

//
// ================= TECLADO =================
//
typedef struct {
  CONST CHAR16  *Etiqueta;
  UINT8         Fila;
  UINT8         Col;      // en cuartos de tecla
  UINT8         Ancho;    // en cuartos de tecla
  CHAR16        Uni;      // caracter que produce (sin Shift); 0 si va por ScanCode
  UINT16        Scan;     // ScanCode UEFI
  BOOLEAN       Visto;
} TECLA;

#define TU(e, f, c, a, u)  { e, f, c, a, u, 0, FALSE }
#define TS(e, f, c, a, s)  { e, f, c, a, 0, s, FALSE }

// Teclas fisicas de la T470p latinoamericana. El firmware lee el teclado como EE.UU., asi que cada tecla
// se reconoce por el caracter de EE.UU. que produce (la etiqueta es la de la tecla latinoamericana).
STATIC TECLA  mTeclas[] = {
  TS (L"Esc", 0, 0, 4, SCAN_ESC), TS (L"F1", 0, 6, 4, SCAN_F1), TS (L"F2", 0, 10, 4, SCAN_F2), TS (L"F3", 0, 14, 4, SCAN_F3),
  TS (L"F4", 0, 18, 4, SCAN_F4), TS (L"F5", 0, 23, 4, SCAN_F5), TS (L"F6", 0, 27, 4, SCAN_F6), TS (L"F7", 0, 31, 4, SCAN_F7),
  TS (L"F8", 0, 35, 4, SCAN_F8), TS (L"F9", 0, 40, 4, SCAN_F9), TS (L"F10", 0, 44, 4, SCAN_F10), TS (L"F11", 0, 48, 4, SCAN_F11),
  TS (L"F12", 0, 52, 4, SCAN_F12), TS (L"Ins", 0, 57, 4, SCAN_INSERT), TS (L"Supr", 0, 61, 4, SCAN_DELETE),

  TU (L"|", 1, 0, 4, L'`'), TU (L"1", 1, 4, 4, L'1'), TU (L"2", 1, 8, 4, L'2'), TU (L"3", 1, 12, 4, L'3'), TU (L"4", 1, 16, 4, L'4'),
  TU (L"5", 1, 20, 4, L'5'), TU (L"6", 1, 24, 4, L'6'), TU (L"7", 1, 28, 4, L'7'), TU (L"8", 1, 32, 4, L'8'), TU (L"9", 1, 36, 4, L'9'),
  TU (L"0", 1, 40, 4, L'0'), TU (L"'", 1, 44, 4, L'-'), TU (L"?", 1, 48, 4, L'='), TU (L"<-", 1, 52, 9, CHAR_BACKSPACE),

  TU (L"Tab", 2, 0, 6, CHAR_TAB), TU (L"Q", 2, 6, 4, L'q'), TU (L"W", 2, 10, 4, L'w'), TU (L"E", 2, 14, 4, L'e'), TU (L"R", 2, 18, 4, L'r'),
  TU (L"T", 2, 22, 4, L't'), TU (L"Y", 2, 26, 4, L'y'), TU (L"U", 2, 30, 4, L'u'), TU (L"I", 2, 34, 4, L'i'), TU (L"O", 2, 38, 4, L'o'),
  TU (L"P", 2, 42, 4, L'p'), TU (L"Ac", 2, 46, 4, L'['), TU (L"+", 2, 50, 4, L']'), TU (L"Enter", 2, 55, 6, CHAR_CARRIAGE_RETURN),

  TU (L"A", 3, 7, 4, L'a'), TU (L"S", 3, 11, 4, L's'), TU (L"D", 3, 15, 4, L'd'), TU (L"F", 3, 19, 4, L'f'), TU (L"G", 3, 23, 4, L'g'),
  TU (L"H", 3, 27, 4, L'h'), TU (L"J", 3, 31, 4, L'j'), TU (L"K", 3, 35, 4, L'k'), TU (L"L", 3, 39, 4, L'l'), TU (L"N~", 3, 43, 4, L';'),
  TU (L"{", 3, 47, 4, L'\''), TU (L"}", 3, 51, 4, L'\\'),

  TU (L"<", 4, 5, 4, L'\\'), TU (L"Z", 4, 9, 4, L'z'), TU (L"X", 4, 13, 4, L'x'), TU (L"C", 4, 17, 4, L'c'), TU (L"V", 4, 21, 4, L'v'),
  TU (L"B", 4, 25, 4, L'b'), TU (L"N", 4, 29, 4, L'n'), TU (L"M", 4, 33, 4, L'm'), TU (L",", 4, 37, 4, L','), TU (L".", 4, 41, 4, L'.'),
  TU (L"-", 4, 45, 4, L'/'),

  TU (L"Espacio", 5, 16, 24, L' '),
  TS (L"Inicio", 0, 66, 6, SCAN_HOME), TS (L"Fin", 1, 66, 6, SCAN_END), TS (L"RePag", 2, 66, 6, SCAN_PAGE_UP), TS (L"AvPag", 3, 66, 6, SCAN_PAGE_DOWN),
  TS (L"^", 4, 62, 4, SCAN_UP), TS (L"<", 5, 58, 4, SCAN_LEFT), TS (L"v", 5, 62, 4, SCAN_DOWN), TS (L">", 5, 66, 4, SCAN_RIGHT),
};

STATIC
VOID
DibujarTecla (
  IN CONST TECLA  *K,
  IN BOOLEAN      Ahora
  )
{
  UINT32  Unidad = gCeldaW * 3;     // cuarto de tecla = 3 columnas de texto
  UINT32  X0 = ColX (4), Y0 = FilaY (8);
  UINT32  X, Y = Y0 + K->Fila * gCeldaH * 3;
  UINT32  W = K->Ancho * Unidad - 6, H = gCeldaH * 3 - 6;
  UINTN   ColTxt, FilaTxt;

  X  = X0 + (UINT32)K->Col * (Unidad);
  Rect (X, Y, W, H, Ahora ? &cRojo : (K->Visto ? &cVerde : &cPanel));
  Marco (X, Y, W, H, &cBorde);
  ColTxt  = (X + W / 2) / gCeldaW - StrLen (K->Etiqueta) / 2;
  FilaTxt = (Y + H / 2) / gCeldaH;
  // texto con fondo negro: cuadrito negro detras de la etiqueta
  Texto (ColTxt, FilaTxt, Ahora ? T_BLANCO : (K->Visto ? T_VERDE : T_NORMAL), L"%s", K->Etiqueta);
}

VOID
DiagTeclado (
  VOID
  )
{
  UINTN          I, Vistas, Escs = 0;
  EFI_INPUT_KEY  T;
  CHAR16         U;
  INTN           Ultima = -1;

  for (I = 0; I < ARRAY_SIZE (mTeclas); ++I) {
    mTeclas[I].Visto = FALSE;
  }

  Encabezado (L"Prueba de teclado", L"Aprieta cada tecla: se pone roja al momento y verde cuando ya funciono.   Esc 3 veces: salir");
  Texto (3, 5, T_GRIS, L"Teclas que no detecta el firmware: Fn, Ctrl, Alt, Shift y Windows solas (solo se ven junto con otra).");
  for (I = 0; I < ARRAY_SIZE (mTeclas); ++I) {
    DibujarTecla (&mTeclas[I], FALSE);
  }

  while (TRUE) {
    T = EsperarTecla ();
    U = T.UnicodeChar;
    if ((U >= L'A') && (U <= L'Z')) {
      U = (CHAR16)(U - L'A' + L'a');
    }

    Escs = (T.ScanCode == SCAN_ESC) ? Escs + 1 : 0;
    if (Escs >= 3) {
      break;
    }

    if (Ultima >= 0) {
      DibujarTecla (&mTeclas[Ultima], FALSE);
    }

    Ultima = -1;
    for (I = 0; I < ARRAY_SIZE (mTeclas); ++I) {
      if (((mTeclas[I].Uni != 0) && (mTeclas[I].Uni == U)) || ((mTeclas[I].Scan != 0) && (mTeclas[I].Scan == T.ScanCode))) {
        mTeclas[I].Visto = TRUE;
        DibujarTecla (&mTeclas[I], TRUE);
        Ultima = (INTN)I;
      }
    }

    Vistas = 0;
    for (I = 0; I < ARRAY_SIZE (mTeclas); ++I) {
      Vistas += mTeclas[I].Visto ? 1 : 0;
    }

    Texto (3, 28, T_BLANCO, L"Ultima: ScanCode 0x%02X  Caracter 0x%04X '%c'      Probadas %d de %d      ",
      T.ScanCode, T.UnicodeChar, (T.UnicodeChar >= 0x20) ? T.UnicodeChar : L' ', Vistas, ARRAY_SIZE (mTeclas));
  }
}

//
// ================= BIOS Y THINKPAD =================
// Solo lectura de la BIOS (variables UEFI estandar) + control del ventilador por el EC (registro HFSP 0x2F,
// el mismo que usa YogaSMC). NO se modifica la configuracion de la BIOS (variable Setup): eso puede dejar la
// laptop sin arrancar. Para cambiar opciones de la BIOS con seguridad se usa la interfaz WMI de Lenovo en Windows.
//
STATIC
UINT8
VarByte (
  IN CONST CHAR16  *Nombre,
  IN UINT8         SiNoHay
  )
{
  UINT8  V = 0;
  UINTN  Tam = sizeof (V);

  if (EFI_ERROR (gRT->GetVariable ((CHAR16 *)Nombre, &gEfiGlobalVariableGuid, NULL, &Tam, &V))) {
    return SiNoHay;
  }

  return V;
}

STATIC
UINTN
ListarArranque (
  IN UINTN  Fila
  )
{
  UINT16  Orden[32], Actual = 0xFFFF;
  UINTN   Tam = sizeof (Orden), N, I, TamOp;
  CHAR16  Nombre[16];
  UINT8   *Op;

  TamOp = sizeof (Actual);
  gRT->GetVariable (L"BootCurrent", &gEfiGlobalVariableGuid, NULL, &TamOp, &Actual);
  if (EFI_ERROR (gRT->GetVariable (L"BootOrder", &gEfiGlobalVariableGuid, NULL, &Tam, Orden))) {
    Texto (3, Fila, T_GRIS, L"(no se pudo leer BootOrder)");
    return Fila + 1;
  }

  N = Tam / sizeof (UINT16);
  for (I = 0; I < N && I < 12; ++I) {
    UnicodeSPrint (Nombre, sizeof (Nombre), L"Boot%04X", Orden[I]);
    Op = NULL;
    TamOp = 0;
    if (gRT->GetVariable (Nombre, &gEfiGlobalVariableGuid, NULL, &TamOp, NULL) == EFI_BUFFER_TOO_SMALL) {
      Op = AllocateZeroPool (TamOp + 2);
      if ((Op != NULL) && EFI_ERROR (gRT->GetVariable (Nombre, &gEfiGlobalVariableGuid, NULL, &TamOp, Op))) {
        FreePool (Op);
        Op = NULL;
      }
    }

    // EFI_LOAD_OPTION: UINT32 Atributos, UINT16 TamRuta, CHAR16 Descripcion[]
    Texto (3, Fila + I, (Orden[I] == Actual) ? T_VERDE : T_NORMAL, L"%d. %s  %s%s", I + 1, Nombre,
      ((Op != NULL) && (TamOp > 6)) ? (CHAR16 *)(Op + 6) : L"?",
      (Orden[I] == Actual) ? L"   <- se arranco desde aqui" : L"");
    if (Op != NULL) {
      FreePool (Op);
    }
  }

  return Fila + I;
}

VOID
DiagBios (
  VOID
  )
{
  UINT64         Soporta = 0, Ind;
  UINTN          Tam, Fila;
  UINT8          Fan = 0, Nuevo;
  UINT16         Rpm = 0;
  BOOLEAN        PuedeBios;
  EFI_INPUT_KEY  T;

  Encabezado (L"BIOS y ThinkPad", L"A: ventilador auto   F: full   1-7: nivel   B: reiniciar a la BIOS   Esc: regresar");

  Texto (3, 5, T_ROJO, L"BIOS (solo lectura)");
  Texto (3, 6, T_BLANCO, L"%s   revision 0x%08X   UEFI %d.%d", gST->FirmwareVendor, gST->FirmwareRevision,
    gST->Hdr.Revision >> 16, (gST->Hdr.Revision & 0xFFFF) / 10);
  Texto (3, 7, T_NORMAL, L"Secure Boot: %s    Modo de configuracion (SetupMode): %s",
    (VarByte (L"SecureBoot", 0) == 1) ? L"ACTIVADO" : L"apagado", (VarByte (L"SetupMode", 0) == 1) ? L"si" : L"no");
  Texto (3, 8, T_GRIS, L"La info del modelo (SMBIOS) la reemplaza OpenCore con la de Mac, por eso aqui solo se ve el firmware.");

  Tam = sizeof (Soporta);
  gRT->GetVariable (L"OsIndicationsSupported", &gEfiGlobalVariableGuid, NULL, &Tam, &Soporta);
  PuedeBios = (Soporta & EFI_OS_INDICATIONS_BOOT_TO_FW_UI) != 0;

  Texto (3, 10, T_ROJO, L"ORDEN DE ARRANQUE DE LA BIOS (BootOrder)");
  Fila = ListarArranque (11);

  Texto (3, Fila + 1, T_ROJO, L"CAMBIAR OPCIONES DE LA BIOS");
  Texto (3, Fila + 2, T_NORMAL, L"Por seguridad no se editan aqui (un valor mal puesto puede dejar la laptop sin arrancar).");
  Texto (3, Fila + 3, T_NORMAL, L"%s", PuedeBios ? L"Con B se reinicia directo a la configuracion de la BIOS (funcion oficial de UEFI)."
                                                 : L"Este firmware no ofrece 'reiniciar a la BIOS': usa F1 al prender.");

  Texto (3, Fila + 5, T_ROJO, L"VENTILADOR (EC de la ThinkPad, registro HFSP 0x2F)");
  while (TRUE) {
    EcLee (0x2F, &Fan);
    EcLee16 (0x84, &Rpm);
    Texto (3, Fila + 6, T_BLANCO, L"Modo: %-24s  Velocidad: %5d RPM     ",
      ((Fan & 0x80) != 0) ? L"automatico (lo maneja el EC)" : (((Fan & 0x40) != 0) ? L"FULL (maximo, sin limite)" : L"manual"), Rpm);
    if (((Fan & 0xC0) == 0)) {
      Texto (60, Fila + 6, T_BLANCO, L"nivel %d   ", Fan & 0x07);
    }

    // barra de RPM (0 a 6000)
    Rect (ColX (3), FilaY (Fila + 8), ColX (60), gCeldaH, &cGrisOsc);
    Rect (ColX (3), FilaY (Fila + 8), (ColX (60) * MIN (Rpm, 6000)) / 6000, gCeldaH, (Rpm > 4500) ? &cRojo : &cVerde);
    Texto (3, Fila + 10, T_GRIS, L"El cambio dura hasta que arranque el sistema (en macOS lo maneja YogaSMCNC).");

    gBS->Stall (500000);
    if (!TeclaDisponible (&T)) {
      continue;
    }

    if ((T.ScanCode == SCAN_ESC) || (T.UnicodeChar == L'q')) {
      return;
    }

    Nuevo = 0xFF;
    if ((T.UnicodeChar == L'a') || (T.UnicodeChar == L'A')) {
      Nuevo = 0x80;
    } else if ((T.UnicodeChar == L'f') || (T.UnicodeChar == L'F')) {
      Nuevo = 0x40;
    } else if ((T.UnicodeChar >= L'1') && (T.UnicodeChar <= L'7')) {
      Nuevo = (UINT8)(T.UnicodeChar - L'0');
    } else if (((T.UnicodeChar == L'b') || (T.UnicodeChar == L'B')) && PuedeBios) {
      if (Confirmar (Fila + 12, L"Reiniciar ahora y entrar a la configuracion de la BIOS?")) {
        Tam = sizeof (Ind);
        Ind = 0;
        gRT->GetVariable (L"OsIndications", &gEfiGlobalVariableGuid, NULL, &Tam, &Ind);
        Ind |= EFI_OS_INDICATIONS_BOOT_TO_FW_UI;
        gRT->SetVariable (L"OsIndications", &gEfiGlobalVariableGuid,
          EFI_VARIABLE_NON_VOLATILE | EFI_VARIABLE_BOOTSERVICE_ACCESS | EFI_VARIABLE_RUNTIME_ACCESS, sizeof (Ind), &Ind);
        gRT->ResetSystem (EfiResetCold, EFI_SUCCESS, 0, NULL);
      }
    }

    if (Nuevo != 0xFF) {
      EcEscribe (0x2F, Nuevo);
    }
  }
}

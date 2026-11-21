/** @file
  DiagT470p: prueba de RAM.

  Recorre toda la memoria LIBRE (EfiConventionalMemory) en bloques de 16 MB: reserva cada bloque
  con AllocatePages(AllocateAddress), le aplica 4 patrones (escribir todo y luego verificar todo) y lo
  devuelve. Nunca toca memoria que este en uso.
    1) 0x5555...   2) 0xAAAA...   3) direccion en direccion (detecta lineas de direccion)   4) aleatorio
  Pantalla: mapa de cuadritos (cada uno = una parte de la RAM), barras de velocidad y lista de errores.

  SPDX-License-Identifier: BSD-3-Clause
**/
#include "Comun.h"

#define BLOQUE_PAG   4096U                  // 16 MB
#define BLOQUE_BYTES (BLOQUE_PAG * 4096U)
#define MAPA_COLS    96U
#define MAPA_FILAS   20U
#define MAPA_CELDAS  (MAPA_COLS * MAPA_FILAS)
#define MAX_REG      256U
#define MAX_ERR      10U
#define HIST         120U

typedef struct {
  EFI_PHYSICAL_ADDRESS  Inicio;
  UINT64                Paginas;
} REGION;

STATIC REGION  mReg[MAX_REG];
STATIC UINTN   mNumReg;
STATIC UINT64  mTotalBytes;
STATIC UINT8   mCelda[MAPA_CELDAS];     // 0 pendiente, 1 probando, 2 bien, 3 error, 4 no disponible

STATIC
UINT64
Aleatorio (
  IN OUT UINT64  *S
  )
{
  UINT64  X = *S;

  X ^= LShiftU64 (X, 13);
  X ^= RShiftU64 (X, 7);
  X ^= LShiftU64 (X, 17);
  *S = X;
  return X;
}

STATIC
VOID
LeerRegiones (
  VOID
  )
{
  UINTN                  Tam = 0, Llave, TamDesc, I;
  UINT32                 VerDesc;
  EFI_MEMORY_DESCRIPTOR  *Mapa = NULL, *D;

  mNumReg     = 0;
  mTotalBytes = 0;
  if (gBS->GetMemoryMap (&Tam, NULL, &Llave, &TamDesc, &VerDesc) != EFI_BUFFER_TOO_SMALL) {
    return;
  }

  Tam += 16 * TamDesc;
  Mapa = AllocatePool (Tam);
  if ((Mapa == NULL) || EFI_ERROR (gBS->GetMemoryMap (&Tam, Mapa, &Llave, &TamDesc, &VerDesc))) {
    if (Mapa != NULL) {
      FreePool (Mapa);
    }

    return;
  }

  for (I = 0; (I < Tam / TamDesc) && (mNumReg < MAX_REG); ++I) {
    D = (EFI_MEMORY_DESCRIPTOR *)((UINT8 *)Mapa + I * TamDesc);
    // Solo memoria libre, arriba de 1 MB y de al menos 1 bloque
    if ((D->Type == EfiConventionalMemory) && (D->PhysicalStart >= SIZE_1MB) && (D->NumberOfPages >= BLOQUE_PAG)) {
      mReg[mNumReg].Inicio  = D->PhysicalStart;
      mReg[mNumReg].Paginas = D->NumberOfPages - (D->NumberOfPages % BLOQUE_PAG);
      mTotalBytes          += LShiftU64 (mReg[mNumReg].Paginas, 12);
      ++mNumReg;
    }
  }

  FreePool (Mapa);
}

STATIC
VOID
PintarCelda (
  IN UINTN  I
  )
{
  STATIC CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  *Colores[] = { &cGrisOsc, &cAmarillo, &cVerde, &cRojo, &cFondo };
  UINT32                                      Tam = (gAncho - ColX (8)) / MAPA_COLS;
  UINT32                                      X   = ColX (4) + (UINT32)(I % MAPA_COLS) * Tam;
  UINT32                                      Y   = FilaY (8) + (UINT32)(I / MAPA_COLS) * Tam;

  Rect (X, Y, Tam - 3, Tam - 3, Colores[mCelda[I]]);
}

STATIC
VOID
MarcarRango (
  IN UINT64  Desde,   // bytes desde el inicio de la memoria probada
  IN UINT64  Bytes,
  IN UINT8   Estado
  )
{
  UINT64  C0, C1, C;

  if (mTotalBytes == 0) {
    return;
  }

  C0 = DivU64x64Remainder (MultU64x32 (Desde, MAPA_CELDAS), mTotalBytes, NULL);
  C1 = DivU64x64Remainder (MultU64x32 (Desde + Bytes, MAPA_CELDAS), mTotalBytes, NULL);
  C1 = MAX (C1, C0 + 1);
  for (C = C0; (C < C1) && (C < MAPA_CELDAS); ++C) {
    // un error nunca se borra en la misma pasada
    if ((mCelda[C] != 3) || (Estado == 0)) {
      mCelda[C] = Estado;
      PintarCelda ((UINTN)C);
    }
  }
}

//
// Prueba un bloque. Devuelve el numero de errores; guarda el primero en *DirErr/*Esperado/*Leido.
//
STATIC
UINTN
ProbarBloque (
  IN  EFI_PHYSICAL_ADDRESS  Base,
  IN  UINT64                Semilla,
  OUT UINT64                *DirErr,
  OUT UINT64                *Esperado,
  OUT UINT64                *Leido
  )
{
  volatile UINT64  *P = (volatile UINT64 *)(UINTN)Base;
  UINTN            N  = BLOQUE_BYTES / sizeof (UINT64);
  UINTN            I, Pat, Errores = 0;
  UINT64           V, S;

  for (Pat = 0; Pat < 4; ++Pat) {
    S = Semilla ^ (Base + Pat);
    for (I = 0; I < N; ++I) {
      switch (Pat) {
        case 0:  V = 0x5555555555555555ULL; break;
        case 1:  V = 0xAAAAAAAAAAAAAAAAULL; break;
        case 2:  V = (Base + I * 8) ^ Semilla; break;
        default: V = Aleatorio (&S); break;
      }

      P[I] = V;
    }

    S = Semilla ^ (Base + Pat);
    for (I = 0; I < N; ++I) {
      switch (Pat) {
        case 0:  V = 0x5555555555555555ULL; break;
        case 1:  V = 0xAAAAAAAAAAAAAAAAULL; break;
        case 2:  V = (Base + I * 8) ^ Semilla; break;
        default: V = Aleatorio (&S); break;
      }

      if (P[I] != V) {
        if (Errores == 0) {
          *DirErr   = Base + I * 8;
          *Esperado = V;
          *Leido    = P[I];
        }

        ++Errores;
      }
    }
  }

  return Errores;
}

VOID
DiagRam (
  VOID
  )
{
  UINTN                 R, I, Pasada = 0, Errores = 0, NErrList = 0, NHist = 0, Bloques = 0, NoDisp = 0;
  UINT64                Off, Hecho, T0, T1, Us, MBs, DirE = 0, EspE = 0, LeiE = 0, Semilla;
  EFI_PHYSICAL_ADDRESS  Dir;
  EFI_INPUT_KEY         T;
  BOOLEAN               Salir = FALSE;
  CHAR16                B1[32], B2[32];
  UINT32                Hist[HIST];
  UINT32                X, Y, H, Alto, MaxH;
  UINTN                 FilaInfo = 8 + (MAPA_FILAS * ((gAncho - ColX (8)) / MAPA_COLS)) / gCeldaH + 2;

  Encabezado (L"Prueba de RAM", L"Esc: detener (al terminar el bloque actual)");
  LeerRegiones ();
  if (mTotalBytes == 0) {
    Texto (3, 6, T_ROJO, L"No se encontro memoria libre para probar.");
    EsperarTecla ();
    return;
  }

  Tamano (B1, sizeof (B1), mTotalBytes);
  Texto (3, 5, T_BLANCO, L"Memoria libre a probar: %s en %d regiones (bloques de 16 MB, 4 patrones por bloque)", B1, mNumReg);
  Texto (3, 6, T_GRIS, L"Gris = pendiente   Amarillo = probando   Verde = bien   Rojo = error   Negro = en uso por el firmware");

  ZeroMem (Hist, sizeof (Hist));
  Semilla = AsmReadTsc () | 1;

  while (!Salir) {
    ++Pasada;
    ZeroMem (mCelda, sizeof (mCelda));
    for (I = 0; I < MAPA_CELDAS; ++I) {
      PintarCelda (I);
    }

    Off = 0;
    for (R = 0; (R < mNumReg) && !Salir; ++R) {
      for (Hecho = 0; (Hecho < mReg[R].Paginas) && !Salir; Hecho += BLOQUE_PAG) {
        Dir = mReg[R].Inicio + LShiftU64 (Hecho, 12);
        MarcarRango (Off, BLOQUE_BYTES, 1);

        if (EFI_ERROR (gBS->AllocatePages (AllocateAddress, EfiLoaderData, BLOQUE_PAG, &Dir))) {
          MarcarRango (Off, BLOQUE_BYTES, 4);      // lo esta usando el firmware: se salta
          ++NoDisp;
        } else {
          UINTN  E;

          T0 = AsmReadTsc ();
          E  = ProbarBloque (Dir, Semilla + Pasada, &DirE, &EspE, &LeiE);
          T1 = AsmReadTsc ();
          gBS->FreePages (Dir, BLOQUE_PAG);
          ++Bloques;

          MarcarRango (Off, BLOQUE_BYTES, (E == 0) ? 2 : 3);
          if (E != 0) {
            Errores += E;
            if (NErrList < MAX_ERR) {
              Texto (100, FilaInfo + 1 + NErrList, T_ROJO, L"0x%012lX  esperado %016lX  leido %016lX", DirE, EspE, LeiE);
              ++NErrList;
            }
          }

          // velocidad: 4 patrones x (escribir + leer) x 16 MB
          Us  = Microsegundos (T1 - T0);
          MBs = (Us != 0) ? DivU64x64Remainder (MultU64x32 (8 * 16, 1000000), Us, NULL) : 0;
          if (NHist < HIST) {
            Hist[NHist++] = (UINT32)MBs;
          } else {
            CopyMem (Hist, Hist + 1, sizeof (Hist) - sizeof (Hist[0]));
            Hist[HIST - 1] = (UINT32)MBs;
          }
        }

        Off += BLOQUE_BYTES;

        // --- estado ---
        Tamano (B1, sizeof (B1), Off);
        Tamano (B2, sizeof (B2), mTotalBytes);
        Texto (3, FilaInfo, T_BLANCO, L"Pasada %d   %s de %s   ", Pasada, B1, B2);
        Texto (3, FilaInfo + 1, (Errores == 0) ? T_VERDE : T_ROJO, L"Errores: %d   ", Errores);
        Texto (3, FilaInfo + 2, T_NORMAL, L"Velocidad: %d MB/s   Bloques probados: %d   Saltados (en uso): %d   ",
          (NHist > 0) ? Hist[NHist - 1] : 0, Bloques, NoDisp);
        BarraProgreso (ColX (3), FilaY (FilaInfo + 4), ColX (90), 10, Off, mTotalBytes);
        if (NErrList == 0) {
          Texto (100, FilaInfo, T_GRIS, L"Lista de errores (direccion, esperado, leido):");
          Texto (100, FilaInfo + 1, T_VERDE, L"ninguno");
        }

        // barras de velocidad (MB/s) de los ultimos bloques
        X    = ColX (3);
        Y    = FilaY (FilaInfo + 6);
        H    = gCeldaH * 6;
        MaxH = 1;
        for (I = 0; I < NHist; ++I) {
          MaxH = MAX (MaxH, Hist[I]);
        }

        Rect (X, Y, HIST * 6, H, &cFondo);
        for (I = 0; I < NHist; ++I) {
          Alto = (H * Hist[I]) / MaxH;
          Rect (X + (UINT32)I * 6, Y + H - Alto, 4, Alto, &cRojo);
        }

        Texto (3, FilaInfo + 13, T_GRIS, L"Velocidad por bloque (maximo %d MB/s)   ", MaxH);

        if (TeclaDisponible (&T) && (T.ScanCode == SCAN_ESC)) {
          Salir = TRUE;
        }
      }
    }

    if (!Salir) {
      Texto (3, FilaInfo + 15, (Errores == 0) ? T_VERDE : T_ROJO, L"Pasada %d terminada: %s. Sigue otra pasada (Esc para detener).",
        Pasada, (Errores == 0) ? L"SIN ERRORES" : L"HAY ERRORES EN LA RAM");
    }
  }

  Texto (3, FilaInfo + 15, (Errores == 0) ? T_VERDE : T_ROJO, L"Detenido en la pasada %d. Errores totales: %d. Cualquier tecla: regresar.          ",
    Pasada, Errores);
  EsperarTecla ();
}

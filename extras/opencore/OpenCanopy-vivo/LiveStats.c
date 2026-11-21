/** @file
  LiveStats: panel "EN VIVO" para el menu de OpenCanopy (ThinkPad T470p de Andrew).

  Cada 0.5 s lee directo del procesador:
    - Temperatura del paquete:  IA32_PACKAGE_THERM_STATUS (0x1B1) y MSR_TEMPERATURE_TARGET (0x1A2)
      (si no hay sensor de paquete: IA32_THERM_STATUS 0x19C del nucleo actual)
    - Frecuencia efectiva:      IA32_APERF/IA32_MPERF (0xE8/0xE7) x frecuencia del TSC
    - Consumo del paquete:      MSR_RAPL_POWER_UNIT (0x606) y MSR_PKG_ENERGY_STATUS (0x611)
  y del controlador embebido (EC) de la ThinkPad (puertos 0x62/0x66, solo lectura salvo HIID):
    - Bateria: HIID (0x81) = 0 -> SBRC 0xA0 (carga), SBFC 0xA2 (completa), SBAC 0xA8 (mA), SBVO 0xAA (mV),
      HB0S 0x38 (0x20 cargando, 0x40 descargando)
    - Ventilador: HSPD 0x84 (RPM, 16 bits)      - Temperatura de la placa: TMP0 0x78 (C)
  y dibuja seis tarjetas (dos filas) con valor y grafica de los ultimos 60 s, mas RAM total y reloj.
  Offsets sacados del DSDT de la T470p (LENOVO SKL). Si el EC no responde, esas tarjetas muestran "--".

  Seguridad: cada MSR se lee solo si CPUID dice que existe (o, para RAPL, si el modelo
  de CPU es uno conocido que lo tiene). Si algo no esta, esa tarjeta muestra "--".

  SPDX-License-Identifier: BSD-3-Clause
**/

#include <Uefi.h>
#include <Library/BaseLib.h>
#include <Library/BaseMemoryLib.h>
#include <Library/DebugLib.h>
#include <Library/IoLib.h>
#include <Library/TimerLib.h>
#include <Library/UefiBootServicesTableLib.h>
#include <Library/MemoryAllocationLib.h>
#include <Library/OcCpuLib.h>
#include <Library/PrintLib.h>
#include <Library/UefiRuntimeServicesTableLib.h>

#include "../OpenCanopy.h"
#include "../BmfLib.h"
#include "../GuiApp.h"
#include "BootPicker.h"
#include "LiveStats.h"
#include "LiveFont.h"

//
// Zona horaria para el reloj: el RTC queda en UTC (macOS y, con RealTimeIsUniversal, Windows).
// Andrew esta en UTC-7 todo el año.
//
#define LIVE_UTC_OFFSET_MIN  (-7 * 60)

#define LIVE_HISTORY        120U   // 120 muestras x 0.5 s = 60 s
#define LIVE_FRAMES         30U    // OpenCanopy dibuja a 60 fps -> cada 30 cuadros = 0.5 s

#define PANEL_W  (2 * CARD_X0 + 6 * CARD_W + 5 * CARD_GAP)   // 1302: seis tarjetas en una fila
#define PANEL_H  224U
#define CARD_W   200U
#define CARD_H   150U
#define CARD_GAP 14U
#define CARD_X0  16U
#define CARD_Y0  58U
#define GRAPH_H  58U

#define ROW_GAP  12U

#define EC_DATA   0x62
#define EC_CMD    0x66
#define EC_OBF    BIT0
#define EC_IBF    BIT1
#define EC_HB0S   0x38
#define EC_TMP0   0x78
#define EC_HIID   0x81
#define EC_HSPD   0x84
#define EC_SBRC   0xA0
#define EC_SBFC   0xA2
#define EC_SBAC   0xA8
#define EC_SBVO   0xAA

#define MSR_APERF            0xE8
#define MSR_MPERF            0xE7
#define MSR_THERM_STATUS     0x19C
#define MSR_TEMP_TARGET      0x1A2
#define MSR_PKG_THERM_STATUS 0x1B1
#define MSR_RAPL_UNIT        0x606
#define MSR_PKG_ENERGY       0x611

typedef struct {
  UINT8     R, G, B;
} LIVE_RGB;

STATIC CONST LIVE_RGB  mRed   = { 0xE3, 0x12, 0x21 };
STATIC CONST LIVE_RGB  mWhite = { 0xF5, 0xF5, 0xF5 };
STATIC CONST LIVE_RGB  mGray  = { 0x9E, 0x9E, 0x9E };
STATIC CONST LIVE_RGB  mDark  = { 0x30, 0x30, 0x33 };
STATIC CONST LIVE_RGB  mPanel = { 0x0C, 0x0C, 0x0E };

STATIC GUI_IMAGE  mLiveImage;
STATIC BOOLEAN    mLiveReady = FALSE;
STATIC BOOT_PICKER_GUI_CONTEXT  *mLiveGuiContext = NULL;

STATIC BOOLEAN  mHasDts, mHasPkgDts, mHasAperf, mHasRapl;
STATIC UINT32   mTjMax = 100;
STATIC UINT64   mTscHz;
STATIC UINT32   mEnergyUnitShift;

STATIC UINT64  mLastTsc, mLastAperf, mLastMperf;
STATIC UINT32  mLastEnergy;
STATIC BOOLEAN mHaveLast = FALSE;

// Valores en decimas (temp en 0.1 C, GHz en 0.01, W en 0.1)
STATIC UINT32  mHistTemp[LIVE_HISTORY];
STATIC UINT32  mHistFreq[LIVE_HISTORY];
STATIC UINT32  mHistPower[LIVE_HISTORY];
STATIC UINT32  mHistBat[LIVE_HISTORY];     // 0.1 %
STATIC UINT32  mHistFan[LIVE_HISTORY];     // RPM
STATIC UINT32  mHistBoard[LIVE_HISTORY];   // 0.1 C

STATIC BOOLEAN mEcOk = FALSE;
STATIC UINT32  LiveLast (IN CONST UINT32 *Hist);
STATIC UINT8   mBatState = 0;              // 1 cargando, 2 en uso, 0 nada
STATIC UINT32  mBatWattsX10 = 0;
STATIC UINT32  mRamMb = 0;
STATIC UINT32  mHistCount = 0;
STATIC UINT32  mHistHead  = 0;
STATIC UINT32  mFrameCounter = 0;
STATIC BOOLEAN mBlink = FALSE;

//
// ---------- Dibujo basico sobre mLiveImage (alfa premultiplicado) ----------
//
STATIC
VOID
LivePut (
  IN INT32           X,
  IN INT32           Y,
  IN CONST LIVE_RGB  *C,
  IN UINT8           A
  )
{
  EFI_GRAPHICS_OUTPUT_BLT_PIXEL  *P;
  UINT32                         Inv;

  if ((X < 0) || (Y < 0) || ((UINT32)X >= mLiveImage.Width) || ((UINT32)Y >= mLiveImage.Height) || (A == 0)) {
    return;
  }

  P   = &mLiveImage.Buffer[(UINT32)Y * mLiveImage.Width + (UINT32)X];
  Inv = 0xFF - A;
  P->Red      = (UINT8)((C->R * A) / 0xFF + (P->Red      * Inv) / 0xFF);
  P->Green    = (UINT8)((C->G * A) / 0xFF + (P->Green    * Inv) / 0xFF);
  P->Blue     = (UINT8)((C->B * A) / 0xFF + (P->Blue     * Inv) / 0xFF);
  P->Reserved = (UINT8)(A + (P->Reserved * Inv) / 0xFF);
}

STATIC
VOID
LiveRect (
  IN INT32           X,
  IN INT32           Y,
  IN UINT32          W,
  IN UINT32          H,
  IN CONST LIVE_RGB  *C,
  IN UINT8           A
  )
{
  UINT32  I, J;

  for (J = 0; J < H; ++J) {
    for (I = 0; I < W; ++I) {
      LivePut (X + (INT32)I, Y + (INT32)J, C, A);
    }
  }
}

//
// Rectangulo con esquinas redondeadas (radio R), relleno.
//
STATIC
VOID
LiveRoundRect (
  IN INT32           X,
  IN INT32           Y,
  IN UINT32          W,
  IN UINT32          H,
  IN UINT32          R,
  IN CONST LIVE_RGB  *C,
  IN UINT8           A
  )
{
  INT32  I, J, Dx, Dy;

  for (J = 0; J < (INT32)H; ++J) {
    for (I = 0; I < (INT32)W; ++I) {
      Dx = 0; Dy = 0;
      if (I < (INT32)R) { Dx = (INT32)R - I; } else if (I >= (INT32)(W - R)) { Dx = I - (INT32)(W - R) + 1; }
      if (J < (INT32)R) { Dy = (INT32)R - J; } else if (J >= (INT32)(H - R)) { Dy = J - (INT32)(H - R) + 1; }
      if ((Dx * Dx + Dy * Dy) <= (INT32)(R * R)) {
        LivePut (X + I, Y + J, C, A);
      }
    }
  }
}

//
// Texto con la fuente suavizada propia (LiveFont.h). Devuelve el ancho en pixeles.
// Si Dibujar es FALSE solo mide.
//
STATIC
CONST LIVE_GLIFO *
LiveGlifo (
  IN CONST LIVE_FUENTE  *F,
  IN CHAR16             Car
  )
{
  UINTN  I;

  for (I = 0; I < F->NumGlifos; ++I) {
    if (F->Glifos[I].Car == Car) {
      return &F->Glifos[I];
    }
  }

  return NULL;
}

STATIC
UINT32
LiveTextoF (
  IN INT32              X,
  IN INT32              Y,
  IN CONST CHAR16       *Str,
  IN CONST LIVE_FUENTE  *F,
  IN CONST LIVE_RGB     *C,
  IN BOOLEAN            Dibujar
  )
{
  CONST LIVE_GLIFO  *G;
  UINT32            Ancho = 0, I, J;
  UINT8             A;

  for (; *Str != L'\0'; ++Str) {
    G = LiveGlifo (F, *Str);
    if (G == NULL) {
      G = LiveGlifo (F, L' ');
      if (G == NULL) {
        continue;
      }
    }

    if (Dibujar) {
      for (J = 0; J < F->Alto; ++J) {
        for (I = 0; I < G->Ancho; ++I) {
          A = F->Alfa[G->Datos + J * G->Ancho + I];
          if (A != 0) {
            LivePut (X + (INT32)(Ancho + I), Y + (INT32)J, C, A);
          }
        }
      }
    }

    Ancho += G->Ancho;
  }

  return Ancho;
}

#define LiveText(X, Y, Str, F, C)  LiveTextoF ((X), (Y), (Str), (F), (C), TRUE)
#define LiveMedir(Str, F)          LiveTextoF (0, 0, (Str), (F), NULL, FALSE)

//
// Grafica: area rellena + linea, de los ultimos LIVE_HISTORY valores, con escala Min..Max.
//
STATIC
VOID
LiveGraph (
  IN INT32         X,
  IN INT32         Y,
  IN UINT32        W,
  IN UINT32        H,
  IN CONST UINT32  *Hist,
  IN UINT32        Min,
  IN UINT32        Max
  )
{
  UINT32  Col, Idx, Pos, Val, Top, PrevTop, K, Span;

  // linea base y lineas guia tenues
  LiveRect (X, Y + (INT32)H - 1, W, 1, &mDark, 0xFF);
  LiveRect (X, Y + (INT32)(H / 2), W, 1, &mDark, 0x60);

  if ((mHistCount == 0) || (Max <= Min)) {
    return;
  }

  Span    = Max - Min;
  PrevTop = H;
  for (Col = 0; Col < W; ++Col) {
    // columna -> muestra (la mas reciente a la derecha)
    Pos = (Col * LIVE_HISTORY) / W;
    if (Pos < LIVE_HISTORY - mHistCount) {
      continue;
    }

    Idx = (mHistHead + LIVE_HISTORY - (LIVE_HISTORY - Pos)) % LIVE_HISTORY;
    Val = Hist[Idx];
    Val = (Val < Min) ? Min : ((Val > Max) ? Max : Val);
    Top = H - 1 - ((Val - Min) * (H - 2)) / Span;

    // relleno con degradado (mas fuerte arriba)
    for (K = Top; K < H - 1; ++K) {
      LivePut (X + (INT32)Col, Y + (INT32)K, &mRed, (UINT8)(0x18 + ((H - K) * 0x50) / H));
    }

    // linea (une con la columna anterior)
    if (PrevTop == H) {
      PrevTop = Top;
    }

    for (K = MIN (Top, PrevTop); K <= MAX (Top, PrevTop); ++K) {
      LivePut (X + (INT32)Col, Y + (INT32)K, &mRed, 0xFF);
      LivePut (X + (INT32)Col, Y + (INT32)K + 1, &mRed, 0x80);
    }

    PrevTop = Top;
  }
}

STATIC
UINT32
LiveLast (
  IN CONST UINT32  *Hist
  )
{
  return Hist[(mHistHead + LIVE_HISTORY - 1) % LIVE_HISTORY];
}

STATIC
VOID
LiveCard (
  IN UINT32         Index,
  IN CONST CHAR16   *Title,
  IN CONST CHAR16   *Value,
  IN CONST CHAR16   *Unit,
  IN CONST UINT32   *Hist,
  IN UINT32         Min,
  IN UINT32         Max
  )
{
  INT32   X, Y;
  UINT32  Wv;

  X = (INT32)(CARD_X0 + Index * (CARD_W + CARD_GAP));
  Y = (INT32)CARD_Y0;

  LiveRoundRect (X, Y, CARD_W, CARD_H, 8, &mDark, 0x70);
  LiveText (X + 12, Y + 8, Title, &mFuenteChico, &mGray);
  Wv = LiveText (X + 10, Y + 24, Value, &mFuenteGrande, &mWhite);
  LiveText (X + 14 + (INT32)Wv, Y + 24 + 48 - 23 - 6, Unit, &mFuenteMediano, &mGray);
  LiveGraph (X + 10, Y + (INT32)(CARD_H - GRAPH_H - 10), CARD_W - 20, GRAPH_H, Hist, Min, Max);
}

//
// ---------- Controlador embebido (EC) por puertos ACPI 0x62/0x66 ----------
//
STATIC
BOOLEAN
EcEspera (
  IN UINT8    Mascara,
  IN BOOLEAN  Prendido
  )
{
  UINTN  I;

  for (I = 0; I < 2000; ++I) {        // hasta ~20 ms
    if (((IoRead8 (EC_CMD) & Mascara) != 0) == Prendido) {
      return TRUE;
    }

    MicroSecondDelay (10);
  }

  return FALSE;
}

STATIC
BOOLEAN
EcLee (
  IN  UINT8  Dir,
  OUT UINT8  *Valor
  )
{
  if ((IoRead8 (EC_CMD) & EC_OBF) != 0) {
    (VOID)IoRead8 (EC_DATA);          // descartar un byte viejo
  }

  if (!EcEspera (EC_IBF, FALSE)) { return FALSE; }
  IoWrite8 (EC_CMD, 0x80);            // RD_EC
  if (!EcEspera (EC_IBF, FALSE)) { return FALSE; }
  IoWrite8 (EC_DATA, Dir);
  if (!EcEspera (EC_OBF, TRUE)) { return FALSE; }
  *Valor = IoRead8 (EC_DATA);
  return TRUE;
}

STATIC
BOOLEAN
EcEscribe (
  IN UINT8  Dir,
  IN UINT8  Valor
  )
{
  if (!EcEspera (EC_IBF, FALSE)) { return FALSE; }
  IoWrite8 (EC_CMD, 0x81);            // WR_EC
  if (!EcEspera (EC_IBF, FALSE)) { return FALSE; }
  IoWrite8 (EC_DATA, Dir);
  if (!EcEspera (EC_IBF, FALSE)) { return FALSE; }
  IoWrite8 (EC_DATA, Valor);
  return EcEspera (EC_IBF, FALSE);
}

STATIC
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

STATIC
VOID
LiveSampleEc (
  OUT UINT32  *Bat,
  OUT UINT32  *Fan,
  OUT UINT32  *Board
  )
{
  UINT8   Estado, Temp;
  UINT16  Rc, Fc, Ac, Vo, Rpm;
  INT32   Ma;

  *Bat = 0; *Fan = 0; *Board = 0;
  if (!mEcOk) {
    return;
  }

  if (EcLee (EC_TMP0, &Temp) && (Temp > 0) && (Temp < 120)) {
    *Board = (UINT32)Temp * 10;
  }

  if (EcLee16 (EC_HSPD, &Rpm) && (Rpm < 10000)) {
    *Fan = Rpm;
  }

  // Pagina 0 de la bateria BAT0 (igual que hace _BST en el DSDT)
  if (EcEscribe (EC_HIID, 0x00)
      && EcLee16 (EC_SBRC, &Rc) && EcLee16 (EC_SBFC, &Fc)
      && EcLee16 (EC_SBAC, &Ac) && EcLee16 (EC_SBVO, &Vo)
      && (Fc != 0) && (Fc != 0xFFFF) && (Rc <= Fc + Fc / 10))
  {
    *Bat = MIN (1000U, ((UINT32)Rc * 1000U) / Fc);
    Ma   = (INT16)Ac;
    if (Ma < 0) {
      Ma = -Ma;
    }

    mBatWattsX10 = (UINT32)(((UINT64)Ma * Vo) / 100000U);   // mA x mV = uW -> W x10
  } else {
    *Bat = mHistCount ? LiveLast (mHistBat) : 0;
  }

  mBatState = 0;
  if (EcLee (EC_HB0S, &Estado)) {
    if ((Estado & 0x20) != 0) {
      mBatState = 1;
    } else if ((Estado & 0x40) != 0) {
      mBatState = 2;
    }
  }
}

//
// ---------- Lectura de sensores ----------
//
STATIC
VOID
LiveDetect (
  VOID
  )
{
  UINT32  MaxLeaf, Eax, Ebx, Ecx, Edx, Family, Model;

  AsmCpuid (0, &MaxLeaf, &Ebx, &Ecx, &Edx);
  // "GenuineIntel"
  if ((Ebx != 0x756E6547) || (Edx != 0x49656E69) || (Ecx != 0x6C65746E)) {
    return;
  }

  AsmCpuid (1, &Eax, NULL, NULL, NULL);
  Family = (Eax >> 8) & 0xF;
  Model  = ((Eax >> 4) & 0xF) | (((Eax >> 16) & 0xF) << 4);

  if (MaxLeaf >= 6) {
    AsmCpuid (6, &Eax, NULL, &Ecx, NULL);
    mHasDts    = (Eax & BIT0) != 0;
    mHasPkgDts = (Eax & BIT6) != 0;
    mHasAperf  = (Ecx & BIT0) != 0;
  }

  if (mHasDts && (Family == 6)) {
    // TjMax: bits 23:16 de MSR_TEMPERATURE_TARGET (en Intel Core desde Nehalem)
    UINT32  T = (UINT32)((AsmReadMsr64 (MSR_TEMP_TARGET) >> 16) & 0xFF);
    if ((T >= 70) && (T <= 120)) {
      mTjMax = T;
    }
  }

  // RAPL: solo en modelos Core conocidos (Sandy Bridge en adelante, cliente).
  if (Family == 6) {
    switch (Model) {
      case 0x2A: case 0x3A: case 0x3C: case 0x45: case 0x46:   // SNB, IVB, HSW
      case 0x3D: case 0x47:                                    // BDW
      case 0x4E: case 0x5E:                                    // SKL
      case 0x8E: case 0x9E:                                    // KBL / CFL (T470p: 0x9E)
      case 0xA5: case 0xA6:                                    // CML
      case 0x7E: case 0x8C: case 0x8D: case 0x97: case 0x9A:   // ICL, TGL, ADL
        mHasRapl = TRUE;
        break;
      default:
        break;
    }
  }

  if (mHasRapl) {
    mEnergyUnitShift = (UINT32)((AsmReadMsr64 (MSR_RAPL_UNIT) >> 8) & 0x1F);
  }

  mTscHz = OcGetTSCFrequency ();

  // EC: existe si el puerto de estado no flota (0xFF) y se puede leer la temperatura
  {
    UINT8  T;
    mEcOk = (IoRead8 (EC_CMD) != 0xFF) && EcLee (EC_TMP0, &T);
  }

  // RAM total: suma del mapa de memoria de UEFI (todo lo que es RAM, sin MMIO)
  {
    UINTN                  Tam = 0, Llave, TamDesc;
    UINT32                 VerDesc;
    EFI_MEMORY_DESCRIPTOR  *Mapa = NULL, *D;
    UINT64                 Paginas = 0;
    UINTN                  I;

    if (gBS->GetMemoryMap (&Tam, NULL, &Llave, &TamDesc, &VerDesc) == EFI_BUFFER_TOO_SMALL) {
      Tam += 8 * TamDesc;
      Mapa = AllocatePool (Tam);
      if ((Mapa != NULL) && !EFI_ERROR (gBS->GetMemoryMap (&Tam, Mapa, &Llave, &TamDesc, &VerDesc))) {
        for (I = 0; I < Tam / TamDesc; ++I) {
          D = (EFI_MEMORY_DESCRIPTOR *)((UINT8 *)Mapa + I * TamDesc);
          if ((D->Type != EfiMemoryMappedIO) && (D->Type != EfiMemoryMappedIOPortSpace) && (D->Type != EfiReservedMemoryType)) {
            Paginas += D->NumberOfPages;
          }
        }
      }

      if (Mapa != NULL) {
        FreePool (Mapa);
      }
    }

    mRamMb = (UINT32)RShiftU64 (Paginas, 8);   // paginas de 4 KB -> MB
  }
}

STATIC
VOID
LiveSample (
  VOID
  )
{
  UINT64  Tsc, Aperf = 0, Mperf = 0, DTsc, DA, DM;
  UINT32  Energy = 0, DE, Readout, Temp = 0, Freq = 0, Power = 0;
  UINT64  Msr;

  Tsc = AsmReadTsc ();

  if (mHasPkgDts) {
    Msr = AsmReadMsr64 (MSR_PKG_THERM_STATUS);
  } else if (mHasDts) {
    Msr = AsmReadMsr64 (MSR_THERM_STATUS);
  } else {
    Msr = 0;
  }

  if ((Msr & BIT31) != 0) {   // lectura valida
    Readout = (UINT32)((Msr >> 16) & 0x7F);
    Temp    = (Readout < mTjMax) ? (mTjMax - Readout) * 10 : 0;
  }

  if (mHasAperf) {
    Aperf = AsmReadMsr64 (MSR_APERF);
    Mperf = AsmReadMsr64 (MSR_MPERF);
  }

  if (mHasRapl) {
    Energy = (UINT32)AsmReadMsr64 (MSR_PKG_ENERGY);
  }

  if (mHaveLast) {
    DTsc = Tsc - mLastTsc;
    if (mHasAperf && (mTscHz != 0)) {
      DA = Aperf - mLastAperf;
      DM = Mperf - mLastMperf;
      if (DM != 0) {
        // GHz x100 = TSC(Hz) x DA/DM / 1e7
        Freq = (UINT32)DivU64x64Remainder (MultU64x64 (DivU64x32 (mTscHz, 10000), DA), MultU64x32 (DM, 1000), NULL);
      }
    }

    if (mHasRapl && (DTsc != 0) && (mTscHz != 0)) {
      DE = Energy - mLastEnergy;   // contador de 32 bits, la resta da la vuelta sola
      // W x10 = DE / 2^shift / (DTsc / TscHz) x 10
      Power = (UINT32)DivU64x64Remainder (
                        MultU64x64 (MultU64x32 (DE, 10), mTscHz),
                        LShiftU64 (DTsc, mEnergyUnitShift),
                        NULL
                        );
    }

    mHistTemp[mHistHead]  = Temp;
    mHistFreq[mHistHead]  = Freq;
    mHistPower[mHistHead] = Power;
    LiveSampleEc (&mHistBat[mHistHead], &mHistFan[mHistHead], &mHistBoard[mHistHead]);
    mHistHead             = (mHistHead + 1) % LIVE_HISTORY;
    if (mHistCount < LIVE_HISTORY) {
      ++mHistCount;
    }
  }

  mLastTsc    = Tsc;
  mLastAperf  = Aperf;
  mLastMperf  = Mperf;
  mLastEnergy = Energy;
  mHaveLast   = TRUE;
}

//
// ---------- Componer el panel completo ----------
//
STATIC
VOID
LiveCompose (
  VOID
  )
{
  CHAR16    Buf[32];
  EFI_TIME  Now;
  INT32     Min;
  UINT32    V, Tw;

  ZeroMem (mLiveImage.Buffer, mLiveImage.Width * mLiveImage.Height * sizeof (EFI_GRAPHICS_OUTPUT_BLT_PIXEL));

  // Fondo del panel y barra roja
  LiveRoundRect (0, 0, PANEL_W, PANEL_H, 12, &mPanel, 0xB0);
  LiveRect (0, 14, 4, PANEL_H - 28, &mRed, 0xFF);

  // Encabezado: punto rojo que parpadea + EN VIVO
  if (mBlink) {
    LiveRoundRect (18, 20, 10, 10, 5, &mRed, 0xFF);
  } else {
    LiveRoundRect (18, 20, 10, 10, 5, &mRed, 0x50);
  }

  Tw = LiveText (36, 13, L"EN VIVO", &mFuenteMediano, &mWhite);
  if (mRamMb != 0) {
    UnicodeSPrint (Buf, sizeof (Buf), L"RAM %u GB", (mRamMb + 512) / 1024);
    LiveText ((INT32)(36 + Tw + 24), 17, Buf, &mFuenteChico, &mGray);
  }

  // Reloj (UTC del RTC + zona horaria)
  if (!EFI_ERROR (gRT->GetTime (&Now, NULL))) {
    Min = (INT32)Now.Hour * 60 + (INT32)Now.Minute + LIVE_UTC_OFFSET_MIN;
    while (Min < 0) {
      Min += 24 * 60;
    }

    Min %= 24 * 60;
    UnicodeSPrint (Buf, sizeof (Buf), L"%02d:%02d:%02d", Min / 60, Min % 60, Now.Second);
    Tw = LiveMedir (Buf, &mFuenteMediano);
    LiveText ((INT32)(PANEL_W - 20 - Tw), 13, Buf, &mFuenteMediano, &mWhite);
  }

  // Tarjetas
  if (mHasDts || mHasPkgDts) {
    V = LiveLast (mHistTemp);
    UnicodeSPrint (Buf, sizeof (Buf), L"%u", (V + 5) / 10);
  } else {
    StrCpyS (Buf, ARRAY_SIZE (Buf), L"--");
  }

  LiveCard (0, L"TEMPERATURA CPU", Buf, L"C", mHistTemp, 300, 1000);

  if (mHasAperf) {
    V = LiveLast (mHistFreq);
    UnicodeSPrint (Buf, sizeof (Buf), L"%u.%02u", V / 100, V % 100);
  } else {
    StrCpyS (Buf, ARRAY_SIZE (Buf), L"--");
  }

  LiveCard (1, L"FRECUENCIA CPU", Buf, L"GHz", mHistFreq, 0, 400);

  if (mHasRapl) {
    V = LiveLast (mHistPower);
    UnicodeSPrint (Buf, sizeof (Buf), L"%u.%u", V / 10, V % 10);
  } else {
    StrCpyS (Buf, ARRAY_SIZE (Buf), L"--");
  }

  LiveCard (2, L"CONSUMO CPU", Buf, L"W", mHistPower, 0, 450);

  {
    CHAR16  Titulo[40];

    if (mEcOk && (mHistCount > 0)) {
      V = LiveLast (mHistBat);
      UnicodeSPrint (Buf, sizeof (Buf), L"%u", (V + 5) / 10);
      if (mBatState == 1) {
        UnicodeSPrint (Titulo, sizeof (Titulo), L"BATERIA  CARGA %u.%u W", mBatWattsX10 / 10, mBatWattsX10 % 10);
      } else if (mBatState == 2) {
        UnicodeSPrint (Titulo, sizeof (Titulo), L"BATERIA  USO %u.%u W", mBatWattsX10 / 10, mBatWattsX10 % 10);
      } else {
        StrCpyS (Titulo, ARRAY_SIZE (Titulo), L"BATERIA  CONECTADA");
      }
    } else {
      StrCpyS (Buf, ARRAY_SIZE (Buf), L"--");
      StrCpyS (Titulo, ARRAY_SIZE (Titulo), L"BATERIA");
    }

    LiveCard (3, Titulo, Buf, L"%", mHistBat, 0, 1000);
  }

  if (mEcOk && (mHistCount > 0)) {
    UnicodeSPrint (Buf, sizeof (Buf), L"%u", LiveLast (mHistFan));
  } else {
    StrCpyS (Buf, ARRAY_SIZE (Buf), L"--");
  }

  LiveCard (4, L"VENTILADOR", Buf, L"RPM", mHistFan, 0, 6000);

  if (mEcOk && (mHistCount > 0)) {
    UnicodeSPrint (Buf, sizeof (Buf), L"%u", (LiveLast (mHistBoard) + 5) / 10);
  } else {
    StrCpyS (Buf, ARRAY_SIZE (Buf), L"--");
  }

  LiveCard (5, L"TEMPERATURA PLACA", Buf, L"C", mHistBoard, 300, 1000);
}

//
// ---------- Integracion con OpenCanopy ----------
//
VOID
LiveStatsDraw (
  IN OUT GUI_OBJ                  *This,
  IN OUT GUI_DRAWING_CONTEXT      *DrawContext,
  IN     BOOT_PICKER_GUI_CONTEXT  *Context,
  IN     INT64                    BaseX,
  IN     INT64                    BaseY,
  IN     UINT32                   OffsetX,
  IN     UINT32                   OffsetY,
  IN     UINT32                   Width,
  IN     UINT32                   Height,
  IN     UINT8                    Opacity
  )
{
  if (mLiveReady && (mLiveImage.Buffer != NULL)) {
    GuiDrawToBuffer (&mLiveImage, Opacity, DrawContext, BaseX, BaseY, OffsetX, OffsetY, Width, Height);
  }
}

GLOBAL_REMOVE_IF_UNREFERENCED GUI_OBJ_CHILD  mLiveStatsPanel = {
  {
    0, 0, 0, 0, 0xFF,
    LiveStatsDraw,
    NULL,
    GuiObjDelegatePtrEvent,
    NULL,
    0,
    NULL
  },
  NULL
};

STATIC
BOOLEAN
LiveStatsAnimate (
  IN     BOOT_PICKER_GUI_CONTEXT  *Context,
  IN OUT GUI_DRAWING_CONTEXT      *DrawContext,
  IN     UINT64                   CurrentTime
  )
{
  if (!mLiveReady) {
    return TRUE;   // sin panel: quitar la animacion
  }

  ++mFrameCounter;
  if (mFrameCounter < LIVE_FRAMES) {
    return FALSE;
  }

  mFrameCounter = 0;
  mBlink        = !mBlink;
  LiveSample ();
  LiveCompose ();

  GuiRequestDrawCrop (
    DrawContext,
    mLiveStatsPanel.Obj.OffsetX,
    mLiveStatsPanel.Obj.OffsetY,
    mLiveStatsPanel.Obj.Width,
    mLiveStatsPanel.Obj.Height
    );
  return FALSE;   // seguir animando para siempre
}

STATIC GUI_ANIMATION  mLiveStatsAnimation = {
  { NULL, NULL },
  NULL,
  LiveStatsAnimate
};

VOID
LiveStatsInitialize (
  IN OUT GUI_DRAWING_CONTEXT      *DrawContext,
  IN     BOOT_PICKER_GUI_CONTEXT  *GuiContext
  )
{
  mLiveReady      = FALSE;
  mLiveGuiContext = GuiContext;
  mLiveStatsPanel.Obj.Width  = 0;
  mLiveStatsPanel.Obj.Height = 0;

  // Solo en pantallas grandes a escala 1 (la de la T470p: 1920x1080)
  if ((GuiContext->Scale != 1) || (DrawContext->Screen.Width < PANEL_W + 64) || (DrawContext->Screen.Height < 900)) {
    return;
  }

  mLiveImage.Width  = PANEL_W;
  mLiveImage.Height = PANEL_H;
  mLiveImage.Buffer = AllocateZeroPool (PANEL_W * PANEL_H * sizeof (EFI_GRAPHICS_OUTPUT_BLT_PIXEL));
  if (mLiveImage.Buffer == NULL) {
    return;
  }

  ZeroMem (mHistTemp, sizeof (mHistTemp));
  ZeroMem (mHistFreq, sizeof (mHistFreq));
  ZeroMem (mHistPower, sizeof (mHistPower));
  ZeroMem (mHistBat, sizeof (mHistBat));
  ZeroMem (mHistFan, sizeof (mHistFan));
  ZeroMem (mHistBoard, sizeof (mHistBoard));
  mHistCount    = 0;
  mHistHead     = 0;
  mFrameCounter = 0;
  mHaveLast     = FALSE;

  LiveDetect ();
  LiveSample ();      // primera lectura (referencia)
  LiveCompose ();

  // Centrado, entre los iconos (terminan en H/2 + ~120) y los botones de apagar/reiniciar
  // (empiezan en H - 144 - 36). En 1920x1080: y 668..892.
  mLiveStatsPanel.Obj.Width   = PANEL_W;
  mLiveStatsPanel.Obj.Height  = PANEL_H;
  mLiveStatsPanel.Obj.OffsetX = ((INT64)DrawContext->Screen.Width - PANEL_W) / 2;
  mLiveStatsPanel.Obj.OffsetY = (INT64)DrawContext->Screen.Height - 144 - 36 - 8 - PANEL_H;
  if (mLiveStatsPanel.Obj.OffsetY < (INT64)DrawContext->Screen.Height / 2 + 125) {
    FreePool (mLiveImage.Buffer);   // no cabe sin tapar los iconos: no mostrar
    mLiveImage.Buffer = NULL;
    return;
  }

  mLiveReady = TRUE;
  InitializeListHead (&mLiveStatsAnimation.Link);
  InsertHeadList (&DrawContext->Animations, &mLiveStatsAnimation.Link);
}

VOID
LiveStatsDeinitialize (
  IN OUT GUI_DRAWING_CONTEXT  *DrawContext
  )
{
  if (mLiveReady && IsNodeInList (&DrawContext->Animations, &mLiveStatsAnimation.Link)) {
    RemoveEntryList (&mLiveStatsAnimation.Link);
  }

  mLiveReady = FALSE;
  if (mLiveImage.Buffer != NULL) {
    FreePool (mLiveImage.Buffer);
    mLiveImage.Buffer = NULL;
  }
}

/** @file
  DiagT470p: discos.

  1) Informacion y S.M.A.R.T.: por EFI_ATA_PASS_THRU_PROTOCOL (discos SATA/AHCI).
     Comandos ATA estandar (ACS): IDENTIFY DEVICE (0xEC), SMART READ DATA (0xB0/0xD0),
     SMART READ THRESHOLDS (0xB0/0xD1), SMART RETURN STATUS (0xB0/0xDA). Ninguno escribe.
  2) Escaneo de superficie: por EFI_BLOCK_IO_PROTOCOL, solo ReadBlocks. Lee todo el disco en
     bloques de 256 sectores y clasifica cada lectura por tiempo, como Victoria:
     <5 ms, <20, <50, <150, <500, >=500 ms y error de lectura.

  SPDX-License-Identifier: BSD-3-Clause
**/
#include "Comun.h"

#define MAX_DISCOS  16U

//
// ================= ATA =================
//
typedef struct {
  EFI_ATA_PASS_THRU_PROTOCOL  *Ata;
  UINT16                      Puerto;
  UINT16                      Pmp;
} DISCO_ATA;

STATIC DISCO_ATA  mAta[MAX_DISCOS];
STATIC UINTN      mNumAta;

STATIC
EFI_STATUS
ComandoAta (
  IN  DISCO_ATA  *D,
  IN  UINT8      Comando,
  IN  UINT8      Feature,
  IN  BOOLEAN    ConDatos,
  OUT VOID       *Buf512,             // alineado
  OUT EFI_ATA_STATUS_BLOCK  *Estado OPTIONAL
  )
{
  EFI_ATA_COMMAND_BLOCK             Acb;
  EFI_ATA_STATUS_BLOCK              Asb;
  EFI_ATA_PASS_THRU_COMMAND_PACKET  Pkt;
  EFI_STATUS                        St;

  ZeroMem (&Acb, sizeof (Acb));
  ZeroMem (&Asb, sizeof (Asb));
  ZeroMem (&Pkt, sizeof (Pkt));
  Acb.AtaCommand  = Comando;
  Acb.AtaFeatures = Feature;
  Acb.AtaSectorCount = 1;
  if (Comando == 0xB0) {          // SMART: firma obligatoria
    Acb.AtaCylinderLow  = 0x4F;
    Acb.AtaCylinderHigh = 0xC2;
  }

  Acb.AtaDeviceHead = 0xA0;
  Pkt.Asb     = &Asb;
  Pkt.Acb     = &Acb;
  Pkt.Timeout = EFI_TIMER_PERIOD_SECONDS (5);
  if (ConDatos) {
    Pkt.InDataBuffer     = Buf512;
    Pkt.InTransferLength = 512;
    Pkt.Protocol         = EFI_ATA_PASS_THRU_PROTOCOL_PIO_DATA_IN;
    Pkt.Length           = EFI_ATA_PASS_THRU_LENGTH_BYTES;
  } else {
    Pkt.Protocol = EFI_ATA_PASS_THRU_PROTOCOL_ATA_NON_DATA;
    Pkt.Length   = EFI_ATA_PASS_THRU_LENGTH_NO_DATA_TRANSFER;
  }

  St = D->Ata->PassThru (D->Ata, D->Puerto, D->Pmp, &Pkt, NULL);
  if (Estado != NULL) {
    *Estado = Asb;
  }

  return St;
}

STATIC
VOID
BuscarAta (
  VOID
  )
{
  EFI_HANDLE                  *Handles = NULL;
  UINTN                       N = 0, I;
  EFI_ATA_PASS_THRU_PROTOCOL  *Ata;
  UINT16                      Puerto, Pmp;

  mNumAta = 0;
  if (EFI_ERROR (gBS->LocateHandleBuffer (ByProtocol, &gEfiAtaPassThruProtocolGuid, NULL, &N, &Handles))) {
    return;
  }

  for (I = 0; I < N; ++I) {
    if (EFI_ERROR (gBS->HandleProtocol (Handles[I], &gEfiAtaPassThruProtocolGuid, (VOID **)&Ata))) {
      continue;
    }

    Puerto = 0xFFFF;
    while (!EFI_ERROR (Ata->GetNextPort (Ata, &Puerto)) && (mNumAta < MAX_DISCOS)) {
      Pmp = 0xFFFF;
      while (!EFI_ERROR (Ata->GetNextDevice (Ata, Puerto, &Pmp)) && (mNumAta < MAX_DISCOS)) {
        mAta[mNumAta].Ata    = Ata;
        mAta[mNumAta].Puerto = Puerto;
        mAta[mNumAta].Pmp    = Pmp;
        ++mNumAta;
      }
    }
  }

  FreePool (Handles);
}

// Cadena ATA: palabras con los bytes al reves, rellena con espacios
STATIC
VOID
CadenaAta (
  IN  CONST UINT16  *Id,
  IN  UINTN         Palabra,
  IN  UINTN         NumPal,
  OUT CHAR8         *Sal       // NumPal*2 + 1
  )
{
  UINTN  I;
  INTN   F;

  for (I = 0; I < NumPal; ++I) {
    Sal[I * 2]     = (CHAR8)(Id[Palabra + I] >> 8);
    Sal[I * 2 + 1] = (CHAR8)(Id[Palabra + I] & 0xFF);
  }

  Sal[NumPal * 2] = '\0';
  for (F = (INTN)NumPal * 2 - 1; F >= 0 && Sal[F] == ' '; --F) {
    Sal[F] = '\0';
  }

  for (I = 0; Sal[I] == ' '; ++I) {
  }

  if (I > 0) {
    CopyMem (Sal, Sal + I, AsciiStrLen (Sal + I) + 1);
  }
}

typedef struct {
  UINT8         Id;
  CONST CHAR16  *Nombre;
} ATRIBUTO;

STATIC CONST ATRIBUTO  mNombres[] = {
  { 0x01, L"Errores de lectura" },        { 0x05, L"Sectores reasignados" },       { 0x09, L"Horas encendido" },
  { 0x0C, L"Veces encendido" },           { 0x0A, L"Reintentos de giro" },          { 0x7F, L"(fabricante)" },
  { 0xA0, L"Sectores no corregibles" },   { 0xA1, L"Bloques validos" },             { 0xA3, L"Bloques iniciales malos" },
  { 0xA4, L"Total de borrados" },         { 0xA5, L"Borrados maximo" },             { 0xA6, L"Borrados minimo" },
  { 0xA7, L"Bloques malos (tarde)" },     { 0xA9, L"Vida restante %" },             { 0xAA, L"Bloques de reserva" },
  { 0xAB, L"Fallas de programacion" },    { 0xAC, L"Fallas de borrado" },           { 0xAD, L"Nivel de desgaste" },
  { 0xAE, L"Apagones inesperados" },      { 0xAF, L"Fallas de programacion" },     { 0xB1, L"Nivel de desgaste" },
  { 0xB4, L"Bloques de reserva libres" }, { 0xB5, L"Fallas de programacion" },     { 0xB6, L"Fallas de borrado" },
  { 0xB7, L"Bajadas de velocidad SATA" }, { 0xBB, L"Errores no corregidos" },       { 0xBC, L"Comandos con timeout" },
  { 0xBE, L"Temperatura del aire" },      { 0xC0, L"Apagones bruscos" },            { 0xC2, L"Temperatura" },
  { 0xC3, L"ECC corregidos" },            { 0xC4, L"Eventos de reasignacion" },     { 0xC5, L"Sectores pendientes" },
  { 0xC6, L"Sectores incorregibles" },    { 0xC7, L"Errores CRC (cable)" },         { 0xCE, L"Errores de escritura" },
  { 0xE7, L"Vida restante SSD" },         { 0xE8, L"Reserva disponible" },          { 0xE9, L"GB escritos a NAND" },
  { 0xEA, L"GB leidos/escritos" },        { 0xF1, L"GB escritos (host)" },          { 0xF2, L"GB leidos (host)" },
  { 0xF5, L"Vida restante SSD" },         { 0xF6, L"Escrituras totales" },
};

STATIC
CONST CHAR16 *
NombreAtributo (
  IN UINT8  Id
  )
{
  UINTN  I;

  for (I = 0; I < ARRAY_SIZE (mNombres); ++I) {
    if (mNombres[I].Id == Id) {
      return mNombres[I].Nombre;
    }
  }

  return L"-";
}

// Atributos "criticos": si su valor crudo es > 0 hay que preocuparse
STATIC
BOOLEAN
Critico (
  IN UINT8  Id
  )
{
  return (Id == 0x05) || (Id == 0xC4) || (Id == 0xC5) || (Id == 0xC6) || (Id == 0xBB) || (Id == 0xA0) || (Id == 0xAB) || (Id == 0xAC);
}

STATIC
VOID
MostrarDiscoAta (
  IN DISCO_ATA  *D,
  IN UINTN      Num
  )
{
  UINT16                *Id;
  UINT8                 *Smart, *Umbral;
  CHAR8                 Modelo[41], Serie[21], Firmware[9];
  UINT64                Sectores;
  CHAR16                B1[32];
  EFI_ATA_STATUS_BLOCK  Est;
  UINTN                 I, Fila;
  UINT8                 IdAtr, Actual, Peor, Lim;
  UINT64                Crudo;
  BOOLEAN               SmartOk, Malo = FALSE, Aviso = FALSE;
  UINT32                X, Y, W;
  UINT32                Horas = 0, Temp = 0, Vida = 0xFFFF;

  Encabezado (L"Discos: informacion y S.M.A.R.T.", L"Flechas: otro disco    Esc: regresar");
  Id     = AllocateAlignedPages (1, 512);
  Smart  = AllocateAlignedPages (1, 512);
  Umbral = AllocateAlignedPages (1, 512);
  if ((Id == NULL) || (Smart == NULL) || (Umbral == NULL)) {
    return;
  }

  ZeroMem (Id, 4096);
  ZeroMem (Smart, 4096);
  ZeroMem (Umbral, 4096);

  Texto (3, 5, T_ROJO, L"DISCO %d de %d   (puerto SATA %d)", Num + 1, mNumAta, D->Puerto);
  if (EFI_ERROR (ComandoAta (D, 0xEC, 0, TRUE, Id, NULL))) {
    Texto (3, 7, T_ROJO, L"No respondio a IDENTIFY DEVICE.");
    goto Fin;
  }

  CadenaAta (Id, 27, 20, Modelo);
  CadenaAta (Id, 10, 10, Serie);
  CadenaAta (Id, 23, 4, Firmware);
  Sectores = ((Id[83] & BIT10) != 0)
             ? (Id[100] | LShiftU64 (Id[101], 16) | LShiftU64 (Id[102], 32) | LShiftU64 (Id[103], 48))
             : (Id[60] | LShiftU64 (Id[61], 16));
  Tamano (B1, sizeof (B1), MultU64x32 (Sectores, 512));

  Texto (3, 6, T_BLANCO, L"%a", Modelo);
  Texto (3, 7, T_NORMAL, L"Serie %a   Firmware %a   Capacidad %s (%lu sectores)", Serie, Firmware, B1, Sectores);
  Texto (3, 8, T_NORMAL, L"Tipo: %s   SATA %s   TRIM %s   NCQ %s",
    (Id[217] == 1) ? L"SSD (sin rotacion)" : L"Disco duro",
    ((Id[76] & BIT3) != 0) ? L"3 (6 Gb/s)" : (((Id[76] & BIT2) != 0) ? L"2 (3 Gb/s)" : L"1"),
    ((Id[169] & BIT0) != 0) ? L"si" : L"no", ((Id[76] & BIT8) != 0) ? L"si" : L"no");

  SmartOk = ((Id[82] & BIT0) != 0) && !EFI_ERROR (ComandoAta (D, 0xB0, 0xD0, TRUE, Smart, NULL));
  if (!SmartOk) {
    Texto (3, 10, T_AMARILLO, L"Este disco no entrego S.M.A.R.T.");
    goto Fin;
  }

  ComandoAta (D, 0xB0, 0xD1, TRUE, Umbral, NULL);
  if (!EFI_ERROR (ComandoAta (D, 0xB0, 0xDA, FALSE, NULL, &Est)) && (Est.AtaCylinderLow == 0xF4) && (Est.AtaCylinderHigh == 0x2C)) {
    Malo = TRUE;     // el propio disco dice que paso un umbral
  }

  // Tabla de atributos
  Texto (3, 10, T_GRIS, L"ID   Atributo                       Actual  Peor  Umbral          Crudo");
  Fila      = 11;
  for (I = 0; I < 30; ++I) {
    UINT8  *A = Smart + 2 + I * 12;

    IdAtr = A[0];
    if (IdAtr == 0) {
      continue;
    }

    Actual = A[3];
    Peor   = A[4];
    Crudo  = A[5] | LShiftU64 (A[6], 8) | LShiftU64 (A[7], 16) | LShiftU64 (A[8], 24) | LShiftU64 (A[9], 32) | LShiftU64 (A[10], 40);
    if ((IdAtr == 0xC2) || (IdAtr == 0xBE)) {
      Crudo &= 0xFF;          // el crudo de temperatura trae tambien minimo y maximo en los otros bytes
    }
    Lim    = 0;
    if (Umbral[2 + I * 12] == IdAtr) {
      Lim = Umbral[2 + I * 12 + 1];
    }

    if (IdAtr == 0x09) { Horas = (UINT32)(Crudo & 0xFFFFFFFF); }
    if ((IdAtr == 0xC2) || (IdAtr == 0xBE)) { Temp = (UINT32)(Crudo & 0xFF); }
    if ((IdAtr == 0xA9) || (IdAtr == 0xE7) || (IdAtr == 0xAD) || (IdAtr == 0xB1)) { Vida = MIN (Vida, Actual); }

    if ((Lim != 0) && (Actual <= Lim)) {
      Malo = TRUE;
    }

    if (Critico (IdAtr) && ((Crudo & 0xFFFFFFFF) != 0)) {
      Aviso = TRUE;
    }

    Texto (3, Fila, ((Lim != 0) && (Actual <= Lim)) ? T_ROJO : ((Critico (IdAtr) && ((Crudo & 0xFFFFFFFF) != 0)) ? T_AMARILLO : T_NORMAL),
      L"%02X   %-30s %6d %5d %7d  %13lu", IdAtr, NombreAtributo (IdAtr), Actual, Peor, Lim, Crudo);

    // mini barra del valor actual (0-100 normalizado de 0-253)
    X = ColX (90);
    Y = FilaY (Fila) + 4;
    W = ColX (20);
    Rect (X, Y, W, gCeldaH - 8, &cGrisOsc);
    {
      UINT32  Escala = (MAX (Actual, Peor) > 100) ? 253 : 100;
      Rect (X, Y, (W * MIN ((UINT32)Actual, Escala)) / Escala, gCeldaH - 8,
        ((Lim != 0) && (Actual <= Lim)) ? &cRojo : ((Actual * 100 / Escala < 30) ? &cAmarillo : &cVerde));
    }
    ++Fila;
  }

  // Veredicto grande
  X = ColX (118);
  Y = FilaY (5);
  Rect (X, Y, ColX (40), gCeldaH * 6, Malo ? &cRojo : (Aviso ? &cAmarillo : &cVerde));
  Texto (120, 12, Malo ? T_ROJO : (Aviso ? T_AMARILLO : T_VERDE), L"SALUD: %s",
    Malo ? L"MALA (respalda ya)" : (Aviso ? L"REVISAR (hay sectores marcados)" : L"BUENA"));
  if (Horas != 0) {
    Texto (120, 14, T_NORMAL, L"Encendido: %d horas (%d dias)", Horas, Horas / 24);
  }

  if (Temp != 0) {
    Texto (120, 15, T_NORMAL, L"Temperatura: %d C", Temp);
  }

  if (Vida != 0xFFFF) {
    Texto (120, 16, T_NORMAL, L"Vida restante (segun el SSD): %d %%", Vida);
    Rect (ColX (120), FilaY (17) + 2, ColX (36), gCeldaH - 4, &cGrisOsc);
    Rect (ColX (120), FilaY (17) + 2, (ColX (36) * MIN (Vida, 100)) / 100, gCeldaH - 4,
      (Vida >= 50) ? &cVerde : ((Vida >= 20) ? &cAmarillo : &cRojo));
  }

Fin:
  FreeAlignedPages (Id, 1);
  FreeAlignedPages (Smart, 1);
  FreeAlignedPages (Umbral, 1);
}

VOID
DiagDiscoInfo (
  VOID
  )
{
  UINTN          Sel = 0;
  EFI_INPUT_KEY  T;

  BuscarAta ();
  if (mNumAta == 0) {
    Encabezado (L"Discos: informacion y S.M.A.R.T.", L"Cualquier tecla: regresar");
    Texto (3, 6, T_AMARILLO, L"El firmware no ofrece acceso ATA directo (EFI_ATA_PASS_THRU).");
    Texto (3, 7, T_NORMAL, L"Las memorias USB y algunos discos externos no tienen S.M.A.R.T. desde aqui.");
    Texto (3, 8, T_NORMAL, L"El escaneo de superficie si funciona con cualquier disco.");
    EsperarTecla ();
    return;
  }

  while (TRUE) {
    MostrarDiscoAta (&mAta[Sel], Sel);
    T = EsperarTecla ();
    if ((T.ScanCode == SCAN_ESC) || (T.UnicodeChar == L'q')) {
      return;
    }

    if ((T.ScanCode == SCAN_RIGHT) || (T.ScanCode == SCAN_DOWN)) {
      Sel = (Sel + 1) % mNumAta;
    } else if ((T.ScanCode == SCAN_LEFT) || (T.ScanCode == SCAN_UP)) {
      Sel = (Sel + mNumAta - 1) % mNumAta;
    }
  }
}

//
// ================= ESCANEO DE SUPERFICIE (solo lectura) =================
//
typedef struct {
  EFI_BLOCK_IO_PROTOCOL  *Bio;
  CHAR16                 *Ruta;
  BOOLEAN                EsUsb;        // conectado por USB (externo)
  BOOLEAN                EsArranque;   // de aqui se cargo esta herramienta (la USB de OpenCore)
  DISCO_ATA              Ata;          // acceso ATA directo (solo discos SATA); Ata.Ata == NULL si no hay
} DISCO_BIO;

//
// TRUE si el disco Dp es el mismo de donde se cargo esta app (su ruta es prefijo de la del cargador).
//
STATIC
BOOLEAN
EsDiscoDeArranque (
  IN EFI_DEVICE_PATH_PROTOCOL  *Dp
  )
{
  EFI_LOADED_IMAGE_PROTOCOL  *Img;
  EFI_DEVICE_PATH_PROTOCOL   *DpImg;
  UINTN                      Tam;

  if (EFI_ERROR (gBS->HandleProtocol (gImageHandle, &gEfiLoadedImageProtocolGuid, (VOID **)&Img))
      || EFI_ERROR (gBS->HandleProtocol (Img->DeviceHandle, &gEfiDevicePathProtocolGuid, (VOID **)&DpImg)))
  {
    return TRUE;      // si no se sabe, se trata como de arranque (no se deja escribir)
  }

  Tam = GetDevicePathSize (Dp) - END_DEVICE_PATH_LENGTH;
  return (GetDevicePathSize (DpImg) - END_DEVICE_PATH_LENGTH >= Tam) && (CompareMem (Dp, DpImg, Tam) == 0);
}

//
// Si el disco cuelga de un controlador SATA con EFI_ATA_PASS_THRU, guarda el protocolo y el puerto.
//
STATIC
VOID
BuscarAtaDeDisco (
  IN  EFI_DEVICE_PATH_PROTOCOL  *Dp,
  OUT DISCO_ATA                 *Ata
  )
{
  EFI_DEVICE_PATH_PROTOCOL  *Nodo, *Resto;
  EFI_HANDLE                Ctrl;
  SATA_DEVICE_PATH          *Sata = NULL;

  ZeroMem (Ata, sizeof (*Ata));
  for (Nodo = Dp; !IsDevicePathEnd (Nodo); Nodo = NextDevicePathNode (Nodo)) {
    if ((DevicePathType (Nodo) == MESSAGING_DEVICE_PATH) && (DevicePathSubType (Nodo) == MSG_SATA_DP)) {
      Sata = (SATA_DEVICE_PATH *)Nodo;
    }
  }

  if (Sata == NULL) {
    return;
  }

  Resto = Dp;
  if (EFI_ERROR (gBS->LocateDevicePath (&gEfiAtaPassThruProtocolGuid, &Resto, &Ctrl))
      || EFI_ERROR (gBS->HandleProtocol (Ctrl, &gEfiAtaPassThruProtocolGuid, (VOID **)&Ata->Ata)))
  {
    Ata->Ata = NULL;
    return;
  }

  Ata->Puerto = Sata->HBAPortNumber;
  Ata->Pmp    = Sata->PortMultiplierPortNumber;
}

STATIC
BOOLEAN
EsRutaUsb (
  IN EFI_DEVICE_PATH_PROTOCOL  *Dp
  )
{
  for (; !IsDevicePathEnd (Dp); Dp = NextDevicePathNode (Dp)) {
    if ((DevicePathType (Dp) == MESSAGING_DEVICE_PATH)
        && ((DevicePathSubType (Dp) == MSG_USB_DP) || (DevicePathSubType (Dp) == MSG_USB_CLASS_DP)))
    {
      return TRUE;
    }
  }

  return FALSE;
}

STATIC DISCO_BIO  mBio[MAX_DISCOS];
STATIC UINTN      mNumBio;

STATIC
VOID
BuscarBlockIo (
  VOID
  )
{
  EFI_HANDLE                *Handles = NULL;
  UINTN                     N = 0, I;
  EFI_BLOCK_IO_PROTOCOL     *Bio;
  EFI_DEVICE_PATH_PROTOCOL  *Dp;

  for (I = 0; I < mNumBio; ++I) {
    if (mBio[I].Ruta != NULL) {
      FreePool (mBio[I].Ruta);
    }
  }

  mNumBio = 0;
  if (EFI_ERROR (gBS->LocateHandleBuffer (ByProtocol, &gEfiBlockIoProtocolGuid, NULL, &N, &Handles))) {
    return;
  }

  for (I = 0; (I < N) && (mNumBio < MAX_DISCOS); ++I) {
    if (EFI_ERROR (gBS->HandleProtocol (Handles[I], &gEfiBlockIoProtocolGuid, (VOID **)&Bio))) {
      continue;
    }

    // Solo discos completos con medio presente (no particiones)
    if (Bio->Media->LogicalPartition || !Bio->Media->MediaPresent || (Bio->Media->LastBlock == 0)) {
      continue;
    }

    mBio[mNumBio].Bio        = Bio;
    mBio[mNumBio].Ruta       = NULL;
    mBio[mNumBio].EsUsb      = FALSE;
    mBio[mNumBio].EsArranque = TRUE;
    if (!EFI_ERROR (gBS->HandleProtocol (Handles[I], &gEfiDevicePathProtocolGuid, (VOID **)&Dp))) {
      mBio[mNumBio].Ruta       = ConvertDevicePathToText (Dp, FALSE, TRUE);
      mBio[mNumBio].EsUsb      = EsRutaUsb (Dp);
      mBio[mNumBio].EsArranque = EsDiscoDeArranque (Dp);
      BuscarAtaDeDisco (Dp, &mBio[mNumBio].Ata);
    }

    ++mNumBio;
  }

  FreePool (Handles);
}


//
// ================= MOTOR DE PRUEBAS Y REPARACION =================
//
#define SC_COLS    150U
#define SC_FILAS   26U
#define SC_CELDAS  (SC_COLS * SC_FILAS)
#define SC_SECT    256U          // sectores por operacion (como Victoria)
#define SC_HIST    150U
#define SC_MAXERR  12U
#define SC_ALEAT   4096U         // lecturas del acceso aleatorio

typedef enum {
  M_LEER, M_VERIFICAR, M_MARIPOSA, M_ALEATORIO,                // solo leen
  M_REPARAR, M_REFRESCAR, M_LEER_ESCRIBIR, M_PATRON, M_BORRAR, // escriben (solo USB externos)
  M_TOTAL
} METODO;

typedef struct {
  CONST CHAR16  *Nombre;
  CONST CHAR16  *Detalle;
  BOOLEAN       Escribe;
  BOOLEAN       Destruye;
} INFO_METODO;

STATIC CONST INFO_METODO  mMetodos[M_TOTAL] = {
  { L"Lectura lineal",              L"Lee todo el disco de principio a fin y mide cada bloque",                          FALSE, FALSE },
  { L"Verificar (ATA VERIFY)",      L"El disco revisa sus sectores sin mandar datos (solo discos SATA)",                FALSE, FALSE },
  { L"Mariposa (butterfly)",        L"Alterna bloques del inicio y del final: exige al brazo en discos mecanicos",      FALSE, FALSE },
  { L"Acceso aleatorio",            L"4096 lecturas en posiciones al azar: tiempo de acceso min, promedio y max",       FALSE, FALSE },
  { L"Reparar sectores (remap)",    L"Lo ilegible (3 intentos) se escribe en ceros para que el disco lo reasigne",      TRUE,  FALSE },
  { L"Refrescar sectores lentos",   L"Bloques de 150 ms o mas se reescriben con sus mismos datos",                      TRUE,  FALSE },
  { L"Leer - escribir - leer",      L"Cada bloque se lee, se reescribe igual y se compara (refresca TODO, sin perder)", TRUE,  FALSE },
  { L"Escribir patron y verificar", L"Patron distinto por bloque, luego se lee y compara. BORRA TODO",                  TRUE,  TRUE  },
  { L"Borrar todo (ceros)",         L"Escribe ceros en todo el disco. BORRA TODO",                                       TRUE,  TRUE  },
};

STATIC CONST UINT32  mLimites[] = { 5000, 20000, 50000, 150000, 500000 };   // microsegundos
STATIC CONST EFI_GRAPHICS_OUTPUT_BLT_PIXEL  *mColLat[] = { &cGrisOsc, &cGris, &cVerde, &cAmarillo, &cNaranja, &cRojo, &cAzul };
STATIC CONST CHAR16  *mNomLat[] = { L"<5 ms", L"<20 ms", L"<50 ms", L"<150 ms", L"<500 ms", L">500 ms", L"Error" };
STATIC UINT8         mPeorCelda[SC_CELDAS];

STATIC
BOOLEAN
PuedeEscribir (
  IN DISCO_BIO  *D
  )
{
  return D->EsUsb && !D->EsArranque && !D->Bio->Media->ReadOnly;
}

// ATA READ VERIFY SECTORS EXT (0x42): el disco lee internamente, sin transferir datos
STATIC
EFI_STATUS
VerificarAta (
  IN DISCO_ATA  *D,
  IN UINT64     Lba,
  IN UINTN      Cuantos
  )
{
  EFI_ATA_COMMAND_BLOCK             Acb;
  EFI_ATA_STATUS_BLOCK              Asb;
  EFI_ATA_PASS_THRU_COMMAND_PACKET  Pkt;

  ZeroMem (&Acb, sizeof (Acb));
  ZeroMem (&Asb, sizeof (Asb));
  ZeroMem (&Pkt, sizeof (Pkt));
  Acb.AtaCommand            = 0x42;
  Acb.AtaSectorNumber       = (UINT8)Lba;
  Acb.AtaCylinderLow        = (UINT8)RShiftU64 (Lba, 8);
  Acb.AtaCylinderHigh       = (UINT8)RShiftU64 (Lba, 16);
  Acb.AtaSectorNumberExp    = (UINT8)RShiftU64 (Lba, 24);
  Acb.AtaCylinderLowExp     = (UINT8)RShiftU64 (Lba, 32);
  Acb.AtaCylinderHighExp    = (UINT8)RShiftU64 (Lba, 40);
  Acb.AtaSectorCount        = (UINT8)Cuantos;
  Acb.AtaSectorCountExp     = (UINT8)(Cuantos >> 8);
  Acb.AtaDeviceHead         = 0x40;          // modo LBA
  Pkt.Asb      = &Asb;
  Pkt.Acb      = &Acb;
  Pkt.Timeout  = EFI_TIMER_PERIOD_SECONDS (10);
  Pkt.Protocol = EFI_ATA_PASS_THRU_PROTOCOL_ATA_NON_DATA;
  Pkt.Length   = EFI_ATA_PASS_THRU_LENGTH_NO_DATA_TRANSFER;
  return D->Ata->PassThru (D->Ata, D->Puerto, D->Pmp, &Pkt, NULL);
}

// Patron unico por bloque (detecta tambien errores de direccionamiento)
STATIC
VOID
LlenarPatron (
  OUT UINT64  *Buf,
  IN  UINTN   Bytes,
  IN  UINT64  Lba
  )
{
  UINT64  S = Lba * 0x9E3779B97F4A7C15ULL + 0x5A5A5A5A12345678ULL;
  UINTN   I;

  for (I = 0; I < Bytes / 8; ++I) {
    S ^= LShiftU64 (S, 13);
    S ^= RShiftU64 (S, 7);
    S ^= LShiftU64 (S, 17);
    Buf[I] = S ^ Lba;
  }
}

STATIC
VOID
PintarCeldaDisco (
  IN UINTN   Celda,
  IN UINT32  Tam,
  IN UINTN   Clase
  )
{
  Rect (ColX (4) + (UINT32)(Celda % SC_COLS) * Tam, FilaY (8) + (UINT32)(Celda / SC_COLS) * Tam, Tam - 2, Tam - 2,
    (Clase == 0) ? &cBorde : mColLat[Clase]);
}

STATIC
VOID
Ejecutar (
  IN DISCO_BIO  *D,
  IN METODO     M
  )
{
  EFI_BLOCK_IO_PROTOCOL  *Bio = D->Bio;
  UINT32                 Bs   = Bio->Media->BlockSize;
  UINT64                 Total = Bio->Media->LastBlock + 1, Bloques, NumOps, Op, Lba;
  UINTN                  Sect, Bytes, I, K, Intento, Celda, NErr = 0, Clase, N;
  UINT64                 Cuenta[7];
  VOID                   *Buf, *Buf2, *Sec;
  UINT64                 T0, T1, Us, TIni, MBs, Semilla;
  UINT64                 UsMin = MAX_UINT64, UsMax = 0, UsSuma = 0, NAcc = 0;
  UINT64                 Reparados = 0, Fallidos = 0, Reescritos = 0, NoCoinciden = 0;
  UINT64                 BytesVentana = 0, TVentana;
  EFI_STATUS             St;
  EFI_INPUT_KEY          T;
  CHAR16                 B1[32];
  UINT32                 Tam, X, Y, H, Alto, MaxV;
  UINT32                 Hist[SC_HIST];
  UINTN                  NHist = 0, FilaInfo;
  BOOLEAN                UsaAta;

  // Candado: los metodos que escriben solo en discos USB externos que no sean de arranque
  if (mMetodos[M].Escribe && !PuedeEscribir (D)) {
    return;
  }

  UsaAta = (M == M_VERIFICAR) && (D->Ata.Ata != NULL) && (Bs == 512);
  Sect   = (Bs >= 4096) ? 32 : SC_SECT;
  Bytes  = Sect * Bs;
  Buf    = AllocateAlignedPages (EFI_SIZE_TO_PAGES (Bytes), MAX (Bio->Media->IoAlign, 4096));
  Buf2   = AllocateAlignedPages (EFI_SIZE_TO_PAGES (Bytes), MAX (Bio->Media->IoAlign, 4096));
  Sec    = AllocateAlignedPages (EFI_SIZE_TO_PAGES (Bs), MAX (Bio->Media->IoAlign, 4096));
  if ((Buf == NULL) || (Buf2 == NULL) || (Sec == NULL)) {
    goto Salir;
  }

  if (M == M_BORRAR) {
    ZeroMem (Buf, Bytes);
  }

  Bloques = DivU64x64Remainder (Total + Sect - 1, Sect, NULL);
  NumOps  = (M == M_ALEATORIO) ? MIN (Bloques, SC_ALEAT) : Bloques;
  Semilla = AsmReadTsc () | 1;
  ZeroMem (Cuenta, sizeof (Cuenta));
  ZeroMem (Hist, sizeof (Hist));
  ZeroMem (mPeorCelda, sizeof (mPeorCelda));

  Encabezado (mMetodos[M].Nombre, L"Esc: detener");
  Tamano (B1, sizeof (B1), MultU64x32 (Total, Bs));
  Texto (3, 5, T_BLANCO, L"%s   %s   %d bytes/sector   %d sectores por operacion", B1,
    (D->Ruta != NULL) ? D->Ruta : L"", Bs, Sect);
  Texto (3, 6, mMetodos[M].Escribe ? T_AMARILLO : T_GRIS, L"%s%s", mMetodos[M].Detalle,
    (M == M_VERIFICAR && !UsaAta) ? L"  (este disco no tiene ATA directo: se usa lectura normal)" : L"");

  Tam = (gAncho - ColX (8)) / SC_COLS;
  for (I = 0; I < SC_CELDAS; ++I) {
    Rect (ColX (4) + (UINT32)(I % SC_COLS) * Tam, FilaY (8) + (UINT32)(I / SC_COLS) * Tam, Tam - 2, Tam - 2, &cFondo);
  }

  FilaInfo = 8 + (SC_FILAS * Tam) / gCeldaH + 2;
  for (I = 0; I < 7; ++I) {
    Rect (ColX (3), FilaY (FilaInfo + I) + 3, gCeldaW * 2, gCeldaH - 6, mColLat[I]);
  }

  TIni     = AsmReadTsc ();
  TVentana = TIni;
  for (Op = 0; Op < NumOps; ++Op) {
    // --- donde toca ---
    switch (M) {
      case M_MARIPOSA:
        K   = (UINTN)RShiftU64 (Op, 1);
        Lba = MultU64x32 (((Op & 1) == 0) ? K : (Bloques - 1 - K), (UINT32)Sect);
        break;
      case M_ALEATORIO:
        Semilla ^= LShiftU64 (Semilla, 13);
        Semilla ^= RShiftU64 (Semilla, 7);
        Semilla ^= LShiftU64 (Semilla, 17);
        {
          UINT64  Resto;

          DivU64x64Remainder (Semilla, Bloques, &Resto);    // bloque al azar entre 0 y Bloques-1
          Lba = MultU64x32 (Resto, (UINT32)Sect);
        }
        break;
      default:
        Lba = MultU64x32 (Op, (UINT32)Sect);
        break;
    }

    N  = (UINTN)MIN ((UINT64)Sect, Total - Lba);
    T0 = AsmReadTsc ();

    // --- que se hace ---
    switch (M) {
      case M_VERIFICAR:
        St = UsaAta ? VerificarAta (&D->Ata, Lba, N) : Bio->ReadBlocks (Bio, Bio->Media->MediaId, Lba, N * Bs, Buf);
        break;
      case M_BORRAR:
        St = Bio->WriteBlocks (Bio, Bio->Media->MediaId, Lba, N * Bs, Buf);
        break;
      case M_PATRON:
        LlenarPatron (Buf, N * Bs, Lba);
        St = Bio->WriteBlocks (Bio, Bio->Media->MediaId, Lba, N * Bs, Buf);
        if (!EFI_ERROR (St)) {
          St = Bio->ReadBlocks (Bio, Bio->Media->MediaId, Lba, N * Bs, Buf2);
          if (!EFI_ERROR (St) && (CompareMem (Buf, Buf2, N * Bs) != 0)) {
            St = EFI_CRC_ERROR;
            ++NoCoinciden;
          }
        }

        break;
      case M_LEER_ESCRIBIR:
        St = Bio->ReadBlocks (Bio, Bio->Media->MediaId, Lba, N * Bs, Buf);
        if (!EFI_ERROR (St)) {
          St = Bio->WriteBlocks (Bio, Bio->Media->MediaId, Lba, N * Bs, Buf);
          if (!EFI_ERROR (St)) {
            ++Reescritos;
            St = Bio->ReadBlocks (Bio, Bio->Media->MediaId, Lba, N * Bs, Buf2);
            if (!EFI_ERROR (St) && (CompareMem (Buf, Buf2, N * Bs) != 0)) {
              St = EFI_CRC_ERROR;
              ++NoCoinciden;
            }
          }
        }

        break;
      default:   // M_LEER, M_MARIPOSA, M_ALEATORIO, M_REPARAR, M_REFRESCAR
        St = Bio->ReadBlocks (Bio, Bio->Media->MediaId, Lba, N * Bs, Buf);
        break;
    }

    T1 = AsmReadTsc ();
    Us = Microsegundos (T1 - T0);

    if (EFI_ERROR (St)) {
      Clase = 6;
      if (M == M_REPARAR) {
        for (K = 0; K < N; ++K) {
          for (Intento = 0; Intento < 3; ++Intento) {
            if (!EFI_ERROR (Bio->ReadBlocks (Bio, Bio->Media->MediaId, Lba + K, Bs, Sec))) {
              break;
            }
          }

          if (Intento < 3) {
            continue;
          }

          ZeroMem (Sec, Bs);
          if (!EFI_ERROR (Bio->WriteBlocks (Bio, Bio->Media->MediaId, Lba + K, Bs, Sec))
              && !EFI_ERROR (Bio->ReadBlocks (Bio, Bio->Media->MediaId, Lba + K, Bs, Sec)))
          {
            ++Reparados;
            if (NErr < SC_MAXERR) {
              Texto (120, FilaInfo + 1 + NErr++, T_AMARILLO, L"LBA %lu: reasignado", Lba + K);
            }
          } else {
            ++Fallidos;
            if (NErr < SC_MAXERR) {
              Texto (120, FilaInfo + 1 + NErr++, T_ROJO, L"LBA %lu: NO se pudo reparar", Lba + K);
            }
          }
        }
      } else if (NErr < SC_MAXERR) {
        Texto (120, FilaInfo + 1 + NErr++, T_ROJO, L"LBA %lu (+%d): %s", Lba, N,
          (St == EFI_CRC_ERROR) ? L"lo leido NO coincide con lo escrito" : L"error de lectura/escritura");
      } else {
        ++NErr;
      }
    } else {
      for (Clase = 0; Clase < 5 && Us >= mLimites[Clase]; ++Clase) {
      }

      if ((M == M_REFRESCAR) && (Clase >= 3)
          && !EFI_ERROR (Bio->WriteBlocks (Bio, Bio->Media->MediaId, Lba, N * Bs, Buf)))
      {
        ++Reescritos;
      }

      if (M == M_ALEATORIO) {
        UsMin   = MIN (UsMin, Us);
        UsMax   = MAX (UsMax, Us);
        UsSuma += Us;
        ++NAcc;
      }
    }

    ++Cuenta[Clase];
    BytesVentana += N * Bs;

    // Mapa: cada celda guarda la PEOR operacion que cayo en su zona del disco
    Celda = (UINTN)DivU64x64Remainder (MultU64x32 (Lba, SC_CELDAS), Total, NULL);
    if ((Celda < SC_CELDAS) && ((Clase >= mPeorCelda[Celda]) || (mPeorCelda[Celda] == 0))) {
      mPeorCelda[Celda] = (UINT8)Clase;
      PintarCeldaDisco (Celda, Tam, Clase);
    }

    // --- estado cada ~250 ms ---
    if ((Microsegundos (T1 - TVentana) >= 250000) || (Op + 1 == NumOps)) {
      UINT64  UsV = MAX (1, Microsegundos (T1 - TVentana));

      MBs          = DivU64x64Remainder (BytesVentana, UsV, NULL);
      BytesVentana = 0;
      TVentana     = T1;
      if (NHist < SC_HIST) {
        Hist[NHist++] = (UINT32)MBs;
      } else {
        CopyMem (Hist, Hist + 1, sizeof (Hist) - sizeof (Hist[0]));
        Hist[SC_HIST - 1] = (UINT32)MBs;
      }

      for (I = 0; I < 7; ++I) {
        Texto (7, FilaInfo + I, (I == 6 && Cuenta[6]) ? T_ROJO : ((I >= 4 && Cuenta[I]) ? T_AMARILLO : T_NORMAL),
          L"%-8s %10lu", mNomLat[I], Cuenta[I]);
      }

      Texto (32, FilaInfo, T_BLANCO, L"Avance: %lu de %lu operaciones (%d%%)     ", Op + 1, NumOps,
        (UINTN)DivU64x64Remainder (MultU64x32 (Op + 1, 100), NumOps, NULL));
      Texto (32, FilaInfo + 1, T_NORMAL, L"Velocidad: %lu MB/s     Tiempo: %lu s     ", MBs,
        DivU64x32 (Microsegundos (T1 - TIni), 1000000));
      if (M == M_ALEATORIO && NAcc > 0) {
        Texto (32, FilaInfo + 2, T_CIAN, L"Acceso: min %lu.%lu ms   promedio %lu.%lu ms   max %lu.%lu ms     ",
          DivU64x32 (UsMin, 1000), DivU64x32 (UsMin, 100) % 10, DivU64x32 (DivU64x64Remainder (UsSuma, NAcc, NULL), 1000),
          DivU64x32 (DivU64x64Remainder (UsSuma, NAcc, NULL), 100) % 10, DivU64x32 (UsMax, 1000), DivU64x32 (UsMax, 100) % 10);
      } else if (mMetodos[M].Escribe) {
        Texto (32, FilaInfo + 2, T_AMARILLO, L"Reasignados %lu   No reparables %lu   Reescritos %lu   No coinciden %lu     ",
          Reparados, Fallidos, Reescritos, NoCoinciden);
      }

      BarraProgreso (ColX (32), FilaY (FilaInfo + 4), ColX (80), 10, Op + 1, NumOps);
      if (NErr == 0) {
        Texto (120, FilaInfo, T_GRIS, L"Problemas encontrados:");
        Texto (120, FilaInfo + 1, T_VERDE, L"ninguno");
      }

      X = ColX (32); Y = FilaY (FilaInfo + 6); H = gCeldaH * 6; MaxV = 1;
      for (I = 0; I < NHist; ++I) {
        MaxV = MAX (MaxV, Hist[I]);
      }

      Rect (X, Y, SC_HIST * 4, H, &cFondo);
      for (I = 0; I < 4; ++I) {
        Rect (X, Y + (H * (UINT32)I) / 4, SC_HIST * 4, 1, &cPanel);    // lineas guia
      }

      for (I = 0; I < NHist; ++I) {
        Alto = (H * Hist[I]) / MaxV;
        Rect (X + (UINT32)I * 4, Y + H - Alto, 3, Alto, &cRojo);
        if (Alto > 2) {
          Rect (X + (UINT32)I * 4, Y + H - Alto, 3, 2, &cBlanco);        // brillo arriba de cada barra
        }
      }

      Texto (32, FilaInfo + 13, T_GRIS, L"Velocidad (max %d MB/s)     ", MaxV);

      if (TeclaDisponible (&T) && (T.ScanCode == SCAN_ESC)) {
        ++Op;
        break;
      }
    }
  }

  if (mMetodos[M].Escribe) {
    Bio->FlushBlocks (Bio);
  }

  Texto (32, FilaInfo + 15, (Cuenta[6] == 0 && Cuenta[5] == 0) ? T_VERDE : T_ROJO,
    L"%s  Operaciones: %lu de %lu   Problemas: %d   Lentas (>500 ms): %lu.   Cualquier tecla: regresar.",
    (Op >= NumOps) ? L"TERMINADO." : L"DETENIDO.", Op, NumOps, NErr, Cuenta[5]);
  EsperarTecla ();

Salir:
  if (Sec != NULL) {
    FreeAlignedPages (Sec, EFI_SIZE_TO_PAGES (Bs));
  }

  if (Buf2 != NULL) {
    FreeAlignedPages (Buf2, EFI_SIZE_TO_PAGES (Bytes));
  }

  if (Buf != NULL) {
    FreeAlignedPages (Buf, EFI_SIZE_TO_PAGES (Bytes));
  }
}

//
// Pide escribir una palabra exacta para confirmar
//
STATIC
BOOLEAN
EscribirPalabra (
  IN UINTN         Fila,
  IN CONST CHAR16  *Palabra
  )
{
  CHAR16         Buf[16];
  UINTN          N = 0;
  EFI_INPUT_KEY  T;

  Texto (3, Fila, T_ROJO, L"Para confirmar escribe %s y Enter (Esc cancela): ", Palabra);
  while (TRUE) {
    T = EsperarTecla ();
    if (T.ScanCode == SCAN_ESC) {
      return FALSE;
    }

    if (T.UnicodeChar == CHAR_CARRIAGE_RETURN) {
      Buf[N] = L'\0';
      return StrCmp (Buf, Palabra) == 0;
    }

    if ((T.UnicodeChar == CHAR_BACKSPACE) && (N > 0)) {
      --N;
    } else if ((T.UnicodeChar >= L' ') && (N < ARRAY_SIZE (Buf) - 1)) {
      Buf[N++] = (T.UnicodeChar >= L'a' && T.UnicodeChar <= L'z') ? (CHAR16)(T.UnicodeChar - 32) : T.UnicodeChar;
    }

    Buf[N] = L'\0';
    Texto (52 + StrLen (Palabra), Fila, T_BLANCO, L"%-15s", Buf);
  }
}

//
// Menu de metodos para un disco. SoloLectura = TRUE oculta los que escriben.
//
STATIC
VOID
MenuMetodos (
  IN DISCO_BIO  *D,
  IN BOOLEAN    SoloLectura
  )
{
  UINTN          Sel = 0, I, Fila;
  EFI_INPUT_KEY  T;
  CHAR16         B1[32];
  BOOLEAN        Permitido;
  UINT32         Y;

  while (TRUE) {
    Encabezado (L"Pruebas y reparacion: elige el metodo", L"Flechas: elegir   Enter: iniciar   Esc: regresar");
    Tamano (B1, sizeof (B1), MultU64x32 (D->Bio->Media->LastBlock + 1, D->Bio->Media->BlockSize));
    Texto (3, 5, T_BLANCO, L"Disco: %s  %s  %s", B1,
      D->EsArranque ? L"[arranque]" : (D->EsUsb ? L"[USB]" : L"[interno]"), (D->Ruta != NULL) ? D->Ruta : L"");
    if (!PuedeEscribir (D)) {
      Texto (3, 6, T_AMARILLO, L"Disco protegido: los metodos que escriben estan bloqueados (solo se permiten en discos USB externos).");
    }

    Texto (3, 8, T_ROJO, L"SOLO LECTURA");
    Texto (3, 15, T_ROJO, L"ESCRIBEN EN EL DISCO (solo discos USB externos)");
    for (I = 0; I < M_TOTAL; ++I) {
      if (SoloLectura && mMetodos[I].Escribe) {
        continue;
      }

      Permitido = !mMetodos[I].Escribe || PuedeEscribir (D);
      Fila      = 9 + I + ((I >= M_REPARAR) ? 3 : 0);
      Y         = FilaY (Fila);
      Rect (ColX (2), Y, 5, gCeldaH, (I == Sel) ? &cRojo : &cNegro);
      Texto (4, Fila, !Permitido ? T_GRIS : ((I == Sel) ? T_BLANCO : (mMetodos[I].Destruye ? T_ROJO : T_NORMAL)),
        L"%d  %-30s", I + 1, mMetodos[I].Nombre);
      Texto (40, Fila, T_GRIS, L"%s%s", mMetodos[I].Detalle, Permitido ? L"" : L"  [bloqueado]");
    }

    T = EsperarTecla ();
    if (T.ScanCode == SCAN_ESC) {
      return;
    }

    if (T.ScanCode == SCAN_DOWN) {
      do {
        Sel = (Sel + 1) % M_TOTAL;
      } while (SoloLectura && mMetodos[Sel].Escribe);
      continue;
    }

    if (T.ScanCode == SCAN_UP) {
      do {
        Sel = (Sel + M_TOTAL - 1) % M_TOTAL;
      } while (SoloLectura && mMetodos[Sel].Escribe);
      continue;
    }

    if ((T.UnicodeChar >= L'1') && (T.UnicodeChar < L'1' + M_TOTAL)) {
      Sel = T.UnicodeChar - L'1';
    } else if (T.UnicodeChar != CHAR_CARRIAGE_RETURN) {
      continue;
    }

    if ((SoloLectura && mMetodos[Sel].Escribe) || (mMetodos[Sel].Escribe && !PuedeEscribir (D))) {
      continue;
    }

    if (mMetodos[Sel].Destruye) {
      if (!EscribirPalabra (22, L"BORRAR")) {
        continue;
      }
    } else if (mMetodos[Sel].Escribe) {
      if (!Confirmar (22, L"Este metodo ESCRIBE en el disco USB elegido. Seguir?")
          || !Confirmar (22, L"Seguro? Respalda antes si te importa lo que tiene."))
      {
        continue;
      }
    }

    Ejecutar (D, (METODO)Sel);
  }
}

STATIC
VOID
ElegirDisco (
  IN BOOLEAN  SoloUsb
  )
{
  UINTN          Lista[MAX_DISCOS], NLista = 0, Sel = 0, I;
  EFI_INPUT_KEY  T;
  CHAR16         B1[32];
  DISCO_BIO      *D;

  BuscarBlockIo ();
  for (I = 0; I < mNumBio; ++I) {
    if (!SoloUsb || PuedeEscribir (&mBio[I])) {
      Lista[NLista++] = I;
    }
  }

  while (TRUE) {
    Encabezado (SoloUsb ? L"Reparacion: elige el disco USB" : L"Pruebas de disco: elige el disco",
      L"Flechas: elegir   Enter: abrir   Esc: regresar");
    if (SoloUsb) {
      Texto (3, 5, T_AMARILLO, L"Solo aparecen discos USB externos. Tu disco interno (Windows y macOS) y la USB de OpenCore no salen aqui.");
    }

    if (NLista == 0) {
      Texto (3, 8, T_NORMAL, SoloUsb ? L"No hay discos USB externos. Conecta uno (o su adaptador) y vuelve a entrar."
                                     : L"No hay discos.");
      EsperarTecla ();
      return;
    }

    for (I = 0; I < NLista; ++I) {
      D = &mBio[Lista[I]];
      Tamano (B1, sizeof (B1), MultU64x32 (D->Bio->Media->LastBlock + 1, D->Bio->Media->BlockSize));
      Rect (ColX (2), FilaY (8 + I * 2) - 4, 5, gCeldaH + 8, (I == Sel) ? &cRojo : &cNegro);
      Texto (4, 8 + I * 2, (I == Sel) ? T_BLANCO : T_NORMAL, L"%d  %10s  %-10s %s  %s", I + 1, B1,
        D->EsArranque ? L"[arranque]" : (D->EsUsb ? L"[USB]" : L"[interno]"),
        (D->Ata.Ata != NULL) ? L"ATA" : L"   ", (D->Ruta != NULL) ? D->Ruta : L"");
    }

    T = EsperarTecla ();
    if (T.ScanCode == SCAN_ESC) {
      return;
    } else if (T.ScanCode == SCAN_DOWN) {
      Sel = (Sel + 1) % NLista;
    } else if (T.ScanCode == SCAN_UP) {
      Sel = (Sel + NLista - 1) % NLista;
    } else if (T.UnicodeChar == CHAR_CARRIAGE_RETURN) {
      MenuMetodos (&mBio[Lista[Sel]], FALSE);
    }
  }
}

VOID
DiagDiscoSuperficie (
  VOID
  )
{
  ElegirDisco (FALSE);
}

VOID
DiagDiscoReparar (
  VOID
  )
{
  ElegirDisco (TRUE);
}

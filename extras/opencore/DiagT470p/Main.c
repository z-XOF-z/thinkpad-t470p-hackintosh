/** @file
  DiagT470p: menu principal.

  Herramienta propia de diagnostico para la ThinkPad T470p, se abre desde el menu de OpenCore.
  Todo es de SOLO LECTURA: no escribe en ningun disco. (La prueba de RAM solo usa memoria libre
  que reserva y devuelve.)

  SPDX-License-Identifier: BSD-3-Clause
**/
#include "Comun.h"

typedef struct {
  CONST CHAR16  *Nombre;
  CONST CHAR16  *Detalle;
  VOID          (*Funcion)(VOID);
} OPCION;

STATIC CONST OPCION  mOpciones[] = {
  { L"Resumen del sistema",            L"CPU, memoria, pantalla, firmware y mapa de la RAM",          DiagResumen         },
  { L"Prueba de RAM",                  L"Patrones sobre toda la memoria libre, con mapa de bloques", DiagRam             },
  { L"Discos: informacion y S.M.A.R.T.", L"Modelo, salud, horas, temperatura y atributos",          DiagDiscoInfo       },
  { L"Discos: pruebas",                L"Lectura, ATA Verify, mariposa, acceso aleatorio (cualquier disco)", DiagDiscoSuperficie },
  { L"Discos: reparacion",             L"Remap, refrescar, leer-escribir-leer, patron, borrar (solo USB)",  DiagDiscoReparar    },
  { L"Prueba de teclado",              L"Teclado de la T470p en pantalla: cada tecla se ilumina",    DiagTeclado         },
  { L"Prueba de pantalla",             L"Colores solidos y degradados para pixeles muertos",          DiagPantalla        },
  { L"Bateria",                        L"Carga, salud, ciclos, voltaje y corriente (del EC)",         DiagBateria         },
  { L"BIOS y ThinkPad",                L"Firmware, Secure Boot, orden de arranque, ventilador, reiniciar a la BIOS", DiagBios },
};

#define NUM_OPCIONES  (sizeof (mOpciones) / sizeof (mOpciones[0]))

STATIC
VOID
DibujarMenu (
  IN UINTN  Sel
  )
{
  UINTN   I, Fila;
  UINT32  Y;

  Encabezado (L"Menu", L"Flechas: elegir    Enter: abrir    Esc: regresar a OpenCore");
  Texto (3, 5, T_GRIS, L"Herramienta propia de diagnostico. Solo la opcion de reparacion escribe, y solo en discos USB externos.");

  for (I = 0; I < NUM_OPCIONES + 1; ++I) {
    Fila = 8 + I * 3;
    Y    = FilaY (Fila) - gCeldaH / 2;
    // La consola pinta fondo negro detras de cada letra: se marca con borde y barra, no con relleno
    Rect (ColX (2), Y, ColX (120), gCeldaH * 2, &cNegro);
    if (I == Sel) {
      Marco (ColX (2), Y, ColX (120), gCeldaH * 2, &cRojo);
      Rect (ColX (2), Y, 5, gCeldaH * 2, &cRojo);
    }

    if (I < NUM_OPCIONES) {
      Texto (5, Fila, (I == Sel) ? T_BLANCO : T_NORMAL, L"%d  %s", I + 1, mOpciones[I].Nombre);
      Texto (44, Fila, T_GRIS, L"%s", mOpciones[I].Detalle);
    } else {
      Texto (5, Fila, (I == Sel) ? T_BLANCO : T_NORMAL, L"0  Regresar al menu de OpenCore");
    }
  }
}

EFI_STATUS
EFIAPI
UefiMain (
  IN EFI_HANDLE        ImageHandle,
  IN EFI_SYSTEM_TABLE  *SystemTable
  )
{
  UINTN          Sel = 0;
  EFI_INPUT_KEY  T;

  PantallaIniciar ();
  if (gGop == NULL) {
    Print (L"DiagT470p: no hay salida grafica (GOP).\n");
    gBS->Stall (3000000);
    return EFI_UNSUPPORTED;
  }

  DibujarMenu (Sel);
  while (TRUE) {
    T = EsperarTecla ();
    if (T.ScanCode == SCAN_UP) {
      Sel = (Sel == 0) ? NUM_OPCIONES : Sel - 1;
    } else if (T.ScanCode == SCAN_DOWN) {
      Sel = (Sel + 1) % (NUM_OPCIONES + 1);
    } else if (T.ScanCode == SCAN_ESC) {
      break;
    } else if ((T.UnicodeChar >= L'1') && (T.UnicodeChar < L'1' + (CHAR16)NUM_OPCIONES)) {
      Sel = T.UnicodeChar - L'1';
      mOpciones[Sel].Funcion ();
    } else if (T.UnicodeChar == L'0') {
      break;
    } else if ((T.UnicodeChar == CHAR_CARRIAGE_RETURN) || (T.UnicodeChar == L' ')) {
      if (Sel == NUM_OPCIONES) {
        break;
      }

      mOpciones[Sel].Funcion ();
    } else {
      continue;
    }

    DibujarMenu (Sel);
  }

  Limpiar ();
  return EFI_SUCCESS;
}

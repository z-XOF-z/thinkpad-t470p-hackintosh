/** @file
  LiveStats: panel EN VIVO (temperatura, frecuencia y consumo del CPU) para el menu de OpenCanopy.
  SPDX-License-Identifier: BSD-3-Clause
**/
#ifndef LIVE_STATS_H_
#define LIVE_STATS_H_

extern GUI_OBJ_CHILD  mLiveStatsPanel;

VOID
LiveStatsInitialize (
  IN OUT GUI_DRAWING_CONTEXT      *DrawContext,
  IN     BOOT_PICKER_GUI_CONTEXT  *GuiContext
  );

VOID
LiveStatsDeinitialize (
  IN OUT GUI_DRAWING_CONTEXT  *DrawContext
  );

#endif // LIVE_STATS_H_

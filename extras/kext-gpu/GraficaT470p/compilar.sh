#!/bin/bash
# Compila GraficaT470p.kext sin Xcode (mismos parametros que el proyecto de WhateverGreen + MacKernelSDK).
set -e
cd "$(dirname "$0")"
F=../fuentes
SDK=$F/MacKernelSDK
LILU=$F/Lilu/Lilu
OUT=build; rm -rf $OUT; mkdir -p $OUT/GraficaT470p.kext/Contents/MacOS
COMUN=(-arch x86_64 -mkernel -nostdinc -fno-builtin -fno-common -fno-stack-protector -fno-asynchronous-unwind-tables
       -mmacosx-version-min=10.15 -O2 -g0
       -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT
       -DPRODUCT_NAME=GraficaT470p -DMODULE_VERSION=1.0.0
       -I"$SDK/Headers" -I"$LILU" -Wno-unknown-warning-option -Wno-ossharedptr-misuse -Wno-vla -Wno-deprecated-declarations)
clang++ "${COMUN[@]}" -std=c++17 -fapple-kext -fno-exceptions -fno-rtti -c kern_start.cpp -o $OUT/kern_start.o
clang++ "${COMUN[@]}" -std=c++17 -fapple-kext -fno-exceptions -fno-rtti -c "$LILU/Library/plugin_start.cpp" -o $OUT/plugin_start.o
clang   "${COMUN[@]}" -c info.c -o $OUT/info.o
clang++ -arch x86_64 -mmacosx-version-min=10.15 -Xlinker -kext -nostdlib -static \
  $OUT/info.o $OUT/kern_start.o $OUT/plugin_start.o \
  -L"$SDK/Library/x86_64" -lkmod \
  /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk/usr/lib/libkmodc++.a \
  /Library/Developer/CommandLineTools/usr/lib/clang/21/lib/darwin/libclang_rt.cc_kext.a \
  -o $OUT/GraficaT470p.kext/Contents/MacOS/GraficaT470p
cp Info.plist $OUT/GraficaT470p.kext/Contents/Info.plist
echo "OK: $OUT/GraficaT470p.kext"

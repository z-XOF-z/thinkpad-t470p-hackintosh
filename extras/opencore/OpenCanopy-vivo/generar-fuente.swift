// Genera LiveFont.h: glifos suavizados (alfa 8 bits) para el panel EN VIVO de OpenCanopy.
// Tres tamaños: Grande (numeros del valor), Mediano (titulos/reloj) y Chico (etiquetas).
// Uso: swift generar-fuente.swift > OpenCorePkg/Platform/OpenCanopy/Views/LiveFont.h
import AppKit

struct Fuente { let nombre: String; let tam: CGFloat; let peso: NSFont.Weight; let chars: [Character] }

let ascii = (32...126).map { Character(UnicodeScalar($0)!) }
let fuentes = [
    Fuente(nombre: "Grande", tam: 40, peso: .bold, chars: Array(" 0123456789.-%:")),
    Fuente(nombre: "Mediano", tam: 19, peso: .bold, chars: ascii),
    Fuente(nombre: "Chico", tam: 14, peso: .medium, chars: ascii),
]

var salida = """
/** @file
  LiveFont.h: fuente suavizada para el panel EN VIVO (generada con generar-fuente.swift, Helvetica Neue / SF).
  Cada glifo es una celda de alto fijo con alfa de 8 bits (0 = transparente, 255 = solido).
  SPDX-License-Identifier: BSD-3-Clause
**/
#ifndef LIVE_FONT_H_
#define LIVE_FONT_H_

typedef struct {
  UINT16        Car;      // caracter
  UINT8         Ancho;    // ancho de la celda en pixeles (= avance)
  UINT32        Datos;    // desplazamiento en el arreglo de alfa
} LIVE_GLIFO;

typedef struct {
  UINT8             Alto;
  UINT16            NumGlifos;
  CONST LIVE_GLIFO  *Glifos;
  CONST UINT8       *Alfa;
} LIVE_FUENTE;


"""

for f in fuentes {
    let font = NSFont(name: f.peso == .bold ? "HelveticaNeue-Bold" : "HelveticaNeue-Medium", size: f.tam)
        ?? NSFont.systemFont(ofSize: f.tam, weight: f.peso)
    let alto = Int(ceil(font.ascender - font.descender))
    var datos: [UInt8] = []
    var glifos: [(UInt16, Int, Int)] = []
    for c in f.chars {
        let s = NSAttributedString(string: String(c), attributes: [.font: font, .foregroundColor: NSColor.white])
        let ancho = max(1, Int(ceil(s.size().width)))
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: ancho, pixelsHigh: alto, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)!
        ctx.shouldAntialias = true
        NSGraphicsContext.current = ctx
        NSColor.clear.set(); NSRect(x: 0, y: 0, width: ancho, height: alto).fill()
        s.draw(at: NSPoint(x: 0, y: -font.descender))
        NSGraphicsContext.restoreGraphicsState()
        glifos.append((UInt16(c.unicodeScalars.first!.value), ancho, datos.count))
        for y in 0..<alto {
            for x in 0..<ancho {
                datos.append(UInt8(rep.colorAt(x: x, y: y).map { $0.alphaComponent * 255 } ?? 0))
            }
        }
    }
    salida += "STATIC CONST UINT8  mAlfa\(f.nombre)[\(datos.count)] = {\n"
    for i in stride(from: 0, to: datos.count, by: 24) {
        salida += "  " + datos[i..<min(i + 24, datos.count)].map { String(format: "0x%02X,", $0) }.joined(separator: " ") + "\n"
    }
    salida += "};\n\nSTATIC CONST LIVE_GLIFO  mGlifos\(f.nombre)[\(glifos.count)] = {\n"
    for g in glifos { salida += "  { 0x\(String(g.0, radix: 16)), \(g.1), \(g.2) },\n" }
    salida += "};\n\nSTATIC CONST LIVE_FUENTE  mFuente\(f.nombre) = { \(alto), \(glifos.count), mGlifos\(f.nombre), mAlfa\(f.nombre) };\n\n"
}
salida += "#endif // LIVE_FONT_H_\n"
print(salida)

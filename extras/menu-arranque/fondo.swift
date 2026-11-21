// Dibuja el fondo del menu de OpenCore (OpenCanopy) estilo ThinkPad: 1920x1080, centro libre para los iconos.
// Uso: swift fondo.swift   -> Background.png y Background.icns (PNG dentro de un registro 'ic07') junto a este archivo
import AppKit

let W: CGFloat = 1920, H: CGFloat = 1080
let dir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let rojo = NSColor(srgbRed: 0.89, green: 0.07, blue: 0.13, alpha: 1)
let gris = NSColor(white: 0.62, alpha: 1)
let blanco = NSColor(white: 0.96, alpha: 1)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

// Fondo: degradado casi negro con un brillo rojo muy suave arriba a la izquierda
NSGradient(colors: [NSColor(white: 0.085, alpha: 1), NSColor(white: 0.035, alpha: 1)])!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -70)
NSGradient(colors: [rojo.withAlphaComponent(0.16), rojo.withAlphaComponent(0)])!
    .draw(fromCenter: NSPoint(x: 140, y: H - 120), radius: 0, toCenter: NSPoint(x: 140, y: H - 120), radius: 820, options: [])

// Textura tipo fibra de carbono: lineas diagonales muy tenues
ctx.setStrokeColor(NSColor(white: 1, alpha: 0.0).cgColor)  // textura apagada (casi no se veia y hacia pesado el PNG)
ctx.setLineWidth(1)
var x: CGFloat = -H
while x < W { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x + H, y: H)); x += 7 }
ctx.strokePath()

func texto(_ s: String, _ f: NSFont, _ c: NSColor, _ p: NSPoint, kern: CGFloat = 0) -> NSSize {
    let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: c, .kern: kern]
    let t = NSAttributedString(string: s, attributes: a); t.draw(at: p); return t.size()
}
func fuente(_ n: String, _ t: CGFloat, _ peso: NSFont.Weight = .regular) -> NSFont {
    NSFont(name: n, size: t) ?? NSFont.systemFont(ofSize: t, weight: peso)
}

// --- Logo arriba a la izquierda: "ThinkPad" con el punto de la i en rojo ---
let logo = fuente("HelveticaNeue-BoldItalic", 74, .bold)
let px: CGFloat = 96, py: CGFloat = H - 168
let a1 = texto("Th", logo, blanco, NSPoint(x: px, y: py))
let anchoI = NSAttributedString(string: "ı", attributes: [.font: logo]).size().width
_ = texto("ı", logo, blanco, NSPoint(x: px + a1.width, y: py))           // i sin punto
let punto = NSBezierPath(ovalIn: NSRect(x: px + a1.width + anchoI * 0.5 - 6, y: py + 60, width: 13, height: 13))
rojo.setFill(); punto.fill()
_ = texto("nkPad", logo, blanco, NSPoint(x: px + a1.width + anchoI, y: py))
_ = texto("T470p", fuente("HelveticaNeue-Light", 30), gris, NSPoint(x: px + 4, y: py - 40), kern: 6)

// --- Panel de hardware arriba a la derecha ---
let filas: [(String, String)] = [
    ("CPU", "Intel Core i5-7300HQ · 4 núcleos · 2.5–3.5 GHz"),
    ("GPU", "Intel HD Graphics 630 · Metal 3 · 1.5 GB"),
    ("RAM", "16 GB DDR4 · 2400 MHz · 2 × 8 GB"),
    ("SSD", "Kingston A400 · 480 GB SATA"),
    ("PANTALLA", "14\" Full HD 1920 × 1080 · IPS"),
    ("RED", "Intel 8265 WiFi AC · Bluetooth 4.2 · I219-V"),
]
let etiqueta = fuente("HelveticaNeue-Bold", 15, .bold)
let valor = fuente("HelveticaNeue", 21)
let panelX: CGFloat = W - 700, panelTop: CGFloat = H - 96
rojo.setFill(); NSRect(x: panelX - 28, y: panelTop - CGFloat(filas.count) * 52 - 2, width: 4, height: CGFloat(filas.count) * 52 + 4).fill()
for (i, (e, v)) in filas.enumerated() {
    let y = panelTop - CGFloat(i + 1) * 52
    _ = texto(e, etiqueta, rojo, NSPoint(x: panelX, y: y + 26), kern: 2.5)
    _ = texto(v, valor, blanco, NSPoint(x: panelX, y: y + 1))
}

// --- Abajo: linea roja, sistemas e instrucciones ---
let baseY: CGFloat = 92
NSGradient(colors: [rojo.withAlphaComponent(0), rojo, rojo.withAlphaComponent(0)])!
    .draw(in: NSRect(x: 96, y: baseY + 52, width: W - 192, height: 2), angle: 0)
_ = texto("macOS Tahoe 26.7.3   ·   Windows   ·   OpenCore 1.0.8", fuente("HelveticaNeue-Medium", 20), gris,
          NSPoint(x: 96, y: baseY))
let ayuda = "←  →  elegir      ENTER  arrancar      ESPACIO  más opciones"
let ta = NSAttributedString(string: ayuda, attributes: [.font: fuente("Menlo-Regular", 17), .kern: 1, .foregroundColor: gris])
ta.draw(at: NSPoint(x: W - 96 - ta.size().width, y: baseY + 2))
// toque: tres puntos rojos tipo LED abajo a la izquierda del texto
for k in 0..<3 {
    (k == 0 ? rojo : NSColor(white: 0.25, alpha: 1)).setFill()
    NSBezierPath(ovalIn: NSRect(x: 96 + CGFloat(k) * 18, y: baseY + 26, width: 8, height: 8)).fill()
}

NSGraphicsContext.restoreGraphicsState()

// Guardar PNG y meterlo en un .icns con un solo registro 'ic07' (OpenCanopy lo usa a escala 1x, de cualquier tamaño)
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: dir.appendingPathComponent("Background.png"))
func be32(_ v: Int) -> Data { var b = UInt32(v).bigEndian; return Data(bytes: &b, count: 4) }
var icns = Data("icns".utf8); icns += be32(8 + 8 + png.count)
icns += Data("ic07".utf8); icns += be32(8 + png.count); icns += png
try! icns.write(to: dir.appendingPathComponent("Background.icns"))
print("Background.png y Background.icns:", png.count, "bytes de PNG")

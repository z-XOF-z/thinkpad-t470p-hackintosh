// PantallaHz: cambia el panel interno al modo de mas Hz que tenga (1920x1080) y pide confirmar en 30 s.
// La ventana de confirmacion sale en TODAS las pantallas (si el panel se queda negro, se ve en la tele).
// Si no se confirma a tiempo, regresa solo al modo de antes.
// Uso: PantallaHz            -> prueba el maximo disponible
//      PantallaHz 60         -> regresa a 60 Hz (sin preguntar)
import Cocoa
import CoreGraphics

func panelInterno() -> CGDirectDisplayID? {
    var ids = [CGDirectDisplayID](repeating: 0, count: 8)
    var n: UInt32 = 0
    CGGetOnlineDisplayList(8, &ids, &n)
    return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 }
}

func modos(_ d: CGDirectDisplayID) -> [CGDisplayMode] {
    let opts = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
    return (CGDisplayCopyAllDisplayModes(d, opts) as? [CGDisplayMode]) ?? []
}

func poner(_ d: CGDirectDisplayID, _ m: CGDisplayMode) -> Bool {
    var cfg: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
    CGConfigureDisplayWithDisplayMode(cfg, d, m, nil)
    return CGCompleteDisplayConfiguration(cfg, .permanently) == .success
}

guard let panel = panelInterno(), let anterior = CGDisplayCopyDisplayMode(panel) else {
    print("No encontre el panel interno"); exit(1)
}
let actual = modos(panel).filter { $0.width == anterior.width && $0.height == anterior.height && $0.pixelWidth == anterior.pixelWidth }
let hzLista = Set(actual.map { Int($0.refreshRate.rounded()) }).sorted()
print("Modos de \(anterior.width)x\(anterior.height) en el panel: \(hzLista.map { "\($0) Hz" }.joined(separator: ", "))  (ahora: \(Int(anterior.refreshRate.rounded())) Hz)")

if let pedido = CommandLine.arguments.dropFirst().first.flatMap(Int.init) {
    guard let m = actual.first(where: { Int($0.refreshRate.rounded()) == pedido }) else { print("No hay modo de \(pedido) Hz"); exit(1) }
    print(poner(panel, m) ? "Listo: \(pedido) Hz" : "No se pudo cambiar")
    exit(0)
}

guard let mejor = actual.max(by: { $0.refreshRate < $1.refreshRate }), mejor.refreshRate > anterior.refreshRate + 1 else {
    print("No hay un modo con mas Hz que el actual. (Instala el override con pantalla-hz.sh y reinicia.)"); exit(0)
}
let hz = Int(mejor.refreshRate.rounded())
guard poner(panel, mejor) else { print("macOS no acepto el modo de \(hz) Hz"); exit(1) }

// --- Confirmacion en todas las pantallas, con cuenta regresiva ---
final class Confirmar: NSObject, NSApplicationDelegate {
    let panel: CGDirectDisplayID
    let anterior: CGDisplayMode
    let hz: Int
    init(_ p: CGDirectDisplayID, _ a: CGDisplayMode, _ h: Int) { panel = p; anterior = a; hz = h }
    var ventanas: [NSWindow] = []
    var etiquetas: [NSTextField] = []
    var restante = 30
    var timer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        for pantalla in NSScreen.screens {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 170), styleMask: [.titled], backing: .buffered, defer: false, screen: pantalla)
            w.title = "Panel a \(hz) Hz"
            w.level = .screenSaver
            let v = w.contentView!
            let t = NSTextField(labelWithString: "")
            t.font = .systemFont(ofSize: 15)
            t.frame = NSRect(x: 20, y: 90, width: 420, height: 50)
            v.addSubview(t)
            etiquetas.append(t)
            let ok = NSButton(title: "Se ve bien, dejar \(hz) Hz", target: self, action: #selector(mantener))
            ok.frame = NSRect(x: 20, y: 25, width: 230, height: 32)
            ok.keyEquivalent = "\r"
            let no = NSButton(title: "Regresar a 60 Hz", target: self, action: #selector(revertir))
            no.frame = NSRect(x: 270, y: 25, width: 170, height: 32)
            v.addSubview(ok); v.addSubview(no)
            let f = pantalla.visibleFrame
            w.setFrameOrigin(NSPoint(x: f.midX - 230, y: f.midY - 85))
            w.makeKeyAndOrderFront(nil)
            ventanas.append(w)
        }
        NSApp.activate(ignoringOtherApps: true)
        actualizar()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tic() }
    }

    func actualizar() {
        for t in etiquetas { t.stringValue = "El panel ya esta a \(hz) Hz. ¿Se ve bien?\nSi no confirmas, regresa a 60 Hz en \(restante) s." }
    }

    func tic() {
        restante -= 1
        if restante <= 0 { revertir() } else { actualizar() }
    }

    @objc func mantener() {
        print("Confirmado: el panel se queda a \(hz) Hz")
        NSApp.terminate(nil)
    }

    @objc func revertir() {
        _ = poner(panel, anterior)
        print("Regresado a \(Int(anterior.refreshRate.rounded())) Hz")
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegado = Confirmar(panel, anterior, hz)
app.delegate = delegado
app.setActivationPolicy(.accessory)
app.run()

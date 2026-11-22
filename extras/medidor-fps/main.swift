// MedidorFPS: muestra en la esquina INFERIOR IZQUIERDA de cada pantalla los cuadros por segundo reales,
// el uso de la GPU y del CPU. No estorba: deja pasar el mouse y sale encima de todo, en todos los escritorios.
//
// Como cuenta los FPS: ScreenCaptureKit entrega un cuadro "completo" solo cuando WindowServer dibuja algo nuevo
// en esa pantalla. Contando esos cuadros por segundo sale lo que de verdad se ve (como el FrameMeter de Quartz Debug).
// Se captura a 128x72 para que casi no cueste. Si nada se mueve, marca pocos FPS: eso es normal (no hay que dibujar).
// Necesita el permiso de "Grabacion de pantalla" (solo para contar cuadros; no guarda ni manda nada).
import Cocoa
import ScreenCaptureKit
import IOKit

// ---------- GPU y CPU ----------
func usoGPU() -> Int? {
    var it: io_iterator_t = 0
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(it) }
    var r: Int?
    var s = IOIteratorNext(it)
    while s != 0 {
        if let d = IORegistryEntryCreateCFProperty(s, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any], let u = d["Device Utilization %"] as? Int { r = max(r ?? 0, u) }
        IOObjectRelease(s)
        s = IOIteratorNext(it)
    }
    return r
}

var cpuAntes: (uso: UInt64, total: UInt64) = (0, 0)
func usoCPU() -> Int {
    var info = host_cpu_load_info()
    var n = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
    let k = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &n) }
    }
    guard k == KERN_SUCCESS else { return 0 }
    let t = info.cpu_ticks
    let uso = UInt64(t.0) + UInt64(t.1) + UInt64(t.3)          // user + system + nice
    let total = uso + UInt64(t.2)                               // + idle
    defer { cpuAntes = (uso, total) }
    let dt = total &- cpuAntes.total
    return dt == 0 || cpuAntes.total == 0 ? 0 : Int(Double(uso &- cpuAntes.uso) / Double(dt) * 100)
}

// ---------- Contador de cuadros de una pantalla ----------
final class Contador: NSObject, SCStreamOutput, SCStreamDelegate {
    private var cuadros = 0
    private let candado = NSLock()
    var stream: SCStream?

    func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of tipo: SCStreamOutputType) {
        guard tipo == .screen,
              let a = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = a.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
        candado.lock(); cuadros += 1; candado.unlock()
    }
    func stream(_ s: SCStream, didStopWithError e: Error) { stream = nil }
    func tomar() -> Int { candado.lock(); defer { cuadros = 0; candado.unlock() }; return cuadros }
}

// ---------- Ventanita de cada pantalla ----------
final class Indicador {
    let ventana: NSWindow
    let texto = NSTextField(labelWithString: "")
    let pantallaID: CGDirectDisplayID
    let contador = Contador()

    init(_ pantalla: NSScreen) {
        pantallaID = (pantalla.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        // Cuadrito angosto (3 lineas) para que quepa en la esquina a la izquierda del Dock sin taparlo
        let ancho: CGFloat = 92, alto: CGFloat = 58
        ventana = NSWindow(contentRect: NSRect(x: pantalla.frame.minX + 8, y: pantalla.frame.minY + 8, width: ancho, height: alto),
                           styleMask: .borderless, backing: .buffered, defer: false)
        ventana.isOpaque = false
        ventana.backgroundColor = .clear
        ventana.ignoresMouseEvents = true
        ventana.hasShadow = false
        ventana.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        ventana.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // no aparece en capturas ni se cuenta a si misma ("--visible" para poder tomarle captura)
        ventana.sharingType = CommandLine.arguments.contains("--visible") ? .readOnly : .none
        let fondo = NSView(frame: NSRect(x: 0, y: 0, width: ancho, height: alto))
        fondo.wantsLayer = true
        fondo.layer?.backgroundColor = NSColor(white: 0, alpha: 0.62).cgColor
        fondo.layer?.cornerRadius = 7
        texto.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        texto.textColor = .white
        texto.alignment = .left
        texto.maximumNumberOfLines = 3
        texto.frame = NSRect(x: 8, y: 5, width: ancho - 12, height: alto - 10)
        fondo.addSubview(texto)
        ventana.contentView = fondo
        ventana.orderFrontRegardless()
        mostrar("-- FPS", "GPU --\nCPU --")
    }

    var hz: Int { CGDisplayCopyDisplayMode(pantallaID).map { Int($0.refreshRate.rounded()) } ?? 60 }

    // Primera linea (FPS) grande y de color; las otras dos chicas en blanco
    func mostrar(_ fps: String, _ resto: String, color: NSColor = .white) {
        let t = NSMutableAttributedString(string: fps + "\n", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold), .foregroundColor: color])
        t.append(NSAttributedString(string: resto, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]))
        texto.attributedStringValue = t
    }

    func empezar(_ disp: SCDisplay) {
        let cfg = SCStreamConfiguration()
        cfg.width = 128; cfg.height = 72
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 240)   // sin tope: cuenta hasta lo que de la pantalla
        cfg.queueDepth = 3
        cfg.showsCursor = true                                       // mover el mouse tambien es dibujar
        cfg.pixelFormat = kCVPixelFormatType_32BGRA
        let s = SCStream(filter: SCContentFilter(display: disp, excludingWindows: []), configuration: cfg, delegate: contador)
        do {
            try s.addStreamOutput(contador, type: .screen, sampleHandlerQueue: DispatchQueue(label: "fps.\(pantallaID)"))
            s.startCapture { e in if e != nil { DispatchQueue.main.async { self.contador.stream = nil } } }
            contador.stream = s
        } catch { contador.stream = nil }
    }

    func cerrar() { contador.stream?.stopCapture(); ventana.orderOut(nil) }
}

final class App: NSObject, NSApplicationDelegate {
    var indicadores: [Indicador] = []
    var sinPermiso = false

    func applicationDidFinishLaunching(_ n: Notification) {
        armar()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.armar() }
        }
        _ = usoCPU()
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tic() }
    }

    func armar() {
        indicadores.forEach { $0.cerrar() }
        indicadores = NSScreen.screens.map { Indicador($0) }
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { contenido, error in
            DispatchQueue.main.async {
                guard let contenido else { self.sinPermiso = true; return }
                self.sinPermiso = false
                for i in self.indicadores {
                    if let d = contenido.displays.first(where: { $0.displayID == i.pantallaID }) { i.empezar(d) }
                }
            }
        }
    }

    func tic() {
        let cpu = usoCPU()
        let gpu = usoGPU().map { "\($0)%" } ?? "--"
        for i in indicadores {
            guard !sinPermiso, i.contador.stream != nil else {
                i.mostrar("? FPS", "GPU \(gpu)\nCPU \(cpu)%", color: .systemYellow); continue
            }
            // ScreenCaptureKit entrega maximo 60 cuadros por segundo (probado en Tahoe con el panel a 75 Hz:
            // CVDisplayLink da 75.0 vsync/s pero la captura nunca pasa de 60). Al llegar al tope se muestra "60+".
            let hz = i.hz
            let tope = min(hz, 60)
            let fps = min(i.contador.tomar(), tope)
            if CommandLine.arguments.contains("--visible") { print("pantalla \(i.pantallaID): \(fps) FPS de \(hz) Hz") }
            // Verde: fluido. Amarillo: a medias. Rojo: se esta trabando. Gris: nada se mueve (no hay que dibujar).
            // El contador mide cuadros NUEVOS: si nadie toca mouse/teclado y nada se anima, macOS no dibuja y el numero baja
            // sin que haya trabazon. Por eso: sin uso en el ultimo segundo y pocos FPS = "reposo" (gris), no rojo.
            let sinUso = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: unsafeBitCast(UInt32.max, to: CGEventType.self)) > 1.0   // kCGAnyInputEventType = cualquier tecla o mouse
            let enReposo = sinUso && fps < tope * 85 / 100
            let color: NSColor = enReposo || fps < 5 ? NSColor(white: 0.75, alpha: 1)
                : fps >= tope * 85 / 100 ? .systemGreen : fps >= tope / 2 ? .systemYellow : .systemRed
            let txt = enReposo ? "reposo" : (fps >= tope - 1 && hz > tope) ? "\(tope)+ FPS" : "\(fps) FPS"
            i.mostrar(txt, "GPU \(gpu)\nCPU \(cpu)%", color: color)
        }
    }
}

setvbuf(stdout, nil, _IONBF, 0)
let app = NSApplication.shared
let delegado = App()
app.delegate = delegado
app.setActivationPolicy(.accessory)
app.run()

// LimpiarPantalla: colores solidos en pantalla completa del panel interno, cambiando SUAVE cada 10 s
// (sin parpadeo rapido). Sirve para ver defectos (fantasma, manchas) y para "lavar" la retencion de imagen del LCD.
// Uso: LimpiarPantalla [minutos]   (por defecto 60). Esc o clic para salir. No deja que la pantalla se apague.
import Cocoa
import IOKit.pwr_mgt

let minutos = Double(CommandLine.arguments.dropFirst().first ?? "60") ?? 60
let colores: [NSColor] = [.white, NSColor(white: 0.5, alpha: 1), .red, .green, .blue, .white, .black, NSColor(white: 0.25, alpha: 1)]
var asercion: IOPMAssertionID = 0
IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                            "LimpiarPantalla" as CFString, &asercion)

final class Vista: NSView {
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with e: NSEvent) { if e.keyCode == 53 { NSApp.terminate(nil) } }
    override func mouseDown(with e: NSEvent) { NSApp.terminate(nil) }
}

final class App: NSObject, NSApplicationDelegate {
    var ventana: NSWindow!
    var i = 0
    func applicationDidFinishLaunching(_ n: Notification) {
        let pantalla = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false } ?? NSScreen.main!
        ventana = NSWindow(contentRect: pantalla.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: pantalla)
        ventana.level = .screenSaver
        ventana.setFrame(pantalla.frame, display: true)
        let v = Vista(frame: pantalla.frame); v.wantsLayer = true
        v.layer?.backgroundColor = colores[0].cgColor
        ventana.contentView = v
        ventana.makeKeyAndOrderFront(nil)
        ventana.makeFirstResponder(v)
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.hide()
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            self.i = (self.i + 1) % colores.count
            NSAnimationContext.runAnimationGroup { c in
                c.duration = 2
                v.animator().layer?.backgroundColor = colores[self.i].cgColor
            }
            CATransaction.begin(); CATransaction.setAnimationDuration(2)
            v.layer?.backgroundColor = colores[self.i].cgColor
            CATransaction.commit()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + minutos * 60) { NSApp.terminate(nil) }
    }
}
let app = NSApplication.shared
let d = App(); app.delegate = d
app.setActivationPolicy(.regular)
app.run()

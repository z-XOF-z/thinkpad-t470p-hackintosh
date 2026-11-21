// BateriaT470p: icono en la barra de menus para el limite de carga de la ThinkPad y la luz que respira.
// El limite se pone con los metodos de la BIOS BCCS (empezar a cargar) y BCSS (dejar de cargar), a traves
// del driver ThinkVPC de YogaSMC (propiedades "Battery", "setCMstart", "setCMstop"). Lo guarda el EC:
// se respeta tambien en Windows y con la laptop apagada. 0/0 = carga normal hasta 100 %.
import Cocoa
import IOKit

let servicio = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("ThinkVPC"))

func poner(_ clave: String, _ v: Int) {
    IORegistryEntrySetCFProperty(servicio, clave as CFString, v as CFNumber)
}

// Lee BCSG (dejar de cargar) de la bateria principal: byte bajo = porcentaje, 0 = 100 %
func limiteActual() -> Int {
    guard let d = IORegistryEntryCreateCFProperty(servicio, "BAT_PRIMARY" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [String: Any], let v = d["BCSG"] as? Int else { return 0 }
    return v & 0xFF
}

func ponerLimite(_ tope: Int) {
    poner("Battery", 1)                         // 1 = bateria principal (BAT0)
    if tope == 0 {
        poner("setCMstart", 0)
        poner("setCMstop", 0)
    } else {
        poner("setCMstop", tope)
        poner("setCMstart", max(tope - 5, 1))   // vuelve a cargar cuando baja 5 % del tope
    }
}

// --- Otras funciones de la ThinkPad que acepta la BIOS (probadas el 2026-11-21) ---
func propiedad(_ k: String) -> Any? { IORegistryEntryCreateCFProperty(servicio, k as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() }
// Fn Lock: F1-F12 como teclas de funcion sin apretar Fn (metodos GMKS/SMKS)
func fnLock() -> Bool { (propiedad("FnlockMode") as? Bool) ?? false }
func ponerFnLock(_ v: Bool) { IORegistryEntrySetCFProperty(servicio, "FnlockMode" as CFString, v as CFBoolean) }
// Pausar la carga aunque este conectada (metodo BICS); BICG bit 0 = en pausa
func cargaEnPausa() -> Bool {
    guard let d = propiedad("BAT_PRIMARY") as? [String: Any], let v = d["BICG"] as? Int else { return false }
    return (v & 1) != 0
}
func pausarCarga(_ v: Bool) { poner("Battery", 1); poner("setCMInhibitCharge", v ? 1 : 0) }
// LED del punto rojo de la "i" en la tapa (metodo LED, EC 0x0C): 0x0A apagado, 0x8A prendido, 0xCA parpadeo
func puntoRojo(_ v: Int) { poner("LED", v) }

let luz = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/LuzTeclado").path
let pidLuz = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/LuzTeclado/respirar.pid").path

let modoLuz = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/LuzTeclado/modo").path

// Modo actual de respiracion ("rapido", "medio", "lento") o "" si no esta respirando
func modoRespiracion() -> String {
    guard let t = try? String(contentsOfFile: pidLuz, encoding: .utf8), let p = pid_t(t.trimmingCharacters(in: .whitespacesAndNewlines)),
          kill(p, 0) == 0 else { return "" }
    return ((try? String(contentsOfFile: modoLuz, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
}

func correr(_ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: luz)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()

    func applicationDidFinishLaunching(_ n: Notification) {
        menu.delegate = self
        item.menu = menu
        poner("Battery", 1)
        actualizarIcono()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.actualizarIcono() }
    }

    func actualizarIcono() {
        let l = limiteActual()
        item.button?.image = NSImage(systemSymbolName: l == 0 ? "battery.100" : "battery.75", accessibilityDescription: "Limite de carga")
        item.button?.title = l == 0 ? "" : " \(l)%"
        item.button?.imagePosition = .imageLeading
    }

    func menuNeedsUpdate(_ m: NSMenu) {
        m.removeAllItems()
        let l = limiteActual()
        let t = NSMenuItem(title: l == 0 ? "Carga normal (hasta 100 %)" : "Cargando solo hasta \(l) %", action: nil, keyEquivalent: "")
        t.isEnabled = false
        m.addItem(t)
        m.addItem(.separator())
        for (titulo, v) in [("Cargar hasta 60 %", 60), ("Cargar hasta 80 % (recomendado si esta siempre conectada)", 80),
                            ("Cargar hasta 90 %", 90), ("Carga normal (100 %)", 0)] {
            let i = NSMenuItem(title: titulo, action: #selector(elegir(_:)), keyEquivalent: "")
            i.target = self
            i.tag = v
            i.state = (l == v) ? .on : .off
            m.addItem(i)
        }
        let pz = NSMenuItem(title: "Pausar la carga (aunque este conectada)", action: #selector(pausa(_:)), keyEquivalent: "")
        pz.target = self
        pz.state = cargaEnPausa() ? .on : .off
        m.addItem(pz)
        m.addItem(.separator())
        let fl = NSMenuItem(title: "Fn Lock (F1-F12 sin apretar Fn)", action: #selector(fn(_:)), keyEquivalent: "")
        fl.target = self
        fl.state = fnLock() ? .on : .off
        m.addItem(fl)
        let pr = NSMenuItem(title: "Punto rojo de la tapa", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for (t, v) in [("Prendido (normal)", 0x8A), ("Apagado", 0x0A), ("Parpadeando", 0xCA)] {
            let i = NSMenuItem(title: t, action: #selector(punto(_:)), keyEquivalent: "")
            i.target = self
            i.tag = v
            sub.addItem(i)
        }
        pr.submenu = sub
        m.addItem(pr)
        m.addItem(.separator())
        let r = NSMenuItem(title: "Luz del teclado", action: nil, keyEquivalent: "")
        let subLuz = NSMenu()
        let actual = modoRespiracion()
        for (t, v) in [("Normal (Fn + Espacio: apagada / baja / alta)", ""), ("Respirar rapido", "rapido"),
                       ("Respirar medio", "medio"), ("Respirar lento", "lento")] {
            let i = NSMenuItem(title: t, action: #selector(respirar(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = v
            i.state = (actual == v) ? .on : .off
            subLuz.addItem(i)
        }
        r.submenu = subLuz
        m.addItem(r)
        m.addItem(.separator())
        let s = NSMenuItem(title: "Salir", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        m.addItem(s)
    }

    @objc func elegir(_ s: NSMenuItem) {
        ponerLimite(s.tag)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.actualizarIcono() }
    }

    @objc func pausa(_ s: NSMenuItem) { pausarCarga(!cargaEnPausa()) }
    @objc func fn(_ s: NSMenuItem) { ponerFnLock(!fnLock()) }
    @objc func punto(_ s: NSMenuItem) { puntoRojo(s.tag) }

    @objc func respirar(_ s: NSMenuItem) {
        let v = (s.representedObject as? String) ?? ""
        correr([v.isEmpty ? "parar" : v])
    }
}

let app = NSApplication.shared
let delegado = App()
app.delegate = delegado
app.setActivationPolicy(.accessory)
app.run()

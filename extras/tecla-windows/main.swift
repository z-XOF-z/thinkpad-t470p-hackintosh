// TeclaWindows: si aprietas y sueltas la tecla Windows SOLA, abre Apps (como el menú Inicio).
// Con otra tecla o clic en medio (Win+C, Win+clic...) no hace nada y sigue funcionando como modificador.
// Por el cambio de hidutil (com.andrew.teclas-ctrl) la tecla Windows física llega como Control izquierdo (código 59).
// Necesita permiso de "Monitoreo de entrada" (Ajustes > Privacidad y seguridad).
import Cocoa

let teclaWin: Int64 = 59          // Control izquierdo = tecla Windows física
let tiempoMax: TimeInterval = 0.6 // si la dejas apretada más que esto, no abre nada
let apps = URL(fileURLWithPath: "/System/Applications/Apps.app")

var apretada = false
var otraTecla = false
var inicio = Date()
var tapGlobal: CFMachPort? = nil

func abrirApps() {
    DispatchQueue.main.async {
        NSWorkspace.shared.openApplication(at: apps, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
}

let callback: CGEventTapCallBack = { _, tipo, evento, refcon in
    switch tipo {
    case .flagsChanged:
        let code = evento.getIntegerValueField(.keyboardEventKeycode)
        let ctrl = evento.flags.contains(.maskControl)
        if code == teclaWin {
            if ctrl && !apretada {                      // se apretó
                apretada = true; otraTecla = false; inicio = Date()
            } else if !ctrl && apretada {               // se soltó
                apretada = false
                if !otraTecla && Date().timeIntervalSince(inicio) < tiempoMax { abrirApps() }
            }
        } else if apretada {
            otraTecla = true                            // otro modificador junto (Shift, Alt...)
        }
    case .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel:
        if apretada { otraTecla = true }
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let t = tapGlobal { CGEvent.tapEnable(tap: t, enable: true) }
    default: break
    }
    return Unmanaged.passUnretained(evento)
}

let tipos: [CGEventType] = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
let mascara = tipos.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

// Pedir permiso de Monitoreo de entrada si no lo tiene, y esperar a que lo den
if !CGPreflightListenEventAccess() {
    _ = CGRequestListenEventAccess()
    NSLog("TeclaWindows: esperando permiso de Monitoreo de entrada; launchd me vuelve a abrir")
    Thread.sleep(forTimeInterval: 20)
    exit(0)
}

guard let tap2 = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                   eventsOfInterest: mascara, callback: callback, userInfo: nil) else {
    NSLog("TeclaWindows: no pude crear el event tap (falta permiso de Monitoreo de entrada)")
    exit(1)
}
tapGlobal = tap2
let fuente = CFMachPortCreateRunLoopSource(nil, tap2, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), fuente, .commonModes)
CGEvent.tapEnable(tap: tap2, enable: true)
NSLog("TeclaWindows: listo")
NSApplication.shared.setActivationPolicy(.prohibited)
CFRunLoopRun()

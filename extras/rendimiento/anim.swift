// anim: cuadro rojo girando con Core Animation (corre a la velocidad de la pantalla). Para medir FPS.
import Cocoa
let app = NSApplication.shared
let w = NSWindow(contentRect: NSRect(x: 300, y: 300, width: 200, height: 200), styleMask: .titled, backing: .buffered, defer: false)
let v = NSView(frame: w.contentView!.bounds); v.wantsLayer = true; w.contentView = v
let l = CALayer(); l.frame = CGRect(x: 50, y: 50, width: 100, height: 100); l.backgroundColor = NSColor.red.cgColor; v.layer!.addSublayer(l)
let a = CABasicAnimation(keyPath: "transform.rotation"); a.fromValue = 0; a.toValue = Double.pi * 2; a.duration = 1; a.repeatCount = .infinity
l.add(a, forKey: "r"); w.orderFrontRegardless()
app.setActivationPolicy(.accessory); app.run()

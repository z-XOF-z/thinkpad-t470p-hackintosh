// fps-mouse: cuenta cuadros nuevos de la pantalla IGNORANDO VS Code, en 3 casos: quieto, moviendo el mouse, mouse + animacion.
import Cocoa
import ScreenCaptureKit
final class C: NSObject, SCStreamOutput { var n = 0; let l = NSLock()
 func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of t: SCStreamOutputType) {
  guard let a = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]], let r = a.first?[.status] as? Int, r == 0 else { return }
  l.lock(); n += 1; l.unlock() }
 func tomar() -> Int { l.lock(); defer { n = 0; l.unlock() }; return n } }
setvbuf(stdout, nil, _IONBF, 0)
let sem = DispatchSemaphore(value: 0); var cont: SCShareableContent!
SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { c, _ in cont = c; sem.signal() }; sem.wait()
let disp = cont.displays.first { CGDisplayIsBuiltin($0.displayID) != 0 }!
let fuera = cont.applications.filter { $0.bundleIdentifier.contains("VSCode") || $0.applicationName.contains("Code") }
let cfg = SCStreamConfiguration(); cfg.width = 128; cfg.height = 72; cfg.minimumFrameInterval = CMTime(value: 1, timescale: 120); cfg.showsCursor = true
let c = C(); let s = SCStream(filter: SCContentFilter(display: disp, excludingApplications: fuera, exceptingWindows: []), configuration: cfg, delegate: nil)
try! s.addStreamOutput(c, type: .screen, sampleHandlerQueue: DispatchQueue(label: "q"))
s.startCapture { _ in }
Thread.sleep(forTimeInterval: 1.5); _ = c.tomar()
func medir(_ seg: Int, mover: Bool) -> String {
    var r = ""; let inicio = NSEvent.mouseLocation
    for _ in 0..<seg {
        let fin = Date().addingTimeInterval(1)
        var k = 0.0
        while Date() < fin {
            if mover { k += 0.05; CGWarpMouseCursorPosition(CGPoint(x: 700 + 250 * cos(k), y: 500 + 150 * sin(k))) }
            usleep(8000)
        }
        r += "\(c.tomar()) "
    }
    if mover { CGWarpMouseCursorPosition(CGPoint(x: inicio.x, y: NSScreen.screens[0].frame.height - inicio.y)) }
    return r
}
print("quieto:        ", medir(4, mover: false))
print("moviendo mouse:", medir(5, mover: true))

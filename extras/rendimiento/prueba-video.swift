// prueba-video: reproduce un video con WebKit (el mismo motor de Safari) y reporta cuadros decodificados, perdidos y errores.
// Uso: prueba-video archivo.webm [segundos]
import Cocoa
import WebKit
setvbuf(stdout, nil, _IONBF, 0)
let archivo = URL(fileURLWithPath: CommandLine.arguments[1])
let seg = Double(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "12") ?? 12
final class D: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    var w: NSWindow!; var web: WKWebView!
    func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
        print(m.body); if "\(m.body)".hasPrefix("FIN") { NSApp.terminate(nil) }
    }
    func applicationDidFinishLaunching(_ n: Notification) {
        let c = WKWebViewConfiguration(); c.mediaTypesRequiringUserActionForPlayback = []
        c.userContentController.add(self, name: "r")
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 540), configuration: c)
        w = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
        w.contentView = web; w.setFrameOrigin(NSPoint(x: 200, y: 200)); w.orderFrontRegardless()
        let mse = CommandLine.arguments.contains("--cambio")
        let html = mse ? """
        <html><body style="margin:0;background:#000"><video id=v muted autoplay playsinline style="width:100%"></video>
        <script>
        // Como YouTube: Media Source, empieza en 480p y a los 4 s cambia a 1080p en el MISMO SourceBuffer
        const v=document.getElementById('v'), r=m=>webkit.messageHandlers.r.postMessage(m);
        v.onerror=()=>r('ERROR del video, codigo '+(v.error&&v.error.code)+' '+(v.error&&v.error.message));
        v.onresize=()=>r('resolucion ahora '+v.videoWidth+'x'+v.videoHeight+' en t='+v.currentTime.toFixed(1));
        const ms=new MediaSource(); v.src=URL.createObjectURL(ms);
        const pedazo=(f,n)=>fetch(f).then(x=>x.arrayBuffer()).then(b=>b.slice(0,n));
        ms.onsourceopen=async()=>{
          try{
            const sb=ms.addSourceBuffer('video/webm; codecs="vp9,opus"');
            sb.onerror=()=>r('ERROR en SourceBuffer');
            const ap=b=>new Promise((ok,no)=>{sb.onupdateend=ok; sb.onerror=()=>no('append fallo'); sb.appendBuffer(b);});
            await ap(await pedazo('bbb-480p.webm', 4000000));
            r('480p cargado, buffer hasta '+sb.buffered.end(0).toFixed(1)+'s');
            await new Promise(ok=>setTimeout(ok,4000));
            const fin=sb.buffered.end(0); sb.timestampOffset=fin;
            await ap(await pedazo('bbb-1080p.webm', 12000000));
            r('1080p agregado desde '+fin.toFixed(1)+'s, buffer hasta '+sb.buffered.end(0).toFixed(1)+'s');
          }catch(e){ r('ERROR '+e); }
        };
        setInterval(()=>{const q=v.getVideoPlaybackQuality(); r('t='+v.currentTime.toFixed(1)+'s '+v.videoWidth+'x'+v.videoHeight+' cuadros='+q.totalVideoFrames+' perdidos='+q.droppedVideoFrames+(v.paused?' PAUSADO':''));},2000);
        setTimeout(()=>{const q=v.getVideoPlaybackQuality(); r('FIN cuadros='+q.totalVideoFrames+' perdidos='+q.droppedVideoFrames+' tiempo='+v.currentTime.toFixed(1)+'s'+(v.error?' CON ERROR':''));}, \(Int(seg * 1000)));
        </script></body></html>
        """ : """
        <html><body style="margin:0;background:#000"><video id=v src="\(archivo.lastPathComponent)" muted autoplay playsinline style="width:100%"></video>
        <script>
        const v=document.getElementById('v'), r=m=>webkit.messageHandlers.r.postMessage(m);
        v.onerror=()=>r('ERROR codigo '+(v.error&&v.error.code)+' '+(v.error&&v.error.message));
        v.onloadedmetadata=()=>r('video '+v.videoWidth+'x'+v.videoHeight);
        let t0=performance.now(), q0=null;
        setInterval(()=>{const q=v.getVideoPlaybackQuality(); r('t='+v.currentTime.toFixed(1)+'s cuadros='+q.totalVideoFrames+' perdidos='+q.droppedVideoFrames+(v.paused?' PAUSADO':''));},2000);
        setTimeout(()=>{const q=v.getVideoPlaybackQuality(); r('FIN cuadros='+q.totalVideoFrames+' perdidos='+q.droppedVideoFrames+' tiempo='+v.currentTime.toFixed(1)+'s');}, \(Int(seg * 1000)));
        </script></body></html>
        """
        let h = archivo.deletingLastPathComponent().appendingPathComponent("prueba.html")
        try! html.write(to: h, atomically: true, encoding: .utf8)
        if let p = ProcessInfo.processInfo.environment["PUERTO"] { web.load(URLRequest(url: URL(string: "http://127.0.0.1:\(p)/prueba.html")!)) }
        else { web.loadFileURL(h, allowingReadAccessTo: archivo.deletingLastPathComponent()) }
    }
}
let app = NSApplication.shared; let d = D(); app.delegate = d; app.setActivationPolicy(.accessory); app.run()

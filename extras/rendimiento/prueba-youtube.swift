// prueba-youtube: abre un video de YouTube con WebKit (motor de Safari), lo reproduce en 480p, sube a 1080p
// y reporta cada 2 s: calidad, codecs, resolucion, cuadros, perdidos y errores del reproductor.
// Uso: prueba-youtube [id_video] [segundos]
import Cocoa
import WebKit
setvbuf(stdout, nil, _IONBF, 0)
let a = CommandLine.arguments
let vid = a.count > 1 ? a[1] : "aqz-KE-bpKQ"
let seg = Double(a.count > 2 ? a[2] : "40") ?? 40
final class D: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var w: NSWindow!; var web: WKWebView!
    func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) { print(m.body) }
    func applicationDidFinishLaunching(_ n: Notification) {
        let c = WKWebViewConfiguration(); c.mediaTypesRequiringUserActionForPlayback = []
        if CommandLine.arguments.contains("--sin-vp9") {
            // Preferencia interna de WebKit (la misma que el Feature Flag "VP9 decoder" de Safari)
            typealias F = @convention(c) (UnsafeMutableRawPointer, Bool) -> Void
            let h = dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_NOW)
            let set = unsafeBitCast(dlsym(h, "WKPreferencesSetVP9DecoderEnabled"), to: F.self)
            set(Unmanaged.passUnretained(c.preferences).toOpaque(), false)
            print("VP9 apagado en esta ventana")
        }
        c.userContentController.add(self, name: "r")
        let js = """
        const r=m=>webkit.messageHandlers.r.postMessage(m); let t0=Date.now(), subio=false;
        r('isTypeSupported vp9: '+MediaSource.isTypeSupported('video/webm; codecs="vp9"')+'  vp09-mp4: '+MediaSource.isTypeSupported('video/mp4; codecs="vp09.00.51.08"')+'  h264: '+MediaSource.isTypeSupported('video/mp4; codecs="avc1.640028"'));
        setInterval(()=>{ try{
          const p=document.getElementById('movie_player'), v=document.querySelector('video');
          if(!p||!v||!p.getStatsForNerds) return;
          const s=p.getStatsForNerds(), q=v.getVideoPlaybackQuality(), e=document.querySelector('.ytp-error');
          const seg=((Date.now()-t0)/1000)|0;
          if(seg>8 && !subio){ p.setPlaybackQualityRange('hd1080','hd1080'); subio=true; r('>>> subiendo a 1080p'); }
          else if(seg<=8 && p.getPlaybackQuality()!=='large'){ p.setPlaybackQualityRange('large','large'); }
          r(seg+'s calidad='+p.getPlaybackQuality()+' '+v.videoWidth+'x'+v.videoHeight+' codecs='+(s.codecs||'?')+' cuadros='+q.totalVideoFrames+' perdidos='+q.droppedVideoFrames+(v.paused?' PAUSADO':'')+(e&&e.offsetParent?' ERROR: '+e.innerText.replace(/\\n/g,' | '):''));
        }catch(x){ r('js '+x); } }, 2000);
        """
        c.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 760), configuration: c)
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        w = NSWindow(contentRect: web.frame, styleMask: [.titled], backing: .buffered, defer: false)
        w.contentView = web; w.setFrameOrigin(NSPoint(x: 100, y: 100)); w.orderFrontRegardless()
        web.load(URLRequest(url: URL(string: "https://www.youtube.com/watch?v=\(vid)&autoplay=1&mute=1")!))
        DispatchQueue.main.asyncAfter(deadline: .now() + seg) { NSApp.terminate(nil) }
    }
}
let app = NSApplication.shared; let d = D(); app.delegate = d; app.setActivationPolicy(.accessory); app.run()

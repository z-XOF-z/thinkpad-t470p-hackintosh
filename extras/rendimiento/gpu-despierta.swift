// GPUDespierta: mantiene la GPU Intel HD 630 a su frecuencia maxima (~1.1 GHz) con pulsos cortos de trabajo.
// El driver de Apple (RPS) baja la GPU a 350 MHz en cuanto se queda unos ms sin trabajo, y el escritorio se siente lento.
// Pulsos de ~1-2 ms (WindowServer espera como maximo eso para dibujar) seguidos de una pausa: la GPU se queda arriba.
// Uso: GPUDespierta [ms_trabajo] [ms_pausa] [--medir]
import Metal
import Foundation
setvbuf(stdout, nil, _IONBF, 0)
let a = CommandLine.arguments
let msTrabajo = Double(a.count > 1 ? a[1] : "1.5") ?? 1.5
let msPausa = Double(a.count > 2 ? a[2] : "2") ?? 2
let medir = a.contains("--medir")
let src = """
#include <metal_stdlib>
using namespace metal;
kernel void pulso(device float *d [[buffer(0)]], constant uint &vueltas [[buffer(1)]], uint i [[thread_position_in_grid]]) {
    float a = d[i], b = a + 1, c = a + 2, e = a + 3;
    for (uint n = 0; n < vueltas; n++) {
        a = fma(a, 0.9999f, 0.0001f); b = fma(b, 0.9999f, 0.0001f); c = fma(c, 0.9999f, 0.0001f); e = fma(e, 0.9999f, 0.0001f);
    }
    d[i] = a + b + c + e;
}
"""
let dev = MTLCreateSystemDefaultDevice()!
let pso = try! dev.makeComputePipelineState(function: try! dev.makeLibrary(source: src, options: nil).makeFunction(name: "pulso")!)
let n = 1 << 16
let buf = dev.makeBuffer(length: n * 4, options: .storageModePrivate)!
let q = dev.makeCommandQueue()!
var vueltas: UInt32 = 64
func pulso() -> Double {
    let cb = q.makeCommandBuffer()!; let e = cb.makeComputeCommandEncoder()!
    e.setComputePipelineState(pso); e.setBuffer(buf, offset: 0, index: 0)
    e.setBytes(&vueltas, length: 4, index: 1)
    e.dispatchThreads(MTLSize(width: n, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: pso.maxTotalThreadsPerThreadgroup, height: 1, depth: 1))
    e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
    return cb.gpuEndTime - cb.gpuStartTime
}
// Calibrar: que cada pulso dure msTrabajo a frecuencia maxima
for _ in 0..<30 { _ = pulso() }
for _ in 0..<8 { let t = pulso() * 1000; vueltas = max(8, UInt32(Double(vueltas) * msTrabajo / max(t, 0.05))) }
var mhz: [Double] = []
var ultimo = Date()
while true {
    let t = pulso()
    if medir {
        mhz.append(Double(n) * Double(vueltas) * 4 / t / 192 / 1e6)
        if Date().timeIntervalSince(ultimo) >= 2 {
            let s = mhz.sorted(); print(String(format: "pulso %.1f ms / pausa %.1f ms -> GPU mediana %.0f MHz (min %.0f)", t * 1000, msPausa, s[s.count / 2], s[s.count / 10]))
            mhz.removeAll(); ultimo = Date()
        }
    }
    usleep(useconds_t(msPausa * 1000))
}

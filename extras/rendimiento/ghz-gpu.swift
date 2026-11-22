// ghz-gpu: mide la frecuencia REAL de la GPU Intel HD 630 contando operaciones FMA por segundo.
// La HD 630 (GT2) tiene 24 EU x 2 FPU SIMD4 = 192 FMA por ciclo de reloj. FMA/s / 192 = MHz (minimo real).
import Metal
import Foundation
let fuente = """
#include <metal_stdlib>
using namespace metal;
kernel void fma8(device float *d [[buffer(0)]], uint i [[thread_position_in_grid]]) {
    float a = d[i], b = a + 1, c = a + 2, e = a + 3, f = a + 4, g = a + 5, h = a + 6, k = a + 7;
    for (int n = 0; n < 2048; n++) {
        a = fma(a, 0.9999f, 0.0001f); b = fma(b, 0.9999f, 0.0001f); c = fma(c, 0.9999f, 0.0001f); e = fma(e, 0.9999f, 0.0001f);
        f = fma(f, 0.9999f, 0.0001f); g = fma(g, 0.9999f, 0.0001f); h = fma(h, 0.9999f, 0.0001f); k = fma(k, 0.9999f, 0.0001f);
    }
    d[i] = a + b + c + e + f + g + h + k;
}
"""
let dev = MTLCreateSystemDefaultDevice()!
let pso = try! dev.makeComputePipelineState(function: try! dev.makeLibrary(source: fuente, options: nil).makeFunction(name: "fma8")!)
let n = 1 << 20
let buf = dev.makeBuffer(length: n * 4, options: .storageModeShared)!
let cola = dev.makeCommandQueue()!
func lote() -> Double {
    let cb = cola.makeCommandBuffer()!
    let e = cb.makeComputeCommandEncoder()!
    e.setComputePipelineState(pso); e.setBuffer(buf, offset: 0, index: 0)
    e.dispatchThreads(MTLSize(width: n, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: pso.maxTotalThreadsPerThreadgroup, height: 1, depth: 1))
    e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
    return cb.gpuEndTime - cb.gpuStartTime
}
for _ in 0..<5 { _ = lote() }                 // calentar: que la GPU suba de frecuencia
var mejor = 0.0
for _ in 0..<15 { let t = lote(); mejor = max(mejor, Double(n) * 2048 * 8 / t) }
print(String(format: "GPU: %.1f G FMA/s  ->  ~%.0f MHz reales (la HD 630 va de 350 a 1100 MHz)", mejor / 1e9, mejor / 192 / 1e6))

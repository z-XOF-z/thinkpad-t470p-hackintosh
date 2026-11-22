// rampa-gpu: despues de 3 s sin trabajo, manda lotes cortos seguidos y mide los MHz de cada uno: cuanto tarda en subir.
import Metal
import Foundation
let src = """
#include <metal_stdlib>
using namespace metal;
kernel void fma8(device float *d [[buffer(0)]], uint i [[thread_position_in_grid]]) {
    float a = d[i], b = a + 1, c = a + 2, e = a + 3, f = a + 4, g = a + 5, h = a + 6, k = a + 7;
    for (int n = 0; n < 256; n++) {
        a = fma(a, 0.9999f, 0.0001f); b = fma(b, 0.9999f, 0.0001f); c = fma(c, 0.9999f, 0.0001f); e = fma(e, 0.9999f, 0.0001f);
        f = fma(f, 0.9999f, 0.0001f); g = fma(g, 0.9999f, 0.0001f); h = fma(h, 0.9999f, 0.0001f); k = fma(k, 0.9999f, 0.0001f);
    }
    d[i] = a + b + c + e + f + g + h + k;
}
"""
let dev = MTLCreateSystemDefaultDevice()!
let pso = try! dev.makeComputePipelineState(function: try! dev.makeLibrary(source: src, options: nil).makeFunction(name: "fma8")!)
let n = 1 << 18
let buf = dev.makeBuffer(length: n * 4, options: .storageModeShared)!
let q = dev.makeCommandQueue()!
func lote() -> (Double, Double) {
    let cb = q.makeCommandBuffer()!; let e = cb.makeComputeCommandEncoder()!
    e.setComputePipelineState(pso); e.setBuffer(buf, offset: 0, index: 0)
    e.dispatchThreads(MTLSize(width: n, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: pso.maxTotalThreadsPerThreadgroup, height: 1, depth: 1))
    e.endEncoding(); cb.commit(); cb.waitUntilCompleted()
    let t = cb.gpuEndTime - cb.gpuStartTime
    return (Double(n) * 256 * 8 / t / 192 / 1e6, t * 1000)
}
_ = lote()
Thread.sleep(forTimeInterval: 3)
var total = 0.0
var linea = ""
for i in 0..<40 { let (mhz, ms) = lote(); total += ms; if i < 12 || i % 5 == 0 { linea += String(format: "%.0fms:%.0f ", total, mhz) } }
print("tiempo acumulado:MHz ->", linea)

// estres-gpu: pone la GPU a trabajar al 100 % con calculo en Metal durante N segundos (por defecto 12).
import Metal
import Foundation
let segundos = Double(CommandLine.arguments.dropFirst().first ?? "12") ?? 12
let fuente = """
#include <metal_stdlib>
using namespace metal;
kernel void quema(device float *d [[buffer(0)]], uint i [[thread_position_in_grid]]) {
    float x = d[i];
    for (int k = 0; k < 4000; k++) { x = fma(x, 1.000001f, 0.5f); x = sin(x) * 0.999f + cos(x); }
    d[i] = x;
}
"""
let dev = MTLCreateSystemDefaultDevice()!
let lib = try! dev.makeLibrary(source: fuente, options: nil)
let pso = try! dev.makeComputePipelineState(function: lib.makeFunction(name: "quema")!)
let n = 1 << 18
let buf = dev.makeBuffer(length: n * 4, options: .storageModePrivate)!
let cola = dev.makeCommandQueue()!
let fin = Date().addingTimeInterval(segundos)
var lotes = 0
while Date() < fin {
    let cb = cola.makeCommandBuffer()!
    let e = cb.makeComputeCommandEncoder()!
    e.setComputePipelineState(pso); e.setBuffer(buf, offset: 0, index: 0)
    e.dispatchThreads(MTLSize(width: n, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: pso.maxTotalThreadsPerThreadgroup, height: 1, depth: 1))
    e.endEncoding(); cb.commit(); cb.waitUntilCompleted(); lotes += 1
}
print("\(dev.name): \(lotes) lotes en \(Int(segundos)) s")

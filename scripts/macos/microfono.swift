// Pone el "Built-in Microphone" como entrada predeterminada y mide el nivel 4 segundos.
// Uso: swift ~/hackintosh-mac/microfono.swift          (habla o aplaude mientras corre)
//      swift ~/hackintosh-mac/microfono.swift lista    (solo lista las entradas)
import AVFoundation
import CoreAudio
import Foundation

func dispositivos() -> [AudioDeviceID] {
    var dir = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var tam: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &dir, 0, nil, &tam)
    var ids = [AudioDeviceID](repeating: 0, count: Int(tam) / MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &dir, 0, nil, &tam, &ids)
    return ids
}
func nombre(_ id: AudioDeviceID) -> String {
    var dir = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var n: Unmanaged<CFString>?
    var tam = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    AudioObjectGetPropertyData(id, &dir, 0, nil, &tam, &n)
    return (n?.takeRetainedValue() as String?) ?? "?"
}
func esEntrada(_ id: AudioDeviceID) -> Bool {
    var dir = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    var tam: UInt32 = 0
    AudioObjectGetPropertyDataSize(id, &dir, 0, nil, &tam)
    return tam > 0
}
let entradas = dispositivos().filter(esEntrada)
for e in entradas { print("entrada: \(nombre(e))") }
if CommandLine.arguments.count > 1 { exit(0) }

guard let mic = entradas.first(where: { nombre($0).contains("Microphone") }) else { print("no encontré el micrófono interno"); exit(1) }
var dir = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var v = mic
let st = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &dir, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &v)
print("entrada predeterminada -> \(nombre(mic)) (código \(st))")

let motor = AVAudioEngine()
let entrada = motor.inputNode
let formato = entrada.outputFormat(forBus: 0)
var pico: Float = 0, suma: Double = 0, n = 0
entrada.installTap(onBus: 0, bufferSize: 4096, format: formato) { buf, _ in
    guard let d = buf.floatChannelData else { return }
    for i in 0..<Int(buf.frameLength) { let x = abs(d[0][i]); pico = max(pico, x); suma += Double(x * x); n += 1 }
}
do { try motor.start() } catch { print("no pude abrir el micrófono: \(error)"); exit(1) }
print("grabando 4 segundos... habla o aplaude")
Thread.sleep(forTimeInterval: 4)
motor.stop()
let rms = n > 0 ? sqrt(suma / Double(n)) : 0
let db = 20 * log10(max(Double(pico), 1e-9))
print(String(format: "muestras: %d, pico: %.4f (%.1f dBFS), RMS: %.5f", n, pico, db, rms))
print(n == 0 ? "RESULTADO: no llegó audio (¿permiso de micrófono para la Terminal?)" :
      (pico < 0.001 ? "RESULTADO: llega audio pero en silencio total (el micrófono no capta)" : "RESULTADO: el micrófono sí capta sonido"))

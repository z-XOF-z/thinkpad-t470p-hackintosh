// Lista las salidas de audio y, si se le pasa un nombre, la pone como predeterminada.
// Uso: swift salida-audio.swift            -> lista
//      swift salida-audio.swift Speaker    -> elige la salida que contenga "Speaker"
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
func esSalida(_ id: AudioDeviceID) -> Bool {
    var dir = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    var tam: UInt32 = 0
    AudioObjectGetPropertyDataSize(id, &dir, 0, nil, &tam)
    return tam > 0
}
func poner(_ sel: AudioObjectPropertySelector, _ id: AudioDeviceID) -> OSStatus {
    var dir = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var v = id
    return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &dir, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &v)
}
let salidas = dispositivos().filter(esSalida)
if CommandLine.arguments.count < 2 {
    for s in salidas { print("salida: \(nombre(s))") }
} else if let s = salidas.first(where: { nombre($0).contains(CommandLine.arguments[1]) }) {
    let a = poner(kAudioHardwarePropertyDefaultOutputDevice, s)
    let b = poner(kAudioHardwarePropertyDefaultSystemOutputDevice, s)
    print("salida predeterminada -> \(nombre(s)) (códigos \(a), \(b))")
} else { print("no encontré una salida con \"\(CommandLine.arguments[1])\"") }

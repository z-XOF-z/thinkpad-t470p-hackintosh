// Registra, activa y selecciona "Latinoamericano (Windows)"; luego prueba unas teclas con UCKeyTranslate.
// Uso: swift ~/hackintosh-mac/teclado/activar-latam.swift
import Carbon
import Foundation

let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Keyboard Layouts/Latinoamericano (Windows).keylayout")
print("registrar:", TISRegisterInputSource(url as CFURL))

func buscar() -> TISInputSource? {
    let props = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
    guard let lista = TISCreateInputSourceList(props, true)?.takeRetainedValue() as? [TISInputSource] else { return nil }
    return lista.first {
        let p = TISGetInputSourceProperty($0, kTISPropertyLocalizedName)
        return p != nil && (Unmanaged<CFString>.fromOpaque(p!).takeUnretainedValue() as String) == "Latinoamericano (Windows)"
    }
}
var fuente: TISInputSource? = nil
for _ in 0..<10 { fuente = buscar(); if fuente != nil { break }; Thread.sleep(forTimeInterval: 0.5) }
guard let src = fuente else { print("macOS todavía no ve la distribución (cierra sesión y vuelve a entrar)"); exit(1) }
print("activar:", TISEnableInputSource(src), " seleccionar:", TISSelectInputSource(src))

guard let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { print("sin datos"); exit(1) }
let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
func tecla(_ code: UInt16, _ mods: UInt32, _ estado: inout UInt32) -> String {
    data.withUnsafeBytes { raw -> String in
        let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!
        var chars = [UniChar](repeating: 0, count: 4); var n = 0
        UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), (mods >> 8) & 0xFF, UInt32(LMGetKbdType()),
                       0, &estado, 4, &n, &chars)
        return String(utf16CodeUnits: chars, count: n)
    }
}
let pruebas: [(String, UInt16, UInt32)] = [
    ("AltGr+Q", 12, UInt32(optionKey)), ("Ñ", 41, 0), ("Shift+2", 19, UInt32(shiftKey)), ("tecla de ?", 27, UInt32(shiftKey)),
    ("AltGr+? (\\)", 27, UInt32(optionKey)), ("{", 39, 0), ("[", 39, UInt32(shiftKey)), ("}", 42, 0), ("]", 42, UInt32(shiftKey)),
    ("+", 30, 0), ("AltGr++ (~)", 30, UInt32(optionKey)), ("<", 10, 0), ("|", 50, 0), ("-", 44, 0), ("¿", 24, 0)]
for (nombre, code, mods) in pruebas { var e: UInt32 = 0; print("\(nombre) -> \(tecla(code, mods, &e))") }
var e: UInt32 = 0
let muerta = tecla(33, 0, &e); let a = tecla(0, 0, &e)
print("´ + a -> \(muerta)\(a)")
e = 0; _ = tecla(33, UInt32(shiftKey), &e); print("¨ + u -> \(tecla(32, 0, &e))")

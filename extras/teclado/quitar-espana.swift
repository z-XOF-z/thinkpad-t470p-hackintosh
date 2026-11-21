// Desactiva "Spanish - ISO" para que macOS no regrese a ella; deja "Latinoamericano (Windows)" seleccionada.
import Carbon
let props = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
let lista = (TISCreateInputSourceList(props, false)?.takeRetainedValue() as? [TISInputSource]) ?? []
func nombre(_ s: TISInputSource) -> String { Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(s, kTISPropertyLocalizedName)!).takeUnretainedValue() as String }
if let la = lista.first(where: { nombre($0) == "Latinoamericano (Windows)" }) {
    print("seleccionar Latinoamericano:", TISSelectInputSource(la))
    for s in lista where (Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(s, kTISPropertyInputSourceID)!).takeUnretainedValue() as String) == "com.apple.keylayout.Spanish-ISO" { print("desactivar Spanish - ISO:", TISDisableInputSource(s)) }
} else { print("no encontré Latinoamericano (Windows) activa") }

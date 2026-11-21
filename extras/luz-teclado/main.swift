// LuzTeclado: hace que la luz del teclado de la ThinkPad "respire" (3 niveles: 0, 1, 2).
// La luz se controla con la propiedad "BacklightLevel" del driver ThinkVPC (YogaSMC) -> metodo MLCS de la BIOS.
//
// IMPORTANTE (aprendido el 2026-11-21): cada cambio por software hace que la BIOS mande el mismo aviso (0x1012)
// que Fn + Espacio, y YogaSMC no marca la diferencia. Por eso esto NO se conecta a Fn + Espacio (se hacia un
// bucle que arrancaba decenas de copias). Fn + Espacio queda normal y la respiracion se elige desde el menu.
//
// Uso:  LuzTeclado rapido | medio | lento   -> respira a esa velocidad (detiene cualquier otra antes)
//       LuzTeclado parar                    -> detiene la respiracion y apaga la luz
import Foundation
import IOKit

let carpeta = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LuzTeclado")
let archivoPid = carpeta.appendingPathComponent("respirar.pid")
let archivoModo = carpeta.appendingPathComponent("modo")
try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)

let servicio = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("ThinkVPC"))
guard servicio != 0 else { FileHandle.standardError.write("No encontre ThinkVPC (YogaSMC)\n".data(using: .utf8)!); exit(1) }
func poner(_ n: Int) { IORegistryEntrySetCFProperty(servicio, "BacklightLevel" as CFString, n as CFNumber) }

// Mata TODAS las copias de "LuzTeclado <modo>" que no sean esta (candado: solo una respiracion a la vez)
func pararOtras() {
    let ps = Process()
    let tubo = Pipe()
    ps.executableURL = URL(fileURLWithPath: "/bin/ps")
    ps.arguments = ["-axo", "pid=,command="]
    ps.standardOutput = tubo
    try? ps.run()
    // leer ANTES de esperar: si no, ps se traba cuando la lista no cabe en el tubo
    let datos = tubo.fileHandleForReading.readDataToEndOfFile()
    ps.waitUntilExit()
    let salida = String(data: datos, encoding: .utf8) ?? ""
    let yo = getpid()
    for linea in salida.split(separator: "\n") {
        let partes = linea.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
        // solo procesos cuyo PROGRAMA es LuzTeclado (no shells que lo mencionen), y nunca un "parar"
        let comando = partes.count == 2 ? partes[1].split(separator: " ") : []
        guard partes.count == 2, let pid = pid_t(partes[0]), pid != yo, let programa = comando.first,
              programa.hasSuffix("/LuzTeclado") || programa == "LuzTeclado",
              comando.dropFirst().first != "parar" else { continue }
        kill(pid, SIGKILL)
    }
    try? FileManager.default.removeItem(at: archivoPid)
}

let modo = CommandLine.arguments.dropFirst().first ?? ""
// pausa entre escalones (ms) y forma del "respiro"
let velocidades: [String: (UInt32, [Int])] = [
    "rapido": (160, [0, 1, 2, 1]),
    "medio":  (380, [0, 1, 2, 2, 1, 0]),
    "lento":  (750, [0, 0, 1, 2, 2, 1, 0, 0]),
]

if let (pausa, pasos) = velocidades[modo] {
    pararOtras()
    try? "\(getpid())".write(to: archivoPid, atomically: true, encoding: .utf8)
    try? modo.write(to: archivoModo, atomically: true, encoding: .utf8)
    signal(SIGTERM) { _ in exit(0) }
    while true {
        for n in pasos { poner(n); usleep(pausa * 1000) }
    }
} else if modo == "parar" {
    pararOtras()
    try? "".write(to: archivoModo, atomically: true, encoding: .utf8)
    usleep(150_000)
    poner(0)
} else {
    print("Uso: LuzTeclado rapido | medio | lento | parar")
}

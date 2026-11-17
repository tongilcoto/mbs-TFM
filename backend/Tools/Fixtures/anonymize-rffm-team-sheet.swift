// Cambia los datos personales de una ficha de equipo de la RFFM (`fichaequipo/<código>`) para guardarla como
// grabación de las pruebas del adaptador (plan R6, decisión 2 de R6.14).
//
// La página lleva los nombres y los códigos federativos de los jugadores —menores, en el fútbol base—, de los
// técnicos, los delegados y los auxiliares, y los datos de contacto del club. Todo eso se cambia **en la página
// entera** (el bloque `__NEXT_DATA__` y el HTML que la RFFM pinta con él), y la forma se queda exacta: lo que se
// prueba es cómo se lee la página, no quién sale en ella.
//
// - Los jugadores, por nombres inventados con la forma medida («APELLIDOS, NOMBRE», en mayúsculas), con tildes,
//   eñe, guion, partícula, nombre compuesto y algún apellido solo; y sus códigos, por otros del mismo largo.
// - Los técnicos, delegados y auxiliares, igual, con otros nombres.
// - El contacto (titular, domicilio, correo, teléfonos, fax) y la clave de acceso, vacíos.
//
// Al final comprueba que no queda ninguno de los datos de antes, en ninguna de sus formas (tal cual, escapado en
// JSON o en HTML), y dice cuántos ha cambiado, sin enseñarlos.
//
// Uso, desde `backend/` (la página de verdad se baja fuera del repositorio, y no se guarda):
//
//     curl -s -A "Mozilla/5.0" https://www.rffm.es/fichaequipo/821 -o /ruta/fuera/ficha.html
//     swift Tools/Fixtures/anonymize-rffm-team-sheet.swift /ruta/fuera/ficha.html \
//         Tests/FederationTests/Fixtures/RFFM-fichaequipo.html

import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("Uso: anonymize-rffm-team-sheet.swift <página de verdad> <grabación>\n".data(using: .utf8)!)
    exit(2)
}
var page = try String(contentsOfFile: arguments[1], encoding: .utf8)

// ── Leer lo que hay que cambiar, del bloque de datos ──

func nextData(_ html: String) throws -> [String: Any] {
    guard let tag = html.range(of: #"id="__NEXT_DATA__""#),
          let open = html[tag.upperBound...].firstIndex(of: ">"),
          let close = html[open...].range(of: "</script>")
    else { throw NSError(domain: "ficha", code: 1, userInfo: [NSLocalizedDescriptionKey: "sin __NEXT_DATA__"]) }
    let json = html[html.index(after: open)..<close.lowerBound]
    return try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
}

let data = try nextData(page)
guard let props = data["props"] as? [String: Any], let pageProps = props["pageProps"] as? [String: Any],
      let team = pageProps["team"] as? [String: Any]
else {
    FileHandle.standardError.write("La página no trae equipo: ¿es un código que no existe?\n".data(using: .utf8)!)
    exit(1)
}

func people(_ list: String, code: String) -> [(name: String, code: String)] {
    ((team[list] as? [[String: Any]]) ?? []).map { (($0["nombre"] as? String) ?? "", ($0[code] as? String) ?? "") }
}
let players = people("jugadores_equipo", code: "cod_jugador")
let staff = people("tecnicos_equipo", code: "cod_tecnico") + people("delegados_equipo", code: "cod_delegado")
    + people("auxiliares_equipo", code: "cod_auxiliar")

// ── Los inventados ──

// Con la forma medida en R6.1 (46 jugadores de dos equipos): «APELLIDOS, NOMBRE», en mayúsculas; con tilde o eñe,
// nombre compuesto, partícula, guion y algún apellido solo.
let fakePlayers = [
    "GARCÍA LÓPEZ, JUAN CARLOS", "MUÑOZ IBÁÑEZ, ÁLVARO", "DE LA FUENTE MARTÍN, PABLO", "PÉREZ-REVERTE GIL, HUGO",
    "SÁNCHEZ RUIZ, MARCOS", "NÚÑEZ ORTEGA, IÑIGO", "FERNÁNDEZ DEL RÍO, JOSÉ MARÍA", "GÓMEZ, DANIEL",
    "MARTÍNEZ SOTO, ADRIÁN", "RODRÍGUEZ PEÑA, LUCAS", "LÓPEZ CASTRO, MARIO", "DÍAZ HERRERO, RAÚL",
    "MORENO VEGA, SERGIO", "ÁLVAREZ CANO, JESÚS", "ROMERO PASCUAL, ÓSCAR", "NAVARRO MOLINA, IVÁN",
    "TORRES CALVO, RUBÉN", "DOMÍNGUEZ LUNA, ANDRÉS", "GIL, NICOLÁS", "SERRANO BRAVO, GONZALO",
    "BLANCO ARIAS, VÍCTOR", "SUÁREZ MÉNDEZ, JOAQUÍN", "CASTILLO ORTIZ, TOMÁS", "RAMOS DE LOS SANTOS, ÁNGEL",
    "PRIETO LEÓN, SAMUEL", "MÉNDEZ ROJAS, ALEJANDRO", "CRESPO VIDAL, MANUEL", "HERRERA PARDO, DIEGO",
]
let fakeStaff = ["ENTRENADOR INVENTADO, PRIMERO", "ENTRENADOR INVENTADO, SEGUNDO", "DELEGADO INVENTADO, PRIMERO",
                 "DELEGADO INVENTADO, SEGUNDO", "AUXILIAR INVENTADO, PRIMERO", "AUXILIAR INVENTADO, SEGUNDO"]
guard players.count <= fakePlayers.count, staff.count <= fakeStaff.count else {
    FileHandle.standardError.write("Más personas que nombres inventados: añade más a la lista.\n".data(using: .utf8)!)
    exit(1)
}

// Un código del mismo largo, que empieza por 9: no es el de nadie que se haya visto.
func fakeCode(_ code: String, _ index: Int) -> String {
    let tail = String(index + 1)
    let width = max(code.count, tail.count + 1)
    return "9" + String(repeating: "0", count: width - 1 - tail.count) + tail
}

var replacements: [(String, String)] = []
for (index, player) in players.enumerated() {
    replacements.append((player.name, fakePlayers[index]))
    if !player.code.isEmpty { replacements.append((player.code, fakeCode(player.code, index))) }
}
for (index, person) in staff.enumerated() {
    replacements.append((person.name, fakeStaff[index]))
    if !person.code.isEmpty { replacements.append((person.code, fakeCode(person.code, 100 + index))) }
}
// El contacto y la clave: vacíos. Solo los que son únicos de este club; la provincia o la localidad, no.
for key in ["titular_correspondencia", "domicilio_correspondencia", "email_correspondencia", "telefonos", "fax",
            "clave_acceso"] {
    if let value = team[key] as? String, !value.trimmingCharacters(in: .whitespaces).isEmpty {
        replacements.append((value, ""))
    }
}

// ── Cambiar en la página entera, en cada forma en que puede salir ──

func htmlEscaped(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#x27;")
}
func jsonEscaped(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}
// Cada forma del dato de antes, con la misma forma del inventado: tal cual, escapado en HTML y en JSON.
func forms(_ original: String, _ fake: String) -> [(String, String)] {
    var seen = Set<String>()
    return [(original, fake), (htmlEscaped(original), htmlEscaped(fake)), (jsonEscaped(original), jsonEscaped(fake))]
        .filter { seen.insert($0.0).inserted }
}

// Los más largos primero: así un código no se cambia dentro de otro más largo antes de tiempo.
var changed = 0
for (original, fake) in replacements.sorted(by: { $0.0.count > $1.0.count }) where !original.isEmpty {
    for (form, fakeForm) in forms(original, fake) {
        let count = page.components(separatedBy: form).count - 1
        if count > 0 {
            page = page.replacingOccurrences(of: form, with: fakeForm)
            changed += count
        }
    }
}

// ── Comprobar que no queda nada de antes ──

var left = 0
for (original, fake) in replacements where !original.isEmpty {
    for (form, _) in forms(original, fake) where page.contains(form) { left += 1 }
}
guard left == 0 else {
    FileHandle.standardError.write("Quedan \(left) datos de antes en la página: no se guarda.\n".data(using: .utf8)!)
    exit(1)
}
// Y que la página se sigue leyendo.
let again = try nextData(page)
let againTeam = ((again["props"] as? [String: Any])?["pageProps"] as? [String: Any])?["team"] as? [String: Any]
let againPlayers = (againTeam?["jugadores_equipo"] as? [[String: Any]]) ?? []
guard againPlayers.count == players.count else {
    FileHandle.standardError.write("La página cambiada no trae los mismos jugadores.\n".data(using: .utf8)!)
    exit(1)
}

try page.write(toFile: arguments[2], atomically: true, encoding: .utf8)
print("Guardada: \(players.count) jugadores y \(staff.count) del cuerpo técnico, con nombre y código inventados;",
      "el contacto, vacío. \(changed) cambios en la página.")

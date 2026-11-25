// Cambia los datos personales de un acta de la RFFM (`acta-partido/<codacta>`) para guardarla como grabación de
// las pruebas del adaptador (plan R7, paso `R7.11`), como `anonymize-rffm-team-sheet.swift` con la ficha.
//
// El acta lleva los nombres y los códigos federativos de los jugadores de los dos equipos —menores, en el fútbol
// base—, y de los entrenadores, los delegados, los demás técnicos y los árbitros. Todo eso se cambia **en la página
// entera** (el bloque `__NEXT_DATA__` y el HTML que la RFFM pinta con él), y la forma se queda exacta: lo que se
// prueba es cómo se lee el acta, no quién sale en ella. Los equipos, su código y el campo se quedan: son públicos y
// son lo que se casa con el calendario.
//
// - Los jugadores, por nombres inventados con la forma medida («APELLIDOS, NOMBRE», en mayúsculas), y sus códigos,
//   por otros del mismo largo. El mismo jugador, el mismo inventado en la lista, en sus goles, sus tarjetas y sus
//   cambios: así el acta sigue cuadrando.
// - Los técnicos, delegados y árbitros, igual, con otros nombres. Lo que no es un nombre («No presenta»), se queda.
// - Las fotos, vacías.
//
// Al final comprueba que no queda ninguno de los datos de antes, en ninguna de sus formas (tal cual, escapado en
// JSON o en HTML), y dice cuántos ha cambiado, sin enseñarlos.
//
// Uso, desde `backend/` (la página de verdad se baja fuera del repositorio, y no se guarda):
//
//     curl -s -A "Mozilla/5.0" https://www.rffm.es/acta-partido/5589189 -o /ruta/fuera/acta.html
//     swift Tools/Fixtures/anonymize-rffm-match-report.swift /ruta/fuera/acta.html \
//         Tests/FederationTests/Fixtures/RFFM-acta-penalti-roja-segunda-amarilla.html

import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write("Uso: anonymize-rffm-match-report.swift <página de verdad> <grabación>\n".data(using: .utf8)!)
    exit(2)
}
var page = try String(contentsOfFile: arguments[1], encoding: .utf8)

// ── Leer lo que hay que cambiar, del bloque de datos ──

func nextData(_ html: String) throws -> [String: Any] {
    guard let tag = html.range(of: #"id="__NEXT_DATA__""#),
          let open = html[tag.upperBound...].firstIndex(of: ">"),
          let close = html[open...].range(of: "</script>")
    else { throw NSError(domain: "acta", code: 1, userInfo: [NSLocalizedDescriptionKey: "sin __NEXT_DATA__"]) }
    let json = html[html.index(after: open)..<close.lowerBound]
    return try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
}

func game(_ html: String) throws -> [String: Any]? {
    ((try nextData(html)["props"] as? [String: Any])?["pageProps"] as? [String: Any])?["game"] as? [String: Any]
}

guard let report = try game(page) else {
    FileHandle.standardError.write("La página no trae acta: ¿es un código que no existe?\n".data(using: .utf8)!)
    exit(1)
}

func list(_ key: String) -> [[String: Any]] { (report[key] as? [[String: Any]]) ?? [] }
func text(_ value: Any?) -> String { ((value as? String) ?? "").trimmingCharacters(in: .whitespaces) }

// Los jugadores, por su código: de las listas de los dos equipos y, por si alguno no estuviera en ellas, de los
// goles, las tarjetas y los cambios.
var players: [(name: String, code: String)] = []
var seenPlayers = Set<String>()
func addPlayer(_ name: String, _ code: String) {
    guard !name.isEmpty || !code.isEmpty, seenPlayers.insert(code + "|" + name).inserted else { return }
    players.append((name, code))
}
for side in ["local", "visitante"] {
    for player in list("jugadores_equipo_\(side)") { addPlayer(text(player["nombre_jugador"]), text(player["codjugador"])) }
}
for side in ["local", "visitante"] {
    for key in ["goles_equipo_\(side)", "tarjetas_equipo_\(side)"] {
        for entry in list(key) { addPlayer(text(entry["nombre_jugador"]), text(entry["codjugador"])) }
    }
    for change in list("sustituciones_equipo_\(side)") {
        addPlayer(text(change["nombre_jugador_entra"]), text(change["codjugador_entra"]))
        addPlayer(text(change["nombre_jugador_sale"]), text(change["codjugador_sale"]))
    }
}
for entry in list("goles_penalti") + list("otras_tarjetas") {
    addPlayer(text(entry["nombre_jugador"]), text(entry["codjugador"]))
}

// El cuerpo técnico, los delegados y los árbitros. Solo lo que tiene forma de nombre («APELLIDOS, NOMBRE»).
var staff: [(name: String, code: String)] = []
func addStaff(_ name: String, _ code: String) {
    if name.contains(",") || !code.isEmpty { staff.append((name.contains(",") ? name : "", code)) }
}
addStaff(text(report["entrenador_local"]), text(report["cod_entrenador_local"]))
addStaff(text(report["entrenador2_local"]), text(report["cod_entrenador2_local"]))
addStaff(text(report["entrenador_visitante"]), text(report["cod_entrenador_visitante"]))
addStaff(text(report["entrenador2_visitante"]), text(report["cod_entrenador_visitante2"]))
for key in ["delegadocampo", "delegadolocal", "delegado_visitante"] { addStaff(text(report[key]), "") }
for side in ["local", "visitante"] {
    for person in list("otros_tecnicos_\(side)") {
        addStaff(text(person["nombre"]), text(person["cod_tecnico"]))
        addStaff(text(person["nombre_otros_tecnicos"]), "")
    }
}
for referee in list("arbitros_partido") { addStaff(text(referee["nombre_arbitro"]), text(referee["cod_arbitro"])) }

// ── Los inventados ──

let fakePlayers = [
    "GARCÍA LÓPEZ, JUAN CARLOS", "MUÑOZ IBÁÑEZ, ÁLVARO", "DE LA FUENTE MARTÍN, PABLO", "PÉREZ-REVERTE GIL, HUGO",
    "SÁNCHEZ RUIZ, MARCOS", "NÚÑEZ ORTEGA, IÑIGO", "FERNÁNDEZ DEL RÍO, JOSÉ MARÍA", "GÓMEZ, DANIEL",
    "MARTÍNEZ SOTO, ADRIÁN", "RODRÍGUEZ PEÑA, LUCAS", "LÓPEZ CASTRO, MARIO", "DÍAZ HERRERO, RAÚL",
    "MORENO VEGA, SERGIO", "ÁLVAREZ CANO, JESÚS", "ROMERO PASCUAL, ÓSCAR", "NAVARRO MOLINA, IVÁN",
    "TORRES CALVO, RUBÉN", "DOMÍNGUEZ LUNA, ANDRÉS", "GIL, NICOLÁS", "SERRANO BRAVO, GONZALO",
    "BLANCO ARIAS, VÍCTOR", "SUÁREZ MÉNDEZ, JOAQUÍN", "CASTILLO ORTIZ, TOMÁS", "RAMOS DE LOS SANTOS, ÁNGEL",
    "PRIETO LEÓN, SAMUEL", "MÉNDEZ ROJAS, ALEJANDRO", "CRESPO VIDAL, MANUEL", "HERRERA PARDO, DIEGO",
    "IGLESIAS MORA, BRUNO", "CABRERA SOLÍS, ENZO", "VARGAS MARÍN, ÉRIC", "CORTÉS PAREDES, LUIS MIGUEL",
    "FUENTES RIVAS, ÍKER", "SALAS DEL CAMPO, JORGE", "AGUILAR PONCE, MATEO", "BENÍTEZ ROCA, ÚRSULO",
    "GALLEGO SANZ, LEO", "ESTEBAN, ALONSO", "OLMEDO QUIRÓS, FÉLIX", "PASTOR-LLORENTE VERA, TEO",
]
let fakeStaff = [
    "ENTRENADOR INVENTADO, PRIMERO", "ENTRENADOR INVENTADO, SEGUNDO", "ENTRENADOR INVENTADO, TERCERO",
    "ENTRENADOR INVENTADO, CUARTO", "DELEGADO INVENTADO, PRIMERO", "DELEGADO INVENTADO, SEGUNDO",
    "DELEGADO INVENTADO, TERCERO", "TÉCNICO INVENTADO, PRIMERO", "TÉCNICO INVENTADO, SEGUNDO",
    "TÉCNICO INVENTADO, TERCERO", "TÉCNICO INVENTADO, CUARTO", "ÁRBITRO INVENTADO, PRIMERO",
    "ÁRBITRO INVENTADO, SEGUNDO", "ÁRBITRO INVENTADO, TERCERO", "ÁRBITRO INVENTADO, CUARTO",
]
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

// Un mismo nombre o código, un solo inventado, aunque salga en varios sitios.
var replacements: [(String, String)] = []
var assigned = [String: String]()
func replace(_ original: String, with fake: String) {
    guard !original.isEmpty, assigned[original] == nil else { return }
    assigned[original] = fake
    replacements.append((original, fake))
}
for (index, player) in players.enumerated() {
    replace(player.name, with: fakePlayers[index])
    replace(player.code, with: fakeCode(player.code, index))
}
for (index, person) in staff.enumerated() {
    replace(person.name, with: fakeStaff[index])
    replace(person.code, with: fakeCode(person.code, 100 + index))
}
// Las fotos: vacías, estén donde estén.
func photos(_ value: Any) -> [String] {
    if let object = value as? [String: Any] {
        return object.flatMap { key, inner in
            key.hasPrefix("foto") ? [text(inner)].filter { !$0.isEmpty } : photos(inner)
        }
    }
    if let array = value as? [Any] { return array.flatMap(photos) }
    return []
}
for photo in photos(report) { replace(photo, with: "") }

// ── Cambiar en la página entera, en cada forma en que puede salir ──

func htmlEscaped(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#x27;")
}
func jsonEscaped(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
}
func forms(_ original: String, _ fake: String) -> [(String, String)] {
    var seen = Set<String>()
    return [(original, fake), (htmlEscaped(original), htmlEscaped(fake)), (jsonEscaped(original), jsonEscaped(fake))]
        .filter { seen.insert($0.0).inserted }
}

// Los más largos primero: así un código no se cambia dentro de otro más largo antes de tiempo.
var changed = 0
for (original, fake) in replacements.sorted(by: { $0.0.count > $1.0.count }) {
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
for (original, fake) in replacements {
    for (form, _) in forms(original, fake) where page.contains(form) { left += 1 }
}
guard left == 0 else {
    FileHandle.standardError.write("Quedan \(left) datos de antes en la página: no se guarda.\n".data(using: .utf8)!)
    exit(1)
}
// Y que el acta se sigue leyendo igual: los mismos jugadores, goles, tarjetas y cambios.
guard let again = try game(page) else {
    FileHandle.standardError.write("La página cambiada ya no trae el acta.\n".data(using: .utf8)!)
    exit(1)
}
for key in ["jugadores_equipo_local", "jugadores_equipo_visitante", "goles_equipo_local", "goles_equipo_visitante",
            "tarjetas_equipo_local", "tarjetas_equipo_visitante", "sustituciones_equipo_local",
            "sustituciones_equipo_visitante"] {
    guard ((again[key] as? [Any]) ?? []).count == list(key).count else {
        FileHandle.standardError.write("La página cambiada no trae lo mismo en \(key).\n".data(using: .utf8)!)
        exit(1)
    }
}

try page.write(toFile: arguments[2], atomically: true, encoding: .utf8)
print("Guardada: \(players.count) jugadores y \(staff.count) técnicos, delegados y árbitros, con nombre y código",
      "inventados. \(changed) cambios en la página.")

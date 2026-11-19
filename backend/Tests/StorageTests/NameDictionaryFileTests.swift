import Application
import Domain
import Foundation
import Testing

@testable import Storage

/// El diccionario de nombres en su fichero (`D-123`; enmienda de R6.19), **sin Docker**: el del repositorio, que es el
/// que usa el servidor, y ficheros temporales para lo que pasa cuando se cambia o falta.
@Suite("Storage · R6.19 · el diccionario de nombres en un fichero")
struct NameDictionaryFileTests {

    /// `backend/diccionario-nombres.txt`, buscado desde este fichero: no depende de dónde se lancen las pruebas.
    static let repositoryFile = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("diccionario-nombres.txt")

    static func repositoryNames() throws -> CastilianNames {
        try #require(NameDictionaryFile(file: repositoryFile).read(), "no se puede leer \(repositoryFile.path)")
    }

    static func withFile(_ text: String?, _ body: (URL) throws -> Void) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tfm-diccionario-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: file) }
        if let text { try text.write(to: file, atomically: true, encoding: .utf8) }
        try body(file)
    }

    // ── La lista de verdad ──

    /// Lo que antes miraban las pruebas de la lista escrita en el código (R6.17): cada palabra con su marca, en
    /// mayúsculas y sola, y ninguna dos veces. Una línea mala no rompería nada, pero no se usaría: aquí se ve antes.
    @Test("el fichero del repositorio no tiene ninguna línea mala")
    func repositoryFileHasNoProblems() throws {
        let names = try Self.repositoryNames()
        #expect(names.problems.isEmpty, "\(names.problems)")
        #expect(names.words.count >= 297)
    }

    /// Las que existen de las dos maneras, decididas con el desarrollador (R6.17).
    @Test("de las dudosas, entran Díez, Sáez, Martí, Mía y Éric; Saiz, Zoe e Iker, no")
    func doubtfulDecided() throws {
        let names = try Self.repositoryNames()
        for (raw, spelled) in [("JORGE DIEZ", "JORGE DÍEZ"), ("JORGE SAEZ", "JORGE SÁEZ"), ("JORGE MARTI", "JORGE MARTÍ"),
                               ("MIA PEREZ", "MÍA PÉREZ"), ("ERIC GIL", "ÉRIC GIL"), ("JORGE SAIZ", "JORGE SAIZ"),
                               ("ZOE GIL", "ZOE GIL"), ("IKER GIL", "IKER GIL")] {
            #expect(try PlayerName(raw).spelledInCastilian(with: names).value == spelled)
        }
    }

    @Test("pone las tildes de los nombres de siempre", arguments: [
        ("JORGE FERNANDEZ PEREZ", "JORGE FERNÁNDEZ PÉREZ"),
        ("JESUS MUNOZ IBANEZ", "JESÚS MUÑOZ IBÁÑEZ"),
        ("ROMAN MARTIN ARGUELLES", "ROMÁN MARTÍN ARGÜELLES"),
    ])
    func spellsTheUsualNames(_ raw: String, _ spelled: String) throws {
        #expect(try PlayerName(raw).spelledInCastilian(with: Self.repositoryNames()).value == spelled)
    }

    // ── En caliente ──

    /// Se lee cada vez: lo cambiado vale desde la siguiente lectura, sin crear otro lector (sin relanzar).
    @Test("lo cambiado en el fichero vale desde la siguiente lectura")
    func readsTheFileEachTime() throws {
        try Self.withFile("JESÚS\n") { file in
            let source = NameDictionaryFile(file: file)
            #expect(source.read()?.words == ["JESÚS"])
            try "JESÚS\nÍÑIGO\n".write(to: file, atomically: true, encoding: .utf8)
            #expect(source.read()?.words == ["JESÚS", "ÍÑIGO"])
        }
    }

    @Test("una línea mala se salta, y las demás se usan")
    func badLineIsSkipped() throws {
        try Self.withFile("JESÚS\nGARCIA\nROMÁN\n") { file in
            let names = try #require(NameDictionaryFile(file: file).read())
            #expect(names.words == ["JESÚS", "ROMÁN"])
            #expect(names.problems == [.init(line: 2, text: "GARCIA", reason: .noMark)])
        }
    }

    @Test("sin fichero, nada: quien lo pide sigue sin diccionario")
    func missingFileGivesNothing() throws {
        try Self.withFile(nil) { file in
            #expect(NameDictionaryFile(file: file).read() == nil)
        }
    }
}

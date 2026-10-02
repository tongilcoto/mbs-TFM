import Foundation
import Testing

/// Nivel 1 (§8.1): **las convenciones del *spec* que el compilador no ve**.
///
/// El generador solo traduce las operaciones del `filter` (`D-69`), así que una
/// regla que deban cumplir **las 83** no la vigila el *build*: la operación que
/// la incumpla compila igual, porque no se genera. Esto lee el YAML tal cual.
///
/// Se recorre **como texto** y no con un parser de YAML a propósito: el *spec*
/// tiene una sola forma de escribir un bloque de respuestas —`responses:` a seis
/// espacios y cada código a ocho—, y si alguien la cambia, que este test caiga
/// es la señal correcta.
@Suite("El spec · convenciones que no compila nadie")
struct SpecConventionTests {

    static let specURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()      // APITests
        .deletingLastPathComponent()      // Tests
        .deletingLastPathComponent()      // backend
        .appending(path: "Sources/APIContract/openapi.yaml")

    /// Los bloques `responses:` de las operaciones, cada uno con sus líneas.
    static func responseBlocks() throws -> [(line: Int, body: [String])] {
        let lines = try String(contentsOf: specURL, encoding: .utf8)
            .components(separatedBy: "\n")
        var blocks: [(Int, [String])] = []
        var index = 0
        while index < lines.count {
            guard lines[index] == "      responses:" else { index += 1; continue }
            var body: [String] = []
            var next = index + 1
            while next < lines.count {
                let line = lines[next]
                if line.trimmingCharacters(in: .whitespaces).isEmpty { next += 1; continue }
                guard line.hasPrefix("        ") else { break }
                body.append(line)
                next += 1
            }
            blocks.append((index + 1, body))
            index = next
        }
        return blocks
    }

    /// **Toda operación declara `default: DefaultProblem`** (`D-99`, `A-14`·H-67).
    ///
    /// Los errores que no son de la ruta sino de todas —el club que no existe, la
    /// petición sin club, la base caída— los decide el middleware por el tipo de
    /// error, así que cualquier operación los puede emitir. Sin `default`, un
    /// cliente generado del *spec* los recibe como *"no documentado"*, sin el
    /// `Problem` tipado por el que se ramifica (`code`).
    @Test("toda operación declara su respuesta default con Problem (D-99 · A-14/H-67)")
    func everyOperationDeclaresTheDefaultProblem() throws {
        let blocks = try Self.responseBlocks()
        // Si el recorrido no encontrara nada, el test aprobaría por vacío.
        #expect(blocks.count >= 83, "bloques de respuestas encontrados: \(blocks.count)")

        let missing = blocks.filter { block in
            !block.body.contains("        default: { $ref: '#/components/responses/DefaultProblem' }")
        }
        #expect(missing.isEmpty,
                "operaciones sin default, por línea de su `responses:`: \(missing.map(\.line))")
    }
}

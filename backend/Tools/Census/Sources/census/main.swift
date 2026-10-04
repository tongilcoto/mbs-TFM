import CensusCore
import Foundation
import Yams

// ─────────────────────────────────────────────────────────────────────────────
// census [--package-path <dir>] [--known-gaps <fichero>]
//
// Desde `backend/`. Escribe el censo por stdout y sale con:
//   0  los huecos de hoy son exactamente los de known-gaps.json
//   1  hay un hueco nuevo, o una entrada de la lista ya no es hueco
//   3  no se pudo hacer el censo
// ─────────────────────────────────────────────────────────────────────────────

struct Failure: Error, CustomStringConvertible {
    var description: String
}

/// Yams puede dar claves que no son `String` (`200:` sin comillas es un entero):
/// se normalizan para que el núcleo solo vea `[String: Any]`.
func normalized(_ node: Any) -> Any {
    if let dictionary = node as? [AnyHashable: Any] {
        return Dictionary(uniqueKeysWithValues: dictionary.map { ("\($0.key.base)", normalized($0.value)) })
    }
    if let dictionary = node as? [String: Any] {
        return dictionary.mapValues(normalized)
    }
    if let array = node as? [Any] { return array.map(normalized) }
    return node
}

func yaml(at url: URL) throws -> [String: Any] {
    let text = try String(contentsOf: url, encoding: .utf8)
    guard let root = normalized(try Yams.load(yaml: text) as Any) as? [String: Any] else {
        throw Failure(description: "\(url.path) no es un mapa YAML")
    }
    return root
}

/// Todos los `.swift` bajo `directory`, con la ruta relativa a `package`.
func swiftFiles(under directory: String, in package: URL) throws -> [SourceFile] {
    // **Con los enlaces resueltos en los dos lados**: en macOS `/tmp` es
    // `/private/tmp`, el enumerador devuelve la ruta resuelta, y sin esto la
    // relativa no se recortaba y ningún fichero parecía estar en `Tests/APITests/`
    // (todos los campos salían sin nombrar; medido al probar el trinquete).
    let base = package.resolvingSymlinksInPath().path + "/"
    let root = package.appendingPathComponent(directory).resolvingSymlinksInPath()
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
    else { throw Failure(description: "no existe \(root.path)") }
    var files: [SourceFile] = []
    for case let url as URL in enumerator where url.pathExtension == "swift" {
        let full = url.resolvingSymlinksInPath().path
        guard full.hasPrefix(base) else {
            throw Failure(description: "\(full) no está dentro de \(base)")
        }
        let relative = String(full.dropFirst(base.count))
        files.append(SourceFile(path: relative, text: try String(contentsOf: url, encoding: .utf8)))
    }
    return files.sorted { $0.path < $1.path }
}

func main() throws -> Int32 {
    var arguments = CommandLine.arguments.dropFirst()[...]
    var packagePath = FileManager.default.currentDirectoryPath
    var knownGapsPath = "Tools/Census/known-gaps.json"
    while let argument = arguments.popFirst() {
        switch argument {
        case "--package-path": packagePath = arguments.popFirst() ?? packagePath
        case "--known-gaps": knownGapsPath = arguments.popFirst() ?? knownGapsPath
        default:
            throw Failure(description: "uso: census [--package-path <dir>] [--known-gaps <fichero>]")
        }
    }
    let package = URL(fileURLWithPath: packagePath).standardizedFileURL

    // ── Lo que se lee ──────────────────────────────────────────────────────
    let spec = try yaml(at: package.appendingPathComponent("Sources/APIContract/openapi.yaml"))
    let config = try yaml(at: package.appendingPathComponent("Sources/APIContract/openapi-generator-config.yaml"))
    guard let operations = (config["filter"] as? [String: Any])?["operations"] as? [String] else {
        throw Failure(description: "openapi-generator-config.yaml no tiene filter.operations")
    }
    let sources = try swiftFiles(under: "Sources", in: package)
    let tests = try swiftFiles(under: "Tests", in: package)
    let apiTests = tests.filter { $0.path.hasPrefix("Tests/APITests/") }
    let known = try JSONDecoder().decode(
        KnownGaps.self, from: Data(contentsOf: package.appendingPathComponent(knownGapsPath)))

    // ── Los dos recuentos ──────────────────────────────────────────────────
    let emissions = emittedProblemCodes(in: sources)
    let codes = Set(emissions.map(\.code)).sorted()
    let codeMentions = Dictionary(uniqueKeysWithValues: codes.map { ($0, filesMentioning(code: $0, in: tests)) })
    let codeGaps = Set(codes.filter { codeMentions[$0]!.isEmpty })

    let fields = try reachableFields(spec: spec, operations: operations).sorted()
    let fieldGaps = Set(fields.filter { !mentions(property: $0.property, in: apiTests) }.map(\.description))

    let codeRatchet = ratchet(gaps: codeGaps, known: known.problemCodes)
    let fieldRatchet = ratchet(gaps: fieldGaps, known: known.fields)

    // ── El informe ─────────────────────────────────────────────────────────
    var out: [String] = []
    out.append("# Censo del contrato")
    out.append("")
    out.append("Operaciones del `filter`: \(operations.count) — \(operations.joined(separator: ", ")).")
    out.append("")
    out.append("## Códigos `Problem`: \(codes.count - codeGaps.count) de \(codes.count) nombrados en `Tests/`")
    out.append("")
    out.append("| Código | Emitido en | Lo nombra |")
    out.append("|---|---|---|")
    for code in codes {
        let places = emissions.filter { $0.code == code }.map { "`\($0.file):\($0.line)`" }
        let named = codeMentions[code]!.map { "`\(($0 as NSString).lastPathComponent)`" }
        out.append("| `\(code)` | \(places.joined(separator: " ")) | \(named.isEmpty ? "—" : named.joined(separator: " ")) |")
    }
    out.append("")
    out.append("## Campos: \(fields.count - fieldGaps.count) de \(fields.count) nombrados en `Tests/APITests/`")
    out.append("")
    out.append("| Campo | ¿Lo nombra un test de API? |")
    out.append("|---|---|")
    for field in fields {
        out.append("| `\(field)` | \(fieldGaps.contains(field.description) ? "—" : "sí") |")
    }
    out.append("")
    out.append("## El trinquete (`\(knownGapsPath)`)")
    out.append("")
    for (name, result) in [("códigos", codeRatchet), ("campos", fieldRatchet)] {
        if result.holds {
            out.append("- **\(name)**: los huecos son exactamente los sabidos.")
        }
        if !result.unexpected.isEmpty {
            out.append("- ⚠️ **\(name), huecos nuevos**: \(result.unexpected.map { "`\($0)`" }.joined(separator: ", ")). "
                       + "Escribe su test, o apúntalo en la lista con su motivo.")
        }
        if !result.stale.isEmpty {
            out.append("- ⚠️ **\(name), la lista caducó**: \(result.stale.map { "`\($0)`" }.joined(separator: ", ")) "
                       + "ya no es hueco. Quítalo de la lista.")
        }
    }
    print(out.joined(separator: "\n"))
    return codeRatchet.holds && fieldRatchet.holds ? 0 : 1
}

do {
    exit(try main())
} catch {
    FileHandle.standardError.write(Data("census: \(error)\n".utf8))
    exit(3)
}

#!/usr/bin/env swift
// Formatea la salida de `swift test` agrupando cada test bajo su suite.
//
// `swift-testing` imprime el nombre del test pero **no el de su suite**, así que
// con varias suites a la vez no se sabe qué está pasando. Aquí se lee su flujo
// de eventos en JSON —que sí trae la jerarquía— y se reimprime agrupado.
//
// Uso:  ./scripts/test-report.sh [argumentos de swift test]
import Foundation

let path = CommandLine.arguments.dropFirst().first ?? "/tmp/test-events.jsonl"
guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
    FileHandle.standardError.write(Data("No se pudo leer \(path)\n".utf8))
    exit(1)
}

struct TestInfo { var display: String; var isSuite: Bool; var suiteID: String? }
var catalog: [String: TestInfo] = [:]
/// Resultados por suite, en el orden en que aparece cada suite.
var order: [String] = []
var results: [String: [(ok: Bool, text: String)]] = [:]
var failures: [String] = []
/// Motivo y ubicación de cada fallo. Un informe que dice "falló" sin decir por
/// qué es peor que la salida por defecto.
var issues: [String: [(text: String, location: String?)]] = [:]

for line in contents.split(separator: "\n") {
    guard let data = line.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let payload = root["payload"] as? [String: Any] else { continue }

    switch root["kind"] as? String {
    case "test":
        guard let id = payload["id"] as? String else { continue }
        let display = (payload["displayName"] as? String)
            ?? (payload["name"] as? String) ?? id
        let isSuite = (payload["kind"] as? String) == "suite"
        // El id es jerárquico (`Modulo.Suite/test()`), así que la suite de un
        // test es su prefijo antes de la barra.
        let suiteID = isSuite ? nil : id.split(separator: "/").first.map(String.init)
        catalog[id] = TestInfo(display: display, isSuite: isSuite, suiteID: suiteID)

    case "event" where payload["kind"] as? String == "issueRecorded":
        guard let id = payload["testID"] as? String else { continue }
        let text = (payload["messages"] as? [[String: Any]])?
            .first { ($0["symbol"] as? String) == "fail" }?["text"] as? String
        let source = (payload["issue"] as? [String: Any])?["sourceLocation"] as? [String: Any]
        let location = (source?["fileID"] as? String).map { file in
            "\(file):\((source?["line"] as? Int).map(String.init) ?? "?")"
        }
        issues[id, default: []].append((text ?? "sin detalle", location))

    case "event":
        guard payload["kind"] as? String == "testEnded",
              let id = payload["testID"] as? String,
              let info = catalog[id], !info.isSuite else { continue }
        let messages = payload["messages"] as? [[String: Any]] ?? []
        let ok = messages.contains { ($0["symbol"] as? String) == "pass" }
        let text = messages.first?["text"] as? String ?? info.display

        let suiteID = info.suiteID ?? "(sin suite)"
        if results[suiteID] == nil { order.append(suiteID) }
        results[suiteID, default: []].append((ok, text))
        if !ok {
            var entry = "\(catalog[suiteID]?.display ?? suiteID) › \(info.display)"
            for issue in issues[id] ?? [] {
                entry += "\n      \(issue.text)"
                if let location = issue.location { entry += "\n      en \(location)" }
            }
            failures.append(entry)
        }

    default: break
    }
}

var passed = 0, failed = 0
for suiteID in order {
    print("\n\u{001B}[1m\(catalog[suiteID]?.display ?? suiteID)\u{001B}[0m")
    for result in results[suiteID] ?? [] {
        // El texto del evento ya viene redactado ("Test \"…\" passed after …s");
        // se recorta el prefijo, que aquí es redundante.
        var line = result.text
        if line.hasPrefix("Test ") { line = String(line.dropFirst(5)) }
        print("  \(result.ok ? "\u{001B}[32m✔\u{001B}[0m" : "\u{001B}[31m✘\u{001B}[0m") \(line)")
        result.ok ? (passed += 1) : (failed += 1)
    }
}

print("\n\u{001B}[1m\(passed + failed) tests en \(order.count) suites · \(passed) ✔ · \(failed) ✘\u{001B}[0m")
if !failures.isEmpty {
    print("\nFallos:")
    for failure in failures { print("  \u{001B}[31m✘\u{001B}[0m \(failure)") }
}
exit(failed == 0 ? 0 : 1)

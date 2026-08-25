import Foundation
import Vapor
import VaporTesting

/// Vuelca petición y respuesta a la consola cuando `HTTP_TRACE=1`.
///
/// Existe para **estudiar** el sistema: `swift test` no enseña los cuerpos que
/// cruzan la frontera, y son justo lo que hay que mirar para entender qué hace
/// un adaptador primario (§2.2). Apagada por defecto, para no ensuciar CI.
///
/// ```sh
/// HTTP_TRACE=1 swift test --filter APITests
/// ```
enum HTTPTrace {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["HTTP_TRACE"] == "1" }

    static func request(_ method: HTTPMethod, _ path: String, headers: HTTPHeaders, body: String?) {
        guard isEnabled else { return }
        print("\n┌─ → \(method.rawValue) \(path)")
        for (name, value) in headers where name.lowercased() != "content-length" {
            print("│  \(name): \(value)")
        }
        if let body, !body.isEmpty { print("│\n\(indent(pretty(body)))") }
    }

    static func response(_ response: TestingHTTPResponse) {
        guard isEnabled else { return }
        print("├─ ← \(response.status.code) \(response.status.reasonPhrase)")
        if let contentType = response.headers.contentType {
            print("│  Content-Type: \(contentType.serialize())")
        }
        let body = response.body.string
        if !body.isEmpty { print("│\n\(indent(pretty(body)))") }
        print("└─")
    }

    /// Reimprime el JSON con sangrado y claves ordenadas. Si no es JSON, lo deja
    /// tal cual: un cuerpo de error mal formado también hay que poder verlo.
    private static func pretty(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(
                  withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: formatted, encoding: .utf8)
        else { return raw }
        return text
    }

    private static func indent(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "│  \($0)" }
            .joined(separator: "\n")
    }
}

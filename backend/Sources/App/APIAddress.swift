import Foundation

/// Dónde escucha la API en este Mac. Lo leen **dos procesos distintos**: `serve`,
/// como puerto por defecto, y los comandos, para imprimir `curl` que se puedan
/// pegar tal cual. Ninguno puede preguntarle al otro, así que comparten la
/// variable `API_PORT`.
public struct APIAddress: Sendable, Equatable {
    public static let defaultPort = 8080

    public var port: Int

    /// Un valor que no es un puerto cae al de por defecto, igual que `DB_PORT`.
    public init(environment: [String: String]) {
        port = environment["API_PORT"].flatMap(Int.init)
            .flatMap { (1...65535).contains($0) ? $0 : nil } ?? Self.defaultPort
    }

    public static func fromEnvironment() -> APIAddress {
        .init(environment: ProcessInfo.processInfo.environment)
    }

    /// Las pistas son para este Mac: el sufijo es siempre `localhost`.
    public func clubURL(slug: String) -> String {
        "http://\(slug).localhost:\(port)"
    }
}

import Foundation

/// Los huecos que se saben, cada uno con su motivo (`known-gaps.json`).
///
/// **Es el trinquete del censo.** Un hueco nuevo que no esté aquí es un aviso;
/// uno que esté aquí y **ya no sea hueco** también, porque la lista ha caducado
/// y seguiría disculpando algo que ya no existe.
public struct KnownGaps: Codable, Sendable, Equatable {
    public var problemCodes: [String: String]
    public var fields: [String: String]

    public init(problemCodes: [String: String] = [:], fields: [String: String] = [:]) {
        self.problemCodes = problemCodes
        self.fields = fields
    }
}

/// Lo que el trinquete encuentra al comparar los huecos de hoy con los sabidos.
public struct RatchetResult: Sendable, Equatable {
    /// Huecos que no están en la lista: código o campo nuevo sin test.
    public var unexpected: [String]
    /// Entradas de la lista que ya no son hueco: o ya tienen test, o ya no existen.
    public var stale: [String]

    public init(unexpected: [String], stale: [String]) {
        self.unexpected = unexpected
        self.stale = stale
    }

    public var holds: Bool { unexpected.isEmpty && stale.isEmpty }
}

public func ratchet(gaps: Set<String>, known: [String: String]) -> RatchetResult {
    let knownKeys = Set(known.keys)
    return RatchetResult(
        unexpected: gaps.subtracting(knownKeys).sorted(),
        stale: knownKeys.subtracting(gaps).sorted())
}

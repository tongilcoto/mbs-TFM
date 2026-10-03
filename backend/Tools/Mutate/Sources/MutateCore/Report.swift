import Foundation

public struct MutationResult: Sendable, Equatable {
    public var mutation: Mutation
    public var filter: String?
    public var outcome: Outcome

    public init(mutation: Mutation, filter: String?, outcome: Outcome) {
        self.mutation = mutation
        self.filter = filter
        self.outcome = outcome
    }

    /// Lo que conviene que lea quien revisa, además del desenlace.
    var note: String {
        switch outcome {
        case .killed where mutation.equivalent != nil:
            "**declarada equivalente y cazada**: la declaración sobra"
        case .equivalent:
            mutation.equivalent ?? ""
        case .survived:
            "falta un test, sobra el código, o es equivalente y hay que declararlo"
        case .invalid(let reason):
            reason.description
        case .killed:
            ""
        }
    }
}

/// El resumen de una pasada del catálogo.
public struct Summary: Sendable, Equatable {
    public var title: String
    public var results: [MutationResult]
    /// La batería sin mutar, al empezar **y al acabar**: si el entorno se cae a
    /// mitad (Postgres, por ejemplo), lo que se leyó como *"cazada"* pudo ser el
    /// entorno, y la pasada entera deja de valer.
    public var closingBaselinePassed: Bool

    public init(title: String, results: [MutationResult], closingBaselinePassed: Bool = true) {
        self.title = title
        self.results = results
        self.closingBaselinePassed = closingBaselinePassed
    }

    public var killed: Int { results.count { $0.outcome == .killed } }
    public var survived: Int { results.count { $0.outcome == .survived } }
    public var equivalent: Int { results.count { $0.outcome == .equivalent } }
    public var invalid: Int {
        results.count { if case .invalid = $0.outcome { true } else { false } }
    }

    /// `0` todas cazadas (o equivalentes declaradas) · `1` alguna sobrevive ·
    /// `2` hay inválidas o la batería no cerró en verde: la cifra no vale.
    public var exitCode: Int32 {
        if invalid > 0 || !closingBaselinePassed { return 2 }
        if survived > 0 { return 1 }
        return 0
    }

    /// La línea que se cita, con sus cuatro cifras por separado.
    public var headline: String {
        var parts = ["\(results.count) mutaciones", "\(killed) cazadas"]
        if survived > 0 { parts.append("\(survived) sobreviven") }
        if equivalent > 0 { parts.append("\(equivalent) equivalentes") }
        if invalid > 0 { parts.append("\(invalid) inválidas") }
        return parts.joined(separator: ", ")
    }

    public func markdown(date: Date = Date()) -> String {
        var lines = [
            "# \(title)",
            "",
            "**\(headline).** \(date.formatted(.iso8601))",
            "",
        ]
        if !closingBaselinePassed {
            lines.append("> ⚠️ **La batería sin mutar no cerró en verde.** El entorno cambió a mitad de la "
                         + "pasada; ningún resultado de esta tabla vale hasta repetirla.")
            lines.append("")
        }
        if invalid > 0 {
            lines.append("> ⚠️ **Hay inválidas: no se probaron.** La cifra no se cita hasta resolverlas.")
            lines.append("")
        }
        lines.append("| Mutación | Qué rompe | Fichero | Filtro | Desenlace | Nota |")
        lines.append("|---|---|---|---|---|---|")
        for result in results {
            let cells = [
                result.mutation.id,
                result.mutation.description,
                "`\(result.mutation.file)`",
                result.filter.map { "`\($0)`" } ?? "*(toda la batería)*",
                result.outcome.label,
                result.note,
            ].map { $0.replacingOccurrences(of: "|", with: "\\|") }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

extension Outcome {
    public var label: String {
        switch self {
        case .killed: "✅ cazada"
        case .survived: "❌ sobrevive"
        case .equivalent: "➖ equivalente"
        case .invalid: "⚠️ inválida"
        }
    }
}

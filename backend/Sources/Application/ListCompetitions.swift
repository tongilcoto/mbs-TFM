public import Domain

/// Caso de uso: las competiciones del club, con los filtros de
/// `GET /v1/competitions` (§5.1).
///
/// Hoy es un paso directo al repositorio. El estado de la ingesta de cada
/// competición (`D-89`, con su enmienda) se añade aquí en R1.8.
public struct ListCompetitions: Sendable {
    private let competitions: any CompetitionRepository

    public init(competitions: any CompetitionRepository) {
        self.competitions = competitions
    }

    public func execute(_ filter: CompetitionFilter) async throws -> [Competition] {
        try await competitions.list(filter)
    }
}

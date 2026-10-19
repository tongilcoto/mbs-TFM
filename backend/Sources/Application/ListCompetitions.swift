public import Domain
public import struct Foundation.Date

/// Caso de uso: las competiciones del club, con los filtros de
/// `GET /v1/competitions` (§5.1) y **el estado de la ingesta de cada una**
/// (`D-89`, con su enmienda).
///
/// El estado se calcula al leer, sin columna detrás. Cuesta **tres consultas al
/// registro de pasadas, tenga el club las competiciones que tenga**, nunca una por
/// competición: las dos últimas pasadas de cada clase, la última hora de fin de
/// cada competición y la del club.
public struct ListCompetitions: Sendable {
    private let competitions: any CompetitionRepository
    private let ingestionRuns: any IngestionRunRepository
    private let clock: any Clock

    public init(
        competitions: any CompetitionRepository,
        ingestionRuns: any IngestionRunRepository,
        clock: any Clock
    ) {
        self.competitions = competitions
        self.ingestionRuns = ingestionRuns
        self.clock = clock
    }

    public func execute(_ filter: CompetitionFilter) async throws -> [CompetitionListing] {
        let list = try await competitions.list(filter)
        let ids = list.map(\.id)
        // Las dos últimas de cada clase: la última decide, y la anterior dice qué
        // había antes de una pasada en marcha (`previousIngestionHealth`).
        let recent = Dictionary(
            grouping: try await ingestionRuns.recent(competitionIDs: ids, perKind: 2),
            by: \.competitionID)
        let lastFinished = try await ingestionRuns.lastFinishedAt(competitionIDs: ids)
        let clubLastFinished = try await ingestionRuns.lastFinishedAt()
        let now = clock.now()
        return list.map { competition in
            CompetitionListing(
                competition: competition,
                ingestion: IngestionHealth.assess(
                    recentRuns: recent[competition.id] ?? [],
                    lastSyncedAt: competition.lastSyncedAt,
                    clubLastFinishedAt: clubLastFinished,
                    now: now),
                lastIngestionAt: lastFinished[competition.id])
        }
    }
}

/// Una competición, con lo que se deriva al leerla: su estado de la ingesta y
/// cuándo acabó su última pasada, bien o mal (`lastIngestionAt`).
public struct CompetitionListing: Equatable, Sendable {
    public let competition: Competition
    public let ingestion: IngestionHealthAssessment
    public let lastIngestionAt: Date?

    public init(competition: Competition, ingestion: IngestionHealthAssessment, lastIngestionAt: Date?) {
        self.competition = competition
        self.ingestion = ingestion
        self.lastIngestionAt = lastIngestionAt
    }
}

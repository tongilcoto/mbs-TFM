import Domain
import Foundation
import Synchronization
import Testing
@testable import Application

/// Nivel 2 (§8.1): `ListCompetitions` con los repositorios y el reloj falseados.
///
/// Los filtros los aplica el nivel 3 y la regla del estado está en el nivel 1.
/// Lo que se prueba aquí es **la orquestación**: que los filtros pasan enteros,
/// que se pregunta por las pasadas **de las competiciones que salen**, y que a
/// cada una le llegan las suyas, su `lastIngestionAt` y el reloj del club.
@Suite("ListCompetitions · §5.1 · las competiciones del club, con su estado de la ingesta")
struct ListCompetitionsTests {

    final class CompetitionRepositorySpy: CompetitionRepository, Sendable {
        let stored: [Competition]
        let requests = Mutex<[CompetitionFilter]>([])

        init(stored: [Competition]) { self.stored = stored }

        func list(_ filter: CompetitionFilter) async throws -> [Competition] {
            requests.withLock { $0.append(filter) }
            return stored
        }
        func find(_ id: CompetitionID) async throws -> Competition? { nil }
        func lock(_ id: CompetitionID) async throws -> Competition? { nil }
        func findByFederationGroup(
            seasonID: SeasonID, federationGroupID: String
        ) async throws -> Competition? { nil }
        func save(_ competition: Competition) async throws {}
    }

    /// Devuelve lo que se le dé y apunta por qué competiciones se le preguntó.
    final class IngestionRunRepositorySpy: IngestionRunRepository, Sendable {
        let runs: [IngestionRun]
        let lastFinished: [CompetitionID: Date]
        let clubLastFinished: Date?
        let recentRequests = Mutex<[[CompetitionID]]>([])
        let perKindRequests = Mutex<[Int]>([])

        init(runs: [IngestionRun], lastFinished: [CompetitionID: Date], clubLastFinished: Date?) {
            self.runs = runs
            self.lastFinished = lastFinished
            self.clubLastFinished = clubLastFinished
        }

        func recent(competitionIDs: [CompetitionID], perKind: Int) async throws -> [IngestionRun] {
            recentRequests.withLock { $0.append(competitionIDs) }
            perKindRequests.withLock { $0.append(perKind) }
            return runs
        }
        func lastFinishedAt(competitionIDs: [CompetitionID]) async throws -> [CompetitionID: Date] {
            lastFinished
        }
        func lastFinishedAt() async throws -> Date? { clubLastFinished }
        func record(_ run: IngestionRun) async throws -> IngestionRunWrite { .recorded }
        func list(competitionID: CompetitionID, limit: Int) async throws -> [IngestionRun] { [] }
        func findAccepted(
            competitionID: CompetitionID, kind: IngestionKind
        ) async throws -> IngestionRun? { nil }
    }

    static let now = try! Date("2026-10-18T22:00:00Z", strategy: .iso8601)
    static func minutesAgo(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

    static func competition(group: String, lastSyncedAt: Date?) throws -> Competition {
        try Competition(
            id: CompetitionID(raw: UUID()), seasonID: SeasonID(raw: UUID()), modality: .futbol11,
            gender: .masculino, federationCompetitionID: "1", federationGroupID: group,
            ageCategory: .cadete, divisionLabel: "Primera", groupLabel: group,
            lastSyncedAt: lastSyncedAt,
            createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
    }

    static func run(
        _ competition: CompetitionID, _ kind: IngestionKind, _ outcome: IngestionOutcome,
        started: Double, finished: Double?
    ) throws -> IngestionRun {
        try IngestionRun(
            id: IngestionRunID(raw: UUID()), competitionID: competition, kind: kind,
            startedAt: minutesAgo(started), finishedAt: finished.map(minutesAgo),
            outcome: outcome, error: outcome == .failed ? "FederationError" : nil)
    }

    @Test("pasa los cuatro filtros al repositorio, tal cual")
    func passesTheFilterThrough() async throws {
        let repository = CompetitionRepositorySpy(stored: [])
        let filter = CompetitionFilter(
            seasonID: SeasonID(raw: UUID()), modality: .futbol7, ageCategory: .cadete, gender: .femenino)
        let useCase = ListCompetitions(
            competitions: repository,
            ingestionRuns: IngestionRunRepositorySpy(runs: [], lastFinished: [:], clubLastFinished: nil),
            clock: FixedClock(instant: Self.now))

        _ = try await useCase.execute(filter)

        #expect(repository.requests.withLock { $0 } == [filter])
    }

    /// Dos competiciones con estados distintos. La `pending` lo es **gracias al
    /// reloj del club**: se pidió hace 20 minutos, pero otra pasada del club acabó
    /// hace 2. Sin ese dato saldría `failing`.
    @Test("a cada competición le llegan sus pasadas, su última hora de fin y el reloj del club")
    func eachCompetitionGetsItsOwnHealth() async throws {
        let cadete = try Self.competition(group: "Grupo 4", lastSyncedAt: Self.minutesAgo(600))
        let alevin = try Self.competition(group: "Grupo 8", lastSyncedAt: Self.minutesAgo(300))
        let runs = [
            try Self.run(cadete.id, .calendar, .succeeded, started: 601, finished: 600),
            try Self.run(cadete.id, .scorers, .failed, started: 599, finished: 598),
            try Self.run(cadete.id, .calendar, .accepted, started: 20, finished: nil),
            try Self.run(alevin.id, .calendar, .succeeded, started: 301, finished: 300),
        ]
        let ingestionRuns = IngestionRunRepositorySpy(
            runs: runs,
            lastFinished: [cadete.id: Self.minutesAgo(598), alevin.id: Self.minutesAgo(300)],
            clubLastFinished: Self.minutesAgo(2))
        let useCase = ListCompetitions(
            competitions: CompetitionRepositorySpy(stored: [cadete, alevin]),
            ingestionRuns: ingestionRuns, clock: FixedClock(instant: Self.now))

        let listings = try await useCase.execute(CompetitionFilter())

        #expect(listings == [
            CompetitionListing(
                competition: cadete,
                ingestion: IngestionHealthAssessment(health: .pending, previous: .failing),
                lastIngestionAt: Self.minutesAgo(598)),
            CompetitionListing(
                competition: alevin,
                ingestion: IngestionHealthAssessment(health: .ok),
                lastIngestionAt: Self.minutesAgo(300)),
        ])
        #expect(ingestionRuns.recentRequests.withLock { $0 } == [[cadete.id, alevin.id]])
        #expect(ingestionRuns.perKindRequests.withLock { $0 } == [2])
    }
}

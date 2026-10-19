import Application
import Domain
import Foundation
import Testing
import TestSupport
@testable import Persistence

/// Nivel 3 (§8.1): las tres lecturas del registro de pasadas que necesita el
/// estado de la ingesta (`D-89`, enmienda; Plan R1, R1.8). La regla está probada
/// en el nivel 1; aquí se prueba **qué filas trae cada consulta**.
///
/// Solo calendario y goleadores: la clasificación lleva jornada, y la jornada no
/// cambia nada de lo que se prueba aquí.
@Suite("Ingesta · D-89 · lo que el estado de la ingesta lee del registro",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct IngestionHealthPersistenceTests {

    static let base = try! Date("2026-10-18T20:00:00Z", strategy: .iso8601)
    static func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }

    static func run(
        _ competition: CompetitionID, _ kind: IngestionKind,
        started: Double, finished: Double?
    ) throws -> IngestionRun {
        try IngestionRun(
            id: IngestionRunID(raw: UUID()), competitionID: competition, kind: kind,
            startedAt: at(started), finishedAt: finished.map(at),
            outcome: finished == nil ? .accepted : .succeeded)
    }

    /// Tres competiciones: `a` y `b` son las que se preguntan; `other` no, y es la
    /// que tiene **la última pasada del club**.
    struct Fixture: Sendable {
        let a: CompetitionID, b: CompetitionID, other: CompetitionID
        let aCalendarOld: IngestionRun, aCalendarMiddle: IngestionRun, aCalendarAccepted: IngestionRun
        let aScorers: IngestionRun, bCalendar: IngestionRun, otherCalendar: IngestionRun
    }

    static func withFixture(
        _ slug: String, _ body: @escaping @Sendable (Fixture, TenantFixture) async throws -> Void
    ) async throws {
        try await IngestionPersistenceTests.withTenant(slug) { tenant in
            let season = try Season(
                id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
                federationSeasonID: "21", createdAt: Date(), updatedAt: Date())
            let ids = (0..<3).map { _ in CompetitionID(raw: UUID()) }
            let (a, b, other) = (ids[0], ids[1], ids[2])
            let fixture = Fixture(
                a: a, b: b, other: other,
                aCalendarOld: try run(a, .calendar, started: 0, finished: 2),
                aCalendarMiddle: try run(a, .calendar, started: 10, finished: 13),
                aCalendarAccepted: try run(a, .calendar, started: 20, finished: nil),
                aScorers: try run(a, .scorers, started: 14, finished: 15),
                bCalendar: try run(b, .calendar, started: 5, finished: 7),
                otherCalendar: try run(other, .calendar, started: 30, finished: 31))
            try await tenant.scope {
                try await $0.seasons.save(season)
                for (index, id) in ids.enumerated() {
                    try await $0.competitions.save(try Competition(
                        id: id, seasonID: season.id, modality: .futbol11, gender: .masculino,
                        federationCompetitionID: "2403754\(index)", federationGroupID: "9900\(index)",
                        ageCategory: .cadete, divisionLabel: "Primera", groupLabel: "Grupo \(index)",
                        createdAt: Date(), updatedAt: Date()))
                }
                for run in [fixture.aCalendarOld, fixture.aCalendarMiddle, fixture.aCalendarAccepted,
                            fixture.aScorers, fixture.bCalendar, fixture.otherCalendar] {
                    try await $0.ingestionRuns.record(run)
                }
            }
            try await body(fixture, tenant)
        }
    }

    @Test("las dos últimas de cada clase, por cuándo empezaron, solo de las competiciones pedidas")
    func recentBringsTheLastTwoOfEachKind() async throws {
        try await Self.withFixture("health-recent") { f, tenant in
            let runs = try await tenant.scope {
                try await $0.ingestionRuns.recent(competitionIDs: [f.a, f.b], perKind: 2)
            }
            #expect(Set(runs.map(\.id)) == Set([
                f.aCalendarAccepted.id, f.aCalendarMiddle.id, f.aScorers.id, f.bCalendar.id,
            ]))
        }
    }

    /// La aceptada no tiene final y no cuenta; la de `a` que acabó más tarde es la
    /// de goleadores, no la del calendario.
    @Test("la última hora de fin de cada competición pedida, bien o mal, sin contar la aceptada")
    func lastFinishedAtPerCompetition() async throws {
        try await Self.withFixture("health-lastfin") { f, tenant in
            let last = try await tenant.scope {
                try await $0.ingestionRuns.lastFinishedAt(competitionIDs: [f.a, f.b])
            }
            #expect(last == [f.a: Self.at(15), f.b: Self.at(7)])
        }
    }

    @Test("la última hora de fin del club cuenta todas las competiciones, también las no pedidas")
    func lastFinishedAtOfTheClub() async throws {
        try await Self.withFixture("health-club") { _, tenant in
            let last = try await tenant.scope { try await $0.ingestionRuns.lastFinishedAt() }
            #expect(last == Self.at(31))
        }
    }
}

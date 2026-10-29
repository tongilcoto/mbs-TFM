import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): `ListRounds` y `GetRound` con los repositorios en memoria
/// (R4.6). La regla de «en curso» la prueba el nivel 1 (`RoundTests`); aquí, lo
/// que deciden los casos de uso: el orden, que solo salgan las de esa
/// competición, que `isCurrent` se mire entre las de su competición, y los 404.
@Suite("ListRounds y GetRound · R4.6 · las jornadas de una competición")
struct RoundQueriesTests {

    static let epoch = Date(timeIntervalSince1970: 0)
    /// Miércoles 8 de octubre de 2025: entre la jornada 1 y la 2.
    static let clock = FixedClock(instant: try! Date("2025-10-08T12:00:00Z", strategy: .iso8601))

    static func day(_ text: String) -> Date { try! Date("\(text)T00:00:00Z", strategy: .iso8601) }

    static func round(_ competition: CompetitionID, _ number: Int, ends: String) throws -> Round {
        try Round(
            id: RoundID(raw: UUID()), competitionID: competition, number: number,
            startDate: day(ends), endDate: day(ends), createdAt: epoch, updatedAt: epoch)
    }

    struct Seeded {
        let store: IngestionStore
        let competition: CompetitionID
        let first: Round, second: Round, third: Round
        /// La jornada 2 de otra competición, que acaba antes: no puede colarse.
        let otherSecond: Round
    }

    /// Las tres jornadas de la competición, **guardadas desordenadas**, y una de
    /// otra competición.
    static func seed() async throws -> Seeded {
        let store = IngestionStore()
        let season = try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"), federationSeasonID: "21",
            createdAt: epoch, updatedAt: epoch)
        let competition = try Competition(
            id: CompetitionID(raw: UUID()), seasonID: season.id, modality: .futbol11, gender: .masculino,
            federationCompetitionID: "1", federationGroupID: "2", ageCategory: .cadete,
            divisionLabel: "PRIMERA CADETE", groupLabel: "Grupo 1", createdAt: epoch, updatedAt: epoch)
        let other = CompetitionID(raw: UUID())
        let (first, second, third) = (
            try round(competition.id, 1, ends: "2025-10-05"), try round(competition.id, 2, ends: "2025-10-12"),
            try round(competition.id, 3, ends: "2025-10-19"))
        let otherSecond = try round(other, 2, ends: "2025-10-09")
        await store.seed(seasons: [season], competitions: [competition])
        for round in [third, otherSecond, first, second] { await store.save(round) }
        return Seeded(store: store, competition: competition.id, first: first, second: second, third: third,
                      otherSecond: otherSecond)
    }

    static func list(_ seeded: Seeded) -> ListRounds {
        ListRounds(
            competitions: FakeCompetitionRepository(store: seeded.store),
            rounds: FakeRoundRepository(store: seeded.store), clock: clock)
    }

    static func get(_ seeded: Seeded) -> GetRound {
        GetRound(rounds: FakeRoundRepository(store: seeded.store), clock: clock)
    }

    @Test("ListRounds: las de esa competición, por número, con la próxima en curso")
    func listsTheRoundsOfTheCompetition() async throws {
        let seeded = try await Self.seed()
        let listing = try await Self.list(seeded).execute(competitionID: seeded.competition)
        #expect(listing.rounds.map(\.number) == [1, 2, 3])
        #expect(listing.rounds.map(\.id) == [seeded.first.id, seeded.second.id, seeded.third.id])
        #expect(listing.currentID == seeded.second.id)
    }

    @Test("ListRounds: una competición sin jornadas da la lista vacía y ninguna en curso")
    func aCompetitionWithoutRounds() async throws {
        let seeded = try await Self.seed()
        let empty = try Competition(
            id: CompetitionID(raw: UUID()), seasonID: SeasonID(raw: UUID()), modality: .futbol7,
            gender: .femenino, federationCompetitionID: "3", federationGroupID: "4", ageCategory: .alevin,
            divisionLabel: "PRIMERA ALEVÍN", groupLabel: "Grupo 2", createdAt: Self.epoch, updatedAt: Self.epoch)
        await seeded.store.save(empty)
        let listing = try await Self.list(seeded).execute(competitionID: empty.id)
        #expect(listing == ListRounds.Listing(rounds: [], currentID: nil))
    }

    @Test("ListRounds: una competición que no existe es competitionNotFound")
    func anUnknownCompetition() async throws {
        let seeded = try await Self.seed()
        let missing = CompetitionID(raw: UUID())
        await #expect(throws: ApplicationError.competitionNotFound(id: "\(missing)")) {
            _ = try await Self.list(seeded).execute(competitionID: missing)
        }
    }

    @Test("GetRound: la jornada en curso dice que lo está")
    func theCurrentRound() async throws {
        let seeded = try await Self.seed()
        let result = try await Self.get(seeded).execute(roundID: seeded.second.id)
        #expect(result == GetRound.Result(round: seeded.second, isCurrent: true))
    }

    /// La jornada 2 de la otra competición acaba el 9, antes que la 2 de esta:
    /// si `isCurrent` se mirara entre todas, la de esta dejaría de estar en curso.
    @Test("GetRound: en curso se mira entre las de su competición, no entre todas")
    func currentAmongItsOwnCompetition() async throws {
        let seeded = try await Self.seed()
        #expect(try await Self.get(seeded).execute(roundID: seeded.otherSecond.id).isCurrent)
        #expect(try await Self.get(seeded).execute(roundID: seeded.second.id).isCurrent)
    }

    @Test("GetRound: una que no está en curso dice que no")
    func aRoundThatIsNotCurrent() async throws {
        let seeded = try await Self.seed()
        let result = try await Self.get(seeded).execute(roundID: seeded.third.id)
        #expect(result == GetRound.Result(round: seeded.third, isCurrent: false))
    }

    @Test("GetRound: una jornada que no existe es roundNotFound")
    func anUnknownRound() async throws {
        let seeded = try await Self.seed()
        let missing = RoundID(raw: UUID())
        await #expect(throws: ApplicationError.roundNotFound(id: "\(missing)")) {
            _ = try await Self.get(seeded).execute(roundID: missing)
        }
    }
}

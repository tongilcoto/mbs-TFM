import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): `GetTeamRegistration` con los repositorios en memoria (R4.5).
/// Lo que decide el caso de uso: **el equipo en esa temporada** con sus
/// competiciones (y no las de otra), la fila de junio con la lista vacía, y los
/// tres 404, cada uno con el suyo: el equipo, la temporada, y **que no esté
/// inscrito**, que es lo que la ficha del backoffice distingue.
@Suite("GetTeamRegistration · R4.5 · el equipo en una temporada, uno solo")
struct GetTeamRegistrationTests {

    static let epoch = ListSeasonRegistrationsTests.epoch
    static let club = ListSeasonRegistrationsTests.club
    static let actor = ListSeasonRegistrationsTests.actor

    static func season(_ label: String) throws -> Season {
        try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel(label), federationSeasonID: nil,
            createdAt: epoch, updatedAt: epoch)
    }

    static func useCase(_ store: IngestionStore) -> GetTeamRegistration {
        GetTeamRegistration(
            clubs: FakeClubRepository(store: store), seasons: FakeSeasonRepository(store: store),
            teams: FakeTeamRepository(store: store),
            registrations: FakeTeamRegistrationRepository(store: store))
    }

    /// El Cadete B con liga y copa en 2026/27 (guardadas con la copa primero) y
    /// otra competición en 2025/26, que no sale; y el Cadete A en la misma
    /// temporada, que tampoco.
    @Test("el equipo en la temporada, con sus competiciones en el orden en que se inscribió, y el club")
    func theTeamInTheSeason() async throws {
        let (season, other) = (try Self.season("2026/27"), try Self.season("2025/26"))
        let (liga, copa) = (CompetitionID(raw: UUID()), CompetitionID(raw: UUID()))
        let cadeteB = try ListSeasonRegistrationsTests.team(.cadete, "B")
        let cadeteA = try ListSeasonRegistrationsTests.team(.cadete, "A")
        let store = IngestionStore()
        await store.seed(club: Self.club)
        await store.seed(seasons: [season, other], teams: [cadeteB, cadeteA])
        await store.seed(teamRegistrations: [
            try ListSeasonRegistrationsTests.registration(cadeteB, season.id, copa, code: "900", at: 20),
            try ListSeasonRegistrationsTests.registration(cadeteB, other.id, CompetitionID(raw: UUID()), code: "666"),
            try ListSeasonRegistrationsTests.registration(cadeteB, season.id, liga, code: "821", at: 10),
            try ListSeasonRegistrationsTests.registration(cadeteA, season.id, CompetitionID(raw: UUID()), code: "777"),
        ])

        let result = try await Self.useCase(store).execute(actor: Self.actor, teamID: cadeteB.id, seasonID: season.id)

        #expect(result.club == Self.club)
        #expect(result.registration == SeasonRegistration(team: cadeteB, seasonID: season.id, competitions: [
            RegisteredCompetition(competitionID: liga, federationTeamID: "821"),
            RegisteredCompetition(competitionID: copa, federationTeamID: "900"),
        ]))
    }

    @Test("inscrito sin competición (junio): la lista vacía")
    func registeredWithoutCompetition() async throws {
        let season = try Self.season("2026/27")
        let alevin = try ListSeasonRegistrationsTests.team(.alevin, "A")
        let store = IngestionStore()
        await store.seed(club: Self.club)
        await store.seed(seasons: [season], teams: [alevin])
        await store.seed(teamRegistrations: [try ListSeasonRegistrationsTests.registration(alevin, season.id)])

        let result = try await Self.useCase(store).execute(actor: Self.actor, teamID: alevin.id, seasonID: season.id)

        #expect(result.registration == SeasonRegistration(team: alevin, seasonID: season.id, competitions: []))
    }

    @Test("un equipo que no existe es teamNotFound")
    func aMissingTeam() async throws {
        let season = try Self.season("2026/27")
        let store = IngestionStore()
        await store.seed(club: Self.club)
        await store.seed(seasons: [season])
        let missing = TeamID(raw: UUID())

        await #expect(throws: ApplicationError.teamNotFound(id: "\(missing)")) {
            _ = try await Self.useCase(store).execute(actor: Self.actor, teamID: missing, seasonID: season.id)
        }
    }

    @Test("una temporada que no existe es unknownSeason")
    func aMissingSeason() async throws {
        let alevin = try ListSeasonRegistrationsTests.team(.alevin, "A")
        let store = IngestionStore()
        await store.seed(club: Self.club)
        await store.seed(teams: [alevin])
        let missing = SeasonID(raw: UUID())

        await #expect(throws: ApplicationError.unknownSeason(id: "\(missing)")) {
            _ = try await Self.useCase(store).execute(actor: Self.actor, teamID: alevin.id, seasonID: missing)
        }
    }

    @Test("un equipo propio inscrito en otra temporada, no en esta, es teamNotRegistered")
    func notRegisteredInThatSeason() async throws {
        let (season, other) = (try Self.season("2026/27"), try Self.season("2025/26"))
        let alevin = try ListSeasonRegistrationsTests.team(.alevin, "A")
        let store = IngestionStore()
        await store.seed(club: Self.club)
        await store.seed(seasons: [season, other], teams: [alevin])
        await store.seed(teamRegistrations: [try ListSeasonRegistrationsTests.registration(alevin, other.id)])

        await #expect(throws: ApplicationError.teamNotRegistered(team: "\(alevin.id)", season: "\(season.id)")) {
            _ = try await Self.useCase(store).execute(actor: Self.actor, teamID: alevin.id, seasonID: season.id)
        }
    }

    @Test("un rival nunca está inscrito (D-68): teamNotRegistered")
    func anOpponentIsNeverRegistered() async throws {
        let season = try Self.season("2026/27")
        let rival = try Team(
            id: TeamID(raw: UUID()), opponentClubID: OpponentClubID(raw: UUID()), seasonID: season.id,
            category: .alevin, letter: "A", gender: .masculino, modality: .futbol11,
            createdAt: Self.epoch, updatedAt: Self.epoch)
        let store = IngestionStore()
        await store.seed(club: Self.club)
        await store.seed(seasons: [season], teams: [rival])

        await #expect(throws: ApplicationError.teamNotRegistered(team: "\(rival.id)", season: "\(season.id)")) {
            _ = try await Self.useCase(store).execute(actor: Self.actor, teamID: rival.id, seasonID: season.id)
        }
    }
}

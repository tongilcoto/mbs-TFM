import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): `ListSeasonRegistrations` con los repositorios en memoria
/// (`D-102`; Plan R1, R1.9). Las consultas las prueba el nivel 3; aquí se prueba
/// lo que decide el caso de uso: **un elemento por equipo** con sus competiciones
/// dentro, la fila de junio con la lista vacía, el orden, y el 404 de una
/// temporada que no existe.
@Suite("ListSeasonRegistrations · D-102 · el equipo en una temporada, leído")
struct ListSeasonRegistrationsTests {

    static let epoch = Date(timeIntervalSince1970: 0)

    static func team(_ category: TeamCategory, _ letter: String?) throws -> Team {
        try Team(
            id: TeamID(raw: UUID()), opponentClubID: nil, category: category, letter: letter,
            gender: .masculino, modality: .futbol11, createdAt: epoch, updatedAt: epoch)
    }

    static func registration(
        _ team: Team, _ season: SeasonID, _ competition: CompetitionID? = nil,
        code: String? = nil, at seconds: TimeInterval = 0
    ) throws -> TeamRegistration {
        try TeamRegistration(
            id: TeamRegistrationID(raw: UUID()), team: team, seasonID: season,
            competitionID: competition, federationTeamID: code,
            createdAt: Date(timeIntervalSince1970: seconds), updatedAt: epoch)
    }

    static let club = try! Club(
        id: .init(raw: UUID()), name: "Celtic Castilla Club de Fútbol", shortName: "Celtic Castilla",
        slug: try! Slug("celtic-castilla"), federation: .rffm, createdAt: epoch, updatedAt: epoch)
    static let actor = ActorContext(clubSlug: try! Slug("celtic-castilla"))

    static func useCase(_ store: IngestionStore) -> ListSeasonRegistrations {
        ListSeasonRegistrations(
            clubs: FakeClubRepository(store: store), seasons: FakeSeasonRepository(store: store),
            teams: FakeTeamRepository(store: store),
            registrations: FakeTeamRegistrationRepository(store: store))
    }

    /// Cuatro equipos **guardados desordenados**: el Cadete B con liga y copa, el
    /// Alevín A sin competición (junio), el Cadete A y el Infantil, sin letra.
    /// Y una inscripción del Cadete A en **otra** temporada, que no sale.
    @Test("un elemento por equipo, con sus competiciones; ordenados por categoría y letra")
    func oneEntryPerTeamInOrder() async throws {
        let season = try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel("2026/27"), federationSeasonID: "22",
            createdAt: Self.epoch, updatedAt: Self.epoch)
        let other = SeasonID(raw: UUID())
        let (liga, copa, infantilLiga, cadeteALiga) =
            (CompetitionID(raw: UUID()), CompetitionID(raw: UUID()),
             CompetitionID(raw: UUID()), CompetitionID(raw: UUID()))
        let cadeteB = try Self.team(.cadete, "B")
        let alevinA = try Self.team(.alevin, "A")
        let cadeteA = try Self.team(.cadete, "A")
        let infantil = try Self.team(.infantil, nil)

        let store = IngestionStore()
        await store.seed(club: Self.club)
        await store.seed(seasons: [season], teams: [cadeteB, alevinA, cadeteA, infantil])
        await store.seed(teamRegistrations: [
            try Self.registration(cadeteB, season.id, copa, code: "900", at: 20),
            try Self.registration(alevinA, season.id),
            try Self.registration(cadeteB, season.id, liga, code: "821", at: 10),
            try Self.registration(infantil, season.id, infantilLiga, code: "333"),
            try Self.registration(cadeteA, season.id, cadeteALiga, code: "777"),
            try Self.registration(cadeteA, other, CompetitionID(raw: UUID()), code: "666"),
        ])

        let result = try await Self.useCase(store).execute(actor: Self.actor, seasonID: season.id)

        #expect(result.club == Self.club)
        #expect(result.entries == [
            SeasonRegistration(team: alevinA, seasonID: season.id, competitions: []),
            SeasonRegistration(team: infantil, seasonID: season.id, competitions: [
                RegisteredCompetition(competitionID: infantilLiga, federationTeamID: "333"),
            ]),
            SeasonRegistration(team: cadeteA, seasonID: season.id, competitions: [
                RegisteredCompetition(competitionID: cadeteALiga, federationTeamID: "777"),
            ]),
            // La liga antes que la copa: en el orden en que se inscribieron.
            SeasonRegistration(team: cadeteB, seasonID: season.id, competitions: [
                RegisteredCompetition(competitionID: liga, federationTeamID: "821"),
                RegisteredCompetition(competitionID: copa, federationTeamID: "900"),
            ]),
        ])
    }

    @Test("una temporada sin inscripciones da la lista vacía, no un error")
    func aSeasonWithoutRegistrationsIsEmpty() async throws {
        let season = try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel("2026/27"), federationSeasonID: "22",
            createdAt: Self.epoch, updatedAt: Self.epoch)
        let store = IngestionStore()
        await store.seed(club: Self.club)
        await store.seed(seasons: [season])

        let result = try await Self.useCase(store).execute(actor: Self.actor, seasonID: season.id)

        #expect(result.entries.isEmpty)
    }

    /// El id lo puso quien llama: es un dato suyo que no existe, **404**.
    @Test("una temporada que no existe es unknownSeason (404)")
    func anUnknownSeasonIsNotFound() async throws {
        let store = IngestionStore()
        await store.seed(club: Self.club)
        let missing = SeasonID(raw: UUID())

        await #expect(throws: ApplicationError.unknownSeason(id: "\(missing)")) {
            try await Self.useCase(store).execute(actor: Self.actor, seasonID: missing)
        }
    }
}

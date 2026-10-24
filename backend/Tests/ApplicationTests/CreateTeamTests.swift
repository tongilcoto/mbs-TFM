import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): `CreateTeam` con los repositorios falseados.
///
/// Lo que decide el caso de uso (`D-107`): **qué es «el mismo equipo»** —uno
/// propio con la misma categoría, letra, género y modalidad—, y entonces si se
/// crea, se inscribe o es un conflicto. Que la temporada exista, también.
@Suite("CreateTeam · §5.1 · el alta crea el equipo, o lo inscribe si ya existía (D-107)")
struct CreateTeamTests {

    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let actor = ActorContext(clubSlug: try! Slug("ejemplo"), isSystem: false)

    struct Seeded {
        let store: IngestionStore
        let thisSeason: SeasonID
        let lastSeason: SeasonID
    }

    static func seed() async throws -> Seeded {
        let store = IngestionStore()
        let this = try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel("2027/28"),
            federationSeasonID: nil, createdAt: now, updatedAt: now)
        let last = try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel("2026/27"),
            federationSeasonID: "22", createdAt: now, updatedAt: now)
        await store.seed(club: try Club(
            id: ClubID(raw: UUID()), name: "C.D. Ejemplo", shortName: "Ejemplo",
            slug: try Slug("ejemplo"), federation: .rffm, createdAt: now, updatedAt: now))
        await store.seed(seasons: [this, last])
        return Seeded(store: store, thisSeason: this.id, lastSeason: last.id)
    }

    static func useCase(_ store: IngestionStore) -> CreateTeam {
        CreateTeam(
            clubs: FakeClubRepository(store: store),
            seasons: FakeSeasonRepository(store: store),
            teams: FakeTeamRepository(store: store),
            registrations: FakeTeamRegistrationRepository(store: store),
            clock: FixedClock(instant: now),
            ids: SequentialUUIDProvider())
    }

    static func command(
        _ seasonID: SeasonID, letter: String? = "A", category: TeamCategory = .alevin
    ) -> CreateTeam.Command {
        .init(category: category, letter: letter, gender: .masculino, modality: .futbol7, seasonID: seasonID)
    }

    static func ownTeam(letter: String? = "A") throws -> Team {
        try Team(
            id: TeamID(raw: UUID()), category: .alevin, letter: letter,
            gender: .masculino, modality: .futbol7, createdAt: now, updatedAt: now)
    }

    @Test("un equipo nuevo se crea propio, sin código, e inscrito en la temporada (201)")
    func aNewTeamIsCreatedAndRegistered() async throws {
        let seeded = try await Self.seed()

        let result = try await Self.useCase(seeded.store)
            .execute(Self.command(seeded.thisSeason), actor: Self.actor)

        #expect(result.created)
        #expect(result.team.isOwn)
        #expect(result.team.federationTeamID == nil)
        #expect(result.team.seasonID == nil, "un propio no lleva temporada (D-104)")
        #expect(await seeded.store.teams.map(\.id) == [result.team.id])
        let registrations = await seeded.store.teamRegistrations
        #expect(registrations.count == 1)
        #expect(registrations.first?.teamID == result.team.id)
        #expect(registrations.first?.seasonID == seeded.thisSeason)
        #expect(registrations.first?.competitionID == nil, "la fila de junio, sin competición (D-68)")
        #expect(result.club.shortName == "Ejemplo")
    }

    /// **`D-107`**: «Alevín A» es el mismo equipo cada año. Darlo de alta en la
    /// temporada nueva no crea otro: le añade la inscripción.
    @Test("el mismo equipo en otra temporada no se duplica: se inscribe (200, D-107)")
    func anExistingTeamIsRegisteredInTheNewSeason() async throws {
        let seeded = try await Self.seed()
        let alevinA = try Self.ownTeam()
        await seeded.store.seed(teams: [alevinA])
        await seeded.store.seed(teamRegistrations: [try TeamRegistration(
            id: TeamRegistrationID(raw: UUID()), team: alevinA, seasonID: seeded.lastSeason,
            createdAt: Self.now, updatedAt: Self.now)])

        let result = try await Self.useCase(seeded.store)
            .execute(Self.command(seeded.thisSeason), actor: Self.actor)

        #expect(!result.created)
        #expect(result.team.id == alevinA.id)
        #expect(await seeded.store.teams.count == 1)
        let seasons = await seeded.store.teamRegistrations.map(\.seasonID)
        #expect(Set(seasons) == [seeded.lastSeason, seeded.thisSeason])
    }

    /// Ya inscrito en **esa** temporada, con competición o sin ella: no hay nada
    /// que hacer, y se dice. No se escribe nada.
    @Test("el mismo equipo ya inscrito en esa temporada: TEAM_ALREADY_REGISTERED, sin escribir (D-107)")
    func aTeamAlreadyRegisteredInThatSeasonIsAConflict() async throws {
        let seeded = try await Self.seed()
        let alevinA = try Self.ownTeam()
        await seeded.store.seed(teams: [alevinA])
        await seeded.store.seed(teamRegistrations: [try TeamRegistration(
            id: TeamRegistrationID(raw: UUID()), team: alevinA, seasonID: seeded.thisSeason,
            createdAt: Self.now, updatedAt: Self.now)])
        let before = await seeded.store.writes

        await #expect(throws: ApplicationError.teamAlreadyRegistered(
            team: "\(alevinA.id)", season: "\(seeded.thisSeason)")) {
            try await Self.useCase(seeded.store)
                .execute(Self.command(seeded.thisSeason), actor: Self.actor)
        }
        #expect(await seeded.store.writes == before)
    }

    /// La identidad son las cuatro: sin letra es **otro** equipo, no «cualquiera».
    @Test("sin letra es otro equipo: se crea, no se reutiliza el «Alevín A»")
    func theLetterIsPartOfTheIdentity() async throws {
        let seeded = try await Self.seed()
        let alevinA = try Self.ownTeam(letter: "A")
        await seeded.store.seed(teams: [alevinA])

        let result = try await Self.useCase(seeded.store)
            .execute(Self.command(seeded.thisSeason, letter: nil), actor: Self.actor)

        #expect(result.created)
        #expect(result.team.id != alevinA.id)
    }

    /// Un rival con la misma categoría, letra, género y modalidad **nunca** es el
    /// equipo propio: es de otro club y de una temporada (`D-104`).
    @Test("un rival con la misma identidad no se reutiliza")
    func anOpponentIsNeverReused() async throws {
        let seeded = try await Self.seed()
        let rival = try Team(
            id: TeamID(raw: UUID()), opponentClubID: OpponentClubID(raw: UUID()),
            seasonID: seeded.thisSeason, category: .alevin, letter: "A",
            gender: .masculino, modality: .futbol7, createdAt: Self.now, updatedAt: Self.now)
        await seeded.store.seed(teams: [rival])

        let result = try await Self.useCase(seeded.store)
            .execute(Self.command(seeded.thisSeason), actor: Self.actor)

        #expect(result.created)
        #expect(result.team.isOwn)
    }

    @Test("una temporada que no existe es 404, y no se escribe nada")
    func anUnknownSeasonIsNotFound() async throws {
        let seeded = try await Self.seed()
        let alien = SeasonID(raw: UUID())

        await #expect(throws: ApplicationError.unknownSeason(id: "\(alien)")) {
            try await Self.useCase(seeded.store).execute(Self.command(alien), actor: Self.actor)
        }
        #expect(await seeded.store.teams.isEmpty)
    }
}

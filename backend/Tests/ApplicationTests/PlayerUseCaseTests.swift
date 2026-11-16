import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): las cinco operaciones de datos de la plantilla (R6.6), con los
/// repositorios falseados.
///
/// Lo que deciden los casos de uso: **qué perfil** lleva la fila (`D-120`), **qué
/// se copia al perfil** (`D-122`), el orden de la lista (`D-118`), y los errores
/// que la base no da con su código (el dorsal, `D-118`, y la plantilla por
/// temporada, `D-121`, se miran antes de escribir).
@Suite("Players · R6.6 · el alta, la lista, la ficha, corregir y la baja")
struct PlayerUseCaseTests {

    /// 2026-11-15, en Madrid.
    static let now = Date(timeIntervalSince1970: 1_794_700_000)

    struct Seeded {
        let store: IngestionStore
        let cadeteA: Team
        let cadeteB: Team
        let rival: Team
        let vigente: Season
        let anterior: Season
        let archivada: Season
    }

    static func seed() async throws -> Seeded {
        let store = IngestionStore()
        func own(_ letter: String) throws -> Team {
            try Team(id: TeamID(raw: UUID()), category: .cadete, letter: letter, gender: .masculino,
                     modality: .futbol11, createdAt: now, updatedAt: now)
        }
        func season(_ label: String, archived: Bool = false) throws -> Season {
            try Season(id: SeasonID(raw: UUID()), label: try SeasonLabel(label), federationSeasonID: nil,
                       archivedAt: archived ? now : nil, createdAt: now, updatedAt: now)
        }
        let vigente = try season("2026/27")
        let anterior = try season("2025/26")
        let archivada = try season("2024/25", archived: true)
        let rival = try Team(
            id: TeamID(raw: UUID()), opponentClubID: OpponentClubID(raw: UUID()),
            seasonID: vigente.id, category: .cadete, letter: "A", gender: .masculino,
            modality: .futbol11, createdAt: now, updatedAt: now)
        let seeded = Seeded(store: store, cadeteA: try own("A"), cadeteB: try own("B"), rival: rival,
                            vigente: vigente, anterior: anterior, archivada: archivada)
        await store.seed(seasons: [vigente, anterior, archivada],
                         teams: [seeded.cadeteA, seeded.cadeteB, rival])
        return seeded
    }

    static func create(_ store: IngestionStore) -> CreatePlayer {
        CreatePlayer(
            teams: FakeTeamRepository(store: store), seasons: FakeSeasonRepository(store: store),
            players: FakePlayerRepository(store: store),
            profiles: FakePlayerProfileRepository(store: store),
            clock: FixedClock(instant: now), ids: SequentialUUIDProvider())
    }

    static func list(_ store: IngestionStore) -> ListPlayers {
        ListPlayers(teams: FakeTeamRepository(store: store), seasons: FakeSeasonRepository(store: store),
                    players: FakePlayerRepository(store: store),
                    profiles: FakePlayerProfileRepository(store: store))
    }

    static func update(_ store: IngestionStore) -> UpdatePlayer {
        UpdatePlayer(seasons: FakeSeasonRepository(store: store),
                     players: FakePlayerRepository(store: store),
                     profiles: FakePlayerProfileRepository(store: store), clock: FixedClock(instant: now))
    }

    static func delete(_ store: IngestionStore) -> DeletePlayer {
        DeletePlayer(seasons: FakeSeasonRepository(store: store),
                     players: FakePlayerRepository(store: store))
    }

    /// Un jugador nuevo en el Cadete A de la temporada en curso.
    @discardableResult
    static func newPlayer(_ s: Seeded, name: String = "Juan García", shirt: Int? = nil,
                          position: PlayerPosition? = nil, team: Team? = nil,
                          season: Season? = nil) async throws -> RosterEntry {
        try await create(s.store).execute(.init(
            teamID: (team ?? s.cadeteA).id, seasonID: (season ?? s.vigente).id,
            who: .newPlayer(fullName: name, birthYear: 2011), shirtNumber: shirt, position: position))
    }

    // ── El alta ─────────────────────────────────────────────────────────────

    @Test("un jugador nuevo crea su perfil y su fila, con el nombre en mayúsculas (D-119, D-120)")
    func newPlayerCreatesProfileAndRow() async throws {
        let s = try await Self.seed()
        let entry = try await Self.newPlayer(s, name: "  juan   garcía ", shirt: 9, position: .delantero)

        #expect(entry.profile.fullName.value == "JUAN GARCÍA")
        #expect(entry.profile.birthYear?.value == 2011)
        #expect(entry.player.teamID == s.cadeteA.id)
        #expect(entry.player.seasonID == s.vigente.id)
        #expect(entry.player.shirtNumber?.value == 9)
        #expect(entry.player.position == .delantero)
        #expect(await s.store.playerProfiles.count == 1)
        #expect(await s.store.players.count == 1)
    }

    @Test("el alta copia el dorsal y la demarcación al perfil (D-122)")
    func creatingCopiesToTheProfile() async throws {
        let s = try await Self.seed()
        let entry = try await Self.newPlayer(s, shirt: 9, position: .delantero)

        let profile = try #require(await s.store.playerProfiles.first)
        #expect(profile.lastShirtNumber?.value == 9)
        #expect(profile.lastPosition == .delantero)
        #expect(entry.profile.lastShirtNumber?.value == 9)
    }

    @Test("sin dorsal ni demarcación también se da de alta (D-118, D-120)")
    func optionalFieldsMayBeEmpty() async throws {
        let s = try await Self.seed()
        let entry = try await Self.newPlayer(s)
        #expect(entry.player.shirtNumber == nil)
        #expect(entry.player.position == nil)
    }

    /// El jugador que el club tuvo otra temporada: **solo la fila**, sin perfil
    /// nuevo, y con el nombre de su perfil (`D-120`).
    @Test("con un perfil que ya existe, solo se crea la fila (D-120)")
    func existingProfileOnlyAddsTheRow() async throws {
        let s = try await Self.seed()
        let pasado = try await Self.newPlayer(s, shirt: 7, season: s.anterior)

        let entry = try await Self.create(s.store).execute(.init(
            teamID: s.cadeteB.id, seasonID: s.vigente.id, who: .profile(pasado.profile.id),
            shirtNumber: 10, position: .defensa))

        #expect(entry.profile.id == pasado.profile.id)
        #expect(await s.store.playerProfiles.count == 1, "no hay perfil nuevo")
        #expect(await s.store.players.count == 2, "una fila por temporada")
        #expect(entry.profile.lastShirtNumber?.value == 10, "y el perfil recuerda la última (D-122)")
    }

    /// Encontrado en la R6.9: el alta no lleva foto (se sube aparte), y copiar al
    /// perfil «lo vacío» le borraba la que tenía. La fila empieza con la del perfil,
    /// como en la sincronización (`D-120`).
    @Test("con un perfil que ya existe, la fila empieza con su foto y el perfil no la pierde (D-122)")
    func existingProfileBringsItsPhoto() async throws {
        let s = try await Self.seed()
        let pasado = try await Self.newPlayer(s, season: s.anterior)
        let p = pasado.profile
        try await FakePlayerProfileRepository(store: s.store).save(PlayerProfile(
            id: p.id, fullName: p.fullName, birthYear: p.birthYear, lastShirtNumber: p.lastShirtNumber,
            lastPosition: p.lastPosition, lastPhotoKey: "club/foto.jpg", createdAt: p.createdAt,
            updatedAt: p.updatedAt))

        let entry = try await Self.create(s.store).execute(.init(
            teamID: s.cadeteA.id, seasonID: s.vigente.id, who: .profile(p.id), shirtNumber: nil, position: nil))

        #expect(entry.player.photoKey == "club/foto.jpg")
        #expect(entry.profile.lastPhotoKey == "club/foto.jpg")
    }

    @Test("un jugador nuevo empieza sin foto (D-35: se sube aparte)")
    func newPlayerHasNoPhoto() async throws {
        let entry = try await Self.newPlayer(try await Self.seed())
        #expect(entry.player.photoKey == nil && entry.profile.lastPhotoKey == nil)
    }

    @Test("un perfil que no existe en el club, 422 con el campo (§5.1)")
    func unknownProfile() async throws {
        let s = try await Self.seed()
        let unknown = PlayerProfileID(raw: UUID())
        await #expect(throws: ApplicationError.referenceNotFound(field: "profileId", id: "\(unknown)")) {
            try await Self.create(s.store).execute(.init(
                teamID: s.cadeteA.id, seasonID: s.vigente.id, who: .profile(unknown)))
        }
    }

    @Test("un equipo o una temporada que no existen, 422 con el campo (§5.1)")
    func unknownTeamOrSeason() async throws {
        let s = try await Self.seed()
        let team = TeamID(raw: UUID())
        await #expect(throws: ApplicationError.referenceNotFound(field: "teamId", id: "\(team)")) {
            try await Self.create(s.store).execute(.init(
                teamID: team, seasonID: s.vigente.id, who: .newPlayer(fullName: "Juan García", birthYear: 2011)))
        }
        let season = SeasonID(raw: UUID())
        await #expect(throws: ApplicationError.referenceNotFound(field: "seasonId", id: "\(season)")) {
            try await Self.create(s.store).execute(.init(
                teamID: s.cadeteA.id, seasonID: season, who: .newPlayer(fullName: "Juan García", birthYear: 2011)))
        }
    }

    @Test("un rival no tiene plantilla, y una temporada archivada no admite altas (§3.7, R6.3)")
    func rosterRules() async throws {
        let s = try await Self.seed()
        await #expect(throws: DomainError.teamNotOwn(team: "\(s.rival.id)")) {
            try await Self.newPlayer(s, team: s.rival)
        }
        await #expect(throws: DomainError.seasonArchived(label: "2024/25")) {
            try await Self.newPlayer(s, season: s.archivada)
        }
        #expect(await s.store.writes == 0, "y no se ha escrito nada")
    }

    @Test("un nombre que no vale, o un año posterior al en curso, 422 sin escribir nada (D-120)")
    func invalidValues() async throws {
        let s = try await Self.seed()
        await #expect(throws: DomainError.self) { try await Self.newPlayer(s, name: "Juan") }
        await #expect(throws: DomainError.invalidValue(field: "birthYear", reason: "no puede ser posterior a 2026")) {
            try await Self.create(s.store).execute(.init(
                teamID: s.cadeteA.id, seasonID: s.vigente.id,
                who: .newPlayer(fullName: "Juan García", birthYear: 2027)))
        }
        await #expect(throws: DomainError.self) { try await Self.newPlayer(s, shirt: 100) }
        #expect(await s.store.writes == 0)
    }

    @Test("un dorsal que ya tiene otro del equipo, 409 (D-118)")
    func shirtTaken() async throws {
        let s = try await Self.seed()
        try await Self.newPlayer(s, shirt: 9)
        await #expect(throws: ApplicationError.shirtNumberTaken(number: 9)) {
            try await Self.newPlayer(s, name: "Pedro López", shirt: 9)
        }
        // El mismo número en el otro equipo sí vale.
        try await Self.newPlayer(s, name: "Pedro López", shirt: 9, team: s.cadeteB)
    }

    @Test("un perfil que ya está en otro equipo de la temporada, 409 (D-121)")
    func alreadyInAnotherRoster() async throws {
        let s = try await Self.seed()
        let juan = try await Self.newPlayer(s)
        await #expect(throws: ApplicationError.playerAlreadyInRoster(
            profile: "\(juan.profile.id)", season: "\(s.vigente.id)")) {
            try await Self.create(s.store).execute(.init(
                teamID: s.cadeteB.id, seasonID: s.vigente.id, who: .profile(juan.profile.id)))
        }
    }

    @Test("dado de baja en un equipo, se le da de alta en otro (D-121)")
    func afterDeletionJoinsAnotherTeam() async throws {
        let s = try await Self.seed()
        let juan = try await Self.newPlayer(s, shirt: 9)
        try await Self.delete(s.store).execute(juan.player.id)
        let nuevo = try await Self.create(s.store).execute(.init(
            teamID: s.cadeteB.id, seasonID: s.vigente.id, who: .profile(juan.profile.id)))
        #expect(nuevo.player.teamID == s.cadeteB.id)
    }

    // ── La lista ────────────────────────────────────────────────────────────

    @Test("por dorsal, y después los que no tienen, por nombre (D-118)")
    func ordering() async throws {
        let s = try await Self.seed()
        try await Self.newPlayer(s, name: "Zoe Ruiz")
        try await Self.newPlayer(s, name: "Luis Pérez", shirt: 10)
        try await Self.newPlayer(s, name: "Ana Gil")
        try await Self.newPlayer(s, name: "Marta Sanz", shirt: 2)

        let names = try await Self.list(s.store).execute(teamID: s.cadeteA.id, seasonID: s.vigente.id)
            .map(\.profile.fullName.value)
        #expect(names == ["MARTA SANZ", "LUIS PÉREZ", "ANA GIL", "ZOE RUIZ"])
    }

    @Test("solo la de ese equipo y temporada, sin los dados de baja, y por demarcación si se pide")
    func listScope() async throws {
        let s = try await Self.seed()
        try await Self.newPlayer(s, name: "Juan García", position: .portero)
        try await Self.newPlayer(s, name: "Luis Pérez", position: .defensa)
        let baja = try await Self.newPlayer(s, name: "Ana Gil")
        try await Self.delete(s.store).execute(baja.player.id)
        try await Self.newPlayer(s, name: "Pedro López", team: s.cadeteB)
        try await Self.newPlayer(s, name: "Marta Sanz", season: s.anterior)

        let roster = try await Self.list(s.store).execute(teamID: s.cadeteA.id, seasonID: s.vigente.id)
        #expect(roster.map(\.profile.fullName.value) == ["JUAN GARCÍA", "LUIS PÉREZ"])
        let porteros = try await Self.list(s.store).execute(
            teamID: s.cadeteA.id, seasonID: s.vigente.id, position: .portero)
        #expect(porteros.map(\.profile.fullName.value) == ["JUAN GARCÍA"])
    }

    @Test("un rival da lista vacía; un equipo o temporada que no existen, 404 (§5.1)")
    func listErrors() async throws {
        let s = try await Self.seed()
        #expect(try await Self.list(s.store).execute(teamID: s.rival.id, seasonID: s.vigente.id).isEmpty)
        let team = TeamID(raw: UUID())
        await #expect(throws: ApplicationError.teamNotFound(id: "\(team)")) {
            try await Self.list(s.store).execute(teamID: team, seasonID: s.vigente.id)
        }
        let season = SeasonID(raw: UUID())
        await #expect(throws: ApplicationError.unknownSeason(id: "\(season)")) {
            try await Self.list(s.store).execute(teamID: s.cadeteA.id, seasonID: season)
        }
    }

    // ── Corregir ────────────────────────────────────────────────────────────

    static func command(name: String = "Juan García", year: Int? = 2011, shirt: Int? = 9,
                        position: PlayerPosition? = .delantero) -> UpdatePlayer.Command {
        .init(fullName: name, birthYear: year, shirtNumber: shirt, position: position)
    }

    @Test("corregir cambia el nombre y el año en el perfil, y lo de la fila (D-119)")
    func correcting() async throws {
        let s = try await Self.seed()
        let juan = try await Self.newPlayer(s, shirt: 9)
        let entry = try await Self.update(s.store).execute(
            juan.player.id, Self.command(name: "Juan García Fuente", year: 2010, shirt: 11, position: .defensa))

        #expect(entry.profile.fullName.value == "JUAN GARCÍA FUENTE")
        #expect(entry.profile.birthYear?.value == 2010)
        #expect(entry.player.shirtNumber?.value == 11)
        #expect(entry.player.position == .defensa)
        #expect(entry.profile.lastShirtNumber?.value == 11, "y el perfil recuerda la fila (D-122)")
    }

    /// El nombre es del perfil: corregirlo desde una temporada lo cambia en todas.
    @Test("corregir el nombre lo cambia también en la otra temporada (D-119)")
    func nameChangesInEverySeason() async throws {
        let s = try await Self.seed()
        let pasado = try await Self.newPlayer(s, season: s.anterior)
        let ahora = try await Self.create(s.store).execute(.init(
            teamID: s.cadeteA.id, seasonID: s.vigente.id, who: .profile(pasado.profile.id)))

        _ = try await Self.update(s.store).execute(ahora.player.id, Self.command(name: "Juan García Fuente"))

        let get = GetPlayer(players: FakePlayerRepository(store: s.store),
                            profiles: FakePlayerProfileRepository(store: s.store))
        #expect(try await get.execute(pasado.player.id).profile.fullName.value == "JUAN GARCÍA FUENTE")
    }

    /// La ficha entera: lo que llega vacío queda vacío, en la fila y en el perfil.
    @Test("el dorsal y la demarcación vacíos quedan vacíos, también en el perfil (R6.6, D-122)")
    func emptyClears() async throws {
        let s = try await Self.seed()
        let juan = try await Self.newPlayer(s, shirt: 9, position: .delantero)
        let entry = try await Self.update(s.store).execute(
            juan.player.id, Self.command(shirt: nil, position: nil))
        #expect(entry.player.shirtNumber == nil)
        #expect(entry.player.position == nil)
        #expect(entry.profile.lastShirtNumber == nil)
        #expect(entry.profile.lastPosition == nil)
    }

    @Test("el año no se puede quitar si el perfil lo tenía (D-120)")
    func birthYearCannotBeRemoved() async throws {
        let s = try await Self.seed()
        let juan = try await Self.newPlayer(s)
        await #expect(throws: DomainError.invalidValue(field: "birthYear", reason: "no se puede quitar")) {
            try await Self.update(s.store).execute(juan.player.id, Self.command(year: nil))
        }
    }

    /// Un perfil sin año lo deja la sincronización (`D-120`); corregir el dorsal no
    /// obliga a ponérselo.
    @Test("un perfil sin año se puede corregir sin ponérselo (D-120)")
    func profileWithoutYearStaysWithout() async throws {
        let s = try await Self.seed()
        let juan = try await Self.newPlayer(s)
        await s.store.save(PlayerProfile(
            id: juan.profile.id, fullName: juan.profile.fullName, birthYear: nil,
            createdAt: Self.now, updatedAt: Self.now))
        let entry = try await Self.update(s.store).execute(juan.player.id, Self.command(year: nil, shirt: 4))
        #expect(entry.profile.birthYear == nil)
        #expect(entry.player.shirtNumber?.value == 4)
    }

    @Test("corregir con el dorsal de otro, 409; con el suyo propio, no (D-118)")
    func correctingShirt() async throws {
        let s = try await Self.seed()
        try await Self.newPlayer(s, name: "Pedro López", shirt: 7)
        let juan = try await Self.newPlayer(s, shirt: 9)
        await #expect(throws: ApplicationError.shirtNumberTaken(number: 7)) {
            try await Self.update(s.store).execute(juan.player.id, Self.command(shirt: 7))
        }
        _ = try await Self.update(s.store).execute(juan.player.id, Self.command(shirt: 9))
    }

    // ── La baja, y la temporada archivada ───────────────────────────────────

    @Test("la baja quita la fila de la plantilla y deja el perfil (D-36, D-119)")
    func deleting() async throws {
        let s = try await Self.seed()
        let juan = try await Self.newPlayer(s, shirt: 9)
        try await Self.delete(s.store).execute(juan.player.id)

        #expect(try await Self.list(s.store).execute(teamID: s.cadeteA.id, seasonID: s.vigente.id).isEmpty)
        #expect(await s.store.playerProfiles.count == 1)
        // Y el dorsal queda libre.
        try await Self.newPlayer(s, name: "Pedro López", shirt: 9)
    }

    @Test("un jugador que no existe o ya está de baja, 404")
    func playerNotFound() async throws {
        let s = try await Self.seed()
        let juan = try await Self.newPlayer(s)
        try await Self.delete(s.store).execute(juan.player.id)
        await #expect(throws: ApplicationError.playerNotFound(id: "\(juan.player.id)")) {
            try await Self.delete(s.store).execute(juan.player.id)
        }
        await #expect(throws: ApplicationError.playerNotFound(id: "\(juan.player.id)")) {
            try await Self.update(s.store).execute(juan.player.id, Self.command())
        }
    }

    /// La temporada archivada es de solo lectura entera (R6.3). Se siembra la
    /// fila a mano: el alta ya no deja ponerla.
    @Test("en una temporada archivada no se corrige ni se da de baja (R6.3)")
    func archivedSeasonIsReadOnly() async throws {
        let s = try await Self.seed()
        let juan = try await Self.newPlayer(s, season: s.anterior)
        await s.store.save(try Season(
            id: s.anterior.id, label: s.anterior.label, federationSeasonID: nil, archivedAt: Self.now,
            createdAt: Self.now, updatedAt: Self.now))

        await #expect(throws: DomainError.seasonArchived(label: "2025/26")) {
            try await Self.update(s.store).execute(juan.player.id, Self.command())
        }
        await #expect(throws: DomainError.seasonArchived(label: "2025/26")) {
            try await Self.delete(s.store).execute(juan.player.id)
        }
    }
}

// ── El buscador del alta (R6.7) ──────────────────────────────────────────────

extension PlayerUseCaseTests {
    static func search(_ s: Seeded, _ query: String, team: Team? = nil) async throws
        -> [SearchPlayerProfiles.Match]
    {
        try await SearchPlayerProfiles(
            clubs: FakeClubRepository(store: s.store), teams: FakeTeamRepository(store: s.store),
            opponentClubs: FakeOpponentClubRepository(store: s.store),
            seasons: FakeSeasonRepository(store: s.store), players: FakePlayerRepository(store: s.store),
            profiles: FakePlayerProfileRepository(store: s.store)
        ).execute(try #require(PlayerSearch(query)), teamID: (team ?? s.cadeteA).id,
                  seasonID: s.vigente.id, actor: ActorContext(clubSlug: try Slug("ejemplo")))
    }

    static func withClub(_ s: Seeded) async throws -> Seeded {
        await s.store.seed(club: try Club(
            id: ClubID(raw: UUID()), name: "C.D. Ejemplo", shortName: "Ejemplo",
            slug: try Slug("ejemplo"), federation: .rffm, createdAt: now, updatedAt: now))
        return s
    }

    @Test("trae el perfil entero y su última plantilla, la de la temporada más reciente (D-120, D-122)")
    func searchBringsTheProfile() async throws {
        let s = try await Self.withClub(try await Self.seed())
        let pasado = try await Self.newPlayer(s, shirt: 7, position: .defensa, team: s.cadeteB,
                                              season: s.anterior)

        let found = try await Self.search(s, "juan gar")
        let match = try #require(found.first)
        #expect(found.count == 1)
        #expect(match.profile.id == pasado.profile.id)
        #expect(match.profile.lastShirtNumber?.value == 7)
        #expect(match.profile.lastPosition == .defensa)
        #expect(match.lastRoster?.team.team.id == s.cadeteB.id)
        #expect(match.lastRoster?.season.label.value == "2025/26")
        #expect(match.lastRoster?.team.clubShortName == "Ejemplo")
        #expect(match.otherTeamThisSeason == nil)
    }

    /// Con dos filas, la más reciente es la de la temporada más reciente, aunque
    /// se escribiera antes.
    @Test("con dos temporadas, la última plantilla es la de la más reciente")
    func lastRosterIsTheLatestSeason() async throws {
        let s = try await Self.withClub(try await Self.seed())
        let ahora = try await Self.newPlayer(s, team: s.cadeteB)
        _ = try await Self.create(s.store).execute(.init(
            teamID: s.cadeteA.id, seasonID: s.anterior.id, who: .profile(ahora.profile.id)))

        let match = try #require(try await Self.search(s, "juan").first)
        #expect(match.lastRoster?.season.id == s.vigente.id)
        #expect(match.lastRoster?.team.team.id == s.cadeteB.id)
    }

    @Test("marca al que ya está en otro equipo esta temporada, y no ofrece al de esta plantilla (D-121)")
    func otherTeamAndThisRoster() async throws {
        let s = try await Self.withClub(try await Self.seed())
        try await Self.newPlayer(s, name: "Juan García")
        try await Self.newPlayer(s, name: "Juan López", team: s.cadeteB)

        let found = try await Self.search(s, "juan")
        #expect(found.map(\.profile.fullName.value) == ["JUAN LÓPEZ"])
        #expect(found.first?.otherTeamThisSeason?.team.id == s.cadeteB.id)
    }

    @Test("un perfil sin filas sale sin última plantilla; sin coincidencias, lista vacía")
    func profileWithoutRows() async throws {
        let s = try await Self.withClub(try await Self.seed())
        await s.store.save(PlayerProfile(
            id: PlayerProfileID(raw: UUID()), fullName: try PlayerName("Ana Gil"), birthYear: nil,
            createdAt: Self.now, updatedAt: Self.now))
        let match = try #require(try await Self.search(s, "ana").first)
        #expect(match.lastRoster == nil)
        #expect(try await Self.search(s, "zzz").isEmpty)
    }

    @Test("hasta diez, por orden de nombre (D-120)")
    func upToTen() async throws {
        let s = try await Self.withClub(try await Self.seed())
        for n in ["Ana", "Bea", "Carla", "Dora", "Eva", "Fany", "Gema", "Hilda", "Inés", "Julia", "Kira"] {
            try await Self.newPlayer(s, name: "\(n) Ruiz", team: s.cadeteB)
        }
        let names = try await Self.search(s, "ruiz").map(\.profile.fullName.value)
        #expect(names.count == 10)
        #expect(names.first == "ANA RUIZ")
        #expect(!names.contains("KIRA RUIZ"))
    }
}

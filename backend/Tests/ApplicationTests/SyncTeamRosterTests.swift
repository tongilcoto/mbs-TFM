import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): sincronizar la plantilla con la federación ([D-120], R6.14), con los repositorios y la
/// federación falseados. **Solo añade**: cada jugador publicado según cómo está en el club, el resumen que lo
/// cuenta, «federado» en cada fila, la fecha en la inscripción, y los errores de antes de preguntar.
@Suite("SyncTeamRoster · D-120 · R6.14 · sincronizar la plantilla con la federación")
struct SyncTeamRosterTests {

    /// 2026-11-17, en Madrid: dentro de la temporada 2026/27.
    static let now = Date(timeIntervalSince1970: 1_794_900_000)

    /// La federación de mentira: publica la plantilla que se le dé, o falla, y apunta qué código le pidieron.
    final class RosterClient: FederationClient, @unchecked Sendable {
        var published: [FederationRosterPlayer]
        var failure: (any Error)?
        var asked: [String] = []

        init(_ names: [String], failing failure: (any Error)? = nil) {
            published = names.map { RosterClient.player($0) }
            self.failure = failure
        }

        /// Como lo publica la RFFM: «APELLIDOS, NOMBRE», y vuelto si tiene una coma.
        static func player(_ published: String) -> FederationRosterPlayer {
            let halves = published.split(separator: ",")
            let flipped = halves.count == 2
                ? "\(halves[1].trimmingCharacters(in: .whitespaces)) \(halves[0].trimmingCharacters(in: .whitespaces))"
                : nil
            return FederationRosterPlayer(publishedName: published, fullName: flipped)
        }

        func fetchTeamRoster(federationTeamID: String) async throws -> FederationTeamRoster {
            asked.append(federationTeamID)
            if let failure { throw failure }
            return FederationTeamRoster(players: published)
        }
        func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar { fatalError() }
        func fetchStandings(_ coordinate: FederationCoordinate, round: Int) async throws -> FederationStanding { fatalError() }
        func fetchScorers(_ coordinate: FederationCoordinate) async throws -> FederationScorerTable { fatalError() }
        func coordinate(fromCalendarURL url: String) throws -> FederationCoordinate { fatalError() }
    }

    struct Seeded {
        let store: IngestionStore
        let cadeteA: Team
        let cadeteB: Team
        let vigente: Season
        let anterior: Season
        let futura: Season
        let archivada: Season
        let liga: CompetitionID
    }

    static func club(_ federation: FederationCode = .rffm) throws -> Club {
        try Club(id: ClubID(raw: UUID()), name: "Celtic Castilla", shortName: "Celtic", slug: try Slug("celtic"),
                 federation: federation, createdAt: now, updatedAt: now)
    }

    /// El club con el Cadete A inscrito en la temporada en curso, en la liga, con el código «821».
    static func seed(federation: FederationCode = .rffm, code: String? = "821") async throws -> Seeded {
        let store = IngestionStore()
        func own(_ letter: String) throws -> Team {
            try Team(id: TeamID(raw: UUID()), category: .cadete, letter: letter, gender: .masculino,
                     modality: .futbol11, createdAt: now, updatedAt: now)
        }
        func season(_ label: String, archived: Bool = false) throws -> Season {
            try Season(id: SeasonID(raw: UUID()), label: try SeasonLabel(label), federationSeasonID: nil,
                       archivedAt: archived ? now : nil, createdAt: now, updatedAt: now)
        }
        let (a, b) = (try own("A"), try own("B"))
        let (vigente, anterior, futura, archivada) =
            (try season("2026/27"), try season("2025/26"), try season("2027/28"), try season("2024/25", archived: true))
        let liga = CompetitionID(raw: UUID())
        await store.seed(club: try club(federation))
        await store.seed(seasons: [vigente, anterior, futura, archivada], teams: [a, b])
        var rows = [try TeamRegistration(id: TeamRegistrationID(raw: UUID()), team: a, seasonID: vigente.id,
                                         competitionID: liga, federationTeamID: code, createdAt: now, updatedAt: now)]
        for other in [anterior, futura, archivada] {
            rows.append(try TeamRegistration(id: TeamRegistrationID(raw: UUID()), team: a, seasonID: other.id,
                                             competitionID: CompetitionID(raw: UUID()), federationTeamID: "821",
                                             createdAt: now, updatedAt: now))
        }
        await store.seed(teamRegistrations: rows)
        return Seeded(store: store, cadeteA: a, cadeteB: b, vigente: vigente, anterior: anterior, futura: futura,
                      archivada: archivada, liga: liga)
    }

    /// El diccionario de nombres de estas pruebas (`D-123`): pequeño, con las palabras que usan. El del fichero de
    /// verdad lo miran las pruebas de `Storage` (R6.19).
    static let names = CastilianNames(text: "MUÑOZ\nFERNÁNDEZ\nPÉREZ\nGARCÍA\nLÓPEZ\nMARTÍN\nJESÚS")

    static func useCase(_ store: IngestionStore, _ client: RosterClient,
                        names: CastilianNames? = names) -> SyncTeamRoster {
        SyncTeamRoster(unitOfWork: FakeUnitOfWork(store: store),
                       federations: FakeFederationClientProvider([.rffm: client]),
                       clock: FixedClock(instant: now), ids: SequentialUUIDProvider(),
                       names: FixedNameDictionary(names))
    }

    static let actor = ActorContext(clubSlug: try! Slug("celtic"))

    static func sync(_ s: Seeded, _ client: RosterClient, team: Team? = nil, season: Season? = nil)
        async throws -> RosterSyncSummary
    {
        try await useCase(s.store, client).execute(actor: actor, teamID: (team ?? s.cadeteA).id,
                                                   seasonID: (season ?? s.vigente).id)
    }

    /// Un perfil del club, con lo que guarda como ayuda (`D-122`).
    @discardableResult
    static func profile(_ s: Seeded, _ name: String, year: Int? = 2011, shirt: Int? = nil,
                        position: PlayerPosition? = nil, photo: String? = nil) async throws -> PlayerProfile {
        let profile = PlayerProfile(
            id: PlayerProfileID(raw: UUID()), fullName: try PlayerName(name),
            birthYear: try year.map { try BirthYear($0, notAfter: 2026) },
            lastShirtNumber: try shirt.map(ShirtNumber.init), lastPosition: position, lastPhotoKey: photo,
            createdAt: now, updatedAt: now)
        await s.store.save(profile)
        return profile
    }

    /// Su fila en una plantilla.
    @discardableResult
    static func row(_ s: Seeded, _ profile: PlayerProfile, team: Team, season: Season, shirt: Int? = nil,
                    deleted: Bool = false) async throws -> Player {
        let player = Player(id: PlayerID(raw: UUID()), profileID: profile.id, teamID: team.id, seasonID: season.id,
                            shirtNumber: try shirt.map(ShirtNumber.init), createdAt: now, updatedAt: now)
        await s.store.save(player)
        if deleted { await s.store.deletePlayer(player.id) }
        return player
    }

    static func roster(_ s: Seeded) async -> [Player] {
        await s.store.players.filter { $0.teamID == s.cadeteA.id && $0.seasonID == s.vigente.id }
    }

    static func profileNamed(_ s: Seeded, _ name: String) async -> [PlayerProfile] {
        await s.store.playerProfiles.filter { $0.fullName.value == name }
    }

    // ── Cada jugador publicado, según cómo está en el club ──

    @Test("uno que el club no tiene: perfil nuevo sin año, y su fila, federado")
    func newPlayer() async throws {
        let s = try await Self.seed()

        let summary = try await Self.sync(s, RosterClient(["GARCÍA LÓPEZ, JUAN"]))

        let profiles = await Self.profileNamed(s, "JUAN GARCÍA LÓPEZ")
        #expect(profiles.count == 1 && profiles.first?.birthYear == nil)
        let rows = await Self.roster(s)
        #expect(rows.count == 1 && rows.first?.profileID == profiles.first?.id)
        #expect(rows.first?.shirtNumber == nil && rows.first?.position == nil && rows.first?.photoKey == nil)
        #expect(rows.first?.federated == true && rows.first?.lastListedAt == Self.now)
        #expect(summary.added == 1 && summary.withoutBirthYear == 1 && summary.alreadyInRoster == 0)
        #expect(summary.syncedAt == Self.now)
    }

    /// «El mismo nombre», sin tildes (`sameNameKey`). Trae lo de su perfil (`D-122`), y con su año no cuenta
    /// entre los que no tienen.
    @Test("uno que casa con un perfil, sin contar tildes: su fila con el dorsal, la demarcación y la foto del perfil")
    func matchedProfile() async throws {
        let s = try await Self.seed()
        let juan = try await Self.profile(s, "Juan Garcia Lopez", shirt: 7, position: .defensa, photo: "c/juan.jpg")

        let summary = try await Self.sync(s, RosterClient(["GARCÍA LÓPEZ, JUAN"]))

        let row = try #require(await Self.roster(s).first)
        #expect(row.profileID == juan.id)
        #expect(row.shirtNumber?.value == 7 && row.position == .defensa && row.photoKey == "c/juan.jpg")
        #expect(row.federated == true)
        #expect(summary.added == 1 && summary.withoutBirthYear == 0)
        #expect(await s.store.playerProfiles.count == 1, "no crea otro perfil")
    }

    @Test("si el dorsal de su perfil ya lo tiene otro de la plantilla, llega sin dorsal (D-122)")
    func shirtTaken() async throws {
        let s = try await Self.seed()
        let marcos = try await Self.profile(s, "Marcos Díaz")
        try await Self.row(s, marcos, team: s.cadeteA, season: s.vigente, shirt: 7)
        try await Self.profile(s, "Juan García", shirt: 7)

        _ = try await Self.sync(s, RosterClient(["DÍAZ, MARCOS", "GARCÍA, JUAN"]))

        let juan = try #require(await Self.roster(s).first { $0.profileID != marcos.id })
        #expect(juan.shirtNumber == nil)
    }

    @Test("uno que casa con un perfil sin año: se añade, y cuenta entre los que no tienen año")
    func matchedWithoutYear() async throws {
        let s = try await Self.seed()
        try await Self.profile(s, "Juan García", year: nil)

        let summary = try await Self.sync(s, RosterClient(["GARCÍA, JUAN"]))

        #expect(summary.added == 1 && summary.withoutBirthYear == 1)
    }

    @Test("el que ya está en la plantilla no se añade otra vez: cuenta como que ya estaba, y queda federado")
    func alreadyInRoster() async throws {
        let s = try await Self.seed()
        let juan = try await Self.profile(s, "Juan García")
        try await Self.row(s, juan, team: s.cadeteA, season: s.vigente, shirt: 9)

        let summary = try await Self.sync(s, RosterClient(["GARCÍA, JUAN"]))

        let rows = await Self.roster(s)
        #expect(rows.count == 1 && rows.first?.shirtNumber?.value == 9, "no se toca lo que el club puso")
        #expect(rows.first?.federated == true && rows.first?.lastListedAt == Self.now)
        #expect(summary.alreadyInRoster == 1 && summary.added == 0)
    }

    @Test("el de la plantilla que la federación no publica queda no federado, y su última vez listado no cambia")
    func notListed() async throws {
        let s = try await Self.seed()
        let juan = try await Self.profile(s, "Juan García")
        let listed = Date(timeIntervalSince1970: 1_700_000_000)
        let row = Player(id: PlayerID(raw: UUID()), profileID: juan.id, teamID: s.cadeteA.id, seasonID: s.vigente.id,
                         federated: true, lastListedAt: listed, createdAt: Self.now, updatedAt: Self.now)
        await s.store.save(row)

        _ = try await Self.sync(s, RosterClient(["DÍAZ, MARCOS"]))

        let stored = try #require(await s.store.players.first { $0.id == row.id })
        #expect(stored.federated == false && stored.lastListedAt == listed)
    }

    @Test("el que el club dio de baja de esta plantilla no se vuelve a añadir (D-120)")
    func deletedInClub() async throws {
        let s = try await Self.seed()
        let juan = try await Self.profile(s, "Juan García")
        try await Self.row(s, juan, team: s.cadeteA, season: s.vigente, deleted: true)

        let summary = try await Self.sync(s, RosterClient(["GARCÍA, JUAN"]))

        #expect(await Self.roster(s).isEmpty)
        #expect(summary.deletedInClub == 1 && summary.added == 0)
    }

    @Test("el que el club tiene en otro equipo de la temporada no se añade, y el resumen dice dónde (D-121)")
    func inOtherTeam() async throws {
        let s = try await Self.seed()
        let juan = try await Self.profile(s, "Juan García")
        try await Self.row(s, juan, team: s.cadeteB, season: s.vigente)

        let summary = try await Self.sync(s, RosterClient(["GARCÍA, JUAN"]))

        #expect(await Self.roster(s).isEmpty)
        #expect(summary.inOtherTeam.map(\.profile.id) == [juan.id])
        #expect(summary.inOtherTeam.first?.team.id == s.cadeteB.id)
        #expect(summary.added == 0)
    }

    @Test("el que casa con varios perfiles: perfil nuevo, y el resumen lo nombra para revisarlo")
    func duplicateName() async throws {
        let s = try await Self.seed()
        try await Self.profile(s, "Juan García", year: 2011)
        try await Self.profile(s, "Juan García", year: 2012)

        let summary = try await Self.sync(s, RosterClient(["GARCÍA, JUAN"]))

        #expect(await Self.profileNamed(s, "JUAN GARCÍA").count == 3)
        let row = try #require(await Self.roster(s).first)
        #expect(summary.duplicateName.map(\.player.id) == [row.id])
        #expect(summary.added == 1 && summary.withoutBirthYear == 1)
    }

    /// La eñe es otra letra (R6.3): «MUNOZ» no casa con «MUÑOZ», y es un jugador nuevo.
    /// La eñe sigue siendo otra letra al casar (`D-120`, punto 4). Con un apellido que no está en el
    /// diccionario (`D-123`): con uno que está, la eñe la pone él (el test siguiente).
    @Test("la eñe no se pliega: «CANERO» no casa con «CAÑERO», que no está en el diccionario")
    func enyeIsDifferent() async throws {
        let s = try await Self.seed()
        let canero = try await Self.profile(s, "Juan Cañero")

        _ = try await Self.sync(s, RosterClient(["CANERO, JUAN"]))

        #expect(await Self.roster(s).first?.profileID != canero.id)
    }

    /// Lo que llega de la federación pasa por el diccionario antes de casar y de guardarse (`D-123`).
    @Test("el diccionario pone las tildes y eñes que quita la federación, antes de casar y de guardar (D-123)")
    func castilianSpelling() async throws {
        let s = try await Self.seed()
        let munoz = try await Self.profile(s, "Juan Muñoz")

        let summary = try await Self.sync(s, RosterClient(["MUNOZ, JUAN", "FERNANDEZ PEREZ, JORGE"]))

        let rows = await Self.roster(s)
        #expect(rows.contains { $0.profileID == munoz.id }, "«MUNOZ» casa ya con «MUÑOZ»: no sale repetido")
        #expect(await Self.profileNamed(s, "JORGE FERNÁNDEZ PÉREZ").count == 1)
        #expect(await Self.profileNamed(s, "JORGE FERNANDEZ PEREZ").isEmpty)
        #expect(summary.added == 2)
    }

    /// Sin el fichero del diccionario, la sincronización no se para (decisión 2 de R6.19): los nombres se guardan como
    /// llegan, y el resumen dice que no se encontró.
    @Test("sin diccionario, sincroniza igual, guarda los nombres como llegan y el resumen lo dice (R6.19)")
    func withoutDictionary() async throws {
        let s = try await Self.seed()

        let summary = try await Self.useCase(s.store, RosterClient(["FERNANDEZ PEREZ, JORGE"]), names: nil)
            .execute(actor: Self.actor, teamID: s.cadeteA.id, seasonID: s.vigente.id)

        #expect(summary.added == 1)
        #expect(await Self.profileNamed(s, "JORGE FERNANDEZ PEREZ").count == 1)
        #expect(summary.namesDictionary == .init(found: false, skippedLines: []))
    }

    /// Una línea mala del diccionario se salta y las demás se usan; el resumen la nombra (decisión 2 de R6.19).
    @Test("con una línea mala en el diccionario, usa las demás y el resumen la nombra (R6.19)")
    func dictionaryWithBadLine() async throws {
        let s = try await Self.seed()
        let names = CastilianNames(text: "FERNÁNDEZ\nPEREZ\nPÉREZ")

        let summary = try await Self.useCase(s.store, RosterClient(["FERNANDEZ PEREZ, JORGE"]), names: names)
            .execute(actor: Self.actor, teamID: s.cadeteA.id, seasonID: s.vigente.id)

        #expect(await Self.profileNamed(s, "JORGE FERNÁNDEZ PÉREZ").count == 1)
        #expect(summary.namesDictionary == .init(found: true, skippedLines: [
            .init(line: 2, text: "PEREZ", reason: .noMark),
        ]))
    }

    /// Con el diccionario bien, el resumen dice que se encontró y que no hay líneas malas.
    @Test("con el diccionario bien, el resumen dice que se encontró, sin líneas malas (R6.19)")
    func dictionaryFine() async throws {
        let s = try await Self.seed()

        let summary = try await Self.sync(s, RosterClient(["FERNANDEZ PEREZ, JORGE"]))

        #expect(summary.namesDictionary == .init(found: true, skippedLines: []))
    }

    @Test("un nombre que no vale no se añade, y el resumen lo da como lo escribe la federación",
          arguments: ["GARCÍA LÓPEZ JUAN", "GARC1A, JUAN", "GARCÍA, JUAN, PEDRO"])
    func invalidName(_ published: String) async throws {
        let s = try await Self.seed()

        let summary = try await Self.sync(s, RosterClient([published]))

        #expect(await Self.roster(s).isEmpty)
        #expect(summary.invalidName == [published])
        #expect(summary.added == 0)
    }

    /// Decisión 5 de R6.14: una ficha sin jugadores se acepta como verdad.
    @Test("una ficha sin jugadores: toda la plantilla queda no federada, y la fecha se pone")
    func emptyRoster() async throws {
        let s = try await Self.seed()
        let juan = try await Self.profile(s, "Juan García")
        try await Self.row(s, juan, team: s.cadeteA, season: s.vigente)

        let summary = try await Self.sync(s, RosterClient([]))

        #expect(await Self.roster(s).first?.federated == false)
        #expect(summary.added == 0 && summary.alreadyInRoster == 0)
        let registration = await s.store.teamRegistrations.first { $0.competitionID == s.liga }
        #expect(registration?.rosterSyncedAt == Self.now)
    }

    // ── La fecha, y qué ficha se pide ──

    @Test("la fecha va en la inscripción del código que se usó; con liga y copa, el de la más antigua")
    func pickTheOldestCode() async throws {
        let s = try await Self.seed()
        let copa = try TeamRegistration(id: TeamRegistrationID(raw: UUID()), team: s.cadeteA, seasonID: s.vigente.id,
                                        competitionID: CompetitionID(raw: UUID()), federationTeamID: "900",
                                        createdAt: Self.now.addingTimeInterval(60), updatedAt: Self.now)
        await s.store.seed(teamRegistrations: [copa])
        let client = RosterClient(["GARCÍA, JUAN"])

        _ = try await Self.sync(s, client)

        #expect(client.asked == ["821"])
        let rows = await s.store.teamRegistrations.filter { $0.teamID == s.cadeteA.id && $0.seasonID == s.vigente.id }
        #expect(rows.first { $0.competitionID == s.liga }?.rosterSyncedAt == Self.now)
        #expect(rows.first { $0.id == copa.id }?.rosterSyncedAt == nil)
    }

    @Test("si la federación falla, no cambia nada: ni filas, ni federado, ni fecha")
    func federationFails() async throws {
        let s = try await Self.seed()
        let juan = try await Self.profile(s, "Juan García")
        try await Self.row(s, juan, team: s.cadeteA, season: s.vigente)

        await #expect(throws: FederationError.self) {
            try await Self.sync(s, RosterClient(["DÍAZ, MARCOS"], failing: FederationError.transportFailure(url: "x", reason: "sin respuesta")))
        }
        let rows = await Self.roster(s)
        #expect(rows.count == 1 && rows.first?.federated == nil)
        #expect(await s.store.teamRegistrations.allSatisfy { $0.rosterSyncedAt == nil })
    }

    // ── Lo que no deja, antes de preguntar a la federación ──

    @Test("en una temporada que no es la en curso, SEASON_NOT_CURRENT; en la archivada, SEASON_ARCHIVED")
    func onlyTheCurrentSeason() async throws {
        let s = try await Self.seed()
        let client = RosterClient(["GARCÍA, JUAN"])
        for season in [s.anterior, s.futura] {
            await #expect(throws: DomainError.seasonNotCurrent(label: season.label.value)) {
                try await Self.sync(s, client, season: season)
            }
        }
        await #expect(throws: DomainError.seasonArchived(label: "2024/25")) {
            try await Self.sync(s, client, season: s.archivada)
        }
        #expect(client.asked.isEmpty)
    }

    @Test("si la federación del club no publica plantillas, FEDERATION_ROSTER_UNAVAILABLE")
    func federationWithoutRosters() async throws {
        let s = try await Self.seed(federation: .fcf)
        let client = RosterClient(["GARCÍA, JUAN"])

        await #expect(throws: ApplicationError.federationRosterUnavailable(federation: "fcf")) {
            try await Self.sync(s, client)
        }
    }

    @Test("un equipo sin código de la federación en la temporada, TEAM_NOT_LINKED")
    func notLinked() async throws {
        let s = try await Self.seed(code: nil)

        await #expect(throws: ApplicationError.teamNotLinked(team: "\(s.cadeteA.id)", season: "\(s.vigente.id)")) {
            try await Self.sync(s, RosterClient(["GARCÍA, JUAN"]))
        }
    }

    @Test("un equipo que no está inscrito en la temporada, teamNotRegistered")
    func notRegistered() async throws {
        let s = try await Self.seed()

        await #expect(throws: ApplicationError.teamNotRegistered(team: "\(s.cadeteB.id)", season: "\(s.vigente.id)")) {
            try await Self.sync(s, RosterClient(["GARCÍA, JUAN"]), team: s.cadeteB)
        }
    }

    // ── Lo que cambia en el alta y en corregir ──

    /// `D-120`: un alta a mano después de una sincronización sale «No federado»; antes de la primera, vacío.
    @Test("un alta a mano tras sincronizar sale no federada; antes de sincronizar, sin dato")
    func manualAfterSync() async throws {
        let s = try await Self.seed()
        let create = PlayerUseCaseTests.create(s.store)
        let before = try await create.execute(.init(teamID: s.cadeteA.id, seasonID: s.vigente.id,
                                                    who: .newPlayer(fullName: "Ana Ruiz", birthYear: 2011)))
        #expect(before.player.federated == nil)

        _ = try await Self.sync(s, RosterClient(["DÍAZ, MARCOS"]))
        let after = try await create.execute(.init(teamID: s.cadeteA.id, seasonID: s.vigente.id,
                                                   who: .newPlayer(fullName: "Eva Gil", birthYear: 2011)))

        #expect(after.player.federated == false)
    }

    @Test("corregir a un jugador no le quita federado ni su última vez listado")
    func updateKeepsFederated() async throws {
        let s = try await Self.seed()
        _ = try await Self.sync(s, RosterClient(["GARCÍA, JUAN"]))
        let row = try #require(await Self.roster(s).first)

        _ = try await PlayerUseCaseTests.update(s.store).execute(
            row.id, .init(fullName: "Juan García", birthYear: 2011, shirtNumber: 5, position: nil))

        let stored = try #require(await s.store.players.first { $0.id == row.id })
        #expect(stored.federated == true && stored.lastListedAt == Self.now)
    }
}

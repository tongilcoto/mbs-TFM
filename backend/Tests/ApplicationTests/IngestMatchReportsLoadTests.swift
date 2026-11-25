import Domain
import Foundation
import Testing

@testable import Application

/// Nivel 2 (§8.1): **la carga de un acta cerrada** (R7.12, D-138), segunda parte: los jugadores —casados por el
/// conector (`D-126`), dados de alta si faltan (`D-127`)— y la convocatoria, en la que manda el acta (`D-133`,
/// `D-132`). Y el registro de la pasada, con sus contadores y sus omitidos.
@Suite("IngestMatchReports · D-127 · D-132 · los jugadores y la convocatoria del acta")
struct IngestMatchReportsLoadTests {
    typealias T = IngestMatchReportsTests
    static let now = T.now

    // ── Andamiaje ────────────────────────────────────────────────────────────

    static func player(
        _ side: FederationReportSide, _ code: String, _ published: String, shirt: Int? = 7,
        starter: Bool = true, cameOn: Bool = false
    ) -> FederationReportPlayer {
        let halves = published.split(separator: ",")
        let flipped = halves.count == 2
            ? "\(halves[1].trimmingCharacters(in: .whitespaces)) \(halves[0].trimmingCharacters(in: .whitespaces))"
            : nil
        return FederationReportPlayer(
            side: side, federationPlayerID: code, publishedName: published, fullName: flipped,
            shirtNumber: shirt, isStarter: starter, cameOn: cameOn)
    }

    static func report(_ players: [FederationReportPlayer], home: String = "821", away: String = "900")
        -> FederationMatchReport
    {
        FederationMatchReport(
            isClosed: true, homeTeamFederationID: home, awayTeamFederationID: away, homeScore: 0, awayScore: 0,
            players: players, goals: [], cards: [], skipped: [])
    }

    /// Un perfil del club, con su fila en una plantilla si se le pide.
    @discardableResult
    static func profile(
        _ f: T.Fixture, _ name: String, code: String? = nil, team: Team? = nil, deleted: Bool = false
    ) async throws -> (profile: PlayerProfile, row: Player?) {
        let profile = PlayerProfile(
            id: PlayerProfileID(raw: UUID()), fullName: try PlayerName(name),
            birthYear: try BirthYear(2011, notAfter: 2026), federationPlayerID: code, createdAt: now, updatedAt: now)
        await f.store.save(profile)
        guard let team else { return (profile, nil) }
        let row = Player(id: PlayerID(raw: UUID()), profileID: profile.id, teamID: team.id,
                         seasonID: f.season.id, createdAt: now, updatedAt: now)
        await f.store.save(row)
        if deleted { await f.store.deletePlayer(row.id) }
        return (profile, deleted ? nil : row)
    }

    /// La plantilla del Cadete A, sincronizada ya: la carga no la sincroniza otra vez (`D-127`, punto 1).
    static func markSynced(_ f: T.Fixture, _ team: Team) async throws {
        let rows = await f.store.teamRegistrations
        for row in rows where row.teamID == team.id {
            await f.store.save(row.rosterSynced(at: now))
        }
    }

    /// Siembra, prepara el acta «1» del Cadete A contra el rival, y corre la pasada.
    static func load(
        _ f: T.Fixture, _ players: [FederationReportPlayer], client: T.ReportClient = T.ReportClient()
    ) async throws -> IngestionRun? {
        try await T.match(f, code: "1")
        client.reports["1"] = .success(report(players))
        return try await T.useCase(f, client).execute(competitionID: f.competition, actor: T.actor)
    }

    static func appearances(_ f: T.Fixture) async -> [Appearance] { await f.store.appearances }

    // ── Los jugadores (D-126, D-127) ─────────────────────────────────────────

    @Test("el de la plantilla, casado por su código: su convocatoria, con su fila y su equipo")
    func rosterPlayerByCode() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        let juan = try await Self.profile(f, "Juanito García", code: "11", team: f.cadeteA)

        let run = try await Self.load(f, [Self.player(.home, "11", "GARCÍA LÓPEZ, JUAN")])

        let appearance = try #require(await Self.appearances(f).first)
        #expect(appearance.playerID == juan.row?.id)
        #expect(appearance.teamID == f.cadeteA.id)
        #expect(await f.store.players.count == 1, "no da de alta a nadie")
        #expect(run?.matchReportPlayersAdded == 0)
    }

    @Test("el que no está en ninguna plantilla ni tiene perfil: perfil nuevo con su código y fila en el equipo del acta")
    func newPlayer() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)

        let run = try await Self.load(f, [Self.player(.home, "11", "GARCIA LOPEZ, JUAN")])

        let profile = try #require(await f.store.playerProfiles.first)
        #expect(profile.fullName.value == "JUAN GARCÍA LÓPEZ", "con las tildes del castellano (D-123)")
        #expect(profile.federationPlayerID == "11")
        #expect(profile.birthYear == nil)
        let row = try #require(await f.store.players.first)
        #expect(row.profileID == profile.id && row.teamID == f.cadeteA.id && row.seasonID == f.season.id)
        #expect(await Self.appearances(f).first?.playerID == row.id)
        #expect(run?.matchReportPlayersAdded == 1)
    }

    @Test("el que tiene perfil pero ninguna fila esta temporada: fila en el equipo del acta, con su perfil")
    func profileWithoutRow() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        let juan = try await Self.profile(f, "Juan García López")

        let run = try await Self.load(f, [Self.player(.home, "11", "GARCÍA LÓPEZ, JUAN")])

        let row = try #require(await f.store.players.first)
        #expect(row.profileID == juan.profile.id && row.teamID == f.cadeteA.id)
        #expect(await f.store.playerProfiles.first { $0.id == juan.profile.id }?.federationPlayerID == "11",
                "casado por el nombre: se le guarda el código (D-126)")
        #expect(run?.matchReportPlayersAdded == 1)
    }

    /// `D-127`, punto 4, y `D-128`: el de otro equipo del club juega de refuerzo. No se le da de alta aquí, y su
    /// convocatoria va con el equipo del acta y con su fila de siempre.
    @Test("el de otro equipo del club: refuerzo, sin alta; su convocatoria, con este equipo y su fila")
    func reinforcement() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        let juan = try await Self.profile(f, "Juan García", code: "11", team: f.cadeteB)

        let run = try await Self.load(f, [Self.player(.home, "11", "GARCÍA, JUAN")])

        #expect(await f.store.players.count == 1, "sigue con su plantilla")
        let appearance = try #require(await Self.appearances(f).first)
        #expect(appearance.playerID == juan.row?.id && appearance.teamID == f.cadeteA.id)
        #expect(run?.matchReportPlayersAdded == 0)
    }

    /// `D-127`, punto 3: si ha jugado, no está de baja. Al revés que la sincronización, que respeta la baja.
    @Test("el que el club dio de baja en este equipo: se da de alta otra vez")
    func deletedComesBack() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        let juan = try await Self.profile(f, "Juan García", code: "11", team: f.cadeteA, deleted: true)

        let run = try await Self.load(f, [Self.player(.home, "11", "GARCÍA, JUAN")])

        let row = try #require(await f.store.players.first)
        #expect(row.profileID == juan.profile.id && row.teamID == f.cadeteA.id)
        #expect(await Self.appearances(f).first?.playerID == row.id)
        #expect(run?.matchReportPlayersAdded == 1)
    }

    /// `D-138`, punto 4: con un nombre que no se lee y un código que no casa, ni alta ni convocatoria. Se apunta.
    @Test("el de nombre que no se lee y código que no casa: fuera, y apuntado con el código del acta")
    func unreadableName() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)

        let run = try await Self.load(f, [Self.player(.home, "11", "GARCIA LOPEZ JUAN")])

        #expect(await f.store.players.isEmpty)
        #expect(await f.store.playerProfiles.isEmpty)
        #expect(await Self.appearances(f).isEmpty)
        #expect(run?.skipped.map(\.reason) == [.unreadableReportPlayerName])
        #expect(run?.skipped.first?.detail.hasPrefix("1: ") == true, "\(run?.skipped ?? [])")
    }

    @Test("el de nombre que no se lee pero código que casa: se usa su perfil")
    func unreadableNameButCode() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        let juan = try await Self.profile(f, "Juan García", code: "11", team: f.cadeteA)

        let run = try await Self.load(f, [Self.player(.home, "11", "GARCIA LOPEZ JUAN")])

        #expect(await Self.appearances(f).first?.playerID == juan.row?.id)
        #expect(run?.skipped.isEmpty == true)
    }

    /// `D-138`, punto 5: del rival, nada.
    @Test("los jugadores del rival no se cargan")
    func rivalPlayersAreIgnored() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)

        _ = try await Self.load(f, [Self.player(.away, "91", "PÉREZ, ANA")])

        #expect(await f.store.playerProfiles.isEmpty)
        #expect(await f.store.players.isEmpty)
        #expect(await Self.appearances(f).isEmpty)
    }

    /// `D-138`, punto 6: entre dos equipos del club, los dos lados, cada uno con su equipo.
    @Test("entre dos equipos del club se cargan los dos lados, cada uno con su equipo")
    func bothOwnSides() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        try await Self.markSynced(f, f.cadeteB)
        try await T.match(f, code: "1", home: f.cadeteA, away: f.cadeteB)
        let client = T.ReportClient()
        client.reports["1"] = .success(Self.report(
            [Self.player(.home, "11", "GARCÍA, JUAN"), Self.player(.away, "22", "PÉREZ, ANA")],
            home: "821", away: "822"))

        _ = try await T.useCase(f, client).execute(competitionID: f.competition, actor: T.actor)

        let byTeam = Dictionary(grouping: await Self.appearances(f), by: \.teamID).mapValues(\.count)
        #expect(byTeam == [f.cadeteA.id: 1, f.cadeteB.id: 1])
        let rows = await f.store.players
        #expect(Set(rows.map(\.teamID)) == [f.cadeteA.id, f.cadeteB.id])
    }

    // ── La convocatoria (D-132, D-133) ───────────────────────────────────────

    /// `D-132`, punto 2: jugó el titular y el que entra en un cambio; los demás suplentes, «Convocado sin minutos».
    @Test("titular y el que entra, «Jugado»; el suplente que no entra, «Convocado sin minutos»; con el dorsal del acta")
    func lineupStatuses() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)

        _ = try await Self.load(f, [
            Self.player(.home, "11", "GARCÍA, JUAN", shirt: 9),
            Self.player(.home, "12", "LÓPEZ, LUIS", shirt: 14, starter: false, cameOn: true),
            Self.player(.home, "13", "MUÑOZ, PABLO", shirt: 16, starter: false),
        ])

        let profiles = await f.store.playerProfiles
        let rows = await f.store.players
        func appearance(_ code: String) async -> Appearance? {
            let profile = profiles.first { $0.federationPlayerID == code }
            let row = rows.first { $0.profileID == profile?.id }
            return await Self.appearances(f).first { $0.playerID == row?.id }
        }
        #expect(await appearance("11")?.status == .jugado)
        #expect(await appearance("12")?.status == .jugado)
        #expect(await appearance("13")?.status == .convocadoSinMinutos)
        #expect(await appearance("11")?.shirtNumber?.value == 9)
        #expect(await appearance("13")?.shirtNumber?.value == 16)
        #expect(await Self.appearances(f).allSatisfy { $0.minutes == nil }, "los minutos no se calculan (D-132)")
    }

    /// `D-133`, punto 5: en la convocatoria manda el acta. Su estado y su dorsal; los minutos del club, si jugó,
    /// se quedan. Al que el acta no trae, se le deja.
    @Test("en la convocatoria manda el acta: estado y dorsal; los minutos del club se quedan; al que no trae, se le deja")
    func reportOverridesTheLineup() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        let juan = try await Self.profile(f, "Juan García", code: "11", team: f.cadeteA)
        let luis = try await Self.profile(f, "Luis López", code: "12", team: f.cadeteA)
        let pablo = try await Self.profile(f, "Pablo Muñoz", code: "13", team: f.cadeteA)
        let match = try await T.match(f, code: "1")
        func club(_ row: Player?, _ status: AppearanceStatus, minutes: Int? = nil) async throws {
            await f.store.save(Appearance(
                id: AppearanceID(raw: UUID()), playerID: try #require(row?.id), matchID: match.id,
                teamID: f.cadeteA.id, status: status, minutes: try minutes.map(MinutesPlayed.init),
                createdAt: Self.now, updatedAt: Self.now))
        }
        try await club(juan.row, .jugado, minutes: 60)
        try await club(luis.row, .bajaMedica)
        try await club(pablo.row, .convocadoSinMinutos)
        let client = T.ReportClient()
        client.reports["1"] = .success(Self.report([
            Self.player(.home, "11", "GARCÍA, JUAN", shirt: 9),
            Self.player(.home, "12", "LÓPEZ, LUIS", shirt: 14, starter: false),
        ]))

        _ = try await T.useCase(f, client).execute(competitionID: f.competition, actor: T.actor)

        let all = await Self.appearances(f)
        #expect(all.count == 3, "ni repetidas ni borradas")
        let j = try #require(all.first { $0.playerID == juan.row?.id })
        #expect(j.status == .jugado && j.minutes?.value == 60 && j.shirtNumber?.value == 9)
        let l = try #require(all.first { $0.playerID == luis.row?.id })
        #expect(l.status == .convocadoSinMinutos && l.shirtNumber?.value == 14 && l.minutes == nil)
        #expect(all.first { $0.playerID == pablo.row?.id }?.status == .convocadoSinMinutos, "no lo trae: se deja")
    }

    // ── La plantilla que nadie sincronizó (D-127, punto 1) ───────────────────

    @Test("si nadie sincronizó la plantilla del equipo, la carga la sincroniza primero, y cuenta sus altas")
    func syncsTheRosterFirst() async throws {
        let f = try await T.seed()
        let client = T.ReportClient()
        client.rosters["821"] = FederationTeamRoster(players: [
            FederationRosterPlayer(publishedName: "GARCÍA, JUAN", fullName: "JUAN GARCÍA", federationPlayerID: "11"),
            FederationRosterPlayer(publishedName: "LÓPEZ, LUIS", fullName: "LUIS LÓPEZ", federationPlayerID: "12"),
        ])

        let run = try await Self.load(f, [Self.player(.home, "11", "GARCÍA, JUAN")], client: client)

        #expect(client.askedRosters == ["821"])
        #expect(await f.store.players.count == 2, "los dos de la ficha; el del acta ya estaba")
        #expect(await f.store.teamRegistrations.first { $0.teamID == f.cadeteA.id }?.rosterSyncedAt == Self.now)
        #expect(run?.matchReportPlayersAdded == 2)
        #expect(await Self.appearances(f).count == 1)
    }

    @Test("la plantilla ya sincronizada no se vuelve a pedir")
    func syncedRosterIsNotAskedAgain() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        let client = T.ReportClient()

        _ = try await Self.load(f, [Self.player(.home, "11", "GARCÍA, JUAN")], client: client)

        #expect(client.askedRosters.isEmpty)
    }

    /// La ficha es la de hoy (decisión 1 de R6.14): en una temporada que no es la en curso no se sincroniza, y los
    /// jugadores entran por el alta del acta (`D-138`, punto 2).
    @Test("en la temporada pasada no se sincroniza: los jugadores entran por el acta")
    func pastSeasonIsNotSynced() async throws {
        let f = try await T.seed(label: "2025/26")
        let client = T.ReportClient()

        let run = try await Self.load(f, [Self.player(.home, "11", "GARCÍA, JUAN")], client: client)

        #expect(client.askedRosters.isEmpty)
        #expect(await f.store.players.count == 1 && run?.matchReportPlayersAdded == 1)
    }

    /// Si la ficha falla, el acta se carga igual —sus jugadores entran por el alta— y la plantilla se intenta con la
    /// siguiente acta, porque sigue sin sincronizar.
    @Test("si la ficha no llega, el acta se carga igual y la plantilla queda sin sincronizar")
    func rosterFailureDoesNotBlock() async throws {
        let f = try await T.seed()
        let client = T.ReportClient()

        let run = try await Self.load(f, [Self.player(.home, "11", "GARCÍA, JUAN")], client: client)

        #expect(client.askedRosters == ["821"])
        #expect(await Self.appearances(f).count == 1)
        #expect(await f.store.teamRegistrations.first { $0.teamID == f.cadeteA.id }?.rosterSyncedAt == nil)
        #expect(run?.matchReportsLoaded == 1)
    }

    // ── El registro de la pasada (D-138, punto 3) ────────────────────────────

    @Test("la pasada deja su fila: actas cargadas, sin cerrar y fallidas, con los omitidos")
    func recordsTheRun() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        try await T.match(f, code: "1")
        try await T.match(f, code: "2")
        try await T.match(f, code: "3")
        let client = T.ReportClient()
        client.reports = [
            "1": .success(Self.report([Self.player(.home, "11", "GARCÍA, JUAN")])),
            "2": .success(T.report(closed: false)),
            "3": .failure(FederationError.transportFailure(url: "x", reason: "caída")),
        ]

        let run = try #require(try await T.useCase(f, client).execute(competitionID: f.competition, actor: T.actor))

        #expect(run.kind == .matchReports && run.outcome == .succeeded && run.roundID == nil)
        #expect(run.matchReportsLoaded == 1 && run.matchReportsNotClosed == 1 && run.matchReportsFailed == 1)
        #expect(run.skipped.map(\.reason) == [.unreadableMatchReport])
        #expect(await f.store.ingestionRuns.map(\.id) == [run.id])
    }

    @Test("en una temporada archivada no hay pasada: ni fila")
    func archivedLeavesNoRow() async throws {
        let f = try await T.seed(archived: true)

        let run = try await T.useCase(f, T.ReportClient()).execute(competitionID: f.competition, actor: T.actor)

        #expect(run == nil)
        #expect(await f.store.ingestionRuns.isEmpty)
    }
}

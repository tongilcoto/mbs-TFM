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

    static func report(
        _ players: [FederationReportPlayer], goals: [FederationReportGoal] = [], cards: [FederationReportCard] = [],
        home: String = "821", away: String = "900"
    ) -> FederationMatchReport {
        FederationMatchReport(
            isClosed: true, homeTeamFederationID: home, awayTeamFederationID: away,
            homeScore: goals.filter { $0.side == .home }.count, awayScore: goals.filter { $0.side == .away }.count,
            players: players, goals: goals, cards: cards, skipped: [])
    }

    static func goal(_ side: FederationReportSide, _ code: String, minute: Int? = 10, _ type: GoalPlayType? = nil)
        -> FederationReportGoal
    {
        FederationReportGoal(side: side, federationPlayerID: code, publishedName: "X, Y", minute: minute,
                             playType: type)
    }

    static func card(_ side: FederationReportSide, _ code: String, _ type: CardType = .amarilla,
                     secondYellow: Bool = false, minute: Int? = 30) -> FederationReportCard {
        FederationReportCard(side: side, federationPlayerID: code, publishedName: "X, Y", minute: minute,
                             type: type, isSecondYellow: secondYellow)
    }

    /// Siembra el partido «1» y corre la pasada con el acta que se le dé.
    static func load(_ f: T.Fixture, report: FederationMatchReport, home: Team? = nil, away: Team? = nil)
        async throws -> (match: Match, run: IngestionRun?)
    {
        let match = try await T.match(f, code: "1", home: home, away: away)
        let client = T.ReportClient()
        client.reports["1"] = .success(report)
        let run = try await T.useCase(f, client).execute(competitionID: f.competition, actor: T.actor)
        return (match, run)
    }

    static func rowOf(_ f: T.Fixture, code: String) async -> PlayerID? {
        let profile = await f.store.playerProfiles.first { $0.federationPlayerID == code }
        return await f.store.players.first { $0.profileID == profile?.id }?.id
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

    /// `D-37`: el equipo es identidad de la fila de la convocatoria. Si el club lo apuntó con el otro equipo del club
    /// y el acta lo trae con este, la fila se rehace: una sola, con el equipo del acta.
    @Test("el que el club apuntó con el otro equipo del partido: su fila se rehace con el equipo del acta")
    func appearanceWithTheOtherOwnTeamIsRebuilt() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        try await Self.markSynced(f, f.cadeteB)
        let juan = try await Self.profile(f, "Juan García", code: "11", team: f.cadeteA)
        let match = try await T.match(f, code: "1", home: f.cadeteA, away: f.cadeteB)
        let clubRow = Appearance(
            id: AppearanceID(raw: UUID()), playerID: try #require(juan.row?.id), matchID: match.id,
            teamID: f.cadeteB.id, status: .jugado, createdAt: Self.now, updatedAt: Self.now)
        await f.store.save(clubRow)
        let client = T.ReportClient()
        client.reports["1"] = .success(Self.report([Self.player(.home, "11", "GARCÍA, JUAN")], home: "821", away: "822"))

        _ = try await T.useCase(f, client).execute(competitionID: f.competition, actor: T.actor)

        let rows = await Self.appearances(f).filter { $0.playerID == juan.row?.id }
        #expect(rows.count == 1)
        #expect(rows.first?.teamID == f.cadeteA.id && rows.first?.id != clubRow.id)
    }

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


    // ── Los goles (D-131, D-133, D-137, D-138 puntos 5 y 6) ──────────────────

    @Test("los goles del club, con su goleador, su minuto y su tipo; los del rival, sin goleador; todos del acta")
    func goals() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)

        let (match, _) = try await Self.load(f, report: Self.report(
            [Self.player(.home, "11", "GARCÍA, JUAN"), Self.player(.away, "91", "PÉREZ, ANA")],
            goals: [Self.goal(.home, "11", minute: 17, .penalti), Self.goal(.home, "11", minute: 40),
                    Self.goal(.away, "91", minute: 55)]))

        let juan = await Self.rowOf(f, code: "11")
        let goals = await f.store.goals.sorted { ($0.minute?.value ?? 0) < ($1.minute?.value ?? 0) }
        #expect(goals.count == 3)
        #expect(goals.map(\.scoringTeamID) == [f.cadeteA.id, f.cadeteA.id, f.rival.id])
        #expect(goals.map(\.concedingTeamID) == [f.rival.id, f.rival.id, f.cadeteA.id])
        #expect(goals.map(\.scorer) == [juan, juan, nil], "del rival, sin goleador (D-09)")
        #expect(goals.map(\.playType) == [.penalti, nil, nil], "el normal, sin tipo (D-131)")
        #expect(goals.allSatisfy { $0.fromReport && $0.matchID == match.id })
    }

    /// `D-138`, punto 5: el gol en propia puerta del rival suma al club, sin goleador; el de uno del club suma al
    /// rival, a su nombre.
    @Test("en propia puerta: el del rival, gol del club sin goleador; el del club, gol del rival a su nombre")
    func ownGoals() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)

        _ = try await Self.load(f, report: Self.report(
            [Self.player(.home, "11", "GARCÍA, JUAN"), Self.player(.away, "91", "PÉREZ, ANA")],
            goals: [Self.goal(.home, "91", minute: 5, .enPropiaPuerta), Self.goal(.away, "11", minute: 60, .enPropiaPuerta)]))

        let juan = await Self.rowOf(f, code: "11")
        let goals = await f.store.goals.sorted { ($0.minute?.value ?? 0) < ($1.minute?.value ?? 0) }
        #expect(goals.map(\.scoringTeamID) == [f.cadeteA.id, f.rival.id])
        #expect(goals.map(\.scorer) == [nil, juan])
        #expect(goals.allSatisfy { $0.playType == .enPropiaPuerta })
    }

    /// `D-138`, punto 6: entre dos equipos del club, el gol en propia puerta va a nombre del que lo mete.
    @Test("entre dos equipos del club, la propia puerta va a nombre del que la mete, del que encaja")
    func ownGoalBetweenOwnTeams() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        try await Self.markSynced(f, f.cadeteB)

        _ = try await Self.load(f, report: Self.report(
            [Self.player(.home, "11", "GARCÍA, JUAN"), Self.player(.away, "22", "PÉREZ, ANA")],
            goals: [Self.goal(.home, "22", .enPropiaPuerta), Self.goal(.away, "22", minute: 70)],
            home: "821", away: "822"), home: f.cadeteA, away: f.cadeteB)

        let ana = await Self.rowOf(f, code: "22")
        let goals = await f.store.goals.sorted { ($0.minute?.value ?? 0) < ($1.minute?.value ?? 0) }
        #expect(goals.map(\.scoringTeamID) == [f.cadeteA.id, f.cadeteB.id])
        #expect(goals.map(\.scorer) == [ana, ana])
        #expect(goals.first?.scorerTeamID == f.cadeteB.id)
    }

    /// `D-133`, punto 5, y `D-137`, punto 1: el mismo gol que ya apuntó el club (equipo, goleador y minuto) no se
    /// repite: pasa a ser del acta, con el desglose y el comentario del club.
    @Test("el gol que ya apuntó el club no se repite: pasa a ser del acta con su desglose y su comentario")
    func clubGoalIsKept() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        let juan = try await Self.profile(f, "Juan García", code: "11", team: f.cadeteA)
        let match = try await T.match(f, code: "1")
        let club = Goal(
            id: GoalID(raw: UUID()), matchID: match.id, scoringTeamID: f.cadeteA.id, concedingTeamID: f.rival.id,
            scorer: juan.row?.id, minute: try MatchMinute(40), zone: .areaChica, comment: try EntryComment.make("golazo"),
            createdAt: Self.now, updatedAt: Self.now)
        await f.store.save(club)
        let client = T.ReportClient()
        client.reports["1"] = .success(Self.report(
            [Self.player(.home, "11", "GARCÍA, JUAN")],
            goals: [Self.goal(.home, "11", minute: 40), Self.goal(.home, "11", minute: 41)]))

        _ = try await T.useCase(f, client).execute(competitionID: f.competition, actor: T.actor)

        let goals = await f.store.goals
        #expect(goals.count == 2, "el del minuto 40 no se repite; el del 41 es otro")
        let kept = try #require(goals.first { $0.id == club.id })
        #expect(kept.fromReport && kept.zone == .areaChica && kept.comment?.value == "golazo")
        #expect(goals.allSatisfy { $0.fromReport })
    }

    /// Con otro minuto no es el mismo: se queda repetido y lo borra el club, que puede porque no es del acta
    /// (`D-133`, lo que se asume; `D-137`, punto 3).
    /// `D-131`: el acta solo dice si es penalti o en propia puerta. Si no dice nada, el tipo que puso el club se queda.
    @Test("el gol que ya apuntó el club, sin tipo en el acta, conserva el tipo del club")
    func clubGoalKeepsItsPlayType() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        let juan = try await Self.profile(f, "Juan García", code: "11", team: f.cadeteA)
        let match = try await T.match(f, code: "1")
        let club = Goal(id: GoalID(raw: UUID()), matchID: match.id, scoringTeamID: f.cadeteA.id,
                        concedingTeamID: f.rival.id, scorer: juan.row?.id, minute: try MatchMinute(40),
                        playType: .trasCorner, createdAt: Self.now, updatedAt: Self.now)
        await f.store.save(club)
        let client = T.ReportClient()
        client.reports["1"] = .success(Self.report([Self.player(.home, "11", "GARCÍA, JUAN")],
                                                   goals: [Self.goal(.home, "11", minute: 40)]))

        _ = try await T.useCase(f, client).execute(competitionID: f.competition, actor: T.actor)

        let kept = try #require(await f.store.goals.first { $0.id == club.id })
        #expect(kept.fromReport && kept.playType == .trasCorner)
    }

    @Test("con otro minuto, el del club se queda como del club, y el del acta entra aparte")
    func otherMinuteIsAnotherGoal() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        let juan = try await Self.profile(f, "Juan García", code: "11", team: f.cadeteA)
        let match = try await T.match(f, code: "1")
        let club = Goal(id: GoalID(raw: UUID()), matchID: match.id, scoringTeamID: f.cadeteA.id,
                        concedingTeamID: f.rival.id, scorer: juan.row?.id, minute: try MatchMinute(39),
                        createdAt: Self.now, updatedAt: Self.now)
        await f.store.save(club)
        let client = T.ReportClient()
        client.reports["1"] = .success(Self.report([Self.player(.home, "11", "GARCÍA, JUAN")],
                                                   goals: [Self.goal(.home, "11", minute: 40)]))

        _ = try await T.useCase(f, client).execute(competitionID: f.competition, actor: T.actor)

        let goals = await f.store.goals
        #expect(goals.count == 2)
        #expect(goals.first { $0.id == club.id }?.fromReport == false)
    }

    /// `D-138`, punto 4: el gol del jugador que no se cargó entra sin goleador.
    @Test("el gol de un jugador que no se pudo cargar entra sin goleador")
    func goalOfUnreadablePlayer() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)

        _ = try await Self.load(f, report: Self.report(
            [Self.player(.home, "11", "GARCIA JUAN")], goals: [Self.goal(.home, "11")]))

        let goal = try #require(await f.store.goals.first)
        #expect(goal.scoringTeamID == f.cadeteA.id && goal.scorer == nil)
    }

    // ── Las tarjetas (D-131, D-133, D-136, D-137) ────────────────────────────

    @Test("las tarjetas del club, con su jugador, su equipo, su tipo y su minuto; las del rival, no; todas del acta")
    func cards() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)

        _ = try await Self.load(f, report: Self.report(
            [Self.player(.home, "11", "GARCÍA, JUAN"), Self.player(.home, "12", "LÓPEZ, LUIS"),
             Self.player(.away, "91", "PÉREZ, ANA")],
            cards: [Self.card(.home, "11", minute: 20), Self.card(.home, "12", .roja, secondYellow: true, minute: 70),
                    Self.card(.away, "91", .roja)]))

        let cards = await f.store.cards.sorted { ($0.minute?.value ?? 0) < ($1.minute?.value ?? 0) }
        #expect(cards.count == 2, "la del rival no se apunta (D-136)")
        #expect(cards.map(\.playerID) == [await Self.rowOf(f, code: "11"), await Self.rowOf(f, code: "12")])
        #expect(cards.map(\.type) == [.amarilla, .roja])
        #expect(cards.map(\.isSecondYellow) == [false, true])
        #expect(cards.allSatisfy { $0.teamID == f.cadeteA.id && $0.fromReport })
    }

    /// La misma tarjeta que ya apuntó el club (jugador y tipo) no se repite: pasa a ser del acta, con su comentario;
    /// el minuto y si es por doble amarilla, los del acta (`D-136`, punto 4).
    @Test("la tarjeta que ya apuntó el club no se repite: pasa a ser del acta con su comentario y el minuto del acta")
    func clubCardIsKept() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        let juan = try await Self.profile(f, "Juan García", code: "11", team: f.cadeteA)
        let match = try await T.match(f, code: "1")
        let club = Card(id: CardID(raw: UUID()), playerID: try #require(juan.row?.id), matchID: match.id,
                        teamID: f.cadeteA.id, type: .amarilla, minute: try MatchMinute(25),
                        comment: try EntryComment.make("protestar"), createdAt: Self.now, updatedAt: Self.now)
        await f.store.save(club)
        let client = T.ReportClient()
        client.reports["1"] = .success(Self.report([Self.player(.home, "11", "GARCÍA, JUAN")],
                                                   cards: [Self.card(.home, "11", minute: 27)]))

        _ = try await T.useCase(f, client).execute(competitionID: f.competition, actor: T.actor)

        let cards = await f.store.cards
        #expect(cards.count == 1)
        let kept = try #require(cards.first)
        #expect(kept.id == club.id && kept.fromReport && kept.minute?.value == 27 && kept.comment?.value == "protestar")
    }

    /// La primera amarilla de una doble no es una sanción aparte (`D-45`, `D-131` punto 3). Si el club la apuntó
    /// suelta y el acta trae la roja por doble amarilla, su fila se convierte en esa roja: no quedan las dos.
    @Test("si el club apuntó la primera amarilla y el acta trae la doble, su fila pasa a ser la roja del acta")
    func clubYellowBecomesTheSecondYellowRed() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        let juan = try await Self.profile(f, "Juan García", code: "11", team: f.cadeteA)
        let match = try await T.match(f, code: "1")
        let club = Card(id: CardID(raw: UUID()), playerID: try #require(juan.row?.id), matchID: match.id,
                        teamID: f.cadeteA.id, type: .amarilla, minute: try MatchMinute(25),
                        comment: try EntryComment.make("primera"), createdAt: Self.now, updatedAt: Self.now)
        await f.store.save(club)
        let client = T.ReportClient()
        client.reports["1"] = .success(Self.report(
            [Self.player(.home, "11", "GARCÍA, JUAN")], cards: [Self.card(.home, "11", .roja, secondYellow: true, minute: 70)]))

        _ = try await T.useCase(f, client).execute(competitionID: f.competition, actor: T.actor)

        let cards = await f.store.cards
        #expect(cards.count == 1)
        let red = try #require(cards.first)
        #expect(red.id == club.id && red.type == .roja && red.isSecondYellow && red.minute?.value == 70)
        #expect(red.fromReport && red.comment?.value == "primera")
    }

    @Test("la tarjeta de un jugador que no se pudo cargar no se carga")
    func cardOfUnreadablePlayer() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)

        _ = try await Self.load(f, report: Self.report([Self.player(.home, "11", "GARCIA JUAN")],
                                                       cards: [Self.card(.home, "11")]))

        #expect(await f.store.cards.isEmpty)
    }

    // ── La copia del acta y la marca (D-133 punto 3, D-134) ──────────────────

    @Test("la carga deja en el partido la copia del acta, con la fecha y la convocatoria tal como llegó")
    func leavesTheCopy() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)

        let (match, _) = try await Self.load(f, report: Self.report([
            Self.player(.home, "11", "GARCÍA, JUAN"), Self.player(.home, "12", "LÓPEZ, LUIS", starter: false),
        ]))

        let copy = try #require(await f.store.reportCopies[match.id])
        #expect(copy.loadedAt == Self.now)
        #expect(copy.lineup.map(\.status) == [.jugado, .convocadoSinMinutos])
        #expect(copy.lineup.map(\.playerID) == [await Self.rowOf(f, code: "11"), await Self.rowOf(f, code: "12")])
        #expect(copy.lineup.allSatisfy { $0.teamID == f.cadeteA.id })
    }

    /// `D-133`, punto 3: una vez cargada, el partido queda marcado y no se vuelve a leer.
    @Test("el acta cargada no se vuelve a pedir en la pasada siguiente")
    func loadedIsNotAskedAgain() async throws {
        let f = try await T.seed()
        try await Self.markSynced(f, f.cadeteA)
        try await T.match(f, code: "1")
        let client = T.ReportClient()
        client.reports["1"] = .success(Self.report([Self.player(.home, "11", "GARCÍA, JUAN")]))

        _ = try await T.useCase(f, client).execute(competitionID: f.competition, actor: T.actor)
        let second = try await T.useCase(f, client).execute(competitionID: f.competition, actor: T.actor)

        #expect(client.asked == ["1"])
        #expect(second?.matchReportsLoaded == 0)
    }

    /// `D-133`, punto 2: si la federación falla o el acta no es de ese partido, nada, ni la marca: se vuelve a pedir.
    @Test("el acta que falla no deja marca: se vuelve a pedir")
    func failedLeavesNoMark() async throws {
        let f = try await T.seed()
        let match = try await T.match(f, code: "1")
        let client = T.ReportClient()
        client.reports["1"] = .success(Self.report([], home: "999"))

        _ = try await T.useCase(f, client).execute(competitionID: f.competition, actor: T.actor)

        #expect(await f.store.reportCopies[match.id] == nil)
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

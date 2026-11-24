import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): la cabecera del acta y las cinco operaciones de la convocatoria
/// (R7.6), con los repositorios falseados.
///
/// Lo que deciden los casos de uso: **de qué partido** hay acta (`D-130`), **con qué
/// equipo** juega cada uno (`D-128`), **qué estado** se apunta según la hora
/// (`D-133`, `D-134`), los minutos (`D-42`, R7.3 P4), la temporada archivada, el 409
/// y **lo que ha cambiado el club** del acta cargada (`D-134`, punto 4).
@Suite("Appearances · R7.6 · la cabecera del acta y la convocatoria")
struct AppearanceUseCaseTests {

    static let epoch = Date(timeIntervalSince1970: 0)
    static let actor = ListSeasonRegistrationsTests.actor
    static let club = ListSeasonRegistrationsTests.club
    static func instant(_ iso: String) -> Date { try! Date(iso, strategy: .iso8601) }
    /// El partido es el 4 de octubre a las 18:00 de Madrid (16:00 UTC).
    static let before = instant("2025-10-04T15:00:00Z")
    static let after = instant("2025-10-04T17:00:00Z")

    struct Seeded {
        let store: IngestionStore
        let cadeteA: Team
        let cadeteB: Team
        let rival: Team
        let match: Match
        /// Entre dos rivales: sin acta (`D-130`).
        let rivals: Match
        let archivedMatch: Match
        let juan: Player
        let pedro: Player
        /// Del Cadete B: un refuerzo para el A (`D-128`).
        let refuerzo: Player
        /// De la temporada pasada.
        let deOtraTemporada: Player
        let enArchivada: Player
    }

    static func seed() async throws -> Seeded {
        let store = IngestionStore()
        let (vigente, pasada, archivada) = (SeasonID(raw: UUID()), SeasonID(raw: UUID()), SeasonID(raw: UUID()))
        let seasons = [
            try Season(id: vigente, label: try SeasonLabel("2025/26"), federationSeasonID: nil,
                       createdAt: epoch, updatedAt: epoch),
            try Season(id: pasada, label: try SeasonLabel("2024/25"), federationSeasonID: nil,
                       createdAt: epoch, updatedAt: epoch),
            try Season(id: archivada, label: try SeasonLabel("2023/24"), federationSeasonID: nil,
                       archivedAt: epoch, createdAt: epoch, updatedAt: epoch),
        ]
        let (liga, ligaArchivada) = (CompetitionID(raw: UUID()), CompetitionID(raw: UUID()))
        func competition(_ id: CompetitionID, _ season: SeasonID) throws -> Competition {
            try Competition(id: id, seasonID: season, modality: .futbol11, gender: .masculino,
                            federationCompetitionID: "1", federationGroupID: "\(id)", ageCategory: .cadete,
                            divisionLabel: "PRIMERA", groupLabel: "Grupo 1", createdAt: epoch, updatedAt: epoch)
        }
        let rivalClub = try OpponentClub(
            id: OpponentClubID(raw: UUID()), name: "C.D. GALAPAGAR", shortName: "Galapagar",
            slug: try Slug("c-d-galapagar"), createdAt: epoch, updatedAt: epoch)
        func own(_ letter: String) throws -> Team {
            try Team(id: TeamID(raw: UUID()), category: .cadete, letter: letter, gender: .masculino,
                     modality: .futbol11, createdAt: epoch, updatedAt: epoch)
        }
        func rival(_ letter: String) throws -> Team {
            try Team(id: TeamID(raw: UUID()), opponentClubID: rivalClub.id, seasonID: vigente, category: .cadete,
                     letter: letter, gender: .masculino, modality: .futbol11, createdAt: epoch, updatedAt: epoch)
        }
        let (a, b, r, r2) = (try own("A"), try own("B"), try rival("B"), try rival("C"))
        let round = try Round(id: RoundID(raw: UUID()), competitionID: liga, number: 1,
                              startDate: ListMatchesTests.day("2025-10-04"), endDate: ListMatchesTests.day("2025-10-05"),
                              createdAt: epoch, updatedAt: epoch)
        let archivedRound = try Round(id: RoundID(raw: UUID()), competitionID: ligaArchivada, number: 1,
                                      startDate: ListMatchesTests.day("2023-10-04"),
                                      endDate: ListMatchesTests.day("2023-10-04"), createdAt: epoch, updatedAt: epoch)
        func match(_ round: Round, _ date: String, _ home: Team, _ away: Team) throws -> Match {
            try Match(id: MatchID(raw: UUID()), competitionID: round.competitionID, roundID: round.id,
                      kickoff: Kickoff(date: ListMatchesTests.day(date), time: WallClockTime(hour: 18, minute: 0)),
                      homeTeamID: home.id, awayTeamID: away.id, status: .programado, createdAt: epoch,
                      updatedAt: epoch)
        }
        let partido = try match(round, "2025-10-04", a, r)
        let entreRivales = try match(round, "2025-10-04", r2, r)
        let archivado = try match(archivedRound, "2023-10-04", a, r)
        func player(_ team: Team, _ season: SeasonID) -> Player {
            Player(id: PlayerID(raw: UUID()), profileID: PlayerProfileID(raw: UUID()), teamID: team.id,
                   seasonID: season, createdAt: epoch, updatedAt: epoch)
        }
        let seeded = Seeded(
            store: store, cadeteA: a, cadeteB: b, rival: r, match: partido, rivals: entreRivales,
            archivedMatch: archivado, juan: player(a, vigente), pedro: player(a, vigente),
            refuerzo: player(b, vigente), deOtraTemporada: player(a, pasada), enArchivada: player(a, archivada))
        await store.seed(club: club)
        await store.seed(seasons: seasons,
                         competitions: [try competition(liga, vigente), try competition(ligaArchivada, archivada)],
                         rounds: [round, archivedRound], opponentClubs: [rivalClub], teams: [a, b, r, r2],
                         matches: [partido, entreRivales, archivado])
        for p in [seeded.juan, seeded.pedro, seeded.refuerzo, seeded.deOtraTemporada, seeded.enArchivada] {
            await store.save(p)
        }
        return seeded
    }

    static func repositories(_ store: IngestionStore) -> AppearanceRepositories {
        AppearanceRepositories(
            matches: FakeMatchRepository(store: store), competitions: FakeCompetitionRepository(store: store),
            seasons: FakeSeasonRepository(store: store), teams: FakeTeamRepository(store: store),
            players: FakePlayerRepository(store: store), appearances: FakeAppearanceRepository(store: store))
    }

    static func create(_ s: Seeded, at instant: Date = after) -> CreateAppearance {
        CreateAppearance(repositories: repositories(s.store), clock: FixedClock(instant: instant),
                         ids: SequentialUUIDProvider())
    }

    static func update(_ s: Seeded, at instant: Date = after) -> UpdateAppearance {
        UpdateAppearance(repositories: repositories(s.store), clock: FixedClock(instant: instant))
    }

    /// Una fila ya apuntada, sin pasar por el caso de uso.
    @discardableResult
    static func recorded(_ s: Seeded, _ player: Player, _ status: AppearanceStatus, team: Team? = nil,
                         shirt: Int? = nil, minutes: Int? = nil, match: Match? = nil) async throws -> Appearance {
        let row = Appearance(id: AppearanceID(raw: UUID()), playerID: player.id, matchID: (match ?? s.match).id,
                             teamID: (team ?? s.cadeteA).id, status: status,
                             shirtNumber: try shirt.map(ShirtNumber.init), minutes: try minutes.map(MinutesPlayed.init),
                             createdAt: epoch, updatedAt: epoch)
        await s.store.save(row)
        return row
    }

    // ── Apuntar ─────────────────────────────────────────────────────────────

    @Test("desde la hora de comienzo se apunta «Jugado» con sus minutos y su dorsal")
    func createsPlayedAfterKickoff() async throws {
        let s = try await Self.seed()
        let line = try await Self.create(s).execute(.init(
            playerID: s.juan.id, matchID: s.match.id, teamID: s.cadeteA.id, status: .jugado,
            shirtNumber: 7, minutes: 70))
        #expect(line.appearance.status == .jugado)
        #expect(line.appearance.minutes?.value == 70)
        #expect(line.appearance.shirtNumber?.value == 7)
        #expect(line.appearance.teamID == s.cadeteA.id)
        #expect(!line.changedFromReport)
        #expect(await s.store.appearances.count == 1)
    }

    @Test("antes de la hora se apunta «Convocado», y «Jugado» no (D-133)")
    func beforeKickoffOnlyTheConvocation() async throws {
        let s = try await Self.seed()
        _ = try await Self.create(s, at: Self.before).execute(.init(
            playerID: s.juan.id, matchID: s.match.id, teamID: s.cadeteA.id, status: .convocadoSinMinutos))
        await #expect(throws: DomainError.matchNotStarted) {
            try await Self.create(s, at: Self.before).execute(.init(
                playerID: s.pedro.id, matchID: s.match.id, teamID: s.cadeteA.id, status: .jugado))
        }
    }

    @Test("un refuerzo de otro equipo del club se apunta con el equipo del partido (D-128)")
    func reinforcementPlaysForTheMatchTeam() async throws {
        let s = try await Self.seed()
        let line = try await Self.create(s).execute(.init(
            playerID: s.refuerzo.id, matchID: s.match.id, teamID: s.cadeteA.id, status: .jugado))
        #expect(line.appearance.teamID == s.cadeteA.id)
    }

    @Test("un equipo que no juega el partido, o el rival, no valen (D-128)")
    func teamMustPlayTheMatch() async throws {
        let s = try await Self.seed()
        await #expect(throws: DomainError.teamNotInMatch(team: s.cadeteB.id.description)) {
            try await Self.create(s).execute(.init(
                playerID: s.juan.id, matchID: s.match.id, teamID: s.cadeteB.id, status: .jugado))
        }
        await #expect(throws: DomainError.teamNotInMatch(team: s.rival.id.description)) {
            try await Self.create(s).execute(.init(
                playerID: s.juan.id, matchID: s.match.id, teamID: s.rival.id, status: .jugado))
        }
    }

    @Test("un jugador de otra temporada no se apunta (D-128)")
    func playerMustBeOfTheSeason() async throws {
        let s = try await Self.seed()
        await #expect(throws: DomainError.playerNotInSeason(player: s.deOtraTemporada.id.description)) {
            try await Self.create(s).execute(.init(
                playerID: s.deOtraTemporada.id, matchID: s.match.id, teamID: s.cadeteA.id, status: .jugado))
        }
    }

    @Test("un partido entre dos rivales no tiene acta, y un jugador que no existe tampoco vale")
    func referencesMustExist() async throws {
        let s = try await Self.seed()
        await #expect(throws: ApplicationError.referenceNotFound(field: "matchId", id: "\(s.rivals.id)")) {
            try await Self.create(s).execute(.init(
                playerID: s.juan.id, matchID: s.rivals.id, teamID: s.cadeteA.id, status: .jugado))
        }
        let nadie = PlayerID(raw: UUID())
        await #expect(throws: ApplicationError.referenceNotFound(field: "playerId", id: "\(nadie)")) {
            try await Self.create(s).execute(.init(
                playerID: nadie, matchID: s.match.id, teamID: s.cadeteA.id, status: .jugado))
        }
    }

    @Test("en una temporada archivada no se apunta")
    func archivedSeasonIsReadOnly() async throws {
        let s = try await Self.seed()
        await #expect(throws: DomainError.seasonArchived(label: "2023/24")) {
            try await Self.create(s).execute(.init(
                playerID: s.enArchivada.id, matchID: s.archivedMatch.id, teamID: s.cadeteA.id, status: .jugado))
        }
    }

    @Test("un jugador ya convocado en el partido es un 409, y los minutos solo con «Jugado»")
    func duplicateAndMinutes() async throws {
        let s = try await Self.seed()
        try await Self.recorded(s, s.juan, .convocadoSinMinutos)
        await #expect(throws: ApplicationError.playerAlreadyConvoked(player: "\(s.juan.id)", match: "\(s.match.id)")) {
            try await Self.create(s).execute(.init(
                playerID: s.juan.id, matchID: s.match.id, teamID: s.cadeteA.id, status: .bajaMedica))
        }
        await #expect(throws: DomainError.invalidValue(field: "minutes", reason: "solo con «Jugado»")) {
            try await Self.create(s).execute(.init(
                playerID: s.pedro.id, matchID: s.match.id, teamID: s.cadeteA.id, status: .convocadoSinMinutos,
                minutes: 20))
        }
    }

    // ── Corregir y borrar ───────────────────────────────────────────────────

    @Test("pasar de «Jugado» a «Convocado sin minutos» borra los minutos (R7.3, P4)")
    func leavingPlayedClearsMinutes() async throws {
        let s = try await Self.seed()
        let row = try await Self.recorded(s, s.juan, .jugado, minutes: 60)
        let line = try await Self.update(s).execute(row.id, .init(status: .convocadoSinMinutos))
        #expect(line.appearance.status == .convocadoSinMinutos)
        #expect(line.appearance.minutes == nil)
    }

    @Test("los minutos de un «Jugado» se cambian, y el estado se queda")
    func changesMinutesOfPlayed() async throws {
        let s = try await Self.seed()
        let row = try await Self.recorded(s, s.juan, .jugado, shirt: 9, minutes: 60)
        let line = try await Self.update(s).execute(row.id, .init(minutes: 80))
        #expect(line.appearance.minutes?.value == 80)
        #expect(line.appearance.status == .jugado)
        #expect(line.appearance.shirtNumber?.value == 9)
    }

    @Test("de baja médica a sancionado no se cambia: se borra y se vuelve a apuntar (D-134)")
    func otherChangesAreRejected() async throws {
        let s = try await Self.seed()
        let row = try await Self.recorded(s, s.juan, .bajaMedica)
        await #expect(throws: DomainError.statusChangeNotAllowed(from: "baja_medica", to: "sancionado")) {
            try await Self.update(s).execute(row.id, .init(status: .sancionado))
        }
    }

    @Test("unos minutos para un convocado sin minutos no se guardan (D-42)")
    func minutesForConvokedAreRejected() async throws {
        let s = try await Self.seed()
        let row = try await Self.recorded(s, s.juan, .convocadoSinMinutos)
        await #expect(throws: DomainError.invalidValue(field: "minutes", reason: "solo con «Jugado»")) {
            try await Self.update(s).execute(row.id, .init(minutes: 30))
        }
    }

    @Test("borrar una convocatoria deja al jugador «no convocado» (D-134)")
    func deleteLeavesNoRow() async throws {
        let s = try await Self.seed()
        let row = try await Self.recorded(s, s.juan, .convocadoSinMinutos)
        try await DeleteAppearance(repositories: Self.repositories(s.store)).execute(row.id)
        #expect(await s.store.appearances.isEmpty)
        await #expect(throws: ApplicationError.appearanceNotFound(id: "\(row.id)")) {
            try await DeleteAppearance(repositories: Self.repositories(s.store)).execute(row.id)
        }
    }

    @Test("en una temporada archivada no se corrige ni se borra")
    func archivedRowsAreReadOnly() async throws {
        let s = try await Self.seed()
        let row = try await Self.recorded(s, s.enArchivada, .jugado, match: s.archivedMatch)
        await #expect(throws: DomainError.seasonArchived(label: "2023/24")) {
            try await Self.update(s).execute(row.id, .init(minutes: 10))
        }
        await #expect(throws: DomainError.seasonArchived(label: "2023/24")) {
            try await DeleteAppearance(repositories: Self.repositories(s.store)).execute(row.id)
        }
    }

    // ── Leer, y lo que ha cambiado el club ──────────────────────────────────

    static func list(_ s: Seeded) -> ListAppearances {
        ListAppearances(matches: FakeMatchRepository(store: s.store), teams: FakeTeamRepository(store: s.store),
                        players: FakePlayerRepository(store: s.store),
                        appearances: FakeAppearanceRepository(store: s.store))
    }

    @Test("la convocatoria va por dorsal, y los que no tienen al final")
    func listGoesByShirt() async throws {
        let s = try await Self.seed()
        try await Self.recorded(s, s.juan, .jugado)
        try await Self.recorded(s, s.pedro, .jugado, shirt: 10)
        try await Self.recorded(s, s.refuerzo, .jugado, shirt: 3)
        let rows = try await Self.list(s).execute(.match(s.match.id, teamID: nil))
        #expect(rows.map(\.appearance.playerID) == [s.refuerzo.id, s.pedro.id, s.juan.id])
    }

    @Test("con el acta cargada, cada fila dice si ha cambiado (D-134)")
    func listSaysWhatChanged() async throws {
        let s = try await Self.seed()
        try await Self.recorded(s, s.juan, .jugado)
        try await Self.recorded(s, s.pedro, .jugado)
        try await Self.recorded(s, s.refuerzo, .bajaMedica)
        await s.store.seed(reportCopy: MatchReportCopy(loadedAt: Self.after, lineup: [
            ReportLineupEntry(playerID: s.juan.id, teamID: s.cadeteA.id, status: .jugado),
            ReportLineupEntry(playerID: s.pedro.id, teamID: s.cadeteA.id, status: .convocadoSinMinutos),
        ]), for: s.match.id)
        let changed = Dictionary(uniqueKeysWithValues: try await Self.list(s).execute(.match(s.match.id, teamID: nil))
            .map { ($0.appearance.playerID, $0.changedFromReport) })
        #expect(changed == [s.juan.id: false, s.pedro.id: true, s.refuerzo.id: true])
    }

    @Test("sin el acta cargada, nada ha cambiado")
    func withoutReportNothingChanged() async throws {
        let s = try await Self.seed()
        try await Self.recorded(s, s.juan, .jugado)
        #expect(try await Self.list(s).execute(.match(s.match.id, teamID: nil)).map(\.changedFromReport) == [false])
    }

    @Test("el ámbito que no existe es su 404; uno sin convocatoria, lista vacía")
    func scopeNotFound() async throws {
        let s = try await Self.seed()
        let nada = MatchID(raw: UUID())
        await #expect(throws: ApplicationError.matchNotFound(id: "\(nada)")) {
            try await Self.list(s).execute(.match(nada, teamID: nil))
        }
        #expect(try await Self.list(s).execute(.match(s.match.id, teamID: nil)).isEmpty)
    }

    // ── La cabecera del acta ────────────────────────────────────────────────

    static func getMatch(_ s: Seeded) -> GetMatch {
        let store = s.store
        return GetMatch(
            clubs: FakeClubRepository(store: store), seasons: FakeSeasonRepository(store: store),
            competitions: FakeCompetitionRepository(store: store), rounds: FakeRoundRepository(store: store),
            matches: FakeMatchRepository(store: store), standingRows: FakeStandingRowRepository(store: store),
            teams: FakeTeamRepository(store: store), opponentClubs: FakeOpponentClubRepository(store: store),
            appearances: FakeAppearanceRepository(store: store))
    }

    @Test("un partido entre dos rivales no tiene acta: 404 (D-130)")
    func rivalsHaveNoReport() async throws {
        let s = try await Self.seed()
        await #expect(throws: ApplicationError.matchNotFound(id: "\(s.rivals.id)")) {
            try await Self.getMatch(s).execute(actor: Self.actor, id: s.rivals.id)
        }
    }

    @Test("sin el acta cargada, la cabecera no tiene fecha de carga ni quitados")
    func headerWithoutReport() async throws {
        let s = try await Self.seed()
        let detail = try await Self.getMatch(s).execute(actor: Self.actor, id: s.match.id)
        #expect(detail.line.match.id == s.match.id)
        #expect(detail.reportLoadedAt == nil)
        #expect(detail.removedFromReport.isEmpty)
    }

    @Test("con el acta cargada, la cabecera dice cuándo y a quién ha quitado el club (D-134)")
    func headerWithReport() async throws {
        let s = try await Self.seed()
        try await Self.recorded(s, s.juan, .jugado)
        await s.store.seed(reportCopy: MatchReportCopy(loadedAt: Self.after, lineup: [
            ReportLineupEntry(playerID: s.juan.id, teamID: s.cadeteA.id, status: .jugado),
            ReportLineupEntry(playerID: s.pedro.id, teamID: s.cadeteA.id, status: .convocadoSinMinutos),
        ]), for: s.match.id)
        let detail = try await Self.getMatch(s).execute(actor: Self.actor, id: s.match.id)
        #expect(detail.reportLoadedAt == Self.after)
        #expect(detail.removedFromReport == [
            ReportLineupEntry(playerID: s.pedro.id, teamID: s.cadeteA.id, status: .convocadoSinMinutos)])
    }
}

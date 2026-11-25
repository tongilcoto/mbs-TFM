import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): las cinco operaciones de los goles (R7.7), con los repositorios
/// falseados. Reutiliza el club de `AppearanceUseCaseTests`: el Cadete A juega en
/// casa contra un rival, a las 18:00 del 4 de octubre.
///
/// Lo que deciden los casos de uso: **quién encaja** (`D-54`), **de qué lado** es el
/// goleador (`D-52`, `D-128`), **cuándo** se apunta (`D-133`, `D-137`), la forma del
/// penalti (`D-135`) y **lo que el acta deja fijo** (`D-135`, punto 6; `D-137`).
@Suite("Goals · R7.7 · apuntar, corregir y borrar un gol")
struct GoalUseCaseTests {
    typealias A = AppearanceUseCaseTests

    static func repositories(_ store: IngestionStore) -> GoalRepositories {
        GoalRepositories(
            matches: FakeMatchRepository(store: store), competitions: FakeCompetitionRepository(store: store),
            seasons: FakeSeasonRepository(store: store), teams: FakeTeamRepository(store: store),
            players: FakePlayerRepository(store: store), goals: FakeGoalRepository(store: store))
    }

    static func create(_ s: A.Seeded, at instant: Date = A.after) -> CreateGoal {
        CreateGoal(repositories: repositories(s.store), clock: FixedClock(instant: instant),
                   ids: SequentialUUIDProvider())
    }

    static func update(_ s: A.Seeded) -> UpdateGoal {
        UpdateGoal(repositories: repositories(s.store), clock: FixedClock(instant: A.after))
    }

    /// Un gol del acta, sin pasar por el caso de uso.
    static func fromReport(_ s: A.Seeded, scorer: PlayerID?, minute: Int, playType: GoalPlayType? = nil)
        async throws -> Goal
    {
        let goal = Goal(id: GoalID(raw: UUID()), matchID: s.match.id, scoringTeamID: s.cadeteA.id,
                        concedingTeamID: s.rival.id, scorer: scorer, minute: try MatchMinute(minute),
                        playType: playType, fromReport: true, createdAt: A.epoch, updatedAt: A.epoch)
        await s.store.save(goal)
        return goal
    }

    // ── Apuntar ─────────────────────────────────────────────────────────────

    @Test("un gol con solo el equipo que marca vale, y el que encaja lo pone el servidor (D-54, D-135)")
    func bareGoal() async throws {
        let s = try await A.seed()
        let goal = try await Self.create(s).execute(matchID: s.match.id, scoringTeamID: s.rival.id, GoalFields())
        #expect(goal.concedingTeamID == s.cadeteA.id)
        #expect(goal.scorer == nil)
        #expect(!goal.fromReport)
        #expect(await s.store.goals.count == 1)
    }

    @Test("un gol con todo el desglose lo guarda entero")
    func fullGoal() async throws {
        let s = try await A.seed()
        let goal = try await Self.create(s).execute(matchID: s.match.id, scoringTeamID: s.cadeteA.id, GoalFields(
            scorer: s.juan.id, assist: s.refuerzo.id, assisted: true, minute: 33, zone: .areaChica,
            attackSide: .izquierda, shotSide: .centro, bodyPart: .pieIzquierdo, playType: .trasCorner,
            comment: "  de cabeza no, de pie  "))
        #expect(goal.scorer == s.juan.id)
        #expect(goal.assist == s.refuerzo.id)
        #expect(goal.minute?.value == 33)
        #expect(goal.attackSide == .izquierda)
        #expect(goal.shotSide == .centro)
        #expect(goal.bodyPart == .pieIzquierdo)
        #expect(goal.playType == .trasCorner)
        #expect(goal.comment?.value == "de cabeza no, de pie")
    }

    @Test("en propia puerta, el goleador es del que encaja (D-52)")
    func ownGoalScorerIsFromTheConcedingTeam() async throws {
        let s = try await A.seed()
        let goal = try await Self.create(s).execute(matchID: s.match.id, scoringTeamID: s.rival.id, GoalFields(
            scorer: s.juan.id, playType: .enPropiaPuerta))
        #expect(goal.scorer == s.juan.id)
        await #expect(throws: DomainError.invalidValue(
            field: "scorerPlayerId", reason: "el goleador de ese lado es del rival: va sin goleador")) {
            try await Self.create(s).execute(matchID: s.match.id, scoringTeamID: s.cadeteA.id, GoalFields(
                scorer: s.juan.id, playType: .enPropiaPuerta))
        }
    }

    @Test("un gol del rival no lleva goleador del club")
    func rivalGoalHasNoClubScorer() async throws {
        let s = try await A.seed()
        await #expect(throws: DomainError.invalidValue(
            field: "scorerPlayerId", reason: "el goleador de ese lado es del rival: va sin goleador")) {
            try await Self.create(s).execute(matchID: s.match.id, scoringTeamID: s.rival.id, GoalFields(scorer: s.juan.id))
        }
    }

    @Test("el goleador, del club en la temporada del partido (D-128)")
    func scorerMustBeOfTheSeason() async throws {
        let s = try await A.seed()
        await #expect(throws: DomainError.playerNotInSeason(player: s.deOtraTemporada.id.description)) {
            try await Self.create(s).execute(matchID: s.match.id, scoringTeamID: s.cadeteA.id,
                                             GoalFields(scorer: s.deOtraTemporada.id))
        }
    }

    @Test("antes de la hora, o con el acta cargada, no se apunta (D-133, D-137)")
    func notBeforeKickoffNorWithReport() async throws {
        let s = try await A.seed()
        await #expect(throws: DomainError.matchNotStarted) {
            try await Self.create(s, at: A.before).execute(matchID: s.match.id, scoringTeamID: s.cadeteA.id, GoalFields())
        }
        await s.store.seed(reportCopy: MatchReportCopy(loadedAt: A.after, lineup: []), for: s.match.id)
        await #expect(throws: DomainError.matchReportLoaded) {
            try await Self.create(s).execute(matchID: s.match.id, scoringTeamID: s.cadeteA.id, GoalFields())
        }
    }

    @Test("un equipo que no juega el partido, o un partido entre rivales, no valen")
    func teamAndMatchMustFit() async throws {
        let s = try await A.seed()
        await #expect(throws: DomainError.teamNotInMatch(team: s.cadeteB.id.description)) {
            try await Self.create(s).execute(matchID: s.match.id, scoringTeamID: s.cadeteB.id, GoalFields())
        }
        await #expect(throws: ApplicationError.referenceNotFound(field: "matchId", id: "\(s.rivals.id)")) {
            try await Self.create(s).execute(matchID: s.rivals.id, scoringTeamID: s.rival.id, GoalFields())
        }
    }

    @Test("un penalti fuera del área no vale (D-135)")
    func penaltyOutsideTheBox() async throws {
        let s = try await A.seed()
        await #expect(throws: DomainError.invalidValue(field: "zone", reason: "un penalti no se tira fuera del área")) {
            try await Self.create(s).execute(matchID: s.match.id, scoringTeamID: s.cadeteA.id,
                                             GoalFields(zone: .fueraArea, playType: .penalti))
        }
    }

    // ── Corregir y borrar ───────────────────────────────────────────────────

    @Test("completar el desglose cambia solo lo que llega")
    func updateOnlyWhatArrives() async throws {
        let s = try await A.seed()
        let goal = try await Self.create(s).execute(matchID: s.match.id, scoringTeamID: s.cadeteA.id,
                                                    GoalFields(scorer: s.juan.id, minute: 10))
        let updated = try await Self.update(s).execute(goal.id, GoalFields(zone: .areaPenalti, playType: .juegoAbierto))
        #expect(updated.scorer == s.juan.id)
        #expect(updated.minute?.value == 10)
        #expect(updated.zone == .areaPenalti)
        #expect(updated.playType == .juegoAbierto)
    }

    @Test("en un gol del acta se elige el tipo, pero no el goleador ni el penalti (D-135, punto 6)")
    func reportGoalLocks() async throws {
        let s = try await A.seed()
        let goal = try await Self.fromReport(s, scorer: s.juan.id, minute: 20)
        let updated = try await Self.update(s).execute(goal.id, GoalFields(playType: .faltaDirecta, comment: "golazo"))
        #expect(updated.playType == .faltaDirecta)
        #expect(updated.comment?.value == "golazo")
        #expect(updated.fromReport)
        await #expect(throws: DomainError.lockedByMatchReport(field: "scorerPlayerId")) {
            try await Self.update(s).execute(goal.id, GoalFields(scorer: s.pedro.id))
        }
        await #expect(throws: DomainError.lockedByMatchReport(field: "playType")) {
            try await Self.update(s).execute(goal.id, GoalFields(playType: .penalti))
        }
    }

    @Test("un gol del acta no se borra; uno del club, sí (D-137)")
    func deleteRules() async throws {
        let s = try await A.seed()
        let report = try await Self.fromReport(s, scorer: s.juan.id, minute: 20)
        await #expect(throws: DomainError.lockedByMatchReport(field: "id")) {
            try await DeleteGoal(repositories: Self.repositories(s.store)).execute(report.id)
        }
        let club = try await Self.create(s).execute(matchID: s.match.id, scoringTeamID: s.cadeteA.id, GoalFields())
        try await DeleteGoal(repositories: Self.repositories(s.store)).execute(club.id)
        #expect(await s.store.goals.map(\.id) == [report.id])
        await #expect(throws: ApplicationError.goalNotFound(id: "\(club.id)")) {
            try await DeleteGoal(repositories: Self.repositories(s.store)).execute(club.id)
        }
    }

    // ── Leer ────────────────────────────────────────────────────────────────

    static func list(_ s: A.Seeded) -> ListGoals {
        ListGoals(matches: FakeMatchRepository(store: s.store), teams: FakeTeamRepository(store: s.store),
                  players: FakePlayerRepository(store: s.store), seasons: FakeSeasonRepository(store: s.store),
                  goals: FakeGoalRepository(store: s.store))
    }

    @Test("los goles de un partido, por minuto; el ámbito que no existe, su 404")
    func listByMatch() async throws {
        let s = try await A.seed()
        let late = try await Self.create(s).execute(matchID: s.match.id, scoringTeamID: s.cadeteA.id, GoalFields(minute: 80))
        let early = try await Self.create(s).execute(matchID: s.match.id, scoringTeamID: s.rival.id, GoalFields(minute: 5))
        let page = try await Self.list(s).execute(GoalFilter(matchID: s.match.id), page: 1, perPage: 25)
        #expect(page.goals.map(\.id) == [early.id, late.id])
        #expect(page.total == 2)
        let nada = MatchID(raw: UUID())
        await #expect(throws: ApplicationError.matchNotFound(id: "\(nada)")) {
            try await Self.list(s).execute(GoalFilter(matchID: nada), page: 1, perPage: 25)
        }
    }
}

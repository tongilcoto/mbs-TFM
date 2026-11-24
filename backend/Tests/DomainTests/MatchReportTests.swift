import Foundation
import Testing
@testable import Domain

/// Nivel 1 (§8.1): las reglas del acta de un partido (R7.5), **cero I/O**: la hora
/// de comienzo, los minutos, el minuto, el comentario, los estados de la
/// convocatoria, la forma del gol y de la tarjeta, y lo que el acta deja fijo
/// (`D-128` a `D-137`).
@Suite("MatchReport · D-128 a D-137 · las reglas del acta")
struct MatchReportTests {

    // ── La hora de comienzo (D-133, punto 1) ────────────────────────────────

    /// El 18 de mayo, como guarda el dominio las fechas sin hora: a las 00:00 UTC.
    static let may18 = Date(timeIntervalSince1970: 1_779_062_400)  // 2026-05-18T00:00:00Z

    static func instant(_ iso: String) -> Date {
        try! Date(iso, strategy: .iso8601)
    }

    @Test("con hora, empieza a esa hora de Madrid", arguments: [
        ("2026-05-18T09:59:59Z", false),  // 11:59:59 en Madrid (CEST)
        ("2026-05-18T10:00:00Z", true),   // 12:00
    ])
    func startsAtItsTime(_ iso: String, _ started: Bool) {
        let kickoff = Kickoff(date: Self.may18, time: WallClockTime(hour: 12, minute: 0))
        #expect(kickoff.hasStarted(on: Self.instant(iso)) == started)
    }

    @Test("sin hora, cuenta el final del día de Madrid", arguments: [
        ("2026-05-18T21:59:59Z", false),  // 23:59:59 en Madrid
        ("2026-05-18T22:00:00Z", true),   // las 00:00 del día siguiente
    ])
    func withoutTimeStartsAtTheEndOfTheDay(_ iso: String, _ started: Bool) {
        let kickoff = Kickoff(date: Self.may18)
        #expect(kickoff.hasStarted(on: Self.instant(iso)) == started)
    }

    // ── Los minutos jugados, el minuto y el comentario ──────────────────────

    @Test("los minutos jugados van de 1 a 120 (D-134)", arguments: [1, 70, 120])
    func acceptsMinutesPlayed(_ value: Int) throws {
        #expect(try MinutesPlayed(value).value == value)
    }

    @Test("con 0 no ha jugado, y más de 120 no cabe", arguments: [0, 121, -5])
    func rejectsMinutesPlayed(_ value: Int) {
        #expect(throws: DomainError.invalidValue(field: "minutes", reason: "tienen que ir del 1 al 120")) {
            try MinutesPlayed(value)
        }
    }

    @Test("el minuto de un gol o una tarjeta va de 0 a 120", arguments: [0, 45, 120])
    func acceptsMatchMinute(_ value: Int) throws {
        #expect(try MatchMinute(value).value == value)
    }

    @Test("un minuto negativo o de más de 120 no vale", arguments: [-1, 121])
    func rejectsMatchMinute(_ value: Int) {
        #expect(throws: DomainError.invalidValue(field: "minute", reason: "tiene que ir del 0 al 120")) {
            try MatchMinute(value)
        }
    }

    @Test("el comentario se recorta, y vacío no se guarda")
    func trimsTheComment() throws {
        #expect(try EntryComment.make("  tras robo  ")?.value == "tras robo")
        #expect(try EntryComment.make("   ") == nil)
        #expect(try EntryComment.make(nil) == nil)
    }

    @Test("el comentario cabe en 500 caracteres, y no en 501")
    func limitsTheComment() throws {
        #expect(try EntryComment.make(String(repeating: "a", count: 500))?.value.count == 500)
        #expect(throws: DomainError.invalidValue(field: "comment", reason: "no puede pasar de 500 caracteres")) {
            try EntryComment.make(String(repeating: "a", count: 501))
        }
    }

    // ── El equipo y el jugador del apunte (D-128) ───────────────────────────

    static let home = TeamID(raw: UUID())
    static let away = TeamID(raw: UUID())

    @Test("el equipo del apunte es uno de los dos del partido, y propio")
    func acceptsATeamOfTheMatch() throws {
        try MatchReportRules.requireTeam(Self.home, isOwn: true, playsIn: (Self.home, Self.away))
        try MatchReportRules.requireTeam(Self.away, isOwn: true, playsIn: (Self.home, Self.away))
    }

    @Test("un equipo que no juega el partido, o un rival, no valen")
    func rejectsAnotherTeam() {
        let other = TeamID(raw: UUID())
        #expect(throws: DomainError.teamNotInMatch(team: other.description)) {
            try MatchReportRules.requireTeam(other, isOwn: true, playsIn: (Self.home, Self.away))
        }
        #expect(throws: DomainError.teamNotInMatch(team: Self.away.description)) {
            try MatchReportRules.requireTeam(Self.away, isOwn: false, playsIn: (Self.home, Self.away))
        }
    }

    @Test("el jugador es del club en la temporada del partido, en cualquier equipo")
    func requiresThePlayerInTheSeason() throws {
        let season = SeasonID(raw: UUID())
        let player = PlayerID(raw: UUID())
        try MatchReportRules.requirePlayer(player, inSeason: season, matchSeason: season)
        #expect(throws: DomainError.playerNotInSeason(player: player.description)) {
            try MatchReportRules.requirePlayer(player, inSeason: SeasonID(raw: UUID()), matchSeason: season)
        }
    }

    // ── La convocatoria (D-134) ─────────────────────────────────────────────

    @Test("antes de la hora se apunta convocado, baja médica o sanción",
          arguments: [AppearanceStatus.convocadoSinMinutos, .bajaMedica, .sancionado])
    func acceptsStatusBeforeKickoff(_ status: AppearanceStatus) throws {
        try MatchReportRules.requireCanRecord(status, started: false)
    }

    @Test("«Jugado», solo desde la hora de comienzo")
    func playedOnlyAfterKickoff() throws {
        try MatchReportRules.requireCanRecord(.jugado, started: true)
        #expect(throws: DomainError.matchNotStarted) {
            try MatchReportRules.requireCanRecord(.jugado, started: false)
        }
    }

    @Test("desde la hora, «Convocado sin minutos» y «Jugado» pasan del uno al otro")
    func switchesBetweenConvokedAndPlayed() throws {
        try MatchReportRules.requireChange(from: .convocadoSinMinutos, to: .jugado, started: true)
        try MatchReportRules.requireChange(from: .jugado, to: .convocadoSinMinutos, started: true)
    }

    @Test("quedarse en el mismo estado siempre vale",
          arguments: [AppearanceStatus.convocadoSinMinutos, .bajaMedica, .sancionado])
    func keepingTheSameStatusIsFine(_ status: AppearanceStatus) throws {
        try MatchReportRules.requireChange(from: status, to: status, started: false)
    }

    @Test("los demás cambios son borrar y volver a apuntar", arguments: [
        (AppearanceStatus.bajaMedica, AppearanceStatus.sancionado),
        (.convocadoSinMinutos, .bajaMedica),
        (.sancionado, .jugado),
        (.jugado, .bajaMedica),
    ])
    func rejectsOtherChanges(_ from: AppearanceStatus, _ to: AppearanceStatus) {
        #expect(throws: DomainError.statusChangeNotAllowed(from: from.rawValue, to: to.rawValue)) {
            try MatchReportRules.requireChange(from: from, to: to, started: true)
        }
    }

    @Test("antes de la hora, pasar a «Jugado» es que el partido no ha empezado")
    func playedBeforeKickoffIsNotStarted() {
        #expect(throws: DomainError.matchNotStarted) {
            try MatchReportRules.requireChange(from: .convocadoSinMinutos, to: .jugado, started: false)
        }
    }

    @Test("los minutos, solo con «Jugado» (D-42)")
    func minutesOnlyWhenPlayed() throws {
        let minutes = try MinutesPlayed(60)
        try MatchReportRules.requireMinutes(minutes, for: .jugado)
        try MatchReportRules.requireMinutes(nil, for: .bajaMedica)
        #expect(throws: DomainError.invalidValue(field: "minutes", reason: "solo con «Jugado»")) {
            try MatchReportRules.requireMinutes(minutes, for: .convocadoSinMinutos)
        }
    }

    @Test("pasar de «Jugado» a «Convocado sin minutos» borra los minutos (R7.3, P4)")
    func leavingPlayedClearsTheMinutes() throws {
        let minutes = try MinutesPlayed(60)
        #expect(MatchReportRules.minutes(minutes, after: .convocadoSinMinutos) == nil)
        #expect(MatchReportRules.minutes(minutes, after: .jugado) == minutes)
    }

    // ── Goles y tarjetas: cuándo se añaden (D-133, D-137) ───────────────────

    @Test("un gol o una tarjeta se añaden desde la hora y sin el acta cargada")
    func addsEntriesAfterKickoffWithoutReport() throws {
        try MatchReportRules.requireCanAddEntry(started: true, reportLoaded: false)
    }

    @Test("antes de la hora, no")
    func noEntriesBeforeKickoff() {
        #expect(throws: DomainError.matchNotStarted) {
            try MatchReportRules.requireCanAddEntry(started: false, reportLoaded: false)
        }
    }

    @Test("con el acta cargada, tampoco")
    func noEntriesWithTheReportLoaded() {
        #expect(throws: DomainError.matchReportLoaded) {
            try MatchReportRules.requireCanAddEntry(started: true, reportLoaded: true)
        }
    }

    @Test("lo que trajo el acta no se borra; lo del club, sí (D-137)")
    func reportEntriesAreNotDeleted() throws {
        try MatchReportRules.requireCanDelete(fromReport: false)
        #expect(throws: DomainError.lockedByMatchReport(field: "id")) {
            try MatchReportRules.requireCanDelete(fromReport: true)
        }
    }

    // ── La forma del gol (D-52, D-135) ──────────────────────────────────────

    static let scorer = PlayerID(raw: UUID())
    static let assistant = PlayerID(raw: UUID())

    static func goal(
        scorer: PlayerID? = scorer, assist: PlayerID? = nil, assisted: Bool = false,
        minute: Int? = nil, zone: GoalZone? = nil, shotSide: GoalSide? = nil,
        playType: GoalPlayType? = nil
    ) throws -> GoalShape {
        GoalShape(scorer: scorer, assist: assist, assisted: assisted,
                  minute: try minute.map(MatchMinute.init), zone: zone, shotSide: shotSide,
                  playType: playType)
    }

    @Test("un gol con solo el equipo que marca vale (D-135, punto 7)")
    func acceptsABareGoal() throws {
        try MatchReportRules.requireShape(try Self.goal(scorer: nil))
    }

    @Test("un penalti desde el área de penalti y sin lado del remate vale")
    func acceptsAPenalty() throws {
        try MatchReportRules.requireShape(try Self.goal(zone: .areaPenalti, playType: .penalti))
    }

    @Test("un penalti fuera del área, o con lado del remate, no vale (D-135, punto 5)")
    func rejectsAWrongPenalty() {
        #expect(throws: DomainError.invalidValue(field: "zone", reason: "un penalti no se tira fuera del área")) {
            try MatchReportRules.requireShape(try Self.goal(zone: .fueraArea, playType: .penalti))
        }
        #expect(throws: DomainError.invalidValue(field: "shotSide", reason: "un penalti no tiene lado del remate")) {
            try MatchReportRules.requireShape(try Self.goal(shotSide: .izquierda, playType: .penalti))
        }
    }

    @Test("un gol de jugada fuera del área y con lado del remate vale")
    func acceptsAnOpenPlayGoalFromOutside() throws {
        try MatchReportRules.requireShape(try Self.goal(zone: .fueraArea, shotSide: .derecha, playType: .juegoAbierto))
    }

    @Test("con asistente, hubo asistencia; y nadie se asiste a sí mismo")
    func assistRules() throws {
        try MatchReportRules.requireShape(try Self.goal(assist: Self.assistant, assisted: true))
        try MatchReportRules.requireShape(try Self.goal(scorer: nil, assisted: true))
        #expect(throws: DomainError.invalidValue(field: "assisted", reason: "con asistente, hubo asistencia")) {
            try MatchReportRules.requireShape(try Self.goal(assist: Self.assistant, assisted: false))
        }
        #expect(throws: DomainError.invalidValue(field: "assistPlayerId", reason: "nadie se asiste a sí mismo")) {
            try MatchReportRules.requireShape(try Self.goal(assist: Self.scorer, assisted: true))
        }
    }

    @Test("un gol en propia puerta no tiene asistencia (D-52)")
    func ownGoalHasNoAssist() {
        #expect(throws: DomainError.invalidValue(field: "assisted", reason: "un gol en propia puerta no tiene asistencia")) {
            try MatchReportRules.requireShape(try Self.goal(assisted: true, playType: .enPropiaPuerta))
        }
    }

    // ── Lo que el acta deja fijo en un gol (D-135, punto 6; D-137) ──────────

    @Test("en un gol del acta se elige el tipo de jugada del gol normal y se completa el desglose")
    func completesAReportGoal() throws {
        let before = try Self.goal(minute: 30)
        let after = try Self.goal(minute: 30, zone: .areaChica, shotSide: .centro, playType: .trasCorner)
        try MatchReportRules.requireReportGoalChange(from: before, to: after)
    }

    @Test("en un gol del acta no cambian el goleador ni el minuto")
    func keepsScorerAndMinuteOfAReportGoal() throws {
        let before = try Self.goal(minute: 30)
        #expect(throws: DomainError.lockedByMatchReport(field: "scorerPlayerId")) {
            try MatchReportRules.requireReportGoalChange(from: before, to: try Self.goal(scorer: Self.assistant, minute: 30))
        }
        #expect(throws: DomainError.lockedByMatchReport(field: "minute")) {
            try MatchReportRules.requireReportGoalChange(from: before, to: try Self.goal(minute: 31))
        }
    }

    @Test("en un gol del acta, ni se vuelve penalti o propia puerta, ni deja de serlo", arguments: [
        (GoalPlayType?.none, GoalPlayType?.some(.penalti)),
        (nil, .enPropiaPuerta),
        (.penalti, .juegoAbierto),
        (.enPropiaPuerta, nil),
    ])
    func keepsPenaltyAndOwnGoalOfAReportGoal(_ from: GoalPlayType?, _ to: GoalPlayType?) throws {
        #expect(throws: DomainError.lockedByMatchReport(field: "playType")) {
            try MatchReportRules.requireReportGoalChange(from: try Self.goal(playType: from), to: try Self.goal(playType: to))
        }
    }

    // ── La tarjeta (D-45, D-136, D-137) ─────────────────────────────────────

    @Test("la segunda amarilla es una roja, y sin una amarilla suelta en el partido")
    func secondYellowRules() throws {
        try MatchReportRules.requireCard(.roja, isSecondYellow: true, looseYellow: false)
        try MatchReportRules.requireCard(.amarilla, isSecondYellow: false, looseYellow: true)
        #expect(throws: DomainError.invalidValue(field: "isSecondYellow", reason: "solo con una roja")) {
            try MatchReportRules.requireCard(.amarilla, isSecondYellow: true, looseYellow: false)
        }
        #expect(throws: DomainError.looseYellowExists) {
            try MatchReportRules.requireCard(.roja, isSecondYellow: true, looseYellow: true)
        }
    }

    @Test("en una tarjeta del acta, solo el comentario cambia")
    func reportCardsOnlyChangeTheComment() throws {
        let card = CardShape(type: .amarilla, isSecondYellow: false, minute: try MatchMinute(20))
        try MatchReportRules.requireReportCardChange(from: card, to: card)
        #expect(throws: DomainError.lockedByMatchReport(field: "type")) {
            try MatchReportRules.requireReportCardChange(
                from: card, to: CardShape(type: .roja, isSecondYellow: false, minute: card.minute))
        }
        #expect(throws: DomainError.lockedByMatchReport(field: "isSecondYellow")) {
            try MatchReportRules.requireReportCardChange(
                from: CardShape(type: .roja, isSecondYellow: true, minute: card.minute),
                to: CardShape(type: .roja, isSecondYellow: false, minute: card.minute))
        }
        #expect(throws: DomainError.lockedByMatchReport(field: "minute")) {
            try MatchReportRules.requireReportCardChange(
                from: card, to: CardShape(type: .amarilla, isSecondYellow: false, minute: nil))
        }
    }
}

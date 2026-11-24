import struct Foundation.Calendar
public import struct Foundation.Date
import struct Foundation.DateComponents
import struct Foundation.TimeZone

// El acta de un partido (R7): la convocatoria, los goles y las tarjetas, con sus
// reglas. Las que miran varias filas a la vez (una convocatoria por jugador y
// partido, una tarjeta de cada tipo) las sostiene la base con sus índices, como
// en la plantilla. **El instante lo pone quien llama**: el dominio no mira el reloj.

// ── Los enumerados del catálogo ─────────────────────────────────────────────

/// Qué hizo el jugador en el partido (`D-132`, `D-134`). **Sin fila es «no
/// convocado»**: no hay valor para eso.
public enum AppearanceStatus: String, CaseIterable, Sendable {
    /// «Convocado» antes de la hora de comienzo, «Convocado sin minutos» después:
    /// un solo valor (`D-134`, punto 2).
    case convocadoSinMinutos = "convocado_sin_minutos"
    case jugado
    case bajaMedica = "baja_medica"
    case sancionado
}

/// Una fila es una sanción, no una cartulina (`D-45`): la doble amarilla es una
/// `roja` con `isSecondYellow`.
public enum CardType: String, CaseIterable, Sendable {
    case amarilla
    case roja
}

public enum GoalZone: String, CaseIterable, Sendable {
    case areaChica = "area_chica"
    case areaPenalti = "area_penalti"
    case fueraArea = "fuera_area"
}

/// Un lado del campo, para los dos lados del gol (`D-135`).
public enum GoalSide: String, CaseIterable, Sendable {
    case derecha
    case izquierda
    case centro
}

public enum GoalBodyPart: String, CaseIterable, Sendable {
    case pieIzquierdo = "pie_izquierdo"
    case pieDerecho = "pie_derecho"
    case cabeza
    case otro
}

/// Seis tipos (`D-135`, punto 3). **Nulo es «sin clasificar»**: así llega el gol
/// normal del acta, que no distingue jugada de falta (`D-131`).
public enum GoalPlayType: String, CaseIterable, Sendable {
    case juegoAbierto = "juego_abierto"
    case faltaDirecta = "falta_directa"
    case trasFalta = "tras_falta"
    case trasCorner = "tras_corner"
    case penalti
    case enPropiaPuerta = "en_propia_puerta"

    /// Lo que la federación dice de un gol, y por eso no se cambia en uno del
    /// acta (`D-135`, punto 6): si fue penalti o en propia puerta.
    var isSetByTheReport: Bool { self == .penalti || self == .enPropiaPuerta }
}

// ── Los valores ─────────────────────────────────────────────────────────────

/// Los minutos que jugó (`D-134`): **de 1 a 120**. Con cero no ha jugado; 120
/// cubre la prórroga. Opcional donde se use: nulo es «jugó, no sé cuánto» (`D-14`).
public struct MinutesPlayed: Hashable, Sendable {
    public let value: Int

    public init(_ value: Int) throws {
        guard (1...120).contains(value) else {
            throw DomainError.invalidValue(field: "minutes", reason: "tienen que ir del 1 al 120")
        }
        self.value = value
    }
}

/// El minuto de un gol o una tarjeta: **de 0 a 120**, lo que puede mandar la
/// federación. Opcional donde se use (`D-14`).
public struct MatchMinute: Hashable, Sendable {
    public let value: Int

    public init(_ value: Int) throws {
        guard (0...120).contains(value) else {
            throw DomainError.invalidValue(field: "minute", reason: "tiene que ir del 0 al 120")
        }
        self.value = value
    }
}

/// El comentario libre de un gol o una tarjeta (`D-135`, `D-136`): recortado por
/// los dos lados, **vacío no se guarda**, y hasta 500 caracteres.
public struct EntryComment: Hashable, Sendable {
    public static let maximumLength = 500
    public let value: String

    private init(value: String) { self.value = value }

    /// `nil` si no hay nada que guardar.
    public static func make(_ raw: String?) throws -> EntryComment? {
        guard let trimmed = raw?.trimmed, !trimmed.isEmpty else {
            return nil
        }
        guard trimmed.count <= maximumLength else {
            throw DomainError.invalidValue(
                field: "comment", reason: "no puede pasar de \(maximumLength) caracteres")
        }
        return EntryComment(value: trimmed)
    }
}

// ── La hora de comienzo ─────────────────────────────────────────────────────

extension Kickoff {
    /// **Si el partido ya ha empezado** en ese instante (`D-133`, punto 1): con
    /// hora, desde esa hora de Madrid; **sin hora, desde el final del día**. Antes,
    /// el acta solo apunta la convocatoria, y la ingesta no pregunta por ella.
    public func hasStarted(on instant: Date) -> Bool {
        guard let time else {
            return MadridDay.of(instant) > date
        }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var madrid = Calendar(identifier: .gregorian)
        madrid.timeZone = TimeZone(identifier: "Europe/Madrid")!
        var start = utc.dateComponents([.year, .month, .day], from: date)
        start.hour = time.hour
        start.minute = time.minute
        // Inalcanzable: la fecha existe y la hora es de un reloj de 24 h. En el
        // cambio de hora de marzo, una hora que no existe se corre a la siguiente.
        return instant >= madrid.date(from: start)!
    }
}

// ── La convocatoria y la copia del acta (R7.6) ──────────────────────────────

/// La convocatoria de un jugador en un partido (§3.2). **Sin fila, «no
/// convocado»** (`D-134`). `teamID` es el equipo con el que jugó (`D-128`).
/// `playerID`, `matchID` y `teamID` son identidad (`D-37`).
public struct Appearance: Identifiable, Equatable, Sendable {
    public let id: AppearanceID
    public let playerID: PlayerID
    public let matchID: MatchID
    public let teamID: TeamID
    public let status: AppearanceStatus
    /// El dorsal del acta (`D-129`).
    public let shirtNumber: ShirtNumber?
    /// Solo con `jugado` (`D-42`); nulo es «jugó, no sé cuánto» (`D-14`).
    public let minutes: MinutesPlayed?
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: AppearanceID, playerID: PlayerID, matchID: MatchID, teamID: TeamID,
                status: AppearanceStatus, shirtNumber: ShirtNumber? = nil, minutes: MinutesPlayed? = nil,
                createdAt: Date, updatedAt: Date) {
        self.id = id
        self.playerID = playerID
        self.matchID = matchID
        self.teamID = teamID
        self.status = status
        self.shirtNumber = shirtNumber
        self.minutes = minutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Un jugador de la convocatoria **tal como la trajo el acta** (`D-134`).
public struct ReportLineupEntry: Equatable, Sendable {
    public let playerID: PlayerID
    public let teamID: TeamID
    public let status: AppearanceStatus

    public init(playerID: PlayerID, teamID: TeamID, status: AppearanceStatus) {
        self.playerID = playerID
        self.teamID = teamID
        self.status = status
    }
}

/// **La copia del acta que guarda el partido** (`D-133`, `D-134`): cuándo se cargó
/// y la convocatoria tal como llegó, escrita una vez. Con ella, el servidor dice
/// qué ha cambiado el club (precisado en R7.4); sin acta cargada no hay copia.
public struct MatchReportCopy: Equatable, Sendable {
    public let loadedAt: Date
    public let lineup: [ReportLineupEntry]

    public init(loadedAt: Date, lineup: [ReportLineupEntry]) {
        self.loadedAt = loadedAt
        self.lineup = lineup
    }

    /// Si una fila **no coincide con el acta**: otro estado del que trajo, o un
    /// jugador que el acta no traía.
    public func changed(_ row: Appearance) -> Bool {
        lineup.first { $0.playerID == row.playerID }?.status != row.status
    }

    /// **Los que el acta traía y ya no tienen fila**: los que ha quitado el club.
    /// En el orden del acta.
    public func removed(keeping rows: [Appearance]) -> [ReportLineupEntry] {
        let present = Set(rows.map(\.playerID))
        return lineup.filter { !present.contains($0.playerID) }
    }
}

// ── El gol (R7.7) ───────────────────────────────────────────────────────────

/// Un gol (§3.2), **denormalizado a propósito**: los dos equipos, copiados del
/// partido (`D-04`, `D-54`). Solo es obligatorio el equipo que marca (`D-135`).
/// `matchID` y `scoringTeamID` son identidad (`D-37`).
public struct Goal: Identifiable, Equatable, Sendable {
    public let id: GoalID
    public let matchID: MatchID
    public let scoringTeamID: TeamID
    public let concedingTeamID: TeamID
    /// Nulo en los goles del rival (`D-09`). En propia puerta, el que la mete (`D-52`).
    public let scorer: PlayerID?
    public let assist: PlayerID?
    public let assisted: Bool
    public let minute: MatchMinute?
    public let zone: GoalZone?
    public let attackSide: GoalSide?
    public let shotSide: GoalSide?
    public let bodyPart: GoalBodyPart?
    /// Nulo es «sin clasificar» (`D-131`).
    public let playType: GoalPlayType?
    public let comment: EntryComment?
    /// Lo trajo el acta (`D-137`).
    public let fromReport: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: GoalID, matchID: MatchID, scoringTeamID: TeamID, concedingTeamID: TeamID,
                scorer: PlayerID? = nil, assist: PlayerID? = nil, assisted: Bool = false,
                minute: MatchMinute? = nil, zone: GoalZone? = nil, attackSide: GoalSide? = nil,
                shotSide: GoalSide? = nil, bodyPart: GoalBodyPart? = nil, playType: GoalPlayType? = nil,
                comment: EntryComment? = nil, fromReport: Bool = false, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.matchID = matchID
        self.scoringTeamID = scoringTeamID
        self.concedingTeamID = concedingTeamID
        self.scorer = scorer
        self.assist = assist
        self.assisted = assisted
        self.minute = minute
        self.zone = zone
        self.attackSide = attackSide
        self.shotSide = shotSide
        self.bodyPart = bodyPart
        self.playType = playType
        self.comment = comment
        self.fromReport = fromReport
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Lo que deciden las reglas de la forma del gol.
    public var shape: GoalShape {
        GoalShape(scorer: scorer, assist: assist, assisted: assisted, minute: minute, zone: zone,
                  shotSide: shotSide, playType: playType)
    }

    /// **El equipo del club del que tiene que ser el goleador** (`D-52`): el que marca
    /// en un gol normal, el que encaja en uno en propia puerta.
    public var scorerTeamID: TeamID { playType == .enPropiaPuerta ? concedingTeamID : scoringTeamID }
}

// ── La tarjeta (R7.8) ───────────────────────────────────────────────────────

/// Una tarjeta (§3.2): **una fila es una sanción** (`D-45`), de un jugador del club
/// (`D-136`), con el equipo con el que jugaba (`D-128`). `playerID`, `matchID` y
/// `teamID` son identidad (`D-37`).
public struct Card: Identifiable, Equatable, Sendable {
    public let id: CardID
    public let playerID: PlayerID
    public let matchID: MatchID
    public let teamID: TeamID
    public let type: CardType
    public let isSecondYellow: Bool
    public let minute: MatchMinute?
    public let comment: EntryComment?
    /// La trajo el acta (`D-137`).
    public let fromReport: Bool
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: CardID, playerID: PlayerID, matchID: MatchID, teamID: TeamID, type: CardType,
                isSecondYellow: Bool = false, minute: MatchMinute? = nil, comment: EntryComment? = nil,
                fromReport: Bool = false, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.playerID = playerID
        self.matchID = matchID
        self.teamID = teamID
        self.type = type
        self.isSecondYellow = isSecondYellow
        self.minute = minute
        self.comment = comment
        self.fromReport = fromReport
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var shape: CardShape { CardShape(type: type, isSecondYellow: isSecondYellow, minute: minute) }
}

// ── Lo que se compara en un gol y en una tarjeta ────────────────────────────

/// Lo de un gol que deciden las reglas: quién, cuándo y cómo. El equipo que marca
/// no está: es identidad (`D-37`), y su regla es la del equipo del partido.
public struct GoalShape: Equatable, Sendable {
    public let scorer: PlayerID?
    public let assist: PlayerID?
    public let assisted: Bool
    public let minute: MatchMinute?
    public let zone: GoalZone?
    public let shotSide: GoalSide?
    public let playType: GoalPlayType?

    public init(scorer: PlayerID?, assist: PlayerID?, assisted: Bool, minute: MatchMinute?,
                zone: GoalZone?, shotSide: GoalSide?, playType: GoalPlayType?) {
        self.scorer = scorer
        self.assist = assist
        self.assisted = assisted
        self.minute = minute
        self.zone = zone
        self.shotSide = shotSide
        self.playType = playType
    }
}

/// Lo de una tarjeta que el acta deja fijo (`D-136`, punto 4).
public struct CardShape: Equatable, Sendable {
    public let type: CardType
    public let isSecondYellow: Bool
    public let minute: MatchMinute?

    public init(type: CardType, isSecondYellow: Bool, minute: MatchMinute?) {
        self.type = type
        self.isSecondYellow = isSecondYellow
        self.minute = minute
    }
}

// ── Las reglas ──────────────────────────────────────────────────────────────

/// Las reglas que deciden si se puede escribir en el acta de un partido. La
/// temporada archivada es la de siempre (`RosterRules.requireNotArchived`): la
/// pasada **sí** se completa (`D-130`, punto 4).
public enum MatchReportRules {

    // El equipo y el jugador (D-128)

    /// El equipo del apunte: **uno de los dos del partido, y propio**.
    public static func requireTeam(_ team: TeamID, isOwn: Bool,
                                   playsIn match: (home: TeamID, away: TeamID)) throws {
        guard isOwn, team == match.home || team == match.away else {
            throw DomainError.teamNotInMatch(team: team.description)
        }
    }

    /// El jugador, **del club en la temporada del partido**, en la plantilla de
    /// cualquier equipo: un refuerzo se apunta igual.
    public static func requirePlayer(_ player: PlayerID, inSeason season: SeasonID,
                                     matchSeason: SeasonID) throws {
        guard season == matchSeason else {
            throw DomainError.playerNotInSeason(player: player.description)
        }
    }

    // La convocatoria (D-133, D-134)

    /// Apuntar a alguien con un estado: «Jugado», solo desde la hora de comienzo.
    public static func requireCanRecord(_ status: AppearanceStatus, started: Bool) throws {
        guard status != .jugado || started else { throw DomainError.matchNotStarted }
    }

    /// Cambiar el estado de una fila: **solo «Convocado sin minutos» ↔ «Jugado»**.
    /// Lo demás es borrar y volver a apuntar.
    public static func requireChange(from old: AppearanceStatus, to new: AppearanceStatus,
                                     started: Bool) throws {
        guard old != new else { return }
        let switchable: Set<AppearanceStatus> = [.convocadoSinMinutos, .jugado]
        guard switchable.contains(old), switchable.contains(new) else {
            throw DomainError.statusChangeNotAllowed(from: old.rawValue, to: new.rawValue)
        }
        try requireCanRecord(new, started: started)
    }

    /// Los minutos, **solo con «Jugado»** (`D-42`).
    public static func requireMinutes(_ minutes: MinutesPlayed?, for status: AppearanceStatus) throws {
        guard minutes == nil || status == .jugado else {
            throw DomainError.invalidValue(field: "minutes", reason: "solo con «Jugado»")
        }
    }

    /// Los minutos que se quedan tras un cambio de estado: **dejar «Jugado» los
    /// borra** (R7.3, P4), sin que haya que mandarlos vacíos.
    public static func minutes(_ minutes: MinutesPlayed?, after status: AppearanceStatus) -> MinutesPlayed? {
        status == .jugado ? minutes : nil
    }

    // Goles y tarjetas (D-133, D-137)

    /// Añadir un gol o una tarjeta: **desde la hora de comienzo, y sin el acta
    /// cargada**; con ella, son los del acta.
    public static func requireCanAddEntry(started: Bool, reportLoaded: Bool) throws {
        guard started else { throw DomainError.matchNotStarted }
        guard !reportLoaded else { throw DomainError.matchReportLoaded }
    }

    /// Borrar un gol o una tarjeta: **los del acta, no** (`D-137`).
    public static func requireCanDelete(fromReport: Bool) throws {
        guard !fromReport else { throw DomainError.lockedByMatchReport(field: "id") }
    }

    /// La forma de un gol, al apuntarlo o al corregirlo (`D-52`, `D-135`).
    public static func requireShape(_ goal: GoalShape) throws {
        if goal.playType == .penalti {
            guard goal.zone != .fueraArea else {
                throw DomainError.invalidValue(field: "zone", reason: "un penalti no se tira fuera del área")
            }
            guard goal.shotSide == nil else {
                throw DomainError.invalidValue(field: "shotSide", reason: "un penalti no tiene lado del remate")
            }
        }
        if goal.playType == .enPropiaPuerta, goal.assisted || goal.assist != nil {
            throw DomainError.invalidValue(field: "assisted", reason: "un gol en propia puerta no tiene asistencia")
        }
        if goal.assist != nil, !goal.assisted {
            throw DomainError.invalidValue(field: "assisted", reason: "con asistente, hubo asistencia")
        }
        if let assist = goal.assist, assist == goal.scorer {
            throw DomainError.invalidValue(field: "assistPlayerId", reason: "nadie se asiste a sí mismo")
        }
    }

    /// Corregir un gol del acta: **el goleador, el minuto, y si fue penalti o en
    /// propia puerta, no cambian** (`D-135`, punto 6). El tipo del gol normal, que
    /// llega sin él (`D-131`), se elige entre los demás.
    public static func requireReportGoalChange(from old: GoalShape, to new: GoalShape) throws {
        guard new.scorer == old.scorer else { throw DomainError.lockedByMatchReport(field: "scorerPlayerId") }
        guard new.minute == old.minute else { throw DomainError.lockedByMatchReport(field: "minute") }
        let wasSet = old.playType?.isSetByTheReport ?? false
        let isSet = new.playType?.isSetByTheReport ?? false
        guard wasSet == isSet, !wasSet || new.playType == old.playType else {
            throw DomainError.lockedByMatchReport(field: "playType")
        }
    }

    /// La tarjeta: la segunda amarilla es una roja, y **sin una amarilla suelta**
    /// del jugador en el partido, que quedaría dentro de la expulsión (`D-45`).
    public static func requireCard(_ type: CardType, isSecondYellow: Bool, looseYellow: Bool) throws {
        guard isSecondYellow else { return }
        guard type == .roja else {
            throw DomainError.invalidValue(field: "isSecondYellow", reason: "solo con una roja")
        }
        guard !looseYellow else { throw DomainError.looseYellowExists }
    }

    /// Corregir una tarjeta del acta: **solo el comentario** (`D-136`, punto 4).
    public static func requireReportCardChange(from old: CardShape, to new: CardShape) throws {
        guard new.type == old.type else { throw DomainError.lockedByMatchReport(field: "type") }
        guard new.isSecondYellow == old.isSecondYellow else {
            throw DomainError.lockedByMatchReport(field: "isSecondYellow")
        }
        guard new.minute == old.minute else { throw DomainError.lockedByMatchReport(field: "minute") }
    }
}

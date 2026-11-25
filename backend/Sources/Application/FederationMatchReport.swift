public import enum Domain.CardType
public import enum Domain.GoalPlayType

/// El acta de un partido, como la publica su federación (`D-125`, `D-131`, R7.11).
///
/// **Ya en nuestros tipos**: el adaptador traduce los códigos de la fuente (en la RFFM, `100`/`101`/`102` en los
/// goles y `100`/`101` en las tarjetas) y deja fuera lo que no entiende, contado en `skipped` (`D-131`, punto 4).
/// **No casa a nadie ni escribe nada**: los jugadores van con el código y el nombre de la federación; con quién son
/// de los nuestros lo decide la carga (`R7.12`, `D-126`).
public struct FederationMatchReport: Equatable, Sendable {
    /// **El acta firmada** (en la RFFM, `acta_cerrada = 1`). Solo entonces se carga (`D-133`); antes, la página
    /// existe y viene vacía.
    public let isClosed: Bool
    /// El código de cada equipo en la federación: el mismo que la inscripción (`D-101`) y el calendario. Es lo que
    /// dice cuál de los dos lados es el del club.
    public let homeTeamFederationID: String
    public let awayTeamFederationID: String
    /// Nulos mientras el acta no tiene marcador.
    public let homeScore: Int?
    public let awayScore: Int?
    /// Los de los dos equipos, en el orden en que los publica: primero el local.
    public let players: [FederationReportPlayer]
    public let goals: [FederationReportGoal]
    /// **Una fila es una sanción** (`D-45`): la doble amarilla llega ya como una sola roja con `isSecondYellow`, y
    /// la primera amarilla de ese jugador no viene aparte (`D-131`, punto 3).
    public let cards: [FederationReportCard]
    /// Los goles y las tarjetas con un código que no es ninguno de los medidos: no se adivinan (`D-131`, punto 4).
    public let skipped: [FederationReportSkip]

    public init(
        isClosed: Bool, homeTeamFederationID: String, awayTeamFederationID: String,
        homeScore: Int?, awayScore: Int?, players: [FederationReportPlayer],
        goals: [FederationReportGoal], cards: [FederationReportCard], skipped: [FederationReportSkip]
    ) {
        self.isClosed = isClosed
        self.homeTeamFederationID = homeTeamFederationID
        self.awayTeamFederationID = awayTeamFederationID
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.players = players
        self.goals = goals
        self.cards = cards
        self.skipped = skipped
    }
}

/// De qué equipo del acta es algo: el local o el visitante.
public enum FederationReportSide: String, Equatable, Sendable {
    case home
    case away
}

/// Un jugador del acta.
public struct FederationReportPlayer: Equatable, Sendable {
    public let side: FederationReportSide
    /// Su código en la federación (`D-126`): con él se casa primero.
    public let federationPlayerID: String
    /// Como lo escribe la federación: en la RFFM, «GARCÍA LÓPEZ, JUAN CARLOS».
    public let publishedName: String
    /// Vuelto a «NOMBRE APELLIDOS», como la plantilla; nulo si no se sabe darle la vuelta.
    public let fullName: String?
    /// El dorsal del acta (`D-129`). Nulo si no lo trae.
    public let shirtNumber: Int?
    /// Titular; si no, suplente.
    public let isStarter: Bool
    /// **Entró en un cambio.** Con los titulares, es quien jugó (`D-132`, punto 2).
    public let cameOn: Bool

    public init(
        side: FederationReportSide, federationPlayerID: String, publishedName: String, fullName: String?,
        shirtNumber: Int?, isStarter: Bool, cameOn: Bool
    ) {
        self.side = side
        self.federationPlayerID = federationPlayerID
        self.publishedName = publishedName
        self.fullName = fullName
        self.shirtNumber = shirtNumber
        self.isStarter = isStarter
        self.cameOn = cameOn
    }
}

/// Un gol del acta.
public struct FederationReportGoal: Equatable, Sendable {
    /// **El equipo al que le suma.** En uno en propia puerta es el contrario del que lo marca (`D-52`, `D-131`): la
    /// RFFM lo pone en la lista del equipo del jugador, y aquí ya viene dado la vuelta. Así, los goles de cada lado
    /// son su marcador.
    public let side: FederationReportSide
    /// Quien lo marca; en uno en propia puerta, el que lo mete en su portería, del otro equipo.
    public let federationPlayerID: String
    public let publishedName: String
    public let minute: Int?
    /// Nulo en el gol «normal», que no distingue jugada de falta (`D-131`, punto 1); `penalti` o
    /// `enPropiaPuerta`, en los otros dos.
    public let playType: GoalPlayType?

    public init(
        side: FederationReportSide, federationPlayerID: String, publishedName: String, minute: Int?,
        playType: GoalPlayType?
    ) {
        self.side = side
        self.federationPlayerID = federationPlayerID
        self.publishedName = publishedName
        self.minute = minute
        self.playType = playType
    }
}

/// Una tarjeta del acta: una sanción (`D-45`).
public struct FederationReportCard: Equatable, Sendable {
    /// El equipo del jugador.
    public let side: FederationReportSide
    public let federationPlayerID: String
    public let publishedName: String
    public let minute: Int?
    public let type: CardType
    /// La roja por doble amarilla.
    public let isSecondYellow: Bool

    public init(
        side: FederationReportSide, federationPlayerID: String, publishedName: String, minute: Int?,
        type: CardType, isSecondYellow: Bool
    ) {
        self.side = side
        self.federationPlayerID = federationPlayerID
        self.publishedName = publishedName
        self.minute = minute
        self.type = type
        self.isSecondYellow = isSecondYellow
    }
}

/// Un gol o una tarjeta que el adaptador no ha sabido traducir: con qué código venía y dónde.
public struct FederationReportSkip: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case goal
        case card
    }

    public let kind: Kind
    public let side: FederationReportSide
    /// El código tal como lo trae la fuente.
    public let code: String

    public init(kind: Kind, side: FederationReportSide, code: String) {
        self.kind = kind
        self.side = side
        self.code = code
    }
}

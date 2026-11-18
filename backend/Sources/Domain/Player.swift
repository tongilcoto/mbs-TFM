public import struct Foundation.Date

/// El año de nacimiento del jugador (`D-119`): **solo el año**, porque es un dato
/// de un menor y en fútbol base la categoría sale de él.
///
/// No se comprueba contra la categoría del equipo: un chaval puede jugar en una
/// superior. **El año en curso lo pone quien llama**: el dominio no mira el reloj.
public struct BirthYear: Hashable, Sendable {
    public let value: Int

    /// El primero que se admite, el del catálogo (`BirthYear.minimum`).
    public static let earliest = 1900

    public init(_ value: Int, notAfter currentYear: Int) throws {
        guard value >= Self.earliest else {
            throw DomainError.invalidValue(
                field: "birthYear", reason: "no puede ser anterior a \(Self.earliest)")
        }
        guard value <= currentYear else {
            throw DomainError.invalidValue(
                field: "birthYear", reason: "no puede ser posterior a \(currentYear)")
        }
        self.value = value
    }

    /// Para leer de la base lo que ya se comprobó al guardar: el `CHECK` de la
    /// tabla sostiene el rango ancho, y un año que fue válido no deja de serlo
    /// porque cambie el calendario.
    public init(stored value: Int) {
        self.value = value
    }
}

/// El dorsal de la plantilla (`D-118`): del 1 al 99, y **opcional** donde se use.
///
/// Que no se repita en el mismo equipo y temporada lo sostiene la base (un índice
/// único parcial, entre los no borrados): es lo único que ve a la vez todas las
/// filas, también las que se escriben a la vez.
public struct ShirtNumber: Hashable, Sendable {
    public let value: Int

    public init(_ value: Int) throws {
        guard (1...99).contains(value) else {
            throw DomainError.invalidValue(field: "shirtNumber", reason: "tiene que ir del 1 al 99")
        }
        self.value = value
    }
}

/// El perfil del jugador: **el que dura entre temporadas** (`D-119`, enmienda a
/// `D-05`), con lo que es de la persona.
///
/// Los tres `last…` **son ayuda, no mandan** (`D-122`): lo que vale es la fila de
/// la plantilla. Cada guardado de una fila los copia (`remembering(_:)`), y el
/// alta y la sincronización los traen.
public struct PlayerProfile: Identifiable, Equatable, Sendable {
    public let id: PlayerProfileID
    public let fullName: PlayerName
    /// Nulo solo si lo creó la sincronización: la federación no da el año.
    public let birthYear: BirthYear?
    public let lastShirtNumber: ShirtNumber?
    public let lastPosition: PlayerPosition?
    public let lastPhotoKey: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: PlayerProfileID, fullName: PlayerName, birthYear: BirthYear?,
        lastShirtNumber: ShirtNumber? = nil, lastPosition: PlayerPosition? = nil,
        lastPhotoKey: String? = nil, createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.fullName = fullName
        self.birthYear = birthYear
        self.lastShirtNumber = lastShirtNumber
        self.lastPosition = lastPosition
        self.lastPhotoKey = lastPhotoKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// El perfil, con el dorsal, la demarcación y la foto de una fila que se
    /// acaba de guardar (`D-122`). **Lo vacío también se copia**: si la fila los
    /// ha quitado, el perfil no se queda con los de antes.
    public func remembering(_ row: Player) -> PlayerProfile {
        PlayerProfile(
            id: id, fullName: fullName, birthYear: birthYear,
            lastShirtNumber: row.shirtNumber, lastPosition: row.position,
            lastPhotoKey: row.photoKey, createdAt: createdAt, updatedAt: updatedAt)
    }
}

/// El jugador **en un equipo y una temporada** (`D-05`): la fila de la plantilla.
///
/// **No lleva el nombre ni el año**: son de su perfil (`D-119`), y se leen de él.
/// `teamID` y `seasonID` son identidad, no atributos (`D-37`): un cambio de equipo
/// es una baja y un alta (`D-121`).
public struct Player: Identifiable, Equatable, Sendable {
    public let id: PlayerID
    public let profileID: PlayerProfileID
    public let teamID: TeamID
    public let seasonID: SeasonID
    public let shirtNumber: ShirtNumber?
    public let position: PlayerPosition?
    /// La clave del fichero en el almacén, no una URL (`D-35`). Puede ser la misma
    /// que la de otra fila del jugador o la de su perfil (`D-122`).
    public let photoKey: String?
    /// **Si la federación lo publica** en la plantilla del equipo, según la
    /// última sincronización (`D-120`): sí, no, o nulo mientras esa plantilla no
    /// se ha sincronizado nunca.
    public let federated: Bool?
    /// La última vez que la federación lo listó; nula si nunca.
    public let lastListedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: PlayerID, profileID: PlayerProfileID, teamID: TeamID, seasonID: SeasonID,
        shirtNumber: ShirtNumber? = nil, position: PlayerPosition? = nil,
        photoKey: String? = nil, federated: Bool? = nil, lastListedAt: Date? = nil,
        createdAt: Date, updatedAt: Date
    ) {
        self.id = id
        self.profileID = profileID
        self.teamID = teamID
        self.seasonID = seasonID
        self.shirtNumber = shirtNumber
        self.position = position
        self.photoKey = photoKey
        self.federated = federated
        self.lastListedAt = lastListedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// La misma fila con otra foto, o sin ella (R6.9).
    public func with(photoKey: String?, updatedAt: Date) -> Player {
        Player(id: id, profileID: profileID, teamID: teamID, seasonID: seasonID, shirtNumber: shirtNumber,
               position: position, photoKey: photoKey, federated: federated, lastListedAt: lastListedAt,
               createdAt: createdAt, updatedAt: updatedAt)
    }
}

/// Las reglas que deciden si se puede escribir en una plantilla.
///
/// Las otras dos (el dorsal sin repetir y un jugador en una sola plantilla por
/// temporada, `D-118` y `D-121`) son de varias filas a la vez, y las sostiene la
/// base con sus índices. **El día lo pone quien llama**: el dominio no mira el reloj.
public enum RosterRules {
    /// El alta: solo en un equipo **propio** (un rival no tiene plantilla, §3.7),
    /// en una temporada en la que se puede escribir, y con el equipo **inscrito**
    /// en ella (decisión 3 de R6.11).
    public static func requireCanAdd(to team: Team, in season: Season, on instant: Date,
                                     registered: Bool) throws {
        guard team.isOwn else {
            throw DomainError.teamNotOwn(team: team.id.description)
        }
        try requireEditable(in: season, on: instant)
        guard registered else {
            throw DomainError.teamNotRegistered(team: team.id.description, season: season.id.description)
        }
    }

    /// Corregir, dar de baja y poner o quitar la foto: ni en una temporada
    /// **archivada** (R6.3) ni en una **terminada** (decisión 4 de R6.14). Si es
    /// las dos cosas, dice que está archivada.
    public static func requireEditable(in season: Season, on instant: Date) throws {
        try requireNotArchived(season)
        guard !season.hasEnded(on: instant) else {
            throw DomainError.seasonEnded(label: season.label.value)
        }
    }

    /// Solo que no esté archivada: lo que mira la sincronización, que además pide
    /// que sea la en curso (`SEASON_NOT_CURRENT`, R6.14).
    public static func requireNotArchived(_ season: Season) throws {
        guard !season.isArchived else {
            throw DomainError.seasonArchived(label: season.label.value)
        }
    }
}

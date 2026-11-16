public import Domain

/// La fila de la plantilla (`D-05`). **Solo ve las no borradas**: el borrado es
/// lógico y sirve a la auditoría (`D-36`), no a los casos de uso.
public protocol PlayerRepository: Sendable {
    func find(_ id: PlayerID) async throws -> Player?

    /// La plantilla de un equipo en una temporada. Sin orden: lo pone el caso de
    /// uso, que es quien sabe cuál es (`D-118`).
    func list(teamID: TeamID, seasonID: SeasonID) async throws -> [Player]

    /// Las filas de un perfil en una temporada: como mucho una (`D-121`).
    func list(profileID: PlayerProfileID, seasonID: SeasonID) async throws -> [Player]

    /// *Upsert* por `id`; el id lo pone el caso de uso.
    func save(_ player: Player) async throws

    /// Borrado **lógico** (`D-36`): la fila deja de verse y su dorsal queda libre.
    func delete(_ id: PlayerID) async throws

    /// Todas las filas no borradas de esos perfiles, de cualquier temporada: el
    /// buscador del alta saca de ellas la última plantilla y el otro equipo
    /// (R6.7). Sin orden.
    func list(profileIDs: [PlayerProfileID]) async throws -> [Player]

    /// **Si alguien usa todavía esa foto** (R6.9, `D-122`): una fila de cualquier
    /// temporada, **también las dadas de baja** (la baja no borra la foto, `D-35`,
    /// para que se pueda deshacer), o un perfil. Un fichero se borra solo si no.
    func isPhotoInUse(_ key: String) async throws -> Bool
}

/// El perfil del jugador, que dura entre temporadas (`D-119`).
public protocol PlayerProfileRepository: Sendable {
    func find(_ id: PlayerProfileID) async throws -> PlayerProfile?
    func list(ids: [PlayerProfileID]) async throws -> [PlayerProfile]
    /// *Upsert* por `id`.
    func save(_ profile: PlayerProfile) async throws

    /// **El buscador del alta** (R6.7, `D-120`): los perfiles cuyo nombre encaja
    /// con lo escrito, como lo pliega `PlayerSearch`, **sin los que ya están en la
    /// plantilla de ese equipo y temporada**, por orden de nombre y hasta `limit`.
    /// Quitarlos aquí y no después es lo que hace que los `limit` que llegan sean
    /// todos enseñables.
    func search(_ search: PlayerSearch, excludingRosterOf teamID: TeamID, seasonID: SeasonID,
                limit: Int) async throws -> [PlayerProfile]
}

/// Un jugador **como lo enseña la plantilla**: su fila y su perfil, de donde
/// salen el nombre y el año (`D-119`).
public struct RosterEntry: Equatable, Sendable {
    public let player: Player
    public let profile: PlayerProfile

    public init(player: Player, profile: PlayerProfile) {
        self.player = player
        self.profile = profile
    }
}

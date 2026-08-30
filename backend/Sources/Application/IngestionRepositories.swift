public import Domain

/// Puerto de salida de `Round` (§4.3).
///
/// **Sin `delete` y sin `find`**, como los de F1: la ingesta no borra jornadas
/// —lo que la fuente deja de publicar no se destruye (`D-75`)— y no busca una
/// suelta, porque carga las de la competición entera para emparejar.
public protocol RoundRepository: Sendable {
    /// Todas las jornadas de la competición. Es la lista contra la que la pasada
    /// decide crear o actualizar.
    func list(competitionID: CompetitionID) async throws -> [Round]

    /// *Upsert* por `id` (§4.3). El id lo pone el caso de uso, no la base:
    /// así la fila recién creada puede entrar en los candidatos de la misma
    /// pasada sin releerla.
    func save(_ round: Round) async throws
}

/// Puerto de salida de `OpponentClub` (§4.3).
public protocol OpponentClubRepository: Sendable {
    /// **Todos los del tenant, sin filtro de competición**, y es deliberado: un
    /// club rival es identidad de club y **no lleva temporada ni competición**
    /// (§3.2, `D-28`). El mismo "C.D. Galapagar" que juega en cadete es el que
    /// juega en juvenil, y emparejarlo solo contra los de esta competición
    /// crearía un duplicado por categoría.
    func list() async throws -> [OpponentClub]

    func save(_ club: OpponentClub) async throws
}

/// Puerto de salida de `Team` (§4.3).
public protocol TeamRepository: Sendable {
    /// **Todos los del tenant**, por el mismo motivo que los clubes: `Team`
    /// tampoco lleva temporada (`D-28`). Incluye los **propios**, que el paso 1
    /// de la cadena sí tiene que poder reconocer si ya están enganchados
    /// (`D-67`).
    func list() async throws -> [Team]

    func save(_ team: Team) async throws
}

/// Puerto de salida de `Match` (§4.3).
public protocol MatchRepository: Sendable {
    func list(competitionID: CompetitionID) async throws -> [Match]

    func save(_ match: Match) async throws
}

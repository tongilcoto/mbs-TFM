public import Domain

/// Puerto de salida (§4.3), uno por raíz de agregado (§4.2).
///
/// Sin `delete` por el mismo motivo que `SeasonRepository`: el *spec* solo
/// permite borrar una competición **sin dependientes** (409 si los tiene), y esa
/// guarda vive en el caso de uso que todavía no existe.
public protocol CompetitionRepository: Sendable {
    func find(_ id: CompetitionID) async throws -> Competition?

    /// Por la **clave única** de la entidad (§3.5).
    ///
    /// Es la consulta con la que la cascada de `D-67` decide crear o **reutilizar**:
    /// dos equipos del club pueden caer en el mismo grupo, y el segundo enganche
    /// no puede volver a crearla.
    ///
    /// Lleva `seasonID` porque el identificador de grupo envuelve categoría +
    /// división + grupo, pero **no la temporada** (§3.5): sin él, la misma
    /// competición no podría existir en dos temporadas, que es el caso normal.
    func findByFederationGroup(
        seasonID: SeasonID, federationGroupID: String
    ) async throws -> Competition?

    func list(seasonID: SeasonID) async throws -> [Competition]

    /// *Upsert* del agregado (§4.3).
    func save(_ competition: Competition) async throws
}

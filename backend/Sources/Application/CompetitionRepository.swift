public import Domain

/// Puerto de salida (§4.3), uno por raíz de agregado (§4.2).
///
/// Sin `delete` por el mismo motivo que `SeasonRepository`: el *spec* solo
/// permite borrar una competición **sin dependientes** (409 si los tiene), y esa
/// guarda vive en el caso de uso que todavía no existe.
public protocol CompetitionRepository: Sendable {
    func find(_ id: CompetitionID) async throws -> Competition?

    /// Como `find`, y **deja la fila bloqueada hasta que cierre el ámbito**, que
    /// es una transacción (§6.2) (A-11·H-55).
    ///
    /// Es lo primero que hace el ámbito que **escribe** de cada pasada de la
    /// ingesta —calendario, clasificación, goleadores—, y lo que hace que dos
    /// pasadas de la misma competición escriban **una detrás de otra**. Sin ello,
    /// dos primeras sincronizaciones a la vez insertaban las mismas jornadas y una
    /// caía en un `23505` que no era de los datos, sino de la coincidencia.
    ///
    /// Solo dentro del ámbito de escritura: el bloqueo dura lo que la transacción,
    /// y en ninguna de las tres hay red dentro (`D-83`), así que nadie espera a un
    /// tercero con la fila cogida.
    func lock(_ id: CompetitionID) async throws -> Competition?

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

    /// Las que cumplen **todos** los filtros que vengan (`GET /v1/competitions`);
    /// uno que no viene no filtra. Orden: categoría y grupo.
    func list(_ filter: CompetitionFilter) async throws -> [Competition]

    /// *Upsert* del agregado (§4.3).
    func save(_ competition: Competition) async throws
}

/// Los filtros de `GET /v1/competitions` (§5.1). **Todos opcionales y se suman**:
/// cada uno que viene estrecha el resultado, y uno que no viene no filtra.
///
/// El catálogo acepta los cuatro, y se programan los cuatro: un filtro que el
/// catálogo acepta y el servidor ignora devolvería datos que no se han pedido, sin
/// avisar (Plan R1, §5).
public struct CompetitionFilter: Equatable, Sendable {
    public var seasonID: SeasonID?
    public var modality: Modality?
    public var ageCategory: TeamCategory?
    public var gender: Gender?

    public init(
        seasonID: SeasonID? = nil, modality: Modality? = nil,
        ageCategory: TeamCategory? = nil, gender: Gender? = nil
    ) {
        self.seasonID = seasonID
        self.modality = modality
        self.ageCategory = ageCategory
        self.gender = gender
    }
}

extension CompetitionRepository {
    /// Las de una temporada. Es la lectura de la ingesta, que recorre la
    /// temporada entera; existía antes que los filtros y se queda como atajo.
    public func list(seasonID: SeasonID) async throws -> [Competition] {
        try await list(CompetitionFilter(seasonID: seasonID))
    }
}

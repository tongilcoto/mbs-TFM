import Domain
public import Fluent
import Foundation

/// Modelo de persistencia del perfil del jugador (§4.4, [D-119]): el que dura
/// entre temporadas.
///
/// **Sin `deleted_at`**: el perfil no se da de baja. Lo borra el purgado de
/// temporada ([D-24]) cuando se queda sin filas, y mientras tenga una, la base no
/// deja borrarlo (la FK de `players` es `RESTRICT`).
public final class PlayerProfileRecord: Model, @unchecked Sendable {
    public static let schema = "player_profiles"

    @ID(key: .id) public var id: UUID?

    /// En mayúsculas y limpio ([D-120]): lo pone `PlayerName`.
    @Field(key: "full_name") public var fullName: String
    /// Nulo solo si lo creó la sincronización ([D-120]).
    @OptionalField(key: "birth_year") public var birthYear: Int?

    // Los tres de ayuda ([D-122]): los copia cada guardado de una fila.
    @OptionalField(key: "last_shirt_number") public var lastShirtNumber: Int?
    @OptionalField(key: "last_position") public var lastPosition: String?
    @OptionalField(key: "last_photo_key") public var lastPhotoKey: String?

    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}
}

/// Modelo de persistencia del jugador **en un equipo y una temporada** (§4.4,
/// [D-05]): la fila de la plantilla.
///
/// **Doble `@Parent`** (`team_id` y `season_id`): la fila **es** el par (§4.4). Y
/// un tercero al perfil ([D-119]), de donde se leen el nombre y el año.
public final class PlayerRecord: Model, @unchecked Sendable {
    public static let schema = "players"

    @ID(key: .id) public var id: UUID?

    @Parent(key: "profile_id") public var profile: PlayerProfileRecord
    @Parent(key: "team_id") public var team: TeamRecord
    @Parent(key: "season_id") public var season: SeasonRecord

    /// Anulables los dos ([D-118], [D-120]).
    @OptionalField(key: "shirt_number") public var shirtNumber: Int?
    @OptionalField(key: "position") public var position: String?
    /// La clave del fichero, no una URL ([D-35]).
    @OptionalField(key: "photo_key") public var photoKey: String?

    /// *Soft delete* sin guarda de dependientes ([D-36]): sus goles y tarjetas
    /// siguen contando para el equipo.
    @Timestamp(key: "deleted_at", on: .delete) public var deletedAt: Date?
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}
}

/// **Las dos tablas de [D-119], a la vez**: el perfil que dura y la fila de la
/// temporada, que no existe sin él.
///
/// # Por qué una migración y no dos
///
/// §4.6 pide una por entidad, pero estas dos nacen juntas y no tienen sentido la
/// una sin la otra: el alta escribe en las dos ([D-119], punto 1). Partirlas
/// dejaría un estado intermedio —perfiles sin tabla de filas— que ningún club
/// tendría nunca.
///
/// # Lo que no trae, y llega con la sincronización
///
/// `federated` y `last_listed_at` en `players`, y `roster_synced_at` en
/// `team_registrations` ([D-120]), van en la migración 23ª, en la rama de la
/// sincronización (R6.14): esta rebanada puede cerrar sin ella.
public struct CreatePlayers: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(PlayerProfileRecord.schema)
            .id()
            .field("full_name", .string, .required)
            .field("birth_year", .int)
            .field("last_shirt_number", .int)
            .field("last_position", .string)
            .field("last_photo_key", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        // El rango ancho del catálogo (`BirthYear`): que no sea posterior al año
        // en curso lo dice el dominio, que es quien sabe qué año es.
        try await database.checkConstraint(
            table: PlayerProfileRecord.schema, name: "chk_player_profiles_birth_year",
            expression: "birth_year BETWEEN 1900 AND 2100")
        try await database.checkConstraint(
            table: PlayerProfileRecord.schema, name: "chk_player_profiles_last_shirt_number",
            expression: "last_shirt_number BETWEEN 1 AND 99")
        try await database.checkConstraint(
            table: PlayerProfileRecord.schema, name: "chk_player_profiles_last_position",
            expression: "last_position IN (\(PlayerPosition.sqlValueList))")

        try await database.schema(PlayerRecord.schema)
            .id()
            // **`RESTRICT` hacia el perfil**: borrarlo con filas dejaría goles y
            // tarjetas sin nombre. El purgado ([D-24]) borra antes las filas.
            .field("profile_id", .uuid, .required,
                   .references(PlayerProfileRecord.schema, "id", onDelete: .restrict))
            // **`CASCADE` desde el equipo y la temporada**, como la inscripción:
            // purgar la temporada se lleva su plantilla ([D-24], [D-73]).
            .field("team_id", .uuid, .required,
                   .references(TeamRecord.schema, "id", onDelete: .cascade))
            .field("season_id", .uuid, .required,
                   .references(SeasonRecord.schema, "id", onDelete: .cascade))
            .field("shirt_number", .int)
            .field("position", .string)
            .field("photo_key", .string)
            .field("deleted_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        try await database.checkConstraint(
            table: PlayerRecord.schema, name: "chk_players_shirt_number",
            expression: "shirt_number BETWEEN 1 AND 99")
        try await database.checkConstraint(
            table: PlayerRecord.schema, name: "chk_players_position",
            expression: "position IN (\(PlayerPosition.sqlValueList))")

        // **El dorsal, sin repetir entre los no borrados** ([D-118], [D-36]). Los
        // nulos no chocan: Postgres no los compara, que es lo que se quiere aquí
        // —muchos sin dorsal— y lo contrario de `uq_teams_identity`.
        try await database.partialUniqueIndex(
            table: PlayerRecord.schema, name: "uq_players_shirt",
            columns: ["team_id", "season_id", "shirt_number"], where: "deleted_at IS NULL")

        // **Un jugador, una plantilla por temporada** ([D-121]), también entre
        // los no borrados: cambiar de equipo es baja y alta.
        try await database.partialUniqueIndex(
            table: PlayerRecord.schema, name: "uq_players_profile_season",
            columns: ["profile_id", "season_id"], where: "deleted_at IS NULL")

        // La consulta de la plantilla (§5.1), que pide siempre el par.
        try await database.index(
            table: PlayerRecord.schema, name: "idx_players_team_season",
            columns: ["team_id", "season_id"])
    }

    public func revert(on database: any Database) async throws {
        // Las filas antes que los perfiles, por la FK. Cada tabla se lleva sus
        // índices y sus `CHECK`.
        try await database.schema(PlayerRecord.schema).delete()
        try await database.schema(PlayerProfileRecord.schema).delete()
    }
}

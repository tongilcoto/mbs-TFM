import Domain
public import Fluent
import Foundation

/// Modelo de persistencia de la clasificación (§4.4, §4.5).
///
/// **Es un modelo de lectura, no un agregado** (§4.2): lo escribe el módulo de
/// ingesta por *upsert* y nadie más. No tiene repositorio de dominio ni `POST`.
public final class StandingRowRecord: Model, @unchecked Sendable {
    public static let schema = "standing_rows"

    @ID(key: .id) public var id: UUID?

    /// Se guarda aunque `Round` ya la fije, por lo mismo que en `Match`: es la FK
    /// por la que se consulta. **La clave única de §3.5 no la lleva.**
    @Parent(key: "competition_id") public var competition: CompetitionRecord

    @Parent(key: "round_id") public var round: RoundRecord
    @Parent(key: "team_id") public var team: TeamRecord

    @Field(key: "position") public var position: Int

    /// La columna PREV (`D-33`). **Anulable y no derivada**: en la primera
    /// jornada no hay anterior, y en un alta a mitad de temporada tampoco hay
    /// *snapshot* previo del que leerla.
    @OptionalField(key: "previous_position") public var previousPosition: Int?

    @Field(key: "played") public var played: Int
    @Field(key: "won") public var won: Int
    @Field(key: "drawn") public var drawn: Int
    @Field(key: "lost") public var lost: Int
    @Field(key: "goals_for") public var goalsFor: Int
    @Field(key: "goals_against") public var goalsAgainst: Int
    @Field(key: "points") public var points: Int

    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}
}

/// **La entidad 22 del modelo.** Va **detrás de `Match`** en el orden de FK de
/// §4.6 —el sitio que el orden canónico de `TenantMigrations` le reserva— porque
/// depende de `Competition`, `Round` y `Team`, y las tres existen ya ahí.
///
/// # Se añade, no se edita nada (`D-90`)
///
/// Ni una línea de las ocho migraciones que ya existen. `_fluent_migrations`
/// guarda **el nombre** de cada una, no su contenido, así que un *schema* que ya
/// aplicó `CreateMatch` no recibiría jamás una edición de su `prepare` — sin
/// error y sin aviso. Esta fase añade una tabla nueva y por tanto una migración
/// nueva, que es el caso fácil; lo que `D-90` prohíbe es la tentación de
/// aprovechar el viaje para "arreglar" una vieja de paso.
///
/// Intercalarla en medio de la lista **no** cambia el esquema resultante —está
/// medido (`A-5`/H-38, `MigrationIntegrityTests`)—: lo que ordena la lista es la
/// dependencia de FK, para que un alta limpia pueda aplicarlas de una pasada.
/// Sobre una base ya migrada, Fluent aplica solo las que faltan.
public struct CreateStandingRow: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(StandingRowRecord.schema)
            .id()
            // `CASCADE` desde competición y jornada, como todo el subárbol de
            // `Season` (`D-73`): purgar una temporada se lleva sus
            // clasificaciones, que sin la jornada no significan nada.
            .field("competition_id", .uuid, .required,
                   .references(CompetitionRecord.schema, "id", onDelete: .cascade))
            .field("round_id", .uuid, .required,
                   .references(RoundRecord.schema, "id", onDelete: .cascade))
            // **Sin cascada desde el equipo**, igual que en `Match` y por el mismo
            // motivo: borrar un equipo no puede llevarse por delante la
            // clasificación de una jornada, que es también de los otros quince.
            .field("team_id", .uuid, .required,
                   .references(TeamRecord.schema, "id"))
            .field("position", .int, .required)
            .field("previous_position", .int)
            .field("played", .int, .required)
            .field("won", .int, .required)
            .field("drawn", .int, .required)
            .field("lost", .int, .required)
            .field("goals_for", .int, .required)
            .field("goals_against", .int, .required)
            .field("points", .int, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            // La unicidad de §3.5, y **es la identidad de negocio de la fila**:
            // un *snapshot* es (jornada, equipo). No lleva `competition_id`
            // porque `Round` ya la fija, igual que en `Match`.
            //
            // Y es además el índice que sirve la consulta de la pantalla —la
            // tabla de una jornada—, así que no hace falta uno aparte para
            // `round_id`.
            .unique(on: "round_id", "team_id")
            .create()

        try await database.index(
            table: StandingRowRecord.schema, name: "idx_standing_rows_competition",
            columns: ["competition_id"])
        try await database.index(
            table: StandingRowRecord.schema, name: "idx_standing_rows_team",
            columns: ["team_id"])

        // Las dos guardas estructurales del Dominio, bajadas al esquema (`D-28`):
        // el *spec* las declara (`minimum: 1` y `minimum: 0`) y el generador no
        // las hace cumplir (`D-65`).
        try await database.checkConstraint(
            table: StandingRowRecord.schema, name: "chk_standing_rows_position",
            expression: "position >= 1")
        try await database.checkConstraint(
            table: StandingRowRecord.schema, name: "chk_standing_rows_previous_position",
            expression: "previous_position IS NULL OR previous_position >= 1")
        try await database.checkConstraint(
            table: StandingRowRecord.schema, name: "chk_standing_rows_counters",
            expression: "played >= 0 AND won >= 0 AND drawn >= 0 AND lost >= 0"
                + " AND goals_for >= 0 AND goals_against >= 0 AND points >= 0")

        // **Y aquí NO va un `CHECK` de aritmética**, que es la parte que hay que
        // resistirse a añadir: ni `played = won + drawn + lost` ni
        // `points = 3 * won + drawn`. La tabla oficial de un grupo con una
        // sanción **no los cumple** —la RFFM publica `puntos_sancion`— y el *spec*
        // ya se comprometió a no recalcular los puntos. Un `CHECK` de más aquí
        // sería peor que la invariante de más en el Dominio: allí se pierde la
        // jornada, aquí se pierde con un `23514` que nadie relaciona con una
        // sanción deportiva. La decisión completa, en `StandingRow` y en `D-92`.
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(StandingRowRecord.schema).delete()
    }
}

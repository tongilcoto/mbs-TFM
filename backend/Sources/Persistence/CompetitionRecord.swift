import Domain
public import Fluent
import Foundation

/// Modelo de persistencia de la competición (§4.4).
public final class CompetitionRecord: Model, @unchecked Sendable {
    public static let schema = "competitions"

    @ID(key: .id) public var id: UUID?

    /// FK al UUID interno de `Season` (§3.2). `@Parent` y no un `UUID` suelto,
    /// para que el *eager loading* de las lecturas lo tenga disponible (§4.5);
    /// el mapeo a Dominio entrega **ids**, nunca el objeto (§4.1).
    @Parent(key: "season_id") public var season: SeasonRecord

    /// Enumerados como *raw value* + `CHECK` en la migración (`D-02`). El `enum`
    /// vive en el Dominio y es la fuente de verdad.
    @Field(key: "modality") public var modality: String
    @Field(key: "gender") public var gender: String
    @Field(key: "age_category") public var ageCategory: String

    @Field(key: "federation_competition_id") public var federationCompetitionID: String
    @Field(key: "federation_group_id") public var federationGroupID: String

    @Field(key: "division_label") public var divisionLabel: String
    @Field(key: "group_label") public var groupLabel: String

    /// Procedencia, no rótulo (`D-72`): el nombre literal que publica la
    /// federación, del que sale la inferencia de `gender`. **No lo expone el
    /// contrato**: lo escribe la ingesta y lo lee un humano contra la BD cuando
    /// hay que averiguar por qué esa inferencia falló.
    @OptionalField(key: "federation_name") public var federationName: String?

    /// Nulo ⇒ nunca sincronizada, que es la condición bajo la cual las
    /// coordenadas y el género siguen siendo editables (§3.7, `D-22`).
    @OptionalField(key: "last_synced_at") public var lastSyncedAt: Date?

    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}
}

/// Va **después de `Season`** por su FK (§4.6). Las entidades que en el orden
/// completo se intercalan entre las dos —`OpponentClub`, `Team`,
/// `TeamRegistration`— todavía no existen; `Competition` solo depende de
/// `Season`, así que el orden es correcto tal cual.
public struct CreateCompetition: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(CompetitionRecord.schema)
            .id()
            // **`ON DELETE CASCADE`** (`D-73`): es el mecanismo con el que §5.4
            // diseña la purga de temporada. Lo que impide que un borrado normal
            // se lleve el subárbol es la guarda de "cero dependientes → 409" del
            // caso de uso, no el esquema.
            .field("season_id", .uuid, .required,
                   .references(SeasonRecord.schema, "id", onDelete: .cascade))
            .field("modality", .string, .required)
            .field("gender", .string, .required)
            .field("age_category", .string, .required)
            .field("federation_competition_id", .string, .required)
            .field("federation_group_id", .string, .required)
            .field("division_label", .string, .required)
            .field("group_label", .string, .required)
            .field("federation_name", .string)
            .field("last_synced_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            // §3.5: la clave única de la entidad. **No lleva
            // `federation_competition_id`**: el id de grupo ya es único dentro de
            // la temporada. Y lleva `season_id` porque el id de grupo envuelve
            // categoría + división + grupo, pero **no la temporada** — sin él, la
            // misma competición no podría existir en dos temporadas.
            .unique(on: "season_id", "federation_group_id")
            .create()

        // Índice por la FK (§3.5). El `UNIQUE` de arriba ya sirve las consultas
        // que empiezan por `season_id`, pero se declara explícito porque es la
        // convención del modelo y porque el compuesto podría cambiar de forma.
        try await database.index(
            table: CompetitionRecord.schema, name: "idx_competitions_season",
            columns: ["season_id"])

        // Los `CHECK` de los tres enumerados (§4.6, `D-02`), **derivados de los
        // `enum` del Dominio**, no tecleados: añadir un valor al enumerado sin
        // tocar el `CHECK` compilaría y reventaría en producción.
        try await database.checkConstraint(
            table: CompetitionRecord.schema, name: "chk_competitions_modality",
            expression: "modality IN (\(Modality.sqlValueList))")
        try await database.checkConstraint(
            table: CompetitionRecord.schema, name: "chk_competitions_gender",
            expression: "gender IN (\(Gender.sqlValueList))")
        try await database.checkConstraint(
            table: CompetitionRecord.schema, name: "chk_competitions_age_category",
            expression: "age_category IN (\(TeamCategory.sqlValueList))")
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(CompetitionRecord.schema).delete()
    }
}

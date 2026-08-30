import Domain
public import Fluent
import Foundation

/// Modelo de persistencia de la jornada (§4.4).
public final class RoundRecord: Model, @unchecked Sendable {
    public static let schema = "rounds"

    @ID(key: .id) public var id: UUID?

    @Parent(key: "competition_id") public var competition: CompetitionRecord

    /// El `codjornada` de la fuente, no el índice del array ([Anexo RFFM §F.15]).
    @Field(key: "number") public var number: Int

    /// **Derivadas, y aquí sí son fuente de verdad** — al revés que las de
    /// `Season`: `D-81` las calcula de las fechas de los partidos **de esta
    /// pasada**, y los partidos son entidades hermanas, no un campo de la fila.
    /// Recalcularlas al leer exigiría consultar `matches`.
    @Field(key: "start_date") public var startDate: Date
    @Field(key: "end_date") public var endDate: Date

    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}
}

/// Séptima del orden de FK de §4.6, **detrás de `Competition`**.
public struct CreateRound: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(RoundRecord.schema)
            .id()
            // **`ON DELETE CASCADE`** por `D-73`: es como §5.4 ejecuta la purga
            // de temporada, y `Round` cuelga de `Competition`, que cuelga de
            // `Season`. La guarda del borrado normal sigue estando en el caso de
            // uso, no aquí.
            .field("competition_id", .uuid, .required,
                   .references(CompetitionRecord.schema, "id", onDelete: .cascade))
            .field("number", .int, .required)
            .field("start_date", .date, .required)
            .field("end_date", .date, .required)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            // §3.5: Único(competición, número). Las dos columnas son `NOT NULL`,
            // así que un `UNIQUE` normal basta — no aplica la trampa de `Team`.
            .unique(on: "competition_id", "number")
            .create()

        try await database.index(
            table: RoundRecord.schema, name: "idx_rounds_competition",
            columns: ["competition_id"])
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(RoundRecord.schema).delete()
    }
}

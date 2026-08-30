import Domain
public import Fluent
import Foundation

/// Modelo de persistencia del registro de pasadas (§4.4).
public final class IngestionRunRecord: Model, @unchecked Sendable {
    public static let schema = "ingestion_runs"

    @ID(key: .id) public var id: UUID?

    @Parent(key: "competition_id") public var competition: CompetitionRecord

    @Field(key: "started_at") public var startedAt: Date
    @Field(key: "finished_at") public var finishedAt: Date

    @Field(key: "outcome") public var outcome: String
    @OptionalField(key: "error") public var error: String?

    @Field(key: "opponent_clubs_created") public var opponentClubsCreated: Int
    @Field(key: "opponent_clubs_updated") public var opponentClubsUpdated: Int
    @Field(key: "teams_created") public var teamsCreated: Int
    @Field(key: "teams_updated") public var teamsUpdated: Int
    @Field(key: "rounds_created") public var roundsCreated: Int
    @Field(key: "rounds_updated") public var roundsUpdated: Int
    @Field(key: "matches_created") public var matchesCreated: Int
    @Field(key: "matches_updated") public var matchesUpdated: Int

    /// Documento, no tabla hija.
    ///
    /// **Va envuelto en un `struct` y no como `[IngestionSkip]` a pelo**, y lo
    /// descubrió Postgres: PostgresKit mapea un array de Swift a un **array de
    /// Postgres**, así que un `@Field` de tipo array acaba enlazándose como
    /// `jsonb[]` contra una columna `jsonb` — `42804: column "skipped" is of type
    /// jsonb but expression is of type jsonb[]`. Con un objeto envolvente hay un
    /// solo documento y el tipo casa.
    ///
    /// De paso, la forma guardada (`{"rows":[…]}`) es extensible: añadir un
    /// contador o una marca al documento no obliga a migrar las filas viejas.
    @Field(key: "skipped") public var skipped: SkippedRows

    /// El envoltorio de arriba. Vive aquí, en persistencia, y no en el Dominio:
    /// es una consecuencia de cómo enlaza el driver, no del modelo.
    public struct SkippedRows: Codable, Sendable {
        public var rows: [IngestionSkip]
        public init(rows: [IngestionSkip]) { self.rows = rows }
    }

    /// **Sin `updated_at`**, y es la única tabla del modelo que no lo lleva: una
    /// pasada no se modifica. `created_at` tampoco haría falta —`finished_at` es
    /// más preciso y significa algo— pero se conserva por convención de §3.5.
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?

    public init() {}
}

/// **La entidad 21 del modelo**, y la única que F5 añade a §3.2. Va al final del
/// orden de FK de §4.6 porque depende de `Competition` y de nadie más.
public struct CreateIngestionRun: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(IngestionRunRecord.schema)
            .id()
            // `CASCADE` como el resto del subárbol de `Season` (`D-73`): purgar
            // una temporada se lleva también el registro de sus sincronizaciones,
            // que sin la competición no significan nada.
            .field("competition_id", .uuid, .required,
                   .references(CompetitionRecord.schema, "id", onDelete: .cascade))
            .field("started_at", .datetime, .required)
            .field("finished_at", .datetime, .required)
            .field("outcome", .string, .required)
            .field("error", .string)
            .field("opponent_clubs_created", .int, .required)
            .field("opponent_clubs_updated", .int, .required)
            .field("teams_created", .int, .required)
            .field("teams_updated", .int, .required)
            .field("rounds_created", .int, .required)
            .field("rounds_updated", .int, .required)
            .field("matches_created", .int, .required)
            .field("matches_updated", .int, .required)
            .field("skipped", .json, .required)
            .field("created_at", .datetime)
            .create()

        // **Sin `UNIQUE` ninguno**, y es lo correcto: dos pasadas de la misma
        // competición en el mismo minuto son un caso real —un reintento— y no un
        // duplicado. Es la primera tabla del modelo sin clave natural.
        //
        // El índice es el de la consulta que se le hace: las últimas pasadas de
        // una competición, de la más reciente a la más antigua.
        try await database.index(
            table: IngestionRunRecord.schema, name: "idx_ingestion_runs_competition",
            columns: ["competition_id", "finished_at"])

        try await database.checkConstraint(
            table: IngestionRunRecord.schema, name: "chk_ingestion_runs_outcome",
            expression: "outcome IN (\(IngestionOutcome.sqlValueList))")

        // El par que el Dominio ata en su `init` y aquí se ata también: un fallo
        // sin motivo no se puede depurar, y un éxito con motivo es una
        // contradicción. Es el mismo criterio que `D-42` aplica a
        // `Appearance.minutes`.
        try await database.checkConstraint(
            table: IngestionRunRecord.schema, name: "chk_ingestion_runs_error",
            expression: "(outcome = 'failed') = (error IS NOT NULL)")
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(IngestionRunRecord.schema).delete()
    }
}

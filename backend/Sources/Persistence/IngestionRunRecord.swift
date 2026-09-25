import Domain
public import Fluent
import FluentSQL
import Foundation

/// Modelo de persistencia del registro de pasadas (§4.4).
public final class IngestionRunRecord: Model, @unchecked Sendable {
    public static let schema = "ingestion_runs"

    @ID(key: .id) public var id: UUID?

    @Parent(key: "competition_id") public var competition: CompetitionRecord

    @Field(key: "started_at") public var startedAt: Date
    /// **Anulable desde `C-A.5`** (`D-96`): nulo exactamente cuando la pasada
    /// está `accepted`. La **columna** sigue siendo `NOT NULL` hasta `C-D.5`, que
    /// es la migración que la afloja; hasta entonces nadie escribe una aceptada,
    /// porque la cascada que las crea es del Bloque C.
    @OptionalField(key: "finished_at") public var finishedAt: Date?

    @Field(key: "outcome") public var outcome: String
    @OptionalField(key: "error") public var error: String?

    /// Qué se sincronizó (F7). Ver `AddStandingsToIngestionRun`.
    @Field(key: "kind") public var kind: String

    /// De qué jornada, si va de una. Ver `AddIngestionRunRound`.
    @OptionalParent(key: "round_id") public var round: RoundRecord?

    @Field(key: "opponent_clubs_created") public var opponentClubsCreated: Int
    @Field(key: "opponent_clubs_updated") public var opponentClubsUpdated: Int
    @Field(key: "teams_created") public var teamsCreated: Int
    @Field(key: "teams_updated") public var teamsUpdated: Int
    @Field(key: "rounds_created") public var roundsCreated: Int
    @Field(key: "rounds_updated") public var roundsUpdated: Int
    @Field(key: "matches_created") public var matchesCreated: Int
    @Field(key: "matches_updated") public var matchesUpdated: Int
    @Field(key: "standing_rows_created") public var standingRowsCreated: Int
    @Field(key: "standing_rows_updated") public var standingRowsUpdated: Int

    /// Los tres de F8. Ver `AddScorersToIngestionRun`. **El tercero no tiene
    /// hermano en ninguna otra entidad**: cuenta filas *borradas*, porque
    /// `LeagueScorer` es la única salida de la ingesta que borra (`D-94`).
    @Field(key: "league_scorers_created") public var leagueScorersCreated: Int
    @Field(key: "league_scorers_updated") public var leagueScorersUpdated: Int
    @Field(key: "league_scorers_retired") public var leagueScorersRetired: Int

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

/// **Lo que F7 le añade al registro de pasadas, sin tocar `CreateIngestionRun`.**
///
/// # Por qué una migración nueva y no tres líneas en la de F5
///
/// Porque `D-90`: `_fluent_migrations` guarda **el nombre** de cada migración
/// aplicada, no su contenido. Un *schema* que ya aplicó `CreateIngestionRun` **no
/// recibiría jamás** una edición posterior de su `prepare` —sin error y sin
/// aviso—, así que el club del desarrollador tendría las tres columnas y un club
/// vivo no. Es el caso que ya ocurrió una vez con `CreateClub` (`A-5`/H-31).
///
/// # Las tres columnas, y por qué cada una
///
/// - **`kind`** — hasta F6 la ingesta tenía **una** operación y el registro podía
///   dar por supuesto de qué hablaba. Con la clasificación teniendo su propio
///   `execute`, una competición deja **dos filas por disparo**: misma
///   competición, misma hora, y los ocho contadores del calendario a cero en una
///   de ellas. Sin esto, *"esos contadores no van con esto"* se lee como *"no
///   hizo nada"*.
/// - **`standing_rows_created` / `_updated`** — el par que le toca a la entidad
///   que la pasada escribe, igual que las otras cuatro. Sin él, la clasificación
///   sería la única entidad escrita sin contador. Y lo que cuentan no es
///   deducible después: no es *cuántas jornadas tiene la competición* —eso es
///   fijo— sino **cuántas filas escribió esta pasada**, que es una en régimen y
///   veinticinco en la primera de un alta a mitad de temporada.
///
/// # El `DEFAULT` es el backfill, y es exacto
///
/// `'calendar'` y `0` no son valores de relleno prudentes: son **lo que esas
/// filas son**. Toda fila que ya exista se escribió cuando la única pasada
/// posible era la del calendario, y ninguna escribió una fila de clasificación
/// porque la tabla no existía. No hay que adivinar nada.
///
/// # Lo que NO se toca, y conviene decirlo
///
/// Los dos `CHECK` de `CreateIngestionRun`. `outcome` sigue siendo
/// `succeeded`/`failed` —una clasificación se escribe entera o no se escribe— y
/// `(outcome = 'failed') = (error IS NOT NULL)` vale igual: un fallo de
/// clasificación también tiene motivo.
public struct AddStandingsToIngestionRun: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(IngestionRunRecord.schema)
            .field("kind", .string, .required, .sql(.default("calendar")))
            .field("standing_rows_created", .int, .required, .sql(.default(0)))
            .field("standing_rows_updated", .int, .required, .sql(.default(0)))
            .update()

        // Derivado del enumerado y no tecleado (`D-02`), igual que el de
        // `outcome`: el caso que F8 añada lo hereda sin tocar SQL.
        try await database.checkConstraint(
            table: IngestionRunRecord.schema, name: "chk_ingestion_runs_kind",
            expression: "kind IN (\(IngestionKind.sqlValueList))")
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(IngestionRunRecord.schema)
            .deleteField("kind")
            .deleteField("standing_rows_created")
            .deleteField("standing_rows_updated")
            .update()
    }
}

/// **`round_id`: el agujero que F7 destapa, no un campo nuevo.**
///
/// `ingestion_runs` decía *"qué competición"* y no *"qué jornada"*, y bastaba
/// mientras la única pasada posible era la del calendario, que es agnóstica de
/// jornada por construcción: su endpoint devuelve la competición entera en una
/// petición (§5.6). La de clasificación es lo contrario —`/api/standings?round=N`
/// sirve **una**—, así que una pasada **es** una jornada, y sin esta columna las
/// diez de un alta en la jornada 10 serían **diez filas idénticas**.
///
/// # Migración aparte de `AddStandingsToIngestionRun`, y no por gusto
///
/// Aquélla **ya está aplicada** —se corrió contra la base de trabajo el mismo día
/// que se escribió—, así que `D-90` la declara inmutable: `_fluent_migrations`
/// guarda su **nombre**, no su contenido, y añadirle una línea dejaría al club
/// existente sin la columna y a un alta limpia con ella. Es exactamente el `md5`
/// que `A-5`/H-38 comprobó que cuadra, dejando de cuadrar.
///
/// # `NULL` no es "no lo sé", es "esta pasada no va de una jornada"
///
/// Por eso el `CHECK` ata la pareja en vez de dejar la columna suelta, que es el
/// mismo trato que recibe `(outcome = 'failed') = (error IS NOT NULL)`: una
/// pasada de clasificación sin jornada no se puede leer, y una de calendario con
/// jornada dice algo que no es verdad. Los goleadores de F8 caerán del lado nulo
/// —`LeagueScorer` es estado vigente único, no *snapshot* por jornada (§3.2)—, y
/// la expresión ya los admite sin tocarla.
public struct AddIngestionRunRound: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(IngestionRunRecord.schema)
            // `CASCADE` como el resto del subárbol de `Season` (`D-73`), y por lo
            // mismo que `competition_id`: purgar una temporada se lleva el
            // registro de sus sincronizaciones, que sin la jornada no significan
            // nada.
            .field("round_id", .uuid, .references(RoundRecord.schema, "id", onDelete: .cascade))
            .update()

        try await database.checkConstraint(
            table: IngestionRunRecord.schema, name: "chk_ingestion_runs_round",
            expression: "(kind = 'standings') = (round_id IS NOT NULL)")

        // El índice de la consulta que llega con F7: *"¿está sincronizada la
        // clasificación de esta jornada?"*. Parcial, porque las filas del
        // calendario tienen la columna nula y no se consultan por ella.
        try await database.index(
            table: IngestionRunRecord.schema, name: "idx_ingestion_runs_round",
            columns: ["round_id"])
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(IngestionRunRecord.schema)
            .deleteField("round_id")
            .update()
    }
}

/// **F10-bis · La migración de [D-96]: la pasada que todavía no ha corrido.**
///
/// Tres cosas en una, porque son la misma decisión vista desde tres columnas:
///
/// 1. **`finished_at` deja de ser obligatoria.** Una pasada `accepted` no ha
///    acabado, así que no tiene cuándo. Las dos alternativas que [D-96] descartó
///    están escritas allí: `finishedAt = startedAt` provisional es *"una fila que
///    miente"* —el defecto que F6 destapó mirando la tabla de verdad— y dejar el
///    orden en `finished_at` deja al `NULL` decidiendo dónde cae en el `ORDER BY`.
/// 2. **El `CHECK` de `outcome` se rehace.** No lo hereda solo, y eso está
///    medido: la derivación de [D-02] ocurre **cuando la migración corre** y su
///    texto se congela en el *schema* (ver `replaceCheckConstraint`). Sin esto, un
///    club vivo rechazaría la fila nueva con un `23514` que nadie relaciona con un
///    `enum`. Es la lección de F8 cobrándose por segunda vez, en la fase siguiente.
/// 3. **El índice pasa a `(competition_id, started_at)`**, que es por donde va a
///    ordenar la consulta del registro (`C-D.6`). El viejo
///    —`(competition_id, finished_at)`— **se deja en pie a propósito**: hasta que
///    ese ciclo cambie el `ORDER BY`, es el que la consulta usa. Quitarlo es de
///    `C-D.6`, con su propia migración ([D-90]).
///
/// **Y se añade un `CHECK` que el esquema no tenía cómo expresar antes**: el par
/// `(outcome = 'accepted') = (finished_at IS NULL)`, que es la invariante del
/// `init` del Dominio (`C-A.5`) bajada a la tabla. Mismo reparto que
/// `chk_ingestion_runs_error` y por el mismo motivo (§4.6): lo que entra por un
/// `script` no pasa por el Dominio.
public struct AllowAcceptedIngestionRun: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.dropNotNull(
            table: IngestionRunRecord.schema, column: "finished_at")

        try await database.replaceCheckConstraint(
            table: IngestionRunRecord.schema, name: "chk_ingestion_runs_outcome",
            expression: "outcome IN (\(IngestionOutcome.sqlValueList))")

        try await database.checkConstraint(
            table: IngestionRunRecord.schema, name: "chk_ingestion_runs_finished",
            expression: "(outcome = 'accepted') = (finished_at IS NULL)")

        try await database.index(
            table: IngestionRunRecord.schema,
            name: "idx_ingestion_runs_competition_started",
            columns: ["competition_id", "started_at"])
    }

    public func revert(on database: any Database) async throws {
        try await database.dropIndex(name: "idx_ingestion_runs_competition_started")

        try await database.dropCheckConstraint(
            table: IngestionRunRecord.schema, name: "chk_ingestion_runs_finished")

        // **Volver a `NOT NULL` exige que no quede ni un nulo, y los que hay son
        // exactamente las pasadas aceptadas.** Se borran, y es lo honesto: lo que
        // se está revirtiendo es el estado `accepted`, así que una fila en ese
        // estado no puede sobrevivir a su propia desaparición. No se rellena su
        // `finished_at` con nada, que sería la fila que miente de [D-96].
        //
        // Se filtra por la columna y no por el desenlace a propósito: es la
        // condición que `SET NOT NULL` va a comprobar, y la única que no depende
        // de que el `CHECK` que acabamos de tirar fuera cierto.
        if let sql = database as? any SQLDatabase {
            try await sql.raw(
                """
                DELETE FROM \(ident: IngestionRunRecord.schema) \
                WHERE \(ident: "finished_at") IS NULL
                """
            ).run()
        }

        try await database.setNotNull(
            table: IngestionRunRecord.schema, column: "finished_at")

        // **El `CHECK` de `outcome` NO se toca, y es la misma decisión que tomó
        // F8**: revertir esta migración no revierte el `enum` de Swift, así que
        // teclear aquí el `ARRAY` de ayer dejaría el *schema* rechazando filas que
        // el código sigue sabiendo escribir ([D-02]). Sin `accepted` posible por
        // el `NOT NULL` de arriba, además, no hace falta.
    }
}

/// **F10 · `C-D.6`: se retira el índice que se quedó sin consulta.**
///
/// `CreateIngestionRun` creó `idx_ingestion_runs_competition` sobre
/// (`competition_id`, `finished_at`) porque ése era el orden del registro.
/// F10-bis añadió su pareja por `started_at` y **dejó el viejo en pie a
/// propósito** —hasta este ciclo seguía siendo el que la consulta usaba—. Con
/// `list` ya ordenando por `started_at` ([D-96]), no le queda un solo lector.
///
/// **Va en una migración propia y no editando `AllowAcceptedIngestionRun`**, que
/// es lo que [D-90] obliga: aquélla ya está aplicada. Y va en una migración
/// propia también dentro de F10 —no junto a `CreateTeamRegistration`— porque no
/// son la misma razón: una crea la tabla de [D-68], ésta retira un índice
/// obsoleto. Una migración que hace dos cosas no se puede revertir a medias.
public struct DropFinishedAtIngestionRunIndex: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.dropIndex(name: "idx_ingestion_runs_competition")
    }

    public func revert(on database: any Database) async throws {
        try await database.index(
            table: IngestionRunRecord.schema, name: "idx_ingestion_runs_competition",
            columns: ["competition_id", "finished_at"])
    }
}

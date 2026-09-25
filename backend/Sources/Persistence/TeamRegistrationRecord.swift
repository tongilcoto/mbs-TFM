import Domain
public import Fluent
import Foundation

/// Modelo de persistencia de la inscripción (§4.4, [D-68]).
///
/// **Doble `@Parent`** (`team_id` y `season_id`), igual que `PlayerRecord` y por
/// la misma razón (§4.4): la fila **es** el par. Y un `@OptionalParent` para la
/// competición, que es la tercera pata de la clave y llega **después** — la pone
/// la cascada del enganche ([D-67]) sobre la fila que el club escribió en junio.
///
/// **Sin campos propios**, y es deliberado (§3.2): la fuente es el club, que no
/// tiene ni fecha ni estado federativo que aportar. **Sin `deleted_at`**: una
/// retirada es borrado real, no hay historial que auditar.
public final class TeamRegistrationRecord: Model, @unchecked Sendable {
    public static let schema = "team_registrations"

    @ID(key: .id) public var id: UUID?

    @Parent(key: "team_id") public var team: TeamRecord
    @Parent(key: "season_id") public var season: SeasonRecord

    /// **Nulo ⇒ *"inscrito, sin competición conocida"*** ([D-68] enmienda): la
    /// fila de junio, cuando la federación todavía no ha publicado calendario.
    /// No es un atributo suelto — **entra en la clave**, que es lo que obliga al
    /// `NULLS NOT DISTINCT` de `C-D.3`.
    @OptionalParent(key: "competition_id") public var competition: CompetitionRecord?

    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}
}

/// **La tabla de [D-68]**, y llega en F10 porque su segundo escritor es la
/// cascada del enganche ([D-67]).
///
/// # Dónde va en el orden de FK, y por qué no donde §4.6 la pintaba
///
/// El orden canónico de `TenantMigrations` la ponía **entre `Team` y
/// `Competition`**, que era su sitio cuando la fila era el par
/// `(equipo, temporada)`. La enmienda de [D-68] le añadió `competition_id` **a
/// la clave**, y con la FK compuesta de `C-D.3` la tabla pasa a depender de
/// `competitions`: su sitio es **detrás**. No es una excepción a [D-90] — es
/// [D-90] aplicado: lo que cambió es de quién depende.
public struct CreateTeamRegistration: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(TeamRegistrationRecord.schema)
            .id()
            // **`CASCADE` desde las dos**, y hay que declararlo (§4.6): borrar el
            // equipo o purgar la temporada (§5.4) se lleva la inscripción por
            // delante, **nunca al revés**. Sin esto, la purga de [D-24] se
            // llevaría los equipos del club.
            .field("team_id", .uuid, .required,
                   .references(TeamRecord.schema, "id", onDelete: .cascade))
            .field("season_id", .uuid, .required,
                   .references(SeasonRecord.schema, "id", onDelete: .cascade))
            .field("competition_id", .uuid)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        // La clave de §3.5, y **no con `.unique(on:)`**: `competition_id` es
        // anulable —la fila de junio— y en Postgres los `NULL` no comparan
        // iguales, así que un `UNIQUE` normal deja entrar dos
        // `(equipo, temporada, NULL)` y el mismo equipo sale dos veces en la
        // portada de §9.12. Es la trampa que la clave de `Team` ya se comió en
        // F5; [D-68] la deja escrita para pagarla una sola vez.
        try await database.uniqueIndexNullsNotDistinct(
            table: TeamRegistrationRecord.schema, name: "uq_team_registrations_identity",
            columns: ["team_id", "season_id", "competition_id"])

        // **El apoyo que la FK compuesta necesita, y va sobre `competitions`.**
        // Postgres exige que las columnas referenciadas sean las de una
        // restricción `UNIQUE`, y `competitions` solo tiene la suya sobre
        // (`season_id`, `federation_group_id`). No se añade editando
        // `CreateCompetition` —[D-90]: esa migración ya está aplicada en los
        // clubes vivos— sino aquí, que es la migración nueva que la necesita.
        // Cuesta una restricción redundante sobre una tabla que ya tiene `id`
        // como clave primaria: §4.6 lo dice y lo da por bueno.
        try await database.uniqueConstraint(
            table: CompetitionRecord.schema, name: "uq_competitions_id_season",
            columns: ["id", "season_id"])

        // **La coherencia de [D-61], bajada al esquema**: una inscripción no
        // puede apuntar a una competición de otra temporada. Con `CASCADE`, como
        // el resto del subárbol de `Season` ([D-73]): es el mecanismo con el que
        // §5.4 purga, y la cascada se detiene aquí ([D-68]).
        try await database.compositeForeignKey(
            table: TeamRegistrationRecord.schema,
            name: "fk_team_registrations_competition_season",
            columns: ["competition_id", "season_id"],
            references: CompetitionRecord.schema, referencedColumns: ["id", "season_id"],
            onDelete: "CASCADE")

        // ── `C-D.4` · `A-5`·H-36, y viaja aquí por [D-90] ───────────────────
        //
        // §4.6 manda **dos índices compuestos** en `Match` —*"son los que
        // sostienen la composición de la competición ahora que no hay tabla
        // pivote"* ([D-27])— y `CreateMatch` creó cuatro de una sola columna. La
        // auditoría lo anotó como discrepancia código↔diseño, no como
        // rendimiento, y falló a favor del diseño: falta el índice.
        //
        // **Van en esta migración y no editando `CreateMatch`** porque aquélla
        // está aplicada en los clubes vivos y una migración aplicada es inmutable
        // ([D-90]). Que la migración que los trae sea la de `TeamRegistration` es
        // lo que el plan de F10 decidió, y no es casual: las dos son la misma
        // lectura —qué equipos forman esta competición— vista desde los dos
        // lados, el derivado de `Match` y el afirmado por el club ([D-68]).
        for lado in ["home_team_id", "away_team_id"] {
            try await database.index(
                table: MatchRecord.schema, name: "idx_matches_competition_\(lado)",
                columns: ["competition_id", lado])
        }
    }

    public func revert(on database: any Database) async throws {
        // Primero la tabla: se lleva con ella su índice único y la FK compuesta.
        try await database.schema(TeamRegistrationRecord.schema).delete()
        // Y después lo que esta migración le prestó a `competitions`, que no se
        // va con nadie. Se deshace lo propio y **solo** lo propio: el `UNIQUE`
        // de (`season_id`, `federation_group_id`) es de `CreateCompetition`.
        try await database.dropConstraint(
            table: CompetitionRecord.schema, name: "uq_competitions_id_season")
        // Y los dos índices de `Match` que esta migración añadió (`C-D.4`): no
        // se van con ninguna tabla, porque su tabla sigue en pie.
        for lado in ["home_team_id", "away_team_id"] {
            try await database.dropIndex(name: "idx_matches_competition_\(lado)")
        }
    }
}

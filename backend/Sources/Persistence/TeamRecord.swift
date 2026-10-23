import Domain
public import Fluent
import SQLKit
import Foundation

/// Modelo de persistencia del equipo (§4.4).
public final class TeamRecord: Model, @unchecked Sendable {
    public static let schema = "teams"

    @ID(key: .id) public var id: UUID?

    /// **Nulo ⇒ equipo propio** (§3.6, `D-03`). `@OptionalParent` y no un `UUID`
    /// suelto, por lo mismo que en `CompetitionRecord`: el *eager loading* de las
    /// lecturas lo necesita disponible (§4.5).
    @OptionalParent(key: "opponent_club_id") public var opponentClub: OpponentClubRecord?

    /// **La temporada del rival** (`D-104`): nula en los propios, obligatoria en
    /// los rivales. La añade `AddSeasonToOpponentTeams`, no `CreateTeam` ([D-90]).
    @OptionalParent(key: "season_id") public var season: SeasonRecord?

    @Field(key: "category") public var category: String
    @OptionalField(key: "letter") public var letter: String?
    @Field(key: "gender") public var gender: String
    @Field(key: "modality") public var modality: String

    @OptionalField(key: "federation_team_id") public var federationTeamID: String?

    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}
}

/// Cuarta del orden de FK de §4.6, **detrás de `OpponentClub`** por su FK.
public struct CreateTeam: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(TeamRecord.schema)
            .id()
            // **Sin cascada, y a propósito.** Borrar un club rival no es un
            // camino que F5 abra —la ingesta no borra (`D-75`) y el BFF no tiene
            // `DELETE` sobre esta entidad (§5.1)—, así que el esquema se queda en
            // `NO ACTION`: si algún día alguien lo intenta, la FK lo para en vez
            // de llevarse por delante equipos y, tras ellos, partidos.
            .field("opponent_club_id", .uuid,
                   .references(OpponentClubRecord.schema, "id"))
            .field("category", .string, .required)
            .field("letter", .string)
            .field("gender", .string, .required)
            .field("modality", .string, .required)
            .field("federation_team_id", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            // Criterio **por defecto**, y aquí es el bueno (§3.5): muchos equipos
            // sin enganchar, ningún `codigo_equipo` repetido.
            .unique(on: "federation_team_id")
            .create()

        // La clave única de §3.5, y **no con `.unique(on:)`**: dos de sus cinco
        // columnas son anulables —`opponent_club_id` lo es en **todos** los
        // equipos propios y `letter` en los clubes sin filial—, y en Postgres los
        // `NULL` no comparan iguales. Con un `UNIQUE` normal esta tabla acepta
        // dos "Cadete A" propios idénticos, comprobado contra Postgres.
        try await database.uniqueIndexNullsNotDistinct(
            table: TeamRecord.schema, name: "uq_teams_identity",
            columns: ["opponent_club_id", "category", "letter", "gender", "modality"])

        try await database.index(
            table: TeamRecord.schema, name: "idx_teams_opponent_club",
            columns: ["opponent_club_id"])

        try await database.checkConstraint(
            table: TeamRecord.schema, name: "chk_teams_category",
            expression: "category IN (\(TeamCategory.sqlValueList))")
        try await database.checkConstraint(
            table: TeamRecord.schema, name: "chk_teams_gender",
            expression: "gender IN (\(Gender.sqlValueList))")
        try await database.checkConstraint(
            table: TeamRecord.schema, name: "chk_teams_modality",
            expression: "modality IN (\(Modality.sqlValueList))")
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(TeamRecord.schema).delete()
    }
}

/// `D-104`: el equipo rival pasa a ser **de una temporada**.
///
/// Su letra y su código son los que la federación publica ese año, y pueden
/// cambiar al siguiente, así que la temporada entra en sus dos claves únicas.
/// El propio no la lleva: su temporada va en la inscripción ([D-68]).
///
/// 1. **La guarda**, antes de tocar nada: un rival con partidos o
///    clasificación de **varias** temporadas no cabe en una fila, y la
///    migración se para en vez de repartirlos. No puede haberlo en un club con
///    una sola temporada cargada, y desde aquí no puede nacer otro.
/// 2. Añade la columna, con cascada desde la temporada: borrar una temporada
///    ([D-24]) ya se lleva sus competiciones y sus partidos, y con ellos sobran
///    sus rivales.
/// 3. Borra el rival que nada referencia: no hay de dónde sacar su temporada, y
///    si la federación lo vuelve a publicar la ingesta lo crea con la suya.
/// 4. Da a cada rival la temporada de sus partidos o de su clasificación.
/// 5. Las reglas: el `CHECK` de la pareja club rival ⇔ temporada, y las dos
///    claves únicas rehechas con la temporada delante.
///
/// **Una migración nueva y no una edición** de `CreateTeam`, que ya está
/// aplicada en los clubes vivos ([D-90]).
public struct AddSeasonToOpponentTeams: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        guard let sql = database as? any SQLDatabase else {
            throw PersistenceError.schemaHelperNeedsSQL(
                helper: "AddSeasonToOpponentTeams", object: TeamRecord.schema)
        }

        // Las temporadas en las que aparece cada rival: por sus partidos, de
        // local o de visitante, y por su fila de clasificación.
        let uses: SQLQueryString = """
            SELECT m.home_team_id AS team_id, c.season_id FROM \(ident: MatchRecord.schema) m
              JOIN \(ident: CompetitionRecord.schema) c ON c.id = m.competition_id
            UNION SELECT m.away_team_id, c.season_id FROM \(ident: MatchRecord.schema) m
              JOIN \(ident: CompetitionRecord.schema) c ON c.id = m.competition_id
            UNION SELECT r.team_id, c.season_id FROM \(ident: StandingRowRecord.schema) r
              JOIN \(ident: CompetitionRecord.schema) c ON c.id = r.competition_id
            """

        // 1. La guarda, antes de escribir nada.
        let spread = try await sql.raw("""
            SELECT count(*) AS n FROM (
              SELECT u.team_id FROM (\(uses)) u
                JOIN \(ident: TeamRecord.schema) t ON t.id = u.team_id
               WHERE t.opponent_club_id IS NOT NULL
               GROUP BY u.team_id HAVING count(DISTINCT u.season_id) > 1) x
            """).first(decodingColumn: "n", as: Int.self) ?? 0
        guard spread == 0 else {
            throw PersistenceError.migrationWouldLoseData(
                migration: "AddSeasonToOpponentTeams",
                reason: "\(spread) equipo(s) rival(es) con partidos o clasificación de "
                    + "varias temporadas: no caben en una sola fila (D-104)")
        }

        // 2. La columna.
        try await database.schema(TeamRecord.schema)
            .field("season_id", .uuid,
                   .references(SeasonRecord.schema, "id", onDelete: .cascade))
            .update()

        // 3. El rival que nada referencia.
        try await sql.raw("""
            DELETE FROM \(ident: TeamRecord.schema) t
             WHERE t.opponent_club_id IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM (\(uses)) u WHERE u.team_id = t.id)
            """).run()

        // 4. Los datos.
        try await sql.raw("""
            UPDATE \(ident: TeamRecord.schema) t SET season_id = u.season_id
              FROM (\(uses)) u
             WHERE u.team_id = t.id AND t.opponent_club_id IS NOT NULL
            """).run()

        // 5. Las reglas.
        try await database.checkConstraint(
            table: TeamRecord.schema, name: "chk_teams_season_only_opponents",
            expression: "(opponent_club_id IS NULL) = (season_id IS NULL)")
        try await database.dropConstraint(
            table: TeamRecord.schema, name: "uq:teams.federation_team_id")
        // Un `UNIQUE` normal, como el que sustituye: muchas filas sin código y
        // ningún código repetido **en la misma temporada** (§3.5).
        try await database.uniqueConstraint(
            table: TeamRecord.schema, name: "uq_teams_season_code",
            columns: ["season_id", "federation_team_id"])
        try await database.dropIndex(name: "uq_teams_identity")
        // La temporada delante: es por donde la ingesta filtra los candidatos.
        // En los propios vale `NULL` en todas las filas, y con `NULLS NOT
        // DISTINCT` la clave entre ellos sigue siendo la de siempre.
        try await database.uniqueIndexNullsNotDistinct(
            table: TeamRecord.schema, name: "uq_teams_identity",
            columns: ["season_id", "opponent_club_id", "category", "letter", "gender", "modality"])
    }

    /// Deshace las reglas y la columna. **Los rivales borrados no vuelven**, y
    /// si dos temporadas ya tienen el mismo código o el mismo rival, las claves
    /// de antes no caben: el `revert` es para desarrollo, no para un club vivo.
    public func revert(on database: any Database) async throws {
        try await database.dropIndex(name: "uq_teams_identity")
        try await database.uniqueIndexNullsNotDistinct(
            table: TeamRecord.schema, name: "uq_teams_identity",
            columns: ["opponent_club_id", "category", "letter", "gender", "modality"])
        try await database.dropConstraint(
            table: TeamRecord.schema, name: "uq_teams_season_code")
        try await database.uniqueConstraint(
            table: TeamRecord.schema, name: "uq:teams.federation_team_id",
            columns: ["federation_team_id"])
        try await database.dropConstraint(
            table: TeamRecord.schema, name: "chk_teams_season_only_opponents")
        try await database.schema(TeamRecord.schema)
            .deleteField("season_id")
            .update()
    }
}

public import Domain
public import Fluent
import Foundation
import FluentSQL
import SQLKit

// El acta de un partido (R7, §3.2): la convocatoria, las tarjetas y los goles, las
// tres hijas de `Match` (§4.2). El mapeo al dominio llega con sus operaciones
// (R7.6 a R7.8); aquí, las tablas y lo que solo la base puede sostener.

/// Modelo de persistencia de la convocatoria de un jugador en un partido (§4.4).
///
/// **Sin fila, «no convocado»** ([D-134]). `team_id` es el equipo con el que
/// jugó ([D-128]): un refuerzo cuenta para él, no para el de su plantilla.
public final class AppearanceRecord: Model, @unchecked Sendable {
    public static let schema = "appearances"

    @ID(key: .id) public var id: UUID?

    @Parent(key: "player_id") public var player: PlayerRecord
    @Parent(key: "match_id") public var match: MatchRecord
    @Parent(key: "team_id") public var team: TeamRecord

    @Field(key: "status") public var status: String
    /// El dorsal del acta ([D-129]); la plantilla no se toca.
    @OptionalField(key: "shirt_number") public var shirtNumber: Int?
    /// Solo con `jugado` ([D-42]), de 1 a 120 ([D-134]).
    @OptionalField(key: "minutes") public var minutes: Int?

    @Timestamp(key: "deleted_at", on: .delete) public var deletedAt: Date?
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}
}

/// Modelo de persistencia de una tarjeta (§4.4): **una fila es una sanción**
/// ([D-45]), de un jugador del club ([D-136]).
public final class CardRecord: Model, @unchecked Sendable {
    public static let schema = "cards"

    @ID(key: .id) public var id: UUID?

    @Parent(key: "player_id") public var player: PlayerRecord
    @Parent(key: "match_id") public var match: MatchRecord
    /// El equipo con el que jugaba ([D-128]).
    @Parent(key: "team_id") public var team: TeamRecord

    @Field(key: "type") public var type: String
    @Field(key: "is_second_yellow") public var isSecondYellow: Bool
    @OptionalField(key: "minute") public var minute: Int?
    @OptionalField(key: "comment") public var comment: String?
    /// La trajo el acta ([D-137]): solo se escribe el comentario, y no se borra.
    @Field(key: "from_report") public var fromReport: Bool

    @Timestamp(key: "deleted_at", on: .delete) public var deletedAt: Date?
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}
}

/// Modelo de persistencia de un gol (§4.4), **denormalizado a propósito**: los dos
/// equipos copiados del partido ([D-04], [D-54]).
public final class GoalRecord: Model, @unchecked Sendable {
    public static let schema = "goals"

    @ID(key: .id) public var id: UUID?

    @Parent(key: "match_id") public var match: MatchRecord
    @Parent(key: "scoring_team_id") public var scoringTeam: TeamRecord
    @Parent(key: "conceding_team_id") public var concedingTeam: TeamRecord
    /// Nulo en los goles del rival ([D-09]).
    @OptionalParent(key: "scorer_player_id") public var scorer: PlayerRecord?
    @OptionalParent(key: "assist_player_id") public var assistant: PlayerRecord?

    @Field(key: "assisted") public var assisted: Bool
    @OptionalField(key: "minute") public var minute: Int?
    @OptionalField(key: "zone") public var zone: String?
    @OptionalField(key: "attack_side") public var attackSide: String?
    @OptionalField(key: "shot_side") public var shotSide: String?
    @OptionalField(key: "body_part") public var bodyPart: String?
    /// Nulo es «sin clasificar» ([D-131]).
    @OptionalField(key: "play_type") public var playType: String?
    @OptionalField(key: "comment") public var comment: String?
    /// Lo trajo el acta ([D-137]).
    @Field(key: "from_report") public var fromReport: Bool

    @Timestamp(key: "deleted_at", on: .delete) public var deletedAt: Date?
    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}
}

/// **La migración 25ª** (R7.5): las tres tablas del acta, a la vez.
///
/// # Por qué una y no tres
///
/// §4.6 pide una por entidad, pero estas tres nacen juntas, con la pantalla del
/// acta, y la carga del acta las escribe en la misma pasada ([D-133]). Como las
/// dos de la plantilla ([D-119]), partirlas dejaría estados intermedios que
/// ningún club tendría.
///
/// # Las FK
///
/// **`CASCADE` desde el partido y desde el jugador**: purgar una temporada se
/// lleva sus partidos y su plantilla ([D-24]), y con ellos su acta. La baja de un
/// jugador es lógica ([D-36]) y no borra nada: sus goles y tarjetas siguen
/// contando. **Sin cascada desde el equipo**, como el partido: borrar un equipo
/// no se lleva por delante lo que el partido es también del rival. El goleador y
/// el asistente, **`SET NULL`**: un gol no desaparece porque se borre una fila.
public struct CreateMatchReportTables: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        // ── La convocatoria ──
        try await database.schema(AppearanceRecord.schema)
            .id()
            .field("player_id", .uuid, .required,
                   .references(PlayerRecord.schema, "id", onDelete: .cascade))
            .field("match_id", .uuid, .required,
                   .references(MatchRecord.schema, "id", onDelete: .cascade))
            .field("team_id", .uuid, .required, .references(TeamRecord.schema, "id"))
            .field("status", .string, .required)
            .field("shirt_number", .int)
            .field("minutes", .int)
            .field("deleted_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        try await database.checkConstraint(
            table: AppearanceRecord.schema, name: "chk_appearances_status",
            expression: "status IN (\(AppearanceStatus.sqlValueList))")
        try await database.checkConstraint(
            table: AppearanceRecord.schema, name: "chk_appearances_shirt_number",
            expression: "shirt_number BETWEEN 1 AND 99")
        try await database.checkConstraint(
            table: AppearanceRecord.schema, name: "chk_appearances_minutes",
            expression: "minutes BETWEEN 1 AND 120")
        // **El primer `CHECK` entre columnas** ([D-42]): se refuerza en la base y
        // se dice desde el dominio, que sabe cuál de los dos está mal.
        try await database.checkConstraint(
            table: AppearanceRecord.schema, name: "chk_appearances_minutes_when_played",
            expression: "minutes IS NULL OR status = 'jugado'")

        // **Una convocatoria por jugador y partido**, entre las no borradas (§3.5).
        try await database.partialUniqueIndex(
            table: AppearanceRecord.schema, name: "uq_appearances",
            columns: ["player_id", "match_id"], where: "deleted_at IS NULL")
        // Una puerta de ámbito cada uno ([D-43]), y el equipo, para los refuerzos
        // y las cifras de un equipo ([D-128]).
        try await database.index(
            table: AppearanceRecord.schema, name: "idx_appearances_match", columns: ["match_id"])
        try await database.index(
            table: AppearanceRecord.schema, name: "idx_appearances_player", columns: ["player_id"])
        try await database.index(
            table: AppearanceRecord.schema, name: "idx_appearances_team", columns: ["team_id"])

        // ── Las tarjetas ──
        try await database.schema(CardRecord.schema)
            .id()
            .field("player_id", .uuid, .required,
                   .references(PlayerRecord.schema, "id", onDelete: .cascade))
            .field("match_id", .uuid, .required,
                   .references(MatchRecord.schema, "id", onDelete: .cascade))
            .field("team_id", .uuid, .required, .references(TeamRecord.schema, "id"))
            .field("type", .string, .required)
            .field("is_second_yellow", .bool, .required, .sql(.default(false)))
            .field("minute", .int)
            .field("comment", .string)
            .field("from_report", .bool, .required, .sql(.default(false)))
            .field("deleted_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        try await database.checkConstraint(
            table: CardRecord.schema, name: "chk_cards_type",
            expression: "type IN (\(CardType.sqlValueList))")
        try await database.checkConstraint(
            table: CardRecord.schema, name: "chk_cards_minute", expression: "minute BETWEEN 0 AND 120")
        try await database.checkConstraint(
            table: CardRecord.schema, name: "chk_cards_comment",
            expression: "char_length(comment) BETWEEN 1 AND \(EntryComment.maximumLength)")
        // El segundo entre columnas ([D-45]): la segunda amarilla es una roja.
        try await database.checkConstraint(
            table: CardRecord.schema, name: "chk_cards_second_yellow",
            expression: "NOT is_second_yellow OR type = 'roja'")

        // **Una de cada tipo por jugador y partido** ([D-45]): amarilla y roja
        // directa sí conviven.
        try await database.partialUniqueIndex(
            table: CardRecord.schema, name: "uq_cards",
            columns: ["player_id", "match_id", "type"], where: "deleted_at IS NULL")
        try await database.index(
            table: CardRecord.schema, name: "idx_cards_match", columns: ["match_id"])
        // También el de la cuenta de amarillas pendientes ([D-10]).
        try await database.index(
            table: CardRecord.schema, name: "idx_cards_player", columns: ["player_id"])

        // ── Los goles ──
        try await database.schema(GoalRecord.schema)
            .id()
            .field("match_id", .uuid, .required,
                   .references(MatchRecord.schema, "id", onDelete: .cascade))
            .field("scoring_team_id", .uuid, .required, .references(TeamRecord.schema, "id"))
            .field("conceding_team_id", .uuid, .required, .references(TeamRecord.schema, "id"))
            .field("scorer_player_id", .uuid,
                   .references(PlayerRecord.schema, "id", onDelete: .setNull))
            .field("assist_player_id", .uuid,
                   .references(PlayerRecord.schema, "id", onDelete: .setNull))
            .field("assisted", .bool, .required, .sql(.default(false)))
            .field("minute", .int)
            .field("zone", .string)
            .field("attack_side", .string)
            .field("shot_side", .string)
            .field("body_part", .string)
            .field("play_type", .string)
            .field("comment", .string)
            .field("from_report", .bool, .required, .sql(.default(false)))
            .field("deleted_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()

        for (name, expression) in [
            ("chk_goals_minute", "minute BETWEEN 0 AND 120"),
            ("chk_goals_zone", "zone IN (\(GoalZone.sqlValueList))"),
            ("chk_goals_attack_side", "attack_side IN (\(GoalSide.sqlValueList))"),
            ("chk_goals_shot_side", "shot_side IN (\(GoalSide.sqlValueList))"),
            ("chk_goals_body_part", "body_part IN (\(GoalBodyPart.sqlValueList))"),
            ("chk_goals_play_type", "play_type IN (\(GoalPlayType.sqlValueList))"),
            ("chk_goals_comment", "char_length(comment) BETWEEN 1 AND \(EntryComment.maximumLength)"),
            // Los de la fila (§4.6, [D-52], [D-135]): los dos equipos, distintos; el
            // asistente, con asistencia; la propia puerta, sin ella; el penalti, ni
            // fuera del área ni con lado del remate.
            ("chk_goals_two_teams", "scoring_team_id <> conceding_team_id"),
            ("chk_goals_assist_when_assisted", "assisted OR assist_player_id IS NULL"),
            ("chk_goals_own_goal_no_assist",
             "play_type IS DISTINCT FROM 'en_propia_puerta' OR (NOT assisted AND assist_player_id IS NULL)"),
            ("chk_goals_penalty",
             "play_type IS DISTINCT FROM 'penalti' OR (zone IS DISTINCT FROM 'fuera_area' AND shot_side IS NULL)"),
        ] {
            try await database.checkConstraint(table: GoalRecord.schema, name: name, expression: expression)
        }

        // **Sin unicidad alguna** (§3.5): un jugador marca dos veces. Los índices,
        // los de los dos bloques de estadísticas sin *join* ([D-04]), el relato del
        // partido y el historial del goleador.
        try await database.index(
            table: GoalRecord.schema, name: "idx_goals_scoring_team", columns: ["scoring_team_id"])
        try await database.index(
            table: GoalRecord.schema, name: "idx_goals_conceding_team", columns: ["conceding_team_id"])
        try await database.index(
            table: GoalRecord.schema, name: "idx_goals_match", columns: ["match_id"])
        try await database.index(
            table: GoalRecord.schema, name: "idx_goals_scorer", columns: ["scorer_player_id"])
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(GoalRecord.schema).delete()
        try await database.schema(CardRecord.schema).delete()
        try await database.schema(AppearanceRecord.schema).delete()
    }
}

/// **La migración 26ª** (R7.5): lo que el acta escribe fuera de sus tres tablas.
///
/// - `matches.report_loaded_at`: cuándo la cargó la ingesta, una vez ([D-133]).
/// - `matches.report_lineup`: la convocatoria del acta tal como llegó, para decir
///   qué ha cambiado el club ([D-134]). Un documento (`{"players":[…]}`) y no una
///   tabla: se escribe una vez y se lee entero, con el partido.
/// - `player_profiles.federation_player_id`: el código del jugador en la
///   federación ([D-126]), **único en el club entre los que lo tienen**.
///
/// Anulables todas, sin valor por defecto: «sin cargar» y «sin código» son nulos.
public struct AddMatchReportColumns: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(MatchRecord.schema)
            .field("report_loaded_at", .datetime)
            .field("report_lineup", .json)
            .update()
        // El documento va con la fecha: o los dos, o ninguno.
        try await database.checkConstraint(
            table: MatchRecord.schema, name: "chk_matches_report_lineup_when_loaded",
            expression: "report_lineup IS NULL OR report_loaded_at IS NOT NULL")

        try await database.schema(PlayerProfileRecord.schema)
            .field("federation_player_id", .string)
            .update()
        try await database.partialUniqueIndex(
            table: PlayerProfileRecord.schema, name: "uq_player_profiles_federation_player",
            columns: ["federation_player_id"], where: "federation_player_id IS NOT NULL")
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(PlayerProfileRecord.schema)
            .deleteField("federation_player_id")
            .update()
        try await database.schema(MatchRecord.schema)
            .deleteField("report_lineup")
            .deleteField("report_loaded_at")
            .update()
    }
}

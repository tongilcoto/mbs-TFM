public import Application
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

// ── El mapeo y los repositorios (R7.6) ───────────────────────────────────────

/// **La copia del acta, como se guarda** en `matches.report_lineup`: un objeto con
/// la lista, no la lista a pelo, por lo mismo que `IngestionRunRecord.SkippedRows`.
struct ReportLineupDocument: Codable, Sendable {
    struct Entry: Codable, Sendable {
        let playerId: UUID
        let teamId: UUID
        let status: String
    }
    let players: [Entry]
}

extension AppearanceRecord {
    func toDomain() throws -> Appearance {
        let id = try requireID()
        guard let createdAt, let updatedAt else {
            throw PersistenceError.missingTimestamp(table: Self.schema, id: id.uuidString)
        }
        guard let status = AppearanceStatus(rawValue: status) else {
            throw PersistenceError.corruptEnumeration(table: Self.schema, column: "status", value: status)
        }
        return Appearance(
            id: AppearanceID(raw: id), playerID: PlayerID(raw: $player.id), matchID: MatchID(raw: $match.id),
            teamID: TeamID(raw: $team.id), status: status,
            // **Se vuelven a pasar por sus valores**: lo guardado ya los cumplía, y
            // una fila que no, es la base tocada a mano.
            shirtNumber: try shirtNumber.map(ShirtNumber.init),
            minutes: try minutes.map(MinutesPlayed.init),
            createdAt: createdAt, updatedAt: updatedAt)
    }

    fileprivate func apply(_ appearance: Appearance) {
        $player.id = appearance.playerID.raw
        $match.id = appearance.matchID.raw
        $team.id = appearance.teamID.raw
        status = appearance.status.rawValue
        shirtNumber = appearance.shirtNumber?.value
        minutes = appearance.minutes?.value
    }
}

public struct FluentAppearanceRepository: AppearanceRepository {
    private let database: any Database
    public init(database: any Database) { self.database = database }

    public func find(_ id: AppearanceID) async throws -> Appearance? {
        try await AppearanceRecord.find(id.raw, on: database)?.toDomain()
    }

    /// **Por dorsal del acta**, los que no tienen al final, y luego en el orden en
    /// que se apuntaron; el `id` desempata, para que el orden no dependa de la base.
    public func list(matchID: MatchID, teamID: TeamID?) async throws -> [Appearance] {
        var query = AppearanceRecord.query(on: database).filter(\.$match.$id == matchID.raw)
        if let teamID { query = query.filter(\.$team.$id == teamID.raw) }
        return try await query
            .sort(.sql(unsafeRaw: "shirt_number ASC NULLS LAST"))
            .sort(\.$createdAt)
            .sort(\.$id)
            .all()
            .map { try $0.toDomain() }
    }

    public func list(playerID: PlayerID) async throws -> [Appearance] {
        try await AppearanceRecord.query(on: database)
            .filter(\.$player.$id == playerID.raw)
            .all()
            .map { try $0.toDomain() }
    }

    public func find(playerID: PlayerID, matchID: MatchID) async throws -> Appearance? {
        try await AppearanceRecord.query(on: database)
            .filter(\.$player.$id == playerID.raw)
            .filter(\.$match.$id == matchID.raw)
            .first()?
            .toDomain()
    }

    public func save(_ appearance: Appearance) async throws {
        if let existing = try await AppearanceRecord.find(appearance.id.raw, on: database) {
            existing.apply(appearance)
            try await existing.update(on: database)
        } else {
            let record = AppearanceRecord()
            record.id = appearance.id.raw
            record.apply(appearance)
            try await record.create(on: database)
        }
    }

    public func delete(_ id: AppearanceID) async throws {
        try await AppearanceRecord.find(id.raw, on: database)?.delete(on: database)
    }
}

extension FluentMatchRepository {
    public func find(_ id: MatchID) async throws -> Match? {
        try await MatchRecord.find(id.raw, on: database)?.toDomain()
    }

    /// Con SQL y no con el modelo: las dos columnas son de la carga del acta, y
    /// `MatchRecord` no las lleva para que `save` —la ingesta del calendario— no
    /// pueda pisarlas.
    public func reportCopies(of ids: [MatchID]) async throws -> [MatchID: MatchReportCopy] {
        guard !ids.isEmpty else { return [:] }
        guard let sql = database as? any SQLDatabase else {
            throw PersistenceError.schemaHelperNeedsSQL(helper: "reportCopies", object: MatchRecord.schema)
        }
        let rows = try await sql.raw("""
            SELECT id, report_loaded_at, report_lineup FROM \(ident: MatchRecord.schema)
            WHERE report_loaded_at IS NOT NULL AND id IN (\(binds: ids.map(\.raw)))
            """).all()
        var copies: [MatchID: MatchReportCopy] = [:]
        for row in rows {
            let id = try row.decode(column: "id", as: UUID.self)
            let loadedAt = try row.decode(column: "report_loaded_at", as: Date.self)
            let document = try row.decode(column: "report_lineup", as: ReportLineupDocument?.self)
            let lineup = try (document?.players ?? []).map { entry in
                guard let status = AppearanceStatus(rawValue: entry.status) else {
                    throw PersistenceError.corruptEnumeration(
                        table: MatchRecord.schema, column: "report_lineup", value: entry.status)
                }
                return ReportLineupEntry(playerID: PlayerID(raw: entry.playerId),
                                         teamID: TeamID(raw: entry.teamId), status: status)
            }
            copies[MatchID(raw: id)] = MatchReportCopy(loadedAt: loadedAt, lineup: lineup)
        }
        return copies
    }
}

// ── Los goles (R7.7) ─────────────────────────────────────────────────────────

/// Un enumerado guardado, vuelto a leer: uno que no es del catálogo es la base
/// tocada a mano.
func stored<E: RawRepresentable>(_ raw: String?, _ type: E.Type, table: String, column: String) throws -> E?
    where E.RawValue == String
{
    guard let raw else { return nil }
    guard let value = E(rawValue: raw) else {
        throw PersistenceError.corruptEnumeration(table: table, column: column, value: raw)
    }
    return value
}

extension GoalRecord {
    func toDomain() throws -> Goal {
        let id = try requireID()
        guard let createdAt, let updatedAt else {
            throw PersistenceError.missingTimestamp(table: Self.schema, id: id.uuidString)
        }
        let table = Self.schema
        return Goal(
            id: GoalID(raw: id), matchID: MatchID(raw: $match.id), scoringTeamID: TeamID(raw: $scoringTeam.id),
            concedingTeamID: TeamID(raw: $concedingTeam.id), scorer: $scorer.id.map(PlayerID.init(raw:)),
            assist: $assistant.id.map(PlayerID.init(raw:)), assisted: assisted,
            minute: try minute.map(MatchMinute.init),
            zone: try stored(zone, GoalZone.self, table: table, column: "zone"),
            attackSide: try stored(attackSide, GoalSide.self, table: table, column: "attack_side"),
            shotSide: try stored(shotSide, GoalSide.self, table: table, column: "shot_side"),
            bodyPart: try stored(bodyPart, GoalBodyPart.self, table: table, column: "body_part"),
            playType: try stored(playType, GoalPlayType.self, table: table, column: "play_type"),
            comment: try EntryComment.make(comment), fromReport: fromReport,
            createdAt: createdAt, updatedAt: updatedAt)
    }

    fileprivate func apply(_ goal: Goal) {
        $match.id = goal.matchID.raw
        $scoringTeam.id = goal.scoringTeamID.raw
        $concedingTeam.id = goal.concedingTeamID.raw
        $scorer.id = goal.scorer?.raw
        $assistant.id = goal.assist?.raw
        assisted = goal.assisted
        minute = goal.minute?.value
        zone = goal.zone?.rawValue
        attackSide = goal.attackSide?.rawValue
        shotSide = goal.shotSide?.rawValue
        bodyPart = goal.bodyPart?.rawValue
        playType = goal.playType?.rawValue
        comment = goal.comment?.value
        fromReport = goal.fromReport
    }
}

public struct FluentGoalRepository: GoalRepository {
    private let database: any Database
    public init(database: any Database) { self.database = database }

    public func find(_ id: GoalID) async throws -> Goal? {
        try await GoalRecord.find(id.raw, on: database)?.toDomain()
    }

    /// **Con SQL**: el orden sin partido es por la fecha del partido, y la temporada
    /// se alcanza por la competición (`D-28`); los dos piden juntar tablas. Se sacan
    /// los ids de la página en su orden, y luego las filas.
    public func list(_ filter: GoalFilter, page: Int, perPage: Int) async throws -> (goals: [Goal], total: Int) {
        guard let sql = database as? any SQLDatabase else {
            throw PersistenceError.schemaHelperNeedsSQL(helper: "list", object: GoalRecord.schema)
        }
        var conditions: [SQLQueryString] = ["g.deleted_at IS NULL"]
        if let id = filter.matchID { conditions.append("g.match_id = \(bind: id.raw)") }
        if let id = filter.scoringTeamID { conditions.append("g.scoring_team_id = \(bind: id.raw)") }
        if let id = filter.concedingTeamID { conditions.append("g.conceding_team_id = \(bind: id.raw)") }
        if let id = filter.scorer { conditions.append("g.scorer_player_id = \(bind: id.raw)") }
        if let id = filter.assist { conditions.append("g.assist_player_id = \(bind: id.raw)") }
        if let id = filter.seasonID { conditions.append("c.season_id = \(bind: id.raw)") }
        if let type = filter.playType { conditions.append("g.play_type = \(bind: type.rawValue)") }
        let whereClause = conditions.joined(separator: " AND ")
        let from: SQLQueryString = """
            FROM \(ident: GoalRecord.schema) g
            JOIN \(ident: MatchRecord.schema) m ON m.id = g.match_id
            JOIN \(ident: CompetitionRecord.schema) c ON c.id = m.competition_id
            WHERE \(whereClause)
            """
        let order: SQLQueryString = filter.matchID != nil
            ? "g.minute ASC NULLS LAST, g.created_at, g.id"
            : "m.match_date DESC, g.minute ASC NULLS LAST, g.id"
        let total = try await sql.raw("SELECT count(*)::int AS n \(from)").first(decoding: [String: Int].self)?["n"] ?? 0
        let ids = try await sql.raw("""
            SELECT g.id \(from) ORDER BY \(order) LIMIT \(bind: perPage) OFFSET \(bind: (page - 1) * perPage)
            """).all().map { try $0.decode(column: "id", as: UUID.self) }
        guard !ids.isEmpty else { return ([], total) }
        let byID = Dictionary(uniqueKeysWithValues: try await GoalRecord.query(on: database)
            .filter(\.$id ~~ ids).all().map { (try $0.requireID(), $0) })
        return (try ids.compactMap { try byID[$0]?.toDomain() }, total)
    }

    public func save(_ goal: Goal) async throws {
        if let existing = try await GoalRecord.find(goal.id.raw, on: database) {
            existing.apply(goal)
            try await existing.update(on: database)
        } else {
            let record = GoalRecord()
            record.id = goal.id.raw
            record.apply(goal)
            try await record.create(on: database)
        }
    }

    public func delete(_ id: GoalID) async throws {
        try await GoalRecord.find(id.raw, on: database)?.delete(on: database)
    }
}

// ── Las tarjetas (R7.8) ──────────────────────────────────────────────────────

extension CardRecord {
    func toDomain() throws -> Card {
        let id = try requireID()
        guard let createdAt, let updatedAt else {
            throw PersistenceError.missingTimestamp(table: Self.schema, id: id.uuidString)
        }
        guard let type = try stored(type, CardType.self, table: Self.schema, column: "type") else {
            throw PersistenceError.corruptEnumeration(table: Self.schema, column: "type", value: "")
        }
        return Card(
            id: CardID(raw: id), playerID: PlayerID(raw: $player.id), matchID: MatchID(raw: $match.id),
            teamID: TeamID(raw: $team.id), type: type, isSecondYellow: isSecondYellow,
            minute: try minute.map(MatchMinute.init), comment: try EntryComment.make(comment),
            fromReport: fromReport, createdAt: createdAt, updatedAt: updatedAt)
    }

    fileprivate func apply(_ card: Card) {
        $player.id = card.playerID.raw
        $match.id = card.matchID.raw
        $team.id = card.teamID.raw
        type = card.type.rawValue
        isSecondYellow = card.isSecondYellow
        minute = card.minute?.value
        comment = card.comment?.value
        fromReport = card.fromReport
    }
}

public struct FluentCardRepository: CardRepository {
    private let database: any Database
    public init(database: any Database) { self.database = database }

    public func find(_ id: CardID) async throws -> Card? {
        try await CardRecord.find(id.raw, on: database)?.toDomain()
    }

    /// **Por minuto**, las que no tienen al final, y luego en el orden en que se
    /// apuntaron; el `id` desempata.
    public func list(matchID: MatchID, teamID: TeamID?, playerID: PlayerID?) async throws -> [Card] {
        var query = CardRecord.query(on: database).filter(\.$match.$id == matchID.raw)
        if let teamID { query = query.filter(\.$team.$id == teamID.raw) }
        if let playerID { query = query.filter(\.$player.$id == playerID.raw) }
        return try await query
            .sort(.sql(unsafeRaw: "minute ASC NULLS LAST"))
            .sort(\.$createdAt)
            .sort(\.$id)
            .all()
            .map { try $0.toDomain() }
    }

    public func list(playerID: PlayerID) async throws -> [Card] {
        try await CardRecord.query(on: database).filter(\.$player.$id == playerID.raw).all().map { try $0.toDomain() }
    }

    public func save(_ card: Card) async throws {
        if let existing = try await CardRecord.find(card.id.raw, on: database) {
            existing.apply(card)
            try await existing.update(on: database)
        } else {
            let record = CardRecord()
            record.id = card.id.raw
            record.apply(card)
            try await record.create(on: database)
        }
    }

    public func delete(_ id: CardID) async throws {
        try await CardRecord.find(id.raw, on: database)?.delete(on: database)
    }
}

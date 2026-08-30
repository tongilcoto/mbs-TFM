import Domain
public import Fluent
import Foundation

/// Modelo de persistencia del partido (§4.4).
public final class MatchRecord: Model, @unchecked Sendable {
    public static let schema = "matches"

    @ID(key: .id) public var id: UUID?

    @Parent(key: "competition_id") public var competition: CompetitionRecord
    @Parent(key: "round_id") public var round: RoundRecord

    /// **Siempre tiene valor** (§3.2). Un partido cuya fecha la fuente no publica
    /// no llega a esta tabla: la ingesta lo deja fuera y lo reporta.
    @Field(key: "match_date") public var matchDate: Date

    /// **Texto `HH:mm`, no un `time` de Postgres.** El driver decodifica `time`
    /// a un `Date`, que es un instante, y volver a meter la hora en un instante
    /// es justo lo que `WallClockTime` existe para no hacer (`D-30`). El texto
    /// zero-padded ordena igual que el reloj.
    @OptionalField(key: "kickoff_time") public var kickoffTime: String?

    @Parent(key: "home_team_id") public var homeTeam: TeamRecord
    @Parent(key: "away_team_id") public var awayTeam: TeamRecord

    /// **Dos columnas anulables para un VO que es "los dos o ninguno"**
    /// (`MatchResult`). El esquema no puede expresar el par, así que lo hace
    /// cumplir el mapeo: media fila —un gol sí y el otro no— es corrupción y se
    /// trata como tal, igual que un enumerado fuera de rango.
    @OptionalField(key: "home_score") public var homeScore: Int?
    @OptionalField(key: "away_score") public var awayScore: Int?

    @Field(key: "status") public var status: String
    @OptionalField(key: "venue") public var venue: String?

    @OptionalField(key: "federation_match_id") public var federationMatchID: String?

    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}
}

/// Octava del orden de FK de §4.6: la última de F5, y va detrás de `Round` y de
/// `Team`, que son sus dos dependencias.
public struct CreateMatch: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(MatchRecord.schema)
            .id()
            .field("competition_id", .uuid, .required,
                   .references(CompetitionRecord.schema, "id", onDelete: .cascade))
            .field("round_id", .uuid, .required,
                   .references(RoundRecord.schema, "id", onDelete: .cascade))
            .field("match_date", .date, .required)
            .field("kickoff_time", .string)
            // **Sin cascada desde los equipos**, por lo mismo que `Team` no la
            // tiene desde `OpponentClub`: borrar un equipo no puede llevarse por
            // delante partidos que son también del rival.
            .field("home_team_id", .uuid, .required,
                   .references(TeamRecord.schema, "id"))
            .field("away_team_id", .uuid, .required,
                   .references(TeamRecord.schema, "id"))
            .field("home_score", .int)
            .field("away_score", .int)
            .field("status", .string, .required)
            .field("venue", .string)
            .field("federation_match_id", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            // Las dos unicidades de §3.5, y las dos con `UNIQUE` normal.
            //
            // La primera **es** el paso 2 de la cadena de §3.7: sin el índice no
            // sería una clave, solo una consulta. **No lleva `competition_id`**
            // porque `Round` ya la fija.
            .unique(on: "round_id", "home_team_id", "away_team_id")
            .unique(on: "federation_match_id")
            .create()

        try await database.index(
            table: MatchRecord.schema, name: "idx_matches_competition",
            columns: ["competition_id"])
        try await database.index(
            table: MatchRecord.schema, name: "idx_matches_round", columns: ["round_id"])
        try await database.index(
            table: MatchRecord.schema, name: "idx_matches_home_team",
            columns: ["home_team_id"])
        try await database.index(
            table: MatchRecord.schema, name: "idx_matches_away_team",
            columns: ["away_team_id"])

        try await database.checkConstraint(
            table: MatchRecord.schema, name: "chk_matches_status",
            expression: "status IN (\(MatchStatus.sqlValueList))")
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(MatchRecord.schema).delete()
    }
}

import Domain
public import Fluent
import Foundation

/// Modelo de persistencia del equipo (§4.4).
public final class TeamRecord: Model, @unchecked Sendable {
    public static let schema = "teams"

    @ID(key: .id) public var id: UUID?

    /// **Nulo ⇒ equipo propio** (§3.6, `D-03`). `@OptionalParent` y no un `UUID`
    /// suelto, por lo mismo que en `CompetitionRecord`: el *eager loading* de las
    /// lecturas lo necesita disponible (§4.5).
    @OptionalParent(key: "opponent_club_id") public var opponentClub: OpponentClubRecord?

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

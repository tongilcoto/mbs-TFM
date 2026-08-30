import Domain
public import Fluent
import Foundation

/// Modelo de persistencia del club rival (§4.4).
public final class OpponentClubRecord: Model, @unchecked Sendable {
    public static let schema = "opponent_clubs"

    @ID(key: .id) public var id: UUID?

    @Field(key: "name") public var name: String
    @Field(key: "short_name") public var shortName: String
    @Field(key: "slug") public var slug: String

    /// Anulable **a propósito** (§3.5): al no comparar iguales los `NULL`, un
    /// `UNIQUE` normal permite muchas filas sin código mientras garantiza que no
    /// se repita uno concreto. Es el criterio **opuesto** al de la clave única de
    /// `Team`, en la tabla de al lado.
    @OptionalField(key: "federation_club_id") public var federationClubID: String?

    /// La **clave del objeto** en Storage, no una URL (`D-19`). Hoy siempre nula:
    /// F5 no trae adaptador de Storage.
    @OptionalField(key: "crest_key") public var crestKey: String?

    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}
}

/// Tercera del orden de FK de §4.6: `Club → Season → OpponentClub → Team → …`.
/// **No depende de nadie**, así que va donde el orden manda y no donde obligue
/// una FK.
public struct CreateOpponentClub: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(OpponentClubRecord.schema)
            .id()
            .field("name", .string, .required)
            .field("short_name", .string, .required)
            .field("slug", .string, .required)
            .field("federation_club_id", .string)
            .field("crest_key", .string)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            // Las tres unicidades de §3.5, todas con `UNIQUE` normal. En
            // `federation_club_id` eso significa "muchos nulos, ningún código
            // repetido", que es exactamente lo que se quiere.
            .unique(on: "name")
            .unique(on: "slug")
            .unique(on: "federation_club_id")
            .create()
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(OpponentClubRecord.schema).delete()
    }
}

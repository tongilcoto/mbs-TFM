public import Domain

/// Caso de uso: leer el club del tenant.
///
/// Trivial a propósito — F0 es andamiaje (Plan §3). Lo que importa aquí no es lo
/// que hace, sino su **forma**: recibe `ActorContext`, depende del **puerto** y
/// no de Fluent, y devuelve una **entidad de dominio**. El adaptador primario es
/// quien la traduce a DTO (§2.2); si este tipo devolviera un DTO, la Aplicación
/// conocería el contrato HTTP y la Regla de dependencia se habría roto.
public struct GetClub: Sendable {
    private let clubs: any ClubRepository

    public init(clubs: any ClubRepository) {
        self.clubs = clubs
    }

    public func execute(actor: ActorContext) async throws -> Club {
        guard let club = try await clubs.current() else {
            throw ApplicationError.tenantNotProvisioned(slug: actor.clubSlug.value)
        }
        return club
    }
}

public import APIContract
public import Application
import Domain
import Foundation
import Tenancy

/// Adaptador primario (§2.2): traduce entrada HTTP a caso de uso y entidad de
/// dominio a DTO. **Los DTOs cruzan la frontera; las entidades no** (§4.1).
///
/// Conforma el `APIProtocol` **generado** del *spec* (D-65): si el contrato
/// cambia y esto no, **no compila**. Ese es el motivo entero de *design-first*.
///
/// Es una **sola instancia para todo el transporte** —así lo registra el código
/// generado—, de modo que no puede guardar nada de la petición. El tenant llega
/// por `TenantContext` (`@TaskLocal`), que fija el middleware.
public struct APIHandler: APIProtocol {
    private let unitOfWork: any TenantUnitOfWork

    public init(unitOfWork: any TenantUnitOfWork) {
        self.unitOfWork = unitOfWork
    }

    public func getClub(_ input: Operations.getClub.Input) async throws
        -> Operations.getClub.Output
    {
        let actor = try Self.currentActor()
        let club = try await unitOfWork.withRepositories(actor: actor) { repositories in
            try await GetClub(clubs: repositories.clubs).execute(actor: actor)
        }
        return .ok(.init(body: .json(club.toResponse())))
    }

    /// Traduce el tenant ambiental a contexto de actor (§7.4).
    ///
    /// Hoy solo lleva el club. Cuando §7 aterrice, es **aquí** donde se cargan
    /// el `StaffMember` y sus asignaciones vigentes — la firma del caso de uso
    /// ya no tendrá que cambiar, que es justo lo que esa decisión persigue.
    static func currentActor() throws -> ActorContext {
        guard let tenant = TenantContext.current else {
            throw TenancyError.tenantNotResolved
        }
        return ActorContext(clubSlug: try Slug(tenant.slug))
    }
}

extension Domain.Club {
    /// Mapeo `Entidad → DTO`, trabajo del adaptador primario (§2.2).
    func toResponse() -> Components.Schemas.ClubResponse {
        .init(
            // En minúsculas: `uuidString` de Foundation devuelve mayúsculas, pero
            // la forma canónica de un UUID en JSON (RFC 4122 §3) es minúscula, y es
            // lo que los clientes esperan de un `format: uuid`.
            id: id.raw.uuidString.lowercased(),
            name: name,
            shortName: shortName,
            slug: slug.value,
            // TODO(fase posterior): componer la URL firmada desde `crestKey`
            // cuando exista el adaptador de Storage. Su caducidad es §9.7.
            crestUrl: nil,
            federation: .init(value1: federation.toContract()),
            // **Derivados del catálogo en código, no almacenados** (D-17): por eso
            // salen de la entidad y no de una columna.
            federationProvidesRoundStandings: federationCapabilities.providesRoundStandings,
            federationProvidesScorers: federationCapabilities.providesScorers,
            settings: .init(),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension Domain.FederationCode {
    /// `switch` exhaustivo a propósito, en vez de `init(rawValue:) ?? .rffm`.
    ///
    /// Los dos enumerados —el del Dominio y el generado del *spec*— tienen hoy
    /// los mismos casos, pero son **tipos distintos que pueden divergir**. Un
    /// `??` convertiría esa divergencia en un dato equivocado servido en silencio;
    /// así, añadir una federación al Dominio **no compila** hasta que también se
    /// declare en el contrato. Es el mismo criterio de D-61: la integridad en el
    /// sistema de tipos, no en la disciplina.
    func toContract() -> Components.Schemas.FederationCode {
        switch self {
        case .rffm: .rffm
        case .fcf: .fcf
        }
    }
}

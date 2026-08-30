public import APIContract
public import Application
import Domain
import Foundation
import Tenancy
import Vapor

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
    // `internal` y no `private`: los handlers viven en varios ficheros desde F6
    // —`ClubHandler` y `IngestionHandler`—, y `private` es de fichero.
    let unitOfWork: any TenantUnitOfWork

    /// Los tres de F6. Llegan por el `init` y no se construyen aquí dentro por lo
    /// de siempre: un `Date()` o un `UUID()` escondidos en el adaptador son un
    /// valor que ningún test puede afirmar (§4.3).
    let federationClients: any FederationClientProvider
    let clock: any Clock
    let ids: any UUIDProvider
    let background: any BackgroundWork

    public init(
        unitOfWork: any TenantUnitOfWork,
        federationClients: any FederationClientProvider,
        clock: any Clock = SystemClock(),
        ids: any UUIDProvider = SystemUUIDProvider(),
        background: any BackgroundWork = DetachedBackgroundWork()
    ) {
        self.unitOfWork = unitOfWork
        self.federationClients = federationClients
        self.clock = clock
        self.ids = ids
        self.background = background
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

extension APIHandler {
    /// `PATCH /v1/club` (§5.1). El camino de escritura completo:
    /// DTO generado → comando → Dominio (que revalida) → repositorio.
    ///
    /// # Los errores se **devuelven**, no se lanzan
    ///
    /// Y no es una preferencia de estilo. El transporte generado (D-65) atrapa
    /// cualquier error que salga de este método y lo convierte en **500** antes
    /// de que ningún middleware de Vapor lo vea: `ProblemMiddleware` está *fuera*
    /// del transporte y solo alcanza lo que ocurre antes de entrar —la
    /// resolución de tenant, el 404 de ruta—.
    ///
    /// La consecuencia es buena, aunque cueste descubrirla: **un código de error
    /// que el *spec* no declara no se puede devolver**, porque no existe como
    /// caso del `Output` generado. El contrato deja de ser una promesa y pasa a
    /// ser el juego completo de respuestas posibles.
    public func updateClub(_ input: Operations.updateClub.Input) async throws
        -> Operations.updateClub.Output
    {
        let actor = try Self.currentActor()
        guard case .json(let body) = input.body else {
            return .badRequest(.init(body: .application_problem_plus_json(
                Self.problem(status: 400, code: "BAD_REQUEST",
                             title: "El cuerpo debe ser application/json"))))
        }

        let command = UpdateClub.Command(name: body.name, shortName: body.shortName)

        // **`minProperties: 1` lo comprueba aquí el adaptador**, porque el
        // generador lo ignora (D-65, tabla de reparto de §5.5). Un `PATCH {}` es
        // un cuerpo sintácticamente válido que no pide nada: 400, no 422.
        guard !command.isEmpty else {
            return .badRequest(.init(body: .application_problem_plus_json(
                Self.problem(status: 400, code: "EMPTY_PATCH",
                             title: "El cuerpo debe traer al menos un campo",
                             detail: "minProperties: 1"))))
        }

        do {
            let updated = try await unitOfWork.withRepositories(actor: actor) { repositories in
                try await UpdateClub(clubs: repositories.clubs)
                    .execute(actor: actor, command: command)
            }
            return .ok(.init(body: .json(updated.toResponse())))
        } catch let error as DomainError {
            // 422: bien formado y bien tipado, pero rompe una invariante (§5.4).
            // La regla la puso el Dominio; aquí solo se traduce a HTTP.
            guard case .invalidValue(let field, let reason) = error else { throw error }
            return .unprocessableContent(.init(body: .application_problem_plus_json(
                Self.problem(status: 422, code: "INVALID_VALUE",
                             title: "Valor no válido",
                             detail: "\(field): \(reason)"))))
        }
    }

    /// Construye el cuerpo RFC 7807 con el **tipo generado del spec**, no con un
    /// diccionario suelto: así el cuerpo de error también está atado al contrato.
    static func problem(
        status: Int, code: String, title: String, detail: String? = nil
    ) -> Components.Schemas.Problem {
        .init(_type: "https://api.example.com/problems/\(code.lowercased().replacingOccurrences(of: "_", with: "-"))",
              title: title, status: status, detail: detail, code: code)
    }
}

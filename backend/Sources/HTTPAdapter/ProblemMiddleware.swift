import Application
import Domain
import Foundation
import Tenancy
public import Vapor

/// Traduce **todo** error a RFC 7807 *Problem Details* (§5.4).
///
/// Sin esto, Vapor sirve su propio `{"error":true,"reason":"…"}`, que no es lo
/// que el *spec* declara: **todas** las respuestas de error del contrato son
/// `application/problem+json`. Un cliente generado del *spec* no sabría leer la
/// otra forma.
///
/// Es también el sitio donde el error de dominio se convierte en código HTTP —
/// **la traducción vive aquí, no en el Dominio** (§2.2): `DomainError` y
/// `ApplicationError` no conocen HTTP, y ése es justo el punto.
public struct ProblemMiddleware: AsyncMiddleware {
    /// Prefijo de los `type` de problema. Debe ser una URI (§5.4).
    private let typeBaseURI: String
    /// Con `false` (producción), `detail` se omite en los 5xx: un mensaje de
    /// PostgreSQL o una traza filtran estructura interna al cliente.
    private let exposesInternalDetail: Bool

    public init(typeBaseURI: String = "https://api.example.com/problems",
                exposesInternalDetail: Bool) {
        self.typeBaseURI = typeBaseURI
        self.exposesInternalDetail = exposesInternalDetail
    }

    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch {
            let problem = translate(error)
            request.logger.report(error: error)
            return try problem.response(on: request, exposesDetail: exposesInternalDetail)
        }
    }

    /// El mapa error → HTTP. **Un `switch`, no una cadena de `if`**: cuando
    /// aparezca un caso nuevo de `DomainError`, el compilador lo señalará aquí.
    private func translate(_ error: any Error) -> Problem {
        switch error {
        // ── Dominio: una invariante rota es 422, no 400 ──────────────────────
        case let domain as DomainError:
            switch domain {
            case .invalidValue(let field, let reason):
                // **422 y no 400** (§5.4): el JSON estaba bien formado y el tipo
                // era el correcto; lo que falla es la *regla*. El 400 se reserva
                // para lo que ni siquiera se pudo decodificar.
                return Problem(status: .unprocessableEntity, code: "INVALID_VALUE",
                               title: "Valor no válido", detail: "\(field): \(reason)",
                               base: typeBaseURI, slug: "invalid-value")
            }

        // ── Aplicación ───────────────────────────────────────────────────────
        case let app as ApplicationError:
            switch app {
            case .tenantNotProvisioned(let slug):
                // 500, no 404: el club existe (el plano de control lo resolvió),
                // pero su *schema* está a medio aprovisionar. Es un fallo nuestro.
                return Problem(status: .internalServerError, code: "TENANT_NOT_PROVISIONED",
                               title: "Club sin aprovisionar",
                               detail: "El schema del club '\(slug)' no tiene datos.",
                               base: typeBaseURI, slug: "tenant-not-provisioned")
            }

        // ── Tenancy (§6.1) ───────────────────────────────────────────────────
        case let tenancy as TenancyError:
            switch tenancy {
            case .tenantNotResolved:
                return Problem(status: .badRequest, code: "TENANT_NOT_RESOLVED",
                               title: "La petición no identifica ningún club",
                               detail: nil, base: typeBaseURI, slug: "tenant-not-resolved")
            case .unknownTenant(let slug):
                // 404 **literal**: para esta consulta el club no existe. No es el
                // 404 defensivo que D-64 descarta.
                return Problem(status: .notFound, code: "UNKNOWN_TENANT",
                               title: "Club desconocido", detail: slug,
                               base: typeBaseURI, slug: "unknown-tenant")
            case .tenantMismatch(let host, let claim):
                // §6.1: no se da prioridad a ninguno de los dos, se rechaza.
                return Problem(status: .forbidden, code: "TENANT_MISMATCH",
                               title: "El club del token no coincide con el del dominio",
                               detail: "host=\(host) claim=\(claim)",
                               base: typeBaseURI, slug: "tenant-mismatch")
            case .notASQLDatabase:
                return Problem(status: .internalServerError, code: "INTERNAL",
                               title: "Error interno", detail: nil,
                               base: typeBaseURI, slug: "internal")
            }

        // ── Vapor: 404 de ruta, cuerpo indecodificable, `Abort` explícito ─────
        case let abort as any AbortError:
            return Problem(status: abort.status, code: abort.status.code == 404 ? "NOT_FOUND" : "BAD_REQUEST",
                           title: abort.reason, detail: nil,
                           base: typeBaseURI, slug: abort.status.code == 404 ? "not-found" : "bad-request")

        default:
            return Problem(status: .internalServerError, code: "INTERNAL",
                           title: "Error interno", detail: String(describing: error),
                           base: typeBaseURI, slug: "internal")
        }
    }
}

/// Cuerpo RFC 7807 (§5.4). Coincide campo a campo con `components/schemas/Problem`.
struct Problem {
    let status: HTTPStatus
    let code: String
    let title: String
    let detail: String?
    let base: String
    let slug: String

    func response(on request: Request, exposesDetail: Bool) throws -> Response {
        // En 5xx el `detail` puede llevar el mensaje crudo del driver; fuera de
        // desarrollo se calla.
        let safeDetail = (status.code >= 500 && !exposesDetail) ? nil : detail

        var body: [String: Any] = [
            "type": "\(base)/\(slug)",
            "title": title,
            "status": Int(status.code),
            "code": code,
        ]
        if let safeDetail { body["detail"] = safeDetail }

        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let response = Response(status: status)
        // El `Content-Type` que declara el contrato, no `application/json`.
        response.headers.contentType = HTTPMediaType(type: "application", subType: "problem+json")
        response.body = .init(data: data)
        return response
    }
}

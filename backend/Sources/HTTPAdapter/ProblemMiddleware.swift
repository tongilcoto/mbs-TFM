import Application
import Domain
import Foundation
// `HTTPTypes` no llega de gratis desde `OpenAPIRuntime`: `MemberImportVisibility`
// (SE-0444) exige declarar el módulo que define `.code` de `HTTPResponse.Status`,
// aunque el tipo que lo lleva venga de otro. Quinta fase seguida en que esta
// bandera cobra pieza.
import HTTPTypes
import OpenAPIRuntime
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

            case .notEditableAfterSync(let field):
                // **409 y no 422** (§5.4, D-22): el valor puede ser
                // perfectamente válido — lo que no lo es, es el *momento*. La
                // competición ya se sincronizó, así que cambiar la coordenada
                // sería repuntar a otro calendario con datos ya colgando, y
                // cambiar `gender` desalinearía los equipos que la ingesta creó
                // desde ella (D-58).
                return Problem(status: .conflict, code: "NOT_EDITABLE_AFTER_SYNC",
                               title: "El campo ya no es editable",
                               detail: "\(field): la competición ya se ha sincronizado",
                               base: typeBaseURI, slug: "not-editable-after-sync")

            case .federationSourceMismatch(let expected, let found):
                // **502 y no 409** (§5.4, `D-84`). Nada de lo que el cliente
                // mandó está mal: lo que ha cambiado es lo que el tercero
                // devuelve en esa coordenada. Es el mismo criterio con el que
                // §5.1 trata la latencia de la federación en `/preview` — la
                // familia 5xx dice "el fallo no es tuyo", y un 409 invitaría a
                // reintentar con otro cuerpo, que aquí no arregla nada.
                return Problem(status: .badGateway, code: "FEDERATION_SOURCE_MISMATCH",
                               title: "La coordenada apunta a otra competición",
                               detail: "se esperaba '\(expected)' y la fuente devolvió '\(found)'",
                               base: typeBaseURI, slug: "federation-source-mismatch")
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

            // Los dos siguientes los levanta la pasada de ingesta, que **no
            // pasa por HTTP** (§2.3-b). Se traducen igual porque el `switch` es
            // exhaustivo a propósito, y porque F10 sí los va a hacer cruzar la
            // frontera: el enganche de `D-67` encola una ingesta y su `/preview`
            // la ejecuta en línea.
            case .competitionNotFound(let id):
                // 404 literal: para esta petición la competición no está.
                return Problem(status: .notFound, code: "COMPETITION_NOT_FOUND",
                               title: "Competición desconocida", detail: id,
                               base: typeBaseURI, slug: "competition-not-found")
            case .seasonNotFound(let id):
                // **500 y no 404**, al revés que la de arriba: la FK
                // `competitions.season_id` es `NOT NULL` y con integridad
                // referencial, así que una competición sin temporada no es un
                // dato que falte — es el *schema* roto. Mismo criterio que
                // `tenantNotProvisioned`.
                return Problem(status: .internalServerError, code: "SEASON_NOT_FOUND",
                               title: "Temporada inexistente", detail: id,
                               base: typeBaseURI, slug: "season-not-found")

            case .unknownSeason(let id):
                // 404, al revés que `seasonNotFound`: aquí el id lo puso quien
                // llama, así que es un dato suyo que no existe — no un *schema*
                // roto.
                return Problem(status: .notFound, code: "SEASON_NOT_FOUND",
                               title: "Temporada desconocida", detail: id,
                               base: typeBaseURI, slug: "season-not-found")

            case .federationAdapterMissing(let federation):
                // **501 y no 500**: no se ha roto nada. La federación del club
                // está en el catálogo (`D-17`) y su adaptador todavía no se ha
                // escrito —la FCF es F9—, así que la funcionalidad no existe aún
                // en este servidor. Un 500 invitaría a reintentar y a abrir una
                // incidencia; un 501 dice la verdad: vuelve cuando esté.
                return Problem(status: .notImplemented, code: "FEDERATION_ADAPTER_MISSING",
                               title: "Federación todavía sin adaptador",
                               detail: "No hay adaptador de ingesta para '\(federation)'.",
                               base: typeBaseURI, slug: "federation-adapter-missing")
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

        // ── Lo que el transporte generado rechaza antes de llegar al handler ──
        //
        // F6 lo descubrió con un test: `GET /ingestion-runs` **sin**
        // `competitionId` daba **500**, aunque el *spec* declara 400 para ese
        // caso. El motivo es que un parámetro obligatorio ausente ni siquiera
        // llega al handler — lo rechaza el código generado, y ese error caía en
        // el `default` de aquí abajo.
        //
        // El runtime ya sabe qué código HTTP le corresponde a cada uno
        // (`RuntimeError: HTTPResponseConvertible`), así que se reutiliza en vez
        // de reimplementar la tabla. Lo que **no** se usa es su
        // `ErrorHandlingMiddleware`: devuelve el código **sin cuerpo**, y §5.4
        // exige `application/problem+json` en *todo* error del contrato.
        case let server as ServerError:
            // Primero, desenvolver: si dentro hay un error nuestro, manda el
            // nuestro. Sin esto, un `DomainError` que escapara de un handler
            // pasaría de 422 a 500 solo por venir envuelto.
            let inner = server.underlyingError
            if inner is DomainError || inner is ApplicationError || inner is TenancyError {
                return translate(inner)
            }
            let status = HTTPStatus(statusCode: Int(server.httpStatus.code))
            return Problem(status: status,
                           code: status.code >= 500 ? "INTERNAL" : "BAD_REQUEST",
                           title: status.code >= 500
                               ? "Error interno" : "La petición no cumple el contrato",
                           detail: server.causeDescription,
                           base: typeBaseURI,
                           slug: status.code >= 500 ? "internal" : "bad-request")

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

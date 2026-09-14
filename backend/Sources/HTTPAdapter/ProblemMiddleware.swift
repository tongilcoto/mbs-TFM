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

    /// Fechas de los problemas en ISO y en UTC (`D-91`). El Dominio entrega
    /// `Date` sin formatear porque no conoce zona ni idioma (§5.4); el formato
    /// es cosa de la frontera, y aquí es el mismo que usa el contrato.
    private static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

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
            // **El log va con `diagnosticText` y no solo con `report`** (`A-6`/H-43).
            // `report(error:)` imprime la descripción del error, y la de un
            // `PSQLError` está **enmascarada** a propósito por PostgresNIO — así
            // que en producción, donde el `detail` de un 5xx se calla, no quedaba
            // ni una salida con el motivo verdadero. Se conserva `report` porque
            // añade la ubicación en el fuente, y se le pone al lado lo que de
            // verdad se necesita para depurar.
            request.logger.report(error: error)
            if problem.status.code >= 500 {
                request.logger.error("\(diagnosticText(for: Self.rootCause(of: error)))")
            }
            return try problem.response(on: request, exposesDetail: exposesInternalDetail)
        }
    }

    /// El error que de verdad interesa para depurar: si el transporte generado lo
    /// envolvió en un `ServerError`, **el de dentro**.
    ///
    /// Sin desenvolver, `String(reflecting:)` refleja el envoltorio — y el
    /// envoltorio describe a su contenido con `String(describing:)`, que es
    /// exactamente el enmascaramiento del que se venía huyendo. La primera
    /// versión de este arreglo caía en eso, y lo delató el propio log de los
    /// tests: dos líneas seguidas con el mismo *"Generic description…"*.
    private static func rootCause(of error: any Error) -> any Error {
        (error as? ServerError)?.underlyingError ?? error
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

            case .federationSeasonMismatch(let seasonLabel, let median):
                // **502, igual que su hermano de arriba y por la misma razón**
                // (`D-91`): la coordenada es válida, la fuente contesta, y lo que
                // devuelve es el calendario de **otra temporada**. El cliente no
                // ha mandado nada mal; lo que está mal es la coordenada guardada,
                // y eso no lo arregla reintentar con otro cuerpo.
                //
                // **La fecha se formatea aquí y no en el Dominio** (§5.4): en ISO
                // y en UTC, que es como viaja todo en el contrato, y no en el
                // idioma ni la zona de quien lea el problema.
                return Problem(status: .badGateway, code: "FEDERATION_SEASON_MISMATCH",
                               title: "El calendario es de otra temporada",
                               detail: "la temporada es '\(seasonLabel)' y el calendario "
                                   + "tiene su mitad en \(Self.isoDay.string(from: median))",
                               base: typeBaseURI, slug: "federation-season-mismatch")
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

            case .databaseUnavailable:
                // **503 y no 500** (H-23): 500 dice *"me he roto"* y 503 dice *"no
                // estoy disponible ahora"*, que es la verdad y además la única de
                // las dos ante la que un cliente hace lo correcto — reintentar más
                // tarde en vez de abrir una incidencia. Es la misma distinción que
                // `federationAdapterMissing` hace con el 501.
                return Problem(status: .serviceUnavailable, code: "DATABASE_UNAVAILABLE",
                               title: "La base de datos no responde",
                               detail: "El recorrido se detuvo sin dejar constancia (D-86).",
                               base: typeBaseURI, slug: "database-unavailable")

            case .runNotRecorded(let competitionID, let reason):
                // **500, y es el caso raro en que el 500 es exacto**: la petición
                // estaba bien y los datos **sí se escribieron**, pero la operación
                // no terminó como el contrato dice —la pasada de `D-88` responde
                // con su `IngestionRun`, y esa fila no existe—. Lo importante es
                // el `detail`: sin él, quien lo reciba creerá que la ingesta no se
                // hizo y la repetirá, cuando lo que falta es el apunte.
                return Problem(status: .internalServerError, code: "RUN_NOT_RECORDED",
                               title: "La pasada se escribió y no se pudo registrar",
                               detail: "Competición \(competitionID): los datos están escritos; "
                                   + "falló el registro de D-85 (\(reason)).",
                               base: typeBaseURI, slug: "run-not-recorded")
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
                           // **`causeDescription` no basta para un 5xx** (`A-6`/H-43):
                           // el literal que trae es `"User handler threw an error."`,
                           // que no dice nada — el motivo está en el error envuelto y
                           // hay que pedírselo con `String(reflecting:)` porque un
                           // `PSQLError` esconde el suyo. En los 4xx sí sirve: los
                           // pone el propio runtime y describen qué falta del
                           // contrato ("Missing required query parameter named: …").
                           detail: status.code >= 500
                               ? diagnosticText(for: server.underlyingError)
                               : server.causeDescription,
                           base: typeBaseURI,
                           slug: status.code >= 500 ? "internal" : "bad-request")

        default:
            // Mismo motivo que arriba: éste es el cajón de lo que nadie clasificó,
            // así que es justo donde más falta hace el motivo completo.
            return Problem(status: .internalServerError, code: "INTERNAL",
                           title: "Error interno", detail: diagnosticText(for: error),
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

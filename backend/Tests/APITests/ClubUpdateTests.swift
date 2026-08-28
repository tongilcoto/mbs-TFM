import APIContract
import Domain
import Fluent
import Foundation
import SQLKit
import Testing
import Vapor
import VaporTesting
@testable import App
import TestSupport
@testable import Persistence
@testable import Tenancy

/// `PATCH /v1/club` (§5.1) — el camino de **escritura**.
///
/// Los tres casos que fija la convención de `PATCH` de §5.5, y que conviene leer
/// juntos porque la diferencia entre ellos **es** el diseño:
///
/// | Cuerpo | Respuesta | Quién lo decide |
/// |---|---|---|
/// | un campo válido | 200 | el caso de uso |
/// | `{}` | **400** — no pide nada | el **adaptador** (`minProperties`, D-65) |
/// | `{"name":""}` | **422** — pide algo imposible | el **Dominio** (invariante) |
///
/// Ese 400 contra 422 no es cosmética: el JSON de `{}` está perfectamente
/// formado, así que rechazarlo es una regla del contrato; `{"name":""}` también
/// está bien formado **y bien tipado**, y lo que incumple es una regla de negocio.
@Suite("PATCH /v1/club · §5.1 · el camino de escritura",
        .serialized,
        // Nivel 3/4: necesita Postgres. Sin él se omite en local y **falla**
        // en CI (`REQUIRE_DB`), para que verde nunca signifique "no probado".
        .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct ClubUpdateTests {

    /// La traza de petición y respuesta **no se hace aquí**: la pone
    /// `RequestTraceMiddleware` con `HTTP_TRACE=1`, que es el mismo que usa el
    /// servidor. Duplicarla en el test imprimía cada petición dos veces, y la
    /// del middleware es además la buena: ve la petición **tal como llega** y la
    /// respuesta ya serializada, incluidos los cuerpos que el transporte generado
    /// devuelve como flujo.
    static func send(
        _ app: Application, _ method: HTTPMethod, _ path: String,
        club: String, json: String? = nil
    ) async throws -> TestingHTTPResponse {
        var captured: TestingHTTPResponse!
        try await app.testing().test(method, path, beforeRequest: { request in
            request.headers.add(name: "X-Club", value: club)
            if let json {
                request.headers.contentType = .json
                request.body = ByteBuffer(string: json)
            }
        }, afterResponse: { response async in
            captured = response
        })
        return captured
    }

    @Test("un campo válido se modifica y el resto no se toca (§5.5)")
    func updatesOneField() async throws {
        try await ClubEndpointTests.withApp { app in
            try await ClubEndpointTests.cleanUp(["patch1"], on: app)
            try await ClubEndpointTests.seed("patch1", federation: .rffm, on: app)

            let response = try await Self.send(
                app, .PATCH, "/v1/club", club: "patch1",
                json: #"{"name":"Club Deportivo Renombrado"}"#)

            #expect(response.status == .ok)
            let club = try ClubEndpointTests.decode(response)
            #expect(club.name == "Club Deportivo Renombrado")
            // **Campo ausente = no se modifica.** `shortName` conserva su valor.
            #expect(club.shortName == "PATCH1")
            // Y lo que el contrato no deja escribir sigue intacto.
            #expect(club.slug == "patch1")
            #expect(club.federation.value1 == .rffm)

            try await ClubEndpointTests.cleanUp(["patch1"], on: app)
        }
    }

    /// `minProperties: 1`. **El generador lo ignora** (D-65), así que si esto
    /// pasa a 200 es que alguien quitó la comprobación del adaptador.
    @Test("un cuerpo vacío es 400: el spec lo declara pero no lo hace cumplir (D-65)")
    func rejectsEmptyBody() async throws {
        try await ClubEndpointTests.withApp { app in
            try await ClubEndpointTests.cleanUp(["patch2"], on: app)
            try await ClubEndpointTests.seed("patch2", federation: .rffm, on: app)

            let response = try await Self.send(app, .PATCH, "/v1/club", club: "patch2", json: "{}")

            #expect(response.status == .badRequest)
            #expect(response.headers.contentType?.subType == "problem+json",
                    "todo error del contrato es RFC 7807 (§5.4)")

            try await ClubEndpointTests.cleanUp(["patch2"], on: app)
        }
    }

    /// La invariante vive en el `init` de `Club`, así que **modificar pasa por la
    /// misma puerta que dar de alta**.
    @Test("un nombre vacío es 422: bien formado, pero rompe una invariante (§5.4)")
    func rejectsInvalidValue() async throws {
        try await ClubEndpointTests.withApp { app in
            try await ClubEndpointTests.cleanUp(["patch3"], on: app)
            try await ClubEndpointTests.seed("patch3", federation: .rffm, on: app)

            let response = try await Self.send(
                app, .PATCH, "/v1/club", club: "patch3", json: #"{"name":"   "}"#)

            #expect(response.status == .unprocessableEntity)
            let problem = try JSONSerialization.jsonObject(
                with: Data(response.body.readableBytesView)) as? [String: Any]
            #expect(problem?["code"] as? String == "INVALID_VALUE")
            #expect((problem?["detail"] as? String)?.contains("name") == true,
                    "el problema dice qué campo falla, para que la UI lo señale")

            try await ClubEndpointTests.cleanUp(["patch3"], on: app)
        }
    }

    /// El cambio se persiste de verdad, no solo vuelve en la respuesta.
    @Test("el cambio sobrevive a la petición")
    func persists() async throws {
        try await ClubEndpointTests.withApp { app in
            try await ClubEndpointTests.cleanUp(["patch4"], on: app)
            try await ClubEndpointTests.seed("patch4", federation: .fcf, on: app)

            _ = try await Self.send(app, .PATCH, "/v1/club", club: "patch4",
                                    json: #"{"shortName":"CDR"}"#)
            let reread = try await Self.send(app, .GET, "/v1/club", club: "patch4")

            #expect(try ClubEndpointTests.decode(reread).shortName == "CDR")

            try await ClubEndpointTests.cleanUp(["patch4"], on: app)
        }
    }
}

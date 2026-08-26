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

/// Nivel 4 de la pirámide (§8.1): rutas, DTOs y códigos de error. **Pocos y
/// selectivos** — las reglas ya se probaron abajo, aquí solo se prueba el borde.
@Suite("GET /v1/club · §5.1 · el contrato generado, extremo a extremo", .serialized)
struct ClubEndpointTests {

    /// Decodifica con el **tipo generado del spec**, no comparando *substrings*.
    /// Además de robusto ante el formato, prueba que el DTO va y vuelve: si el
    /// contrato y la respuesta divergieran, esto falla al decodificar.
    static func decode(_ response: TestingHTTPResponse) throws -> Components.Schemas.ClubResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            Components.Schemas.ClubResponse.self,
            from: Data(response.body.readableBytesView)
        )
    }

    static let prefix = "e2e_"

    static func withApp(_ body: (Application) async throws -> Void) async throws {
        try await TestEnvironment.withApp(body)
    }

    static func seed(_ slug: String, federation: FederationCode, on app: Application) async throws {
        try await TestEnvironment.provisionClub(slug, federation: federation, schemaPrefix: prefix, on: app)
    }

    static func cleanUp(_ slugs: [String], on app: Application) async throws {
        try await TestEnvironment.dropClubs(slugs, schemaPrefix: prefix, on: app)
    }

    /// D-17/D-29/D-48: las dos banderas de capacidad **no salen de la fila**, se
    /// derivan del catálogo en código. Por eso el mismo endpoint responde
    /// distinto según la federación del tenant, sin que nadie las haya escrito.
    @Test("las capacidades de la federación se derivan del catálogo, no de la BD (D-17)")
    func capabilitiesComeFromTheCatalogue() async throws {
        try await Self.withApp { app in
            try await Self.cleanUp(["madrid", "catalan"], on: app)
            try await Self.seed("madrid", federation: .rffm, on: app)
            try await Self.seed("catalan", federation: .fcf, on: app)

            try await app.testing().test(
                .GET, "/v1/club",
                beforeRequest: { $0.headers.add(name: "X-Club", value: "madrid") }
            ) { response async throws in
                #expect(response.status == .ok)
                let club = try Self.decode(response)
                #expect(club.federation.value1 == .rffm)
                #expect(club.federationProvidesRoundStandings)
                #expect(club.federationProvidesScorers)
            }

            // Mismo endpoint, mismo código, otro tenant: D-55 y D-48 en acción.
            try await app.testing().test(
                .GET, "/v1/club",
                beforeRequest: { $0.headers.add(name: "X-Club", value: "catalan") }
            ) { response async throws in
                #expect(response.status == .ok)
                let club = try Self.decode(response)
                #expect(club.federation.value1 == .fcf)
                #expect(!club.federationProvidesRoundStandings)
                #expect(!club.federationProvidesScorers)
            }

            try await Self.cleanUp(["madrid", "catalan"], on: app)
        }
    }

    /// El "cierre por arriba" de §6.1, medido en el spike: en ninguno de los dos
    /// casos se llega a tocar un *schema* de tenant.
    @Test("petición sin club → 400; club desconocido → 404 (§6.1)")
    func tenantResolutionClosesFromAbove() async throws {
        try await Self.withApp { app in
            try await app.testing().test(.GET, "/v1/club") { response async in
                #expect(response.status == .badRequest, "sin club identificable")
            }
            try await app.testing().test(
                .GET, "/v1/club",
                beforeRequest: { $0.headers.add(name: "X-Club", value: "no-existe") }
            ) { response async in
                // 404 **literal**: para esta consulta el club no existe. No es el
                // 404 defensivo de §7.5, que ahí sería mentira (D-64).
                #expect(response.status == .notFound)
            }
        }
    }

    /// El aislamiento entre clubes **no usa el mecanismo de 403** (§7.5): un
    /// recurso de otro tenant sencillamente no existe para la consulta, porque el
    /// `search_path` no lo alcanza. Aquí se comprueba que dos tokens ven cosas
    /// distintas por la **misma** ruta, sin `clubId` en ninguna parte (§6).
    @Test("ningún recurso lleva clubId: la misma ruta sirve datos distintos (§6)")
    func sameRouteDifferentTenants() async throws {
        try await Self.withApp { app in
            try await Self.cleanUp(["uno", "dos"], on: app)
            try await Self.seed("uno", federation: .rffm, on: app)
            try await Self.seed("dos", federation: .rffm, on: app)

            var names: [String] = []
            for slug in ["uno", "dos"] {
                try await app.testing().test(
                    .GET, "/v1/club",
                    beforeRequest: { $0.headers.add(name: "X-Club", value: slug) }
                ) { response async throws in
                    #expect(response.status == .ok)
                    let club = try Self.decode(response)
                    #expect(club.slug == slug)
                    names.append(club.slug)
                }
            }
            #expect(names == ["uno", "dos"])

            try await Self.cleanUp(["uno", "dos"], on: app)
        }
    }
}

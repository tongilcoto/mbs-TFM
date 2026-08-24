import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 de la pirámide (§8.1): orquestación con **puertos falseados**, cero I/O.
///
/// Que esto se pueda escribir sin contenedor ni red es el dividendo de D-01, y
/// es la razón por la que la capa rápida de tests puede ser ancha (§8.1).
@Suite("GetClub · §4.3 · el caso de uso depende del puerto, no de Fluent")
struct GetClubTests {

    /// Doble del puerto `ClubRepository`. Nótese lo que **no** hace falta para
    /// escribirlo: ni Postgres, ni `search_path`, ni Vapor.
    struct ClubRepositoryStub: ClubRepository {
        let stored: Club?
        func current() async throws -> Club? { stored }
    }

    static func makeClub(federation: FederationCode = .rffm) throws -> Club {
        try Club(
            id: .init(raw: UUID()),
            name: "Club Deportivo Ejemplo",
            shortName: "CD Ejemplo",
            slug: try Slug("cd-ejemplo"),
            federation: federation,
            createdAt: .init(timeIntervalSince1970: 0),
            updatedAt: .init(timeIntervalSince1970: 0)
        )
    }

    static func makeActor() throws -> ActorContext {
        ActorContext(clubSlug: try Slug("cd-ejemplo"))
    }

    @Test("devuelve el club del tenant")
    func returnsClub() async throws {
        let expected = try Self.makeClub()
        let useCase = GetClub(clubs: ClubRepositoryStub(stored: expected))

        let result = try await useCase.execute(actor: try Self.makeActor())

        #expect(result == expected)
    }

    /// Un *schema* sin club es un fallo de **provisión** (§6.3), no un 404 de
    /// negocio: `Club` es *singleton* del tenant y su alta es un comando
    /// administrativo, no un `POST` (D-23).
    @Test("un schema sin club es fallo de provisión, no un caso de negocio (§6.3, D-23)")
    func failsWhenNotProvisioned() async throws {
        let useCase = GetClub(clubs: ClubRepositoryStub(stored: nil))

        await #expect(throws: ApplicationError.tenantNotProvisioned(slug: "cd-ejemplo")) {
            try await useCase.execute(actor: try Self.makeActor())
        }
    }

    /// D-17: las capacidades **no se almacenan**, se derivan del catálogo en
    /// código. El caso de uso no las toca — y esa es justamente la garantía:
    /// no hay forma de que la BD y el catálogo discrepen.
    @Test("las capacidades salen del catálogo, no de la fila (D-17)")
    func capabilitiesAreDerived() async throws {
        let catalan = try Self.makeClub(federation: .fcf)
        let useCase = GetClub(clubs: ClubRepositoryStub(stored: catalan))

        let result = try await useCase.execute(actor: try Self.makeActor())

        #expect(!result.federationCapabilities.providesRoundStandings)
        #expect(!result.federationCapabilities.providesScorers)
    }
}

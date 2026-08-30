import APIContract
import Application
import Domain
import Fluent
import Foundation
import HTTPAdapter
import SQLKit
import Testing
import Vapor
import VaporTesting
@testable import App
import TestSupport
@testable import Persistence
@testable import Tenancy

/// Nivel 4 (§8.1): los **dos primeros endpoints desde F0**. Pocos y selectivos —
/// las reglas del recorrido ya están probadas en los niveles 2 y 3; aquí se
/// prueba el **borde**: ruta, DTO y código de respuesta.
@Suite("Ingestion · §5.6 · el registro y el disparador",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct IngestionEndpointTests {

    static let prefix = "e2e_"
    static let slug = "ingclub"
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// Dentro de la temporada 2025/26, que es la que se siembra. **El reloj se
    /// fija** para que "la vigente" no dependa del día en que corra la batería.
    static let syncInstant = instant("2026-03-02")

    static func instant(_ yyyyMMdd: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: yyyyMMdd)!
    }

    struct FixedClock: Clock {
        let instant: Date
        func now() -> Date { instant }
    }

    static let emptyCalendar = FederationCalendar(
        seasonLabel: try! SeasonLabel("2025/26"),
        competitionName: nil, groupLabel: "Grupo 1",
        currentRound: 1, rounds: [])

    /// Nunca sale a la red: es la regla de Plan §4.4 —la batería determinista, el
    /// canario aparte—.
    struct StubProvider: FederationClientProvider {
        let failing: Bool
        func client(for code: FederationCode) -> (any FederationClient)? {
            StubClient(failing: failing)
        }
    }

    struct StubClient: FederationClient {
        let failing: Bool
        struct Broken: Error {}
        func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
            if failing { throw Broken() }
            return IngestionEndpointTests.emptyCalendar
        }
    }

    /// El *schema* del club, con la **entrada** de la ingesta sembrada (`D-16`).
    static func withSeededClub(
        failingFederation: Bool = false,
        _ body: @escaping @Sendable (Application, SeasonID, CompetitionID) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp(
            federationClients: StubProvider(failing: failingFederation),
            background: InlineBackgroundWork(),
            clock: FixedClock(instant: syncInstant)
        ) { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(
                slug, federation: .rffm, schemaPrefix: prefix, on: app)

            let seasonID = SeasonID(raw: UUID())
            let competitionID = CompetitionID(raw: UUID())
            let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            let actor = ActorContext(clubSlug: try Slug(slug))
            try await unitOfWork.withRepositories(actor: actor) { repositories in
                try await repositories.seasons.save(
                    try Season(
                        id: seasonID, label: try SeasonLabel("2025/26"),
                        federationSeasonID: "21", createdAt: now, updatedAt: now))
                try await repositories.competitions.save(
                    try Competition(
                        id: competitionID, seasonID: seasonID,
                        modality: .futbol11, gender: .masculino,
                        federationCompetitionID: "24037548", federationGroupID: "24037549",
                        ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
                        groupLabel: "Grupo 1", createdAt: now, updatedAt: now))
            }

            try await body(app, seasonID, competitionID)
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func decodeRuns(_ response: TestingHTTPResponse) throws
        -> [Components.Schemas.IngestionRunResponse]
    {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            [Components.Schemas.IngestionRunResponse].self,
            from: Data(response.body.readableBytesView))
    }

    static func decodeRun(_ response: TestingHTTPResponse) throws
        -> Components.Schemas.IngestionRunResponse
    {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            Components.Schemas.IngestionRunResponse.self,
            from: Data(response.body.readableBytesView))
    }

    static func header(_ request: inout TestingHTTPRequest) {
        request.headers.add(name: "X-Club", value: slug)
    }

    /// Codifica el cuerpo con el **tipo generado del spec**, no con un JSON a
    /// mano: si el contrato y lo que el test manda divergieran, esto no
    /// compilaría — que es el punto entero de *design-first* (`D-65`).
    static func body(
        _ request: inout TestingHTTPRequest,
        seasonId: String? = nil, competitionId: String? = nil
    ) throws {
        let payload = Components.Schemas.TriggerIngestionRequest(
            seasonId: seasonId, competitionId: competitionId)
        request.headers.contentType = .json
        request.body = ByteBuffer(
            string: String(decoding: try JSONEncoder().encode(payload), as: UTF8.self))
    }

    // ─────────────────────────────────────────────────────────────────────────

    @Test("con `competitionId` la pasada se hace y se devuelve (200, §2.3-c)")
    func aSingleCompetitionSyncsInline() async throws {
        try await Self.withSeededClub { app, _, competitionID in
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.body(
                        &request, competitionId: competitionID.raw.uuidString.lowercased())
                }
            ) { response async throws in
                // **200 y no 202**: una petición a la federación y el calendario
                // de un grupo caben dentro de una respuesta HTTP, y devolver la
                // pasada ya hecha es lo que hace útil el botón de la ficha.
                #expect(response.status == .ok)
                let run = try Self.decodeRun(response)
                #expect(run.competitionId == competitionID.raw.uuidString.lowercased())
                #expect(run.outcome == .succeeded)
            }
        }
    }

    @Test("sin `competitionId` se acepta el recorrido y se dice qué entra (202, D-67)")
    func awholeSeasonIsAccepted() async throws {
        try await Self.withSeededClub { app, _, competitionID in
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.body(&request)
                }
            ) { response async throws in
                // **202 y no 200**: una temporada son decenas de competiciones y
                // ~240 partidos cada una. Es el mismo argumento de `D-67`.
                #expect(response.status == .accepted)
                let accepted = try JSONDecoder().decode(
                    Components.Schemas.IngestionAcceptedResponse.self,
                    from: Data(response.body.readableBytesView))
                #expect(accepted.competitionIds == [competitionID.raw.uuidString.lowercased()])
            }
        }
    }

    @Test("un POST sin cuerpo es 400, y por eso el cuerpo es obligatorio (D-65)")
    func aBodylessPostIsRejected() async throws {
        try await Self.withSeededClub { app, _, _ in
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in Self.header(&request) }
            ) { response async in
                // El *spec* declaraba `required: false` y prometía que el cuerpo
                // se podía omitir. **Era falso**: el servidor generado lo parsea
                // igual. Se corrigió el contrato —`required: true`, `{}` para la
                // temporada vigente— y este test es lo que impide que la promesa
                // vuelva a escribirse. Es `D-65` otra vez: el generador emite
                // tipos, no comportamiento, y lo que el YAML dice hay que ir a
                // comprobarlo.
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("el registro se lee de la más reciente a la más antigua (D-85)")
    func theRegistryReadsNewestFirst() async throws {
        try await Self.withSeededClub { app, _, competitionID in
            // Dos pasadas, para que el orden signifique algo.
            for _ in 0..<2 {
                try await app.testing().test(
                    .POST, "/v1/ingestion-runs",
                    beforeRequest: { request async throws in
                        Self.header(&request)
                        try Self.body(
                            &request, competitionId: competitionID.raw.uuidString.lowercased())
                    }
                ) { _ async in }
            }

            try await app.testing().test(
                .GET, "/v1/ingestion-runs?competitionId=\(competitionID.raw.uuidString.lowercased())",
                beforeRequest: { request async throws in Self.header(&request) }
            ) { response async throws in
                #expect(response.status == .ok)
                let runs = try Self.decodeRuns(response)
                #expect(runs.count == 2)
                // La pregunta que esta tabla contesta es *"¿qué pasó la última
                // vez?"*, así que el orden es parte del contrato, no un detalle.
                if runs.count == 2 { #expect(runs[0].finishedAt >= runs[1].finishedAt) }
            }
        }
    }

    @Test("la pasada que falla también se puede leer (D-85)")
    func aFailedPassIsReadable() async throws {
        try await Self.withSeededClub(failingFederation: true) { app, _, competitionID in
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.body(
                        &request, competitionId: competitionID.raw.uuidString.lowercased())
                }
            ) { response async in
                // **502**: el fallo no es del cliente, es del tercero (§5.4, y el
                // mismo criterio que `D-84` en `ProblemMiddleware`).
                #expect(response.status == .badGateway)
            }

            try await app.testing().test(
                .GET, "/v1/ingestion-runs?competitionId=\(competitionID.raw.uuidString.lowercased())",
                beforeRequest: { request async throws in Self.header(&request) }
            ) { response async throws in
                let runs = try Self.decodeRuns(response)
                // Es **toda la razón de ser** de `D-85`: la pasada que falla es la
                // que nadie ve, y se escribe fuera de la transacción que se
                // deshizo para que quede algo que leer.
                #expect(runs.count == 1)
                #expect(runs.first?.outcome == .failed)
                #expect(runs.first?.error != nil)
            }
        }
    }

    @Test("sin `competitionId` el registro no se sirve: 400 (§5.3)")
    func theRegistryDemandsItsScope() async throws {
        try await Self.withSeededClub { app, _, _ in
            try await app.testing().test(
                .GET, "/v1/ingestion-runs",
                beforeRequest: { request async throws in Self.header(&request) }
            ) { response async in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("un `limit` fuera de rango es 400, no un recorte silencioso (§5.5)")
    func anOutOfRangeLimitIsRejected() async throws {
        try await Self.withSeededClub { app, _, competitionID in
            let id = competitionID.raw.uuidString.lowercased()
            for limit in ["0", "101"] {
                try await app.testing().test(
                    .GET, "/v1/ingestion-runs?competitionId=\(id)&limit=\(limit)",
                    beforeRequest: { request async throws in Self.header(&request) }
                ) { response async in
                    // **El generador ignora `minimum`/`maximum`** (`D-65`, tabla de
                    // reparto de §5.5), así que esto lo hace cumplir el handler o no
                    // lo hace nadie. Y recortar en silencio sería peor que un 400:
                    // el cliente creería haber pedido lo que no pidió.
                    #expect(response.status == .badRequest, "limit=\(limit)")
                }
            }
        }
    }

    @Test("una competición de otro club no existe para esta consulta: 404 (§6, §7.5)")
    func anotherClubsCompetitionIsNotFound() async throws {
        try await Self.withSeededClub { app, _, _ in
            let alien = UUID().uuidString.lowercased()
            try await app.testing().test(
                .GET, "/v1/ingestion-runs?competitionId=\(alien)",
                beforeRequest: { request async throws in Self.header(&request) }
            ) { response async in
                // 404 **literal**, no el defensivo de §7.5: el `search_path` no
                // alcanza la fila, así que para esta consulta no existe.
                #expect(response.status == .notFound)
            }
        }
    }

    @Test("una temporada que no existe no cae a la vigente: 404 (D-84)")
    func anUnknownSeasonIsNotFound() async throws {
        try await Self.withSeededClub { app, _, _ in
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.body(&request, seasonId: UUID().uuidString.lowercased())
                }
            ) { response async in
                #expect(response.status == .notFound)
            }
        }
    }
}

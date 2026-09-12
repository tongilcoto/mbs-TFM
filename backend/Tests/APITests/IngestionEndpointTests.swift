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
        _ body: @escaping @Sendable (Application, SeasonID, CompetitionID, CompetitionID) async throws -> Void
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
            // La segunda es el "Infantil A" de la pantalla: el club tiene varios
            // equipos y la lista de casillas tiene más de una fila.
            let otherCompetitionID = CompetitionID(raw: UUID())
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
                try await repositories.competitions.save(
                    try Competition(
                        id: otherCompetitionID, seasonID: seasonID,
                        modality: .futbol11, gender: .masculino,
                        federationCompetitionID: "24037550", federationGroupID: "24037551",
                        ageCategory: .infantil, divisionLabel: "Primera División Autonómica",
                        groupLabel: "Grupo 2", createdAt: now, updatedAt: now))
            }

            try await body(app, seasonID, competitionID, otherCompetitionID)
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
        seasonId: String? = nil, competitionIds: [String]? = nil
    ) throws {
        let payload = Components.Schemas.TriggerIngestionRequest(
            seasonId: seasonId, competitionIds: competitionIds)
        request.headers.contentType = .json
        request.body = ByteBuffer(
            string: String(decoding: try JSONEncoder().encode(payload), as: UTF8.self))
    }

    // ─────────────────────────────────────────────────────────────────────────

    @Test("con `competitionId` la pasada se hace y se devuelve (200, §2.3-c)")
    func aSingleCompetitionSyncsInline() async throws {
        try await Self.withSeededClub { app, _, competitionID, _ in
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.body(
                        &request, competitionIds: [competitionID.raw.uuidString.lowercased()])
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
        try await Self.withSeededClub { app, _, competitionID, _ in
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
                #expect(accepted.competitionIds.count == 2)
                #expect(accepted.competitionIds.contains(competitionID.raw.uuidString.lowercased()))
            }
        }
    }

    @Test("un POST sin cuerpo es 400, y por eso el cuerpo es obligatorio (D-65)")
    func aBodylessPostIsRejected() async throws {
        try await Self.withSeededClub { app, _, _, _ in
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

    @Test("con dos competiciones marcadas es 202, no 200 (D-88)")
    func twoCompetitionsAreAccepted() async throws {
        try await Self.withSeededClub { app, _, cadete, infantil in
            let ids = [cadete, infantil].map { $0.raw.uuidString.lowercased() }
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.body(&request, competitionIds: ids)
                }
            ) { response async throws in
                // **El código lo decide la petición, no los datos.** Una son ~240
                // partidos; dos ya no caben en una respuesta HTTP (`D-67`).
                #expect(response.status == .accepted)
                let accepted = try JSONDecoder().decode(
                    Components.Schemas.IngestionAcceptedResponse.self,
                    from: Data(response.body.readableBytesView))
                // Y en el orden pedido, que es el de las casillas marcadas.
                #expect(accepted.competitionIds == ids)
            }

            // Las dos se sincronizaron de verdad: el 202 no es un "quizá".
            for id in ids {
                try await app.testing().test(
                    .GET, "/v1/ingestion-runs?competitionId=\(id)",
                    beforeRequest: { request async throws in Self.header(&request) }
                ) { response async throws in
                    #expect(try Self.decodeRuns(response).count == 1, "id \(id)")
                }
            }
        }
    }

    @Test("una lista vacía no significa «todas»: 400 (D-88)")
    func anEmptySelectionIsRejected() async throws {
        try await Self.withSeededClub { app, _, _, _ in
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.body(&request, competitionIds: [])
                }
            ) { response async in
                // Adivinar por el cliente aquí significa lanzar el recorrido
                // entero del club por una casilla sin marcar.
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("el registro se lee de la más reciente a la más antigua (D-85)")
    func theRegistryReadsNewestFirst() async throws {
        try await Self.withSeededClub { app, _, competitionID, _ in
            // Dos pasadas, para que el orden signifique algo.
            for _ in 0..<2 {
                try await app.testing().test(
                    .POST, "/v1/ingestion-runs",
                    beforeRequest: { request async throws in
                        Self.header(&request)
                        try Self.body(
                            &request, competitionIds: [competitionID.raw.uuidString.lowercased()])
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
        try await Self.withSeededClub(failingFederation: true) { app, _, competitionID, _ in
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.body(
                        &request, competitionIds: [competitionID.raw.uuidString.lowercased()])
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
        try await Self.withSeededClub { app, _, _, _ in
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
        try await Self.withSeededClub { app, _, competitionID, _ in
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
        try await Self.withSeededClub { app, _, _, _ in
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
        try await Self.withSeededClub { app, _, _, _ in
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

    @Test("lo que el 202 aceptó y no llegó a hacerse se dice por el log (H-27)")
    func acceptedWorkThatVanishesIsReported() async throws {
        try await Self.withSeededClub { app, seasonID, competitionID, otherID in
            // El ámbito 1 —el del plan, el que decide el `202`— pasa; el
            // siguiente no. Es la forma exacta de H-27 medida a mano: el cliente
            // recibe su `202` y la base se cae detrás. El mismo patrón que A-3
            // usó para H-24, y por lo mismo: parar el contenedor desde un test de
            // esta suite se lo llevaría por delante a las demás.
            let spy = LogSpy()
            let handler = APIHandler(
                unitOfWork: CollapsingUnitOfWork(
                    inner: FluentTenantUnitOfWork(controlDatabase: app.db(.control)),
                    collapse: Collapse(failsFromScope: 2)),
                federationClients: StubProvider(failing: false),
                clock: FixedClock(instant: Self.syncInstant),
                background: InlineBackgroundWork(),
                logger: Logger(label: "test") { _ in CapturingLogHandler(spy: spy) })

            let tenant = try await TenantResolver(database: app.db(.control))
                .resolve(slug: Self.slug)
            let output = try await TenantContext.$current.withValue(tenant) {
                try await handler.triggerIngestion(
                    .init(body: .json(.init(seasonId: seasonID.raw.uuidString.lowercased()))))
            }

            // **El `202` se mantiene, y es lo correcto**: la planificación sí
            // ocurrió y el cliente no tiene culpa de lo que pase después. Lo que
            // se audita es que el fallo no se quede sin contar.
            guard case .accepted = output else {
                Issue.record("se esperaba 202, llegó \(output)")
                return
            }

            // La ingesta no dejó fila —la base es lo que falló (H-23)—, así que el
            // log es la única señal posible. Sin esto, el trabajo aceptado
            // desaparece y `ingestionHealth` sigue diciendo `ok` (`D-89`).
            let errors = spy.messages(at: .error)
            #expect(errors.count == 1)
            #expect(errors.first?.contains("no se hizo") == true)
            // Y dice **cuáles**: los dos ids que el `202` prometió.
            #expect(errors.first?.contains(competitionID.raw.uuidString.lowercased()) == true)
            #expect(errors.first?.contains(otherID.raw.uuidString.lowercased()) == true)
        }
    }

    @Test("el recorrido que se para a mitad detrás de un 202 también se dice (H-27, H-23)")
    func anAbortedTraversalBehindA202IsReported() async throws {
        try await Self.withSeededClub { app, seasonID, _, _ in
            // La base aguanta la primera competición y se cae al ir por la
            // segunda: es `abortedByInfrastructure`, la bandera que A-3 creó para
            // que el llamante pudiera distinguir *"falló una"* de *"el recorrido
            // no siguió"*. Por la ruta del `202` ese llamante es un `Task { }`, y
            // antes de esto la bandera se tiraba sin leerla.
            let collapse = Collapse()
            let spy = LogSpy()
            let handler = APIHandler(
                unitOfWork: CollapsingUnitOfWork(
                    inner: FluentTenantUnitOfWork(controlDatabase: app.db(.control)),
                    collapse: collapse),
                federationClients: CollapsingProvider(
                    collapse: collapse, fetches: Collapse(failsFromScope: 2)),
                clock: FixedClock(instant: Self.syncInstant),
                background: InlineBackgroundWork(),
                logger: Logger(label: "test") { _ in CapturingLogHandler(spy: spy) })

            let tenant = try await TenantResolver(database: app.db(.control))
                .resolve(slug: Self.slug)
            _ = try await TenantContext.$current.withValue(tenant) {
                try await handler.triggerIngestion(
                    .init(body: .json(.init(seasonId: seasonID.raw.uuidString.lowercased()))))
            }

            // **`error` y no `warning`**: de esto no queda constancia en ningún
            // otro sitio. La fila de `D-85` no se pudo escribir —la base es lo que
            // falló— así que si esto no se dice, no se dice en ninguna parte.
            let errors = spy.messages(at: .error)
            #expect(errors.count == 1)
            #expect(errors.first?.contains("se paró") == true)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dobles de este fichero. No van a `TestSupport` a propósito: los usa una sola
// suite y moverlos allí sería API compartida por un caso (§3, regla 2).

/// Cuenta ámbitos de tenant y deja de abrirlos a partir del que se le diga.
///
/// Es *"la base se cae detrás del `202`"* sin tocar el contenedor: las suites
/// corren en paralelo y `docker compose stop db` desde aquí sería una carrera
/// contra las demás — la lección de arnés que F6 dejó escrita.
struct CollapsingUnitOfWork: TenantUnitOfWork {
    let inner: any TenantUnitOfWork
    let collapse: Collapse

    struct DatabaseIsGone: Error {}

    func withRepositories<T: Sendable>(
        actor: ActorContext,
        _ work: @escaping @Sendable (any Repositories) async throws -> T
    ) async throws -> T {
        guard !collapse.openScope() else { throw DatabaseIsGone() }
        return try await inner.withRepositories(actor: actor, work)
    }
}

/// El momento de la caída, con **dos gatillos** porque las dos ramas de H-27
/// necesitan momentos distintos.
///
/// - `failsFromScope` — *"la base ya no está cuando vuelva a abrirse un ámbito"*.
///   Sirve para el fallo **antes de empezar**: el plan del `202` pasa (ámbito 1)
///   y el del recorrido, no.
/// - `force()` — *"cáete ahora"*, llamado desde el doble de la federación entre
///   una competición y la siguiente. Es el fallo **a mitad**, y es la forma
///   literal del experimento con que A-3 midió H-23.
final class Collapse: @unchecked Sendable {
    private let lock = NSLock()
    private var scopes = 0
    private var forced = false
    private let failsFromScope: Int?

    init(failsFromScope: Int? = nil) {
        self.failsFromScope = failsFromScope
    }

    func force() {
        lock.lock()
        defer { lock.unlock() }
        forced = true
    }

    /// `true` si este ámbito ya no se puede abrir.
    func openScope() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        scopes += 1
        if forced { return true }
        if let failsFromScope { return scopes >= failsFromScope }
        return false
    }
}

/// Tumba la base **entre una competición y la siguiente**, desde el sitio donde
/// A-3 la tumbó: justo antes de devolver el calendario.
struct CollapsingProvider: FederationClientProvider {
    let collapse: Collapse
    /// Su propio contador, con su propio umbral: **el del test, no uno estático**.
    /// Un contador compartido entre casos sería estado global en una batería
    /// paralela, que es la lección de arnés de F6.
    let fetches: Collapse

    func client(for code: FederationCode) -> (any FederationClient)? {
        CollapsingClient(collapse: collapse, fetches: fetches)
    }
}

struct CollapsingClient: FederationClient {
    let collapse: Collapse
    let fetches: Collapse

    func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
        // `openScope` cuenta llamadas y dice si toca caerse; aquí las llamadas son
        // *fetches*, que es lo mismo con otro nombre.
        if fetches.openScope() { collapse.force() }
        return IngestionEndpointTests.emptyCalendar
    }
}

/// Recoge lo que se registra, para que una aserción pueda mirarlo.
///
/// **Con *lock* y no `actor`**, aunque el proyecto prefiera `actor`: `LogHandler.log`
/// es síncrono, así que desde dentro no se puede `await`. Un `Task { }` para
/// entregarle el mensaje dejaría la aserción corriendo contra él — que es
/// exactamente la carrera que este bloque vino a no arbitrar.
final class LogSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(Logger.Level, String)] = []

    func record(_ level: Logger.Level, _ message: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.append((level, message))
    }

    func messages(at level: Logger.Level) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.0 == level }.map(\.1)
    }
}

struct CapturingLogHandler: LogHandler {
    let spy: LogSpy
    var metadata = Logger.Metadata()
    var logLevel = Logger.Level.trace

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?,
        source: String, file: String, function: String, line: UInt
    ) {
        // El mensaje y los metadatos se aplanan juntos: lo que se afirma es
        // *qué se dijo*, y los ids de competición viajan en los metadatos.
        let flattened = ((metadata ?? [:]).merging(self.metadata) { a, _ in a })
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: " ")
        spy.record(level, "\(message) \(flattened)")
    }
}

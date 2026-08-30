import Application
import Domain
import Fluent
import Foundation
import SQLKit
import Testing
import Vapor

@testable import App
import TestSupport
@testable import Persistence
@testable import Tenancy

/// Nivel 3 (§8.1): **el recorrido por tenant**, contra Postgres real.
///
/// Lo que aquí se prueba es lo que el nivel 2 no puede: que el recorrido escribe
/// en el *schema* de cada club y **no los cruza**. Con dobles no significa nada
/// —no hay *schemas* que cruzar—, y es justo el fallo que más caro sale en un
/// backend multi-tenant.
///
/// El calendario está falseado a propósito: lo que se afirma es **a qué base
/// aterriza cada pasada**, no qué trae. El contenido ya lo cubre F5.
@Suite("Recorrido por tenant · §2.3-b · el job contra Postgres",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct TenantTraversalTests {

    static let prefix = "test_job_"
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// Un calendario vacío. La pasada se hace, escribe `last_synced_at` y deja su
    /// fila en `ingestion_runs`; no crea partidos porque no hay ninguno que
    /// crear.
    static let emptyCalendar = FederationCalendar(
        seasonLabel: try! SeasonLabel("2025/26"),
        competitionName: nil, groupLabel: "Grupo 1",
        currentRound: 1, rounds: [])

    /// Devuelve siempre lo mismo y **apunta con qué coordenada se le llamó**.
    final class RecordingClient: FederationClient, @unchecked Sendable {
        private let failingGroups: Set<String>
        private(set) var received: [FederationCoordinate] = []

        init(failingGroups: Set<String> = []) { self.failingGroups = failingGroups }

        struct Broken: Error {}

        func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
            received.append(coordinate)
            if failingGroups.contains(coordinate.federationGroupID) { throw Broken() }
            return TenantTraversalTests.emptyCalendar
        }
    }

    struct SingleClientProvider: FederationClientProvider {
        let client: any FederationClient
        func client(for code: FederationCode) -> (any FederationClient)? { client }
    }

    static func withTenants(
        _ slugs: [String], _ body: @escaping @Sendable (Application) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs(slugs, schemaPrefix: prefix, on: app)
            for slug in slugs {
                try await TestEnvironment.provisionClub(
                    slug, federation: .rffm, schemaPrefix: prefix, on: app)
            }
            try await body(app)
            try await TestEnvironment.dropClubs(slugs, schemaPrefix: prefix, on: app)
        }
    }

    /// Siembra la **entrada** de la ingesta (`D-16`) en el *schema* de un club:
    /// una temporada vigente y una competición con su coordenada.
    @discardableResult
    static func seed(
        _ slug: String, group: String, on app: Application
    ) async throws -> CompetitionID {
        let fixture = TenantFixture(app: app, slug: slug, schema: "\(prefix)\(slug)")
        let seasonID = SeasonID(raw: UUID())
        let competitionID = CompetitionID(raw: UUID())
        try await fixture.scope { repositories in
            try await repositories.seasons.save(
                try Season(
                    id: seasonID, label: try SeasonLabel("2025/26"),
                    federationSeasonID: "21", createdAt: now, updatedAt: now))
            try await repositories.competitions.save(
                try Competition(
                    id: competitionID, seasonID: seasonID,
                    modality: .futbol11, gender: .masculino,
                    federationCompetitionID: "24037548", federationGroupID: group,
                    ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
                    groupLabel: "Grupo 1", createdAt: now, updatedAt: now))
        }
        return competitionID
    }

    /// Las pasadas registradas en el *schema* de ese club.
    static func runs(_ slug: String, on app: Application) async throws -> [IngestionRun] {
        let fixture = TenantFixture(app: app, slug: slug, schema: "\(prefix)\(slug)")
        return try await fixture.scope { repositories in
            var all: [IngestionRun] = []
            for season in try await repositories.seasons.list(includingArchived: true) {
                for competition in try await repositories.competitions.list(seasonID: season.id) {
                    all += try await repositories.ingestionRuns.list(
                        competitionID: competition.id, limit: 10)
                }
            }
            return all
        }
    }

    // ─────────────────────────────────────────────────────────────────────────

    /// **La temporada vigente depende de la fecha real**, así que el reloj del
    /// job se fija: sin esto el test caducaría el 1 de julio de 2026 y el fallo
    /// aparecería meses después, sin relación con el cambio que lo destapó.
    static var clock: some Clock { FixedInstantClock(instant: instant("2026-03-02")) }

    static func instant(_ yyyyMMdd: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: yyyyMMdd)!
    }

    struct FixedInstantClock: Clock {
        let instant: Date
        func now() -> Date { instant }
    }

    /// **Sin efectos a propósito.** Ejecutar la ingesta para probar esto
    /// escribiría en el *schema* de **todos** los clubes de la base, que en la
    /// batería son los de las demás suites corriendo en paralelo — y sus
    /// aserciones cuentan filas. Lo aprendí rompiéndolas: el recorrido devolvía
    /// `["e2e-sinjugar", "jobcat", "jobmad", "match-rt", "season-arch"]`.
    @Test("sin filtro, el recorrido son todos los clubes del plano de control (§4.7)")
    func everyTenantIsVisited() async throws {
        try await Self.withTenants(["jobuno", "jobdos"]) { app in
            let all = try await IngestCommand.tenants(on: app, slugs: nil)
            let mine = try await IngestCommand.tenants(on: app, slugs: ["jobuno", "jobdos"])

            // Es el recorrido de §4.7 aplicado a la ingesta: el mismo
            // `public.tenants` que recorren las migraciones, y por el mismo
            // motivo — con varios clubes en el proyecto, "el club" no existe.
            #expect(mine == ["jobdos", "jobuno"])
            #expect(Set(mine).isSubset(of: Set(all)))
            #expect(all.count >= mine.count)
        }
    }

    @Test("los dos clubes se sincronizan en la misma pasada (§4.7)")
    func bothTenantsAreSynced() async throws {
        try await Self.withTenants(["jobuno", "jobdos"]) { app in
            try await Self.seed("jobuno", group: "111", on: app)
            try await Self.seed("jobdos", group: "222", on: app)

            let client = RecordingClient()
            _ = try await IngestCommand.ingest(
                on: app, scope: IngestionScope(), tenantSlugs: ["jobuno", "jobdos"],
                federationClients: SingleClientProvider(client: client),
                clock: Self.clock)

            #expect(client.received.map(\.federationGroupID).sorted() == ["111", "222"])
        }
    }

    @Test("cada pasada queda escrita en el schema de su club (§6.2)")
    func eachPassLandsInItsOwnSchema() async throws {
        try await Self.withTenants(["jobuno", "jobdos"]) { app in
            let uno = try await Self.seed("jobuno", group: "111", on: app)
            let dos = try await Self.seed("jobdos", group: "222", on: app)

            _ = try await IngestCommand.ingest(
                on: app, scope: IngestionScope(), tenantSlugs: ["jobuno", "jobdos"],
                federationClients: SingleClientProvider(client: RecordingClient()),
                clock: Self.clock)

            // Es lo que el nivel 2 no puede afirmar: con dobles no hay *schemas*
            // que cruzar. Un `ActorContext` construido con el club equivocado
            // —o un `search_path` que no se fijara— escribiría la pasada de un
            // club en la base de otro, y ninguna restricción lo impediría.
            let runsUno = try await Self.runs("jobuno", on: app)
            let runsDos = try await Self.runs("jobdos", on: app)
            #expect(runsUno.map(\.competitionID) == [uno])
            #expect(runsDos.map(\.competitionID) == [dos])
        }
    }

    @Test("un club sin adaptador no detiene el recorrido de los demás (D-86, D-17)")
    func aClubWithoutAnAdapterDoesNotStopTheRest() async throws {
        try await TestEnvironment.withApp { app in
            let slugs = ["jobcat", "jobmad"]
            try await TestEnvironment.dropClubs(slugs, schemaPrefix: Self.prefix, on: app)
            // El catalán va a la FCF, que no tiene adaptador hasta F9.
            try await TestEnvironment.provisionClub(
                "jobcat", federation: .fcf, schemaPrefix: Self.prefix, on: app)
            try await TestEnvironment.provisionClub(
                "jobmad", federation: .rffm, schemaPrefix: Self.prefix, on: app)
            try await Self.seed("jobcat", group: "111", on: app)
            let madrid = try await Self.seed("jobmad", group: "222", on: app)

            let client = RecordingClient()
            let outcomes = try await IngestCommand.ingest(
                on: app, scope: IngestionScope(), tenantSlugs: slugs,
                // El catálogo **de verdad** (`D-17`): la FCF devuelve `nil`.
                federationClients: CatalogFederationClientProvider(rffm: client),
                clock: Self.clock)

            // El club de Madrid se sincroniza igual. Con el recorrido abortando,
            // bastaría un club de una federación aún no soportada —o una sola
            // coordenada caducada, `D-84`— para dejar sin datos a todos los que
            // vayan detrás por orden alfabético.
            #expect(client.received.map(\.federationGroupID) == ["222"])
            #expect(outcomes.map(\.slug) == ["jobcat", "jobmad"])
            #expect(outcomes.map(\.succeeded) == [false, true])

            // Y **no le deja pasadas fallidas**: no es una pasada que falla, es un
            // club que todavía no se puede sincronizar (`D-85`).
            let catalanRuns = try await Self.runs("jobcat", on: app)
            #expect(catalanRuns.isEmpty)
            #expect(try await Self.runs("jobmad", on: app).map(\.competitionID) == [madrid])

            try await TestEnvironment.dropClubs(slugs, schemaPrefix: Self.prefix, on: app)
        }
    }

    @Test("un club con una competición fallida no cuenta como éxito (D-86)")
    func aClubWithAFailedCompetitionIsNotASuccess() async throws {
        try await Self.withTenants(["jobuno", "jobdos"]) { app in
            try await Self.seed("jobuno", group: "111", on: app)
            try await Self.seed("jobdos", group: "222", on: app)

            let outcomes = try await IngestCommand.ingest(
                on: app, scope: IngestionScope(), tenantSlugs: ["jobuno", "jobdos"],
                federationClients: SingleClientProvider(
                    client: RecordingClient(failingGroups: ["111"])),
                clock: Self.clock)

            // Hay **dos** formas de no terminar bien y las dos tienen que contar:
            // el club que ni llegó a recorrerse y el que se recorrió con alguna
            // competición fallida. Contar solo la primera —que es lo que hacía
            // hasta que la mutación lo destapó— deja al cron viendo verde con
            // media temporada sin sincronizar.
            // Ojo al orden: el recorrido va **ordenado por slug** (§4.7), así
            // que `jobdos` —el sano— va primero. Lo dijo el rojo, no yo.
            #expect(outcomes.map(\.slug) == ["jobdos", "jobuno"])
            #expect(outcomes.map(\.succeeded) == [true, false])
            #expect(IngestCommand.incomplete(outcomes) == ["jobuno"])
        }
    }

    @Test("`--tenant` recorre solo ese club (§4.7)")
    func theTenantOptionNarrowsTheTraversal() async throws {
        try await Self.withTenants(["jobuno", "jobdos"]) { app in
            try await Self.seed("jobuno", group: "111", on: app)
            try await Self.seed("jobdos", group: "222", on: app)

            let client = RecordingClient()
            let outcomes = try await IngestCommand.ingest(
                on: app, scope: IngestionScope(), tenantSlugs: ["jobdos"],
                federationClients: SingleClientProvider(client: client),
                clock: Self.clock)

            // Misma opción y mismo significado que en `migrate-tenants`: es la
            // vía para reparar un club sin tocar a los demás.
            #expect(client.received.map(\.federationGroupID) == ["222"])
            #expect(outcomes.map(\.slug) == ["jobdos"])
        }
    }
}

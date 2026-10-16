import Testing
import Vapor
import Application
import Domain
import App
import TestSupport

/// Nivel 4: **a quién le pregunta `seed-competition`** (hallazgo de `R0.10`).
///
/// El comando se montaba su propio adaptador de la RFFM en vez de pedírselo al
/// catálogo de `configure`, que es el que usa la ingesta. Con `RFFM_BASE_URL`
/// puesta, la ingesta iba a la federación falsa de los escenarios y
/// `seed-competition` a la RFFM de verdad. Y por lo mismo, ninguna prueba podía
/// ponerle un doble delante.
@Suite(
    "SeedCompetitionCommand · el adaptador sale del catálogo (R0.10)",
    .serialized,
    .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct SeedCompetitionCommandTests {

    static let prefix = "test_seed_"

    /// Apunta la coordenada y falla con un error suyo: si el comando lo lanza,
    /// es que le preguntó a este doble y no a la red.
    final class RecordingClient: FederationClient, @unchecked Sendable {
        struct Asked: Error, Equatable {}
        var received: [FederationCoordinate] = []

        func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
            received.append(coordinate)
            throw Asked()
        }
        func fetchStandings(_ coordinate: FederationCoordinate, round: Int) async throws -> FederationStanding {
            throw Asked()
        }
        func fetchScorers(_ coordinate: FederationCoordinate) async throws -> FederationScorerTable {
            throw Asked()
        }
        func coordinate(fromCalendarURL url: String) throws -> FederationCoordinate {
            throw Asked()
        }
    }

    @Test("seed-competition le pregunta al adaptador del catálogo, no a uno propio")
    func asksTheConfiguredAdapter() async throws {
        let client = RecordingClient()
        try await TestEnvironment.withApp(
            federationClients: CatalogFederationClientProvider(rffm: client)
        ) { app in
            try await TestEnvironment.dropClubs(["seedfed"], schemaPrefix: Self.prefix, on: app)
            try await TestEnvironment.provisionClub(
                "seedfed", federation: .rffm, schemaPrefix: Self.prefix, on: app)

            await #expect(throws: RecordingClient.Asked()) {
                try await Self.runCommand([
                    "seed-competition", "-t", "seedfed",
                    "-u", "https://www.rffm.es/competicion/calendario"
                        + "?temporada=21&tipojuego=1&competicion=24037548&grupo=24037549",
                    "-c", "cadete", "-g", "masculino",
                ], on: app)
            }
            #expect(client.received.map(\.federationGroupID) == ["24037549"])

            try await TestEnvironment.dropClubs(["seedfed"], schemaPrefix: Self.prefix, on: app)
        }
    }

    /// Un comando tal como lo ejecuta `Run`, igual que en `MigrationIntegrityTests`.
    static func runCommand(_ arguments: [String], on app: Application) async throws {
        var context = CommandContext(
            console: app.console, input: CommandInput(arguments: ["Run"] + arguments))
        context.application = app
        try await app.console.run(app.asyncCommands.group(), with: context)
    }
}

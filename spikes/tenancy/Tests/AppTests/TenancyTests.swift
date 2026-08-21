import Fluent
import FluentPostgresDriver
import SQLKit
import XCTVapor

@testable import App

/// Batería del spike. Cada test corresponde a una afirmación del LLD que hoy es una
/// suposición: §4.7 (migraciones por tenant), §6.2 (enrutado por `search_path`),
/// §6.4 (implicaciones del pooling).
final class TenancyTests: XCTestCase {
    var app: Application!

    let schemaA = "club_a"
    let schemaB = "club_b"
    let slugA = "atleti"
    let slugB = "rayo"

    override func setUp() async throws {
        app = try await Application.make(.testing)
        try await configure(app)
        try await resetDatabase()
        try await app.autoMigrate()  // plano de control: public.tenants

        for (slug, schema) in [(slugA, schemaA), (slugB, schemaB)] {
            _ = try await TenantRecord.provision(slug: slug, schemaName: schema, on: app.db(.control))
            try await MigrateTenantsCommand.migrate(schema: schema, on: app)
        }
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    // MARK: - §4.7 · Migraciones por tenant

    func testMigrateTenantsCreaUnaTablaPorSchemaYNingunaEnPublic() async throws {
        for schema in [schemaA, schemaB] {
            let seasons = try await tableExists("seasons", in: schema)
            let log = try await tableExists("_fluent_migrations", in: schema)
            XCTAssertTrue(seasons, "falta seasons en \(schema)")
            XCTAssertTrue(log, "falta _fluent_migrations en \(schema)")
        }

        // El juego de migraciones de tenant no debe dejar nada en public…
        let seasonsInPublic = try await tableExists("seasons", in: "public")
        XCTAssertFalse(seasonsInPublic, "una migración de tenant aterrizó en public")

        // …y el plano de control sí vive ahí, y solo ahí.
        let tenantsInPublic = try await tableExists("tenants", in: "public")
        let tenantsInA = try await tableExists("tenants", in: schemaA)
        XCTAssertTrue(tenantsInPublic)
        XCTAssertFalse(tenantsInA)
    }

    /// El progreso de migración se rastrea **por club**: revertir uno no toca al otro.
    func testElProgresoDeMigracionEsPorClub() async throws {
        try await MigrateTenantsCommand.revert(schema: schemaA, on: app)

        let a = try await tableExists("seasons", in: schemaA)
        let b = try await tableExists("seasons", in: schemaB)
        XCTAssertFalse(a, "revertir club_a debía tirar su tabla")
        XCTAssertTrue(b, "revertir club_a no debía tocar club_b")
    }

    /// Un club nuevo parte de cero y recibe el juego completo, no solo la última pendiente.
    func testAltaDeClubNuevoRecibeElJuegoCompleto() async throws {
        let schemaC = "club_c"
        try await dropSchema(schemaC)
        _ = try await TenantRecord.provision(slug: "getafe", schemaName: schemaC, on: app.db(.control))
        try await MigrateTenantsCommand.migrate(schema: schemaC, on: app)

        let exists = try await tableExists("seasons", in: schemaC)
        XCTAssertTrue(exists)
        try await dropSchema(schemaC)
    }

    // MARK: - §6.2 · Aislamiento entre tenants (las dos estrategias)

    func testAislamientoConSetLocalEnTransaccion() async throws {
        try await comprobarAislamiento(con: .setLocalInTransaction)
    }

    func testAislamientoConPoolDedicadoPorTenant() async throws {
        try await comprobarAislamiento(con: .dedicatedPool)
    }

    private func comprobarAislamiento(con estrategia: TenantRoutingStrategy) async throws {
        app.tenantRoutingStrategy = estrategia

        try await crearTemporada(label: "2024/25", federationID: 21, club: slugA)
        try await crearTemporada(label: "2023/24", federationID: 20, club: slugA)
        // Mismo label y mismo id de federación que el club A: legal, porque la unicidad
        // de §3.5 es *por schema*. Si esto da 409, el aislamiento no existe.
        try await crearTemporada(label: "2024/25", federationID: 21, club: slugB)

        let a = try await temporadas(club: slugA)
        let b = try await temporadas(club: slugB)

        XCTAssertEqual(a.map(\.label), ["2023/24", "2024/25"], "estrategia \(estrategia.rawValue)")
        XCTAssertEqual(b.map(\.label), ["2024/25"], "estrategia \(estrategia.rawValue)")
        // Ojo al leer esta cifra: el migrador de setUp ya registra un pool por schema,
        // así que los 2 aparecen también bajo la estrategia A. Lo que distingue a B es que
        // *las peticiones* pasen por ellos; A sirve todas desde el pool compartido.
        evidencia("\(estrategia.rawValue) · pools de tenant registrados: \(app.tenantPools.registeredSchemas.count)")
    }

    /// El caso que de verdad importa: peticiones **concurrentes** de dos clubes contra el
    /// mismo pool. Si el `search_path` fuera un estado compartido, aquí se cruzarían.
    func testAislamientoBajoConcurrencia() async throws {
        app.tenantRoutingStrategy = .setLocalInTransaction
        try await crearTemporada(label: "2024/25", federationID: 21, club: slugA)
        try await crearTemporada(label: "2023/24", federationID: 20, club: slugA)
        try await crearTemporada(label: "2024/25", federationID: 21, club: slugB)

        try await withThrowingTaskGroup(of: (String, [String]).self) { group in
            for i in 0..<40 {
                let club = i.isMultiple(of: 2) ? self.slugA : self.slugB
                group.addTask {
                    (club, try await self.temporadas(club: club).map(\.label))
                }
            }
            for try await (club, labels) in group {
                if club == self.slugA {
                    XCTAssertEqual(labels.sorted(), ["2023/24", "2024/25"])
                } else {
                    XCTAssertEqual(labels, ["2024/25"])
                }
            }
        }
    }

    // MARK: - §6.4 · Pooling: ¿se filtra el search_path?

    /// Estrategia A: `SET LOCAL` dentro de transacción. Postgres lo deshace al commit,
    /// así que la conexión vuelve limpia al pool **sin código de reseteo**.
    func testSetLocalNoFiltraElSearchPathAlPool() async throws {
        let db = pinnedDatabase()
        let pidAntes = try await backendPID(on: db)

        _ = try await TenantRouting.withSearchPath(schemaA, on: db) { tenantDB in
            try await SeasonRecord.query(on: tenantDB).count()
        }

        let pidDespues = try await backendPID(on: db)
        XCTAssertEqual(pidAntes, pidDespues, "el test solo prueba algo si es la misma conexión física")

        let searchPath = try await currentSearchPath(on: db)
        evidencia("A · search_path tras devolver la conexión (pid \(pidDespues)): \(searchPath)")
        XCTAssertFalse(
            searchPath.contains(schemaA),
            "search_path filtrado al pool tras devolver la conexión: \(searchPath)"
        )
    }

    /// **Control negativo.** `SET search_path` a pelo, sin reseteo — que es §6.2 leído
    /// literalmente. Este test *espera* la fuga: documenta por qué el reseteo del LLD no
    /// es una precaución opcional. Si algún día falla, es que el driver empezó a limpiar
    /// las conexiones y habría que revisar la conclusión del spike.
    func testSetSearchPathSinReseteoSiFiltraAlPool() async throws {
        let db = pinnedDatabase()
        let pidAntes = try await backendPID(on: db)

        _ = try await TenantRouting.withNaiveSearchPath(schemaA, on: db) { tenantDB in
            try await SeasonRecord.query(on: tenantDB).count()
        }

        let pidDespues = try await backendPID(on: db)
        XCTAssertEqual(pidAntes, pidDespues)

        let searchPath = try await currentSearchPath(on: db)
        evidencia("A′ · search_path tras devolver la conexión (pid \(pidDespues)): \(searchPath)")
        XCTAssertTrue(
            searchPath.contains(schemaA),
            "esperábamos la fuga; el driver ya no la produce y hay que revisar el spike (search_path: \(searchPath))"
        )
    }

    /// El riesgo fino: una **misma conexión física** sirve a dos clubes con el **mismo SQL**.
    /// Si hubiera caché de plan o de sentencia preparada atada al OID de la tabla, el
    /// segundo cliente vería las filas del primero.
    func testUnaMismaConexionSirveADosClubesSinCruzarFilas() async throws {
        let db = pinnedDatabase()
        try await sembrar(labels: ["2024/25", "2023/24"], en: schemaA, on: db)
        try await sembrar(labels: ["2024/25"], en: schemaB, on: db)

        let pidAntes = try await backendPID(on: db)

        let a = try await TenantRouting.withSearchPath(schemaA, on: db) { tenantDB in
            try await SeasonRecord.query(on: tenantDB).sort(\.$label).all().map(\.label)
        }
        let b = try await TenantRouting.withSearchPath(schemaB, on: db) { tenantDB in
            try await SeasonRecord.query(on: tenantDB).sort(\.$label).all().map(\.label)
        }

        let pidDespues = try await backendPID(on: db)
        XCTAssertEqual(pidAntes, pidDespues, "el test solo prueba algo si es la misma conexión física")
        evidencia("misma conexión (pid \(pidDespues)) → club_a \(a), club_b \(b)")

        XCTAssertEqual(a, ["2023/24", "2024/25"])
        XCTAssertEqual(b, ["2024/25"])
    }

    // MARK: - §6.1 · Resolución

    func testClubDesconocidoNoLlegaANingunSchema() async throws {
        try await app.test(.GET, "seasons", headers: cabeceras(club: "inexistente")) { res async in
            XCTAssertEqual(res.status, .notFound)
        }
    }

    func testPeticionSinClubNoLlegaANingunSchema() async throws {
        try await app.test(.GET, "seasons") { res async in
            XCTAssertEqual(res.status, .badRequest)
        }
    }

    // MARK: - Utilidades

    /// El producto del spike no son los verdes: son las medidas. Se imprimen para poder
    /// citarlas en el §6 cuando se escriba.
    private func evidencia(_ mensaje: String) {
        print("· EVIDENCIA · \(mensaje)")
    }

    private func cabeceras(club: String) -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.add(name: "X-Club", value: club)
        return headers
    }

    private func crearTemporada(label: String, federationID: Int, club: String) async throws {
        var headers = cabeceras(club: club)
        headers.contentType = .json
        let body = try JSONEncoder().encode(SeasonDTO(id: nil, label: label, federationSeasonId: federationID))
        try await app.test(
            .POST, "seasons",
            headers: headers,
            body: ByteBuffer(data: body)
        ) { res async in
            XCTAssertEqual(res.status, .created, "\(res.body.string)")
        }
    }

    private func temporadas(club: String) async throws -> [SeasonDTO] {
        var result: [SeasonDTO] = []
        try await app.test(.GET, "seasons", headers: cabeceras(club: club)) { res async throws in
            XCTAssertEqual(res.status, .ok, "\(res.body.string)")
            result = try res.content.decode([SeasonDTO].self)
        }
        return result
    }

    /// Base de datos fijada a **un** event loop. Con `maxConnectionsPerEventLoop: 1`
    /// (el valor por defecto del driver) eso significa **una** conexión física, que es la
    /// única forma de que los tests de fuga digan algo.
    private func pinnedDatabase() -> any Database {
        app.databases.database(.control, logger: app.logger, on: app.eventLoopGroup.next())!
    }

    private func sembrar(labels: [String], en schema: String, on db: any Database) async throws {
        try await TenantRouting.withSearchPath(schema, on: db) { tenantDB in
            for (i, label) in labels.enumerated() {
                try await SeasonRecord(label: label, federationSeasonID: 100 + i).create(on: tenantDB)
            }
        }
    }

    private func sql() -> any SQLDatabase {
        app.db(.control) as! any SQLDatabase
    }

    private func resetDatabase() async throws {
        for schema in [schemaA, schemaB, "club_c"] {
            try await dropSchema(schema)
        }
        for table in ["tenants", "_fluent_migrations", "seasons"] {
            try await sql().raw("DROP TABLE IF EXISTS public.\(ident: table) CASCADE").run()
        }
    }

    private func dropSchema(_ name: String) async throws {
        try await sql().raw("DROP SCHEMA IF EXISTS \(ident: name) CASCADE").run()
    }

    private func tableExists(_ table: String, in schema: String) async throws -> Bool {
        struct Row: Decodable { let present: Bool }
        let row = try await sql().raw(
            """
            SELECT EXISTS (
                SELECT 1 FROM information_schema.tables
                WHERE table_schema = \(bind: schema) AND table_name = \(bind: table)
            ) AS present
            """
        ).first(decoding: Row.self)
        return row?.present ?? false
    }

    private func backendPID(on db: any Database) async throws -> Int {
        struct Row: Decodable { let pid: Int }
        guard let sql = db as? any SQLDatabase else { throw TenancyError.notASQLDatabase }
        let row = try await sql.raw("SELECT pg_backend_pid() AS pid").first(decoding: Row.self)
        return row?.pid ?? -1
    }

    private func currentSearchPath(on db: any Database) async throws -> String {
        guard let sql = db as? any SQLDatabase else { throw TenancyError.notASQLDatabase }
        return try await showSearchPath(on: sql)
    }
}

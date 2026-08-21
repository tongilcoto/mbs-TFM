import Fluent
import FluentPostgresDriver
import NIOCore
import SQLKit
import XCTVapor

@testable import App

/// Batería del **pooler en modo transacción** (§6.4).
///
/// Cierra la única verificación que el spike dejaba abierta: el punto 3 de la
/// recomendación del README — *"la estrategia A es compatible con pooling en modo
/// transacción y la B no"* — era **inferencia, no medición**. Aquí se mide.
///
/// Nada del código bajo prueba cambia: es la misma `configure`, el mismo
/// `Request.withTenantDB`, las mismas migraciones. Lo único distinto es el socket.
///
/// ## Por qué el `docker-compose.yml` está afinado como está
///
/// `pool_mode = transaction` es la hipótesis. `default_pool_size = 1` es lo que la hace
/// **falsable**: obliga a que todos los clientes multiplexen sobre **una** conexión de
/// servidor, así que la fuga —si existe— es determinista en vez de probabilística.
/// Con el default de 20 estos tests pasarían por casualidad la mitad de las veces, que es
/// la peor propiedad que puede tener un test de aislamiento.
///
/// Y `server_reset_query_always = 0` (el **default** de PgBouncer, no un ajuste nuestro)
/// es lo que hace que `DISCARD ALL` **no** se ejecute en modo transacción. Ese default es
/// la razón última de todo lo que se ve abajo.
final class PoolerTests: XCTestCase {
    /// La aplicación bajo prueba: habla con PgBouncer (:6432).
    var viaPooler: Application!
    /// Conexión directa a Postgres (:5433). **No** es el sistema bajo prueba: sirve para
    /// preparar schemas y migrar, y como observador fuera de banda.
    var direct: Application!

    let schemaA = "pooler_club_a"
    let schemaB = "pooler_club_b"
    let slugA = "atleti"
    let slugB = "rayo"

    override func setUp() async throws {
        try XCTSkipUnless(
            Self.poolerReachable(),
            "PgBouncer no responde en \(SpikeConfig.viaPooler().hostname):\(SpikeConfig.viaPooler().port). "
                + "Levántalo con `docker compose up -d`."
        )

        // El plano de control y las migraciones van por la conexión DIRECTA, igual que en
        // producción: Supabase publica los dos puertos y el DDL nunca debe ir por el pooler
        // (ver `testMigrarPorElPoolerNoEsSeguro`, que enseña por qué).
        direct = try await Application.make(.testing)
        try await configure(direct, config: .fromEnvironment())
        try await limpiar(on: direct)
        try await direct.autoMigrate()
        for (slug, schema) in [(slugA, schemaA), (slugB, schemaB)] {
            _ = try await TenantRecord.provision(slug: slug, schemaName: schema, on: direct.db(.control))
            try await MigrateTenantsCommand.migrate(schema: schema, on: direct)
        }

        viaPooler = try await Application.make(.testing)
        try await configure(viaPooler, config: .viaPooler())
        try await limpiarConexionDeServidor()
    }

    /// PgBouncer mantiene viva su conexión de servidor **entre tests** (`server_lifetime` es
    /// una hora), así que el `search_path` que deja un test lo hereda el siguiente. Es el
    /// mismo fenómeno que la suite estudia, aplicado a la suite: sin esto,
    /// `testEstrategiaANoContaminaLaConexionDeServidor` falla acusando a `SET LOCAL` de una
    /// contaminación que había dejado un test de la estrategia B.
    ///
    /// `SET search_path TO DEFAULT` y no `DISCARD ALL`: este último tira también las sentencias
    /// preparadas, que PgBouncer lleva contadas por su cuenta.
    private func limpiarConexionDeServidor() async throws {
        guard let sql = viaPooler.db(.control) as? any SQLDatabase else { throw TenancyError.notASQLDatabase }
        try await sql.raw("SET search_path TO DEFAULT").run()
    }

    override func tearDown() async throws {
        if viaPooler != nil {
            try await viaPooler.asyncShutdown()
            viaPooler = nil
        }
        if direct != nil {
            try await limpiar(on: direct)
            try await direct.asyncShutdown()
            direct = nil
        }
    }

    // MARK: - Estrategia A · SET LOCAL en transacción

    /// **La luz verde.** `SET LOCAL` vive dentro de la transacción, y la transacción es
    /// justamente la unidad que el pooler **no** parte. Debe aislar igual que sin pooler.
    func testEstrategiaAAislaDetrasDelPooler() async throws {
        viaPooler.tenantRoutingStrategy = .setLocalInTransaction

        try await crearTemporada(label: "2024/25", federationID: 21, club: slugA)
        try await crearTemporada(label: "2023/24", federationID: 20, club: slugA)
        // Mismo label y mismo id de federación que A: legal solo si el aislamiento existe.
        try await crearTemporada(label: "2024/25", federationID: 21, club: slugB)

        let a = try await temporadas(club: slugA).map(\.label)
        let b = try await temporadas(club: slugB).map(\.label)
        evidencia("A · vía pooler → club_a \(a), club_b \(b)")

        XCTAssertEqual(a, ["2023/24", "2024/25"])
        XCTAssertEqual(b, ["2024/25"])
    }

    /// El caso que de verdad importa: peticiones concurrentes de dos clubes, con **una**
    /// conexión de servidor compartida por todas. Si `SET LOCAL` no bastara, aquí se cruzan.
    func testEstrategiaAAislaBajoConcurrenciaDetrasDelPooler() async throws {
        viaPooler.tenantRoutingStrategy = .setLocalInTransaction
        try await crearTemporada(label: "2024/25", federationID: 21, club: slugA)
        try await crearTemporada(label: "2023/24", federationID: 20, club: slugA)
        try await crearTemporada(label: "2024/25", federationID: 21, club: slugB)

        try await withThrowingTaskGroup(of: (String, [String]).self) { group in
            for i in 0..<40 {
                let club = i.isMultiple(of: 2) ? self.slugA : self.slugB
                group.addTask { (club, try await self.temporadas(club: club).map(\.label)) }
            }
            for try await (club, labels) in group {
                if club == self.slugA {
                    XCTAssertEqual(labels.sorted(), ["2023/24", "2024/25"], "cruce en club_a")
                } else {
                    XCTAssertEqual(labels, ["2024/25"], "cruce en club_b")
                }
            }
        }
        evidencia("A · 40 peticiones concurrentes vía pooler (default_pool_size=1): sin cruces")
    }

    /// Y no deja rastro: al cerrar la transacción, Postgres revierte el `SET LOCAL` antes
    /// de que PgBouncer devuelva la conexión de servidor a su pool.
    func testEstrategiaANoContaminaLaConexionDeServidor() async throws {
        viaPooler.tenantRoutingStrategy = .setLocalInTransaction
        _ = try await temporadas(club: slugA)

        let searchPath = try await searchPathDelPoolCompartido()
        evidencia("A · search_path de la conexión de servidor tras la petición: \(searchPath)")
        XCTAssertFalse(
            searchPath.contains(schemaA),
            "SET LOCAL contaminó la conexión de servidor del pooler: \(searchPath)"
        )
    }

    // MARK: - Estrategia B · pool dedicado (SET de sesión)

    /// **El resultado que cierra §6.4.** La estrategia B fija el `search_path` con un `SET`
    /// de **sesión**, que el driver emite una sola vez, al abrir la conexión
    /// (`PostgresConnectionSource`). Detrás de un pooler en modo transacción esa "sesión" es
    /// una ficción: la conexión de servidor se libera en cuanto termina la transacción
    /// implícita del propio `SET`, y el siguiente cliente la recibe tal cual —PgBouncer no
    /// ejecuta `DISCARD ALL` en este modo— y la pisa con su propio `SET`.
    ///
    /// Secuencia, toda secuencial:
    ///
    /// 1. Consulta de **A** → su pool abre conexión y emite `SET search_path TO club_a`.
    /// 2. Consulta de **B** → su pool abre conexión y emite `SET search_path TO club_b`
    ///    sobre **la misma** conexión de servidor. Acierta.
    /// 3. Consulta de **A** otra vez → su conexión de cliente ya estaba abierta, así que el
    ///    driver **no** vuelve a emitir el `SET`. La consulta corre contra una conexión de
    ///    servidor cuyo `search_path` es ahora `club_b`.
    ///
    /// Resultado: **el club A lee las filas del club B**. Tres consultas en fila, sin
    /// concurrencia y sin carreras.
    func testEstrategiaBCruzaDatosEntreClubesDetrasDelPooler() async throws {
        try await sembrarDirecto(labels: ["2023/24", "2024/25"], en: schemaA)
        try await sembrarDirecto(labels: ["2019/20"], en: schemaB)

        let a = pinned(.tenant(schemaA))
        let b = pinned(.tenant(schemaB))

        let a1 = try await etiquetas(on: a)   // 1 · abre y fija club_a
        let b1 = try await etiquetas(on: b)   // 2 · abre y fija club_b sobre la misma conexión
        let a2 = try await etiquetas(on: a)   // 3 · no reabre → no reemite el SET

        evidencia("B · vía pooler → A \(a1) · B \(b1) · A otra vez \(a2)")

        XCTAssertEqual(a1, ["2023/24", "2024/25"], "la primera consulta de A sí debería acertar")
        XCTAssertEqual(b1, ["2019/20"], "la consulta de B sí debería acertar")
        XCTAssertEqual(
            a2, ["2019/20"],
            """
            Esperábamos el cruce: el club A leyendo las filas del club B. Si esto falla, algo \
            cambió —PgBouncer limpia ahora la conexión entre clientes, el driver reemite el \
            SET, o default_pool_size dejó de ser 1— y hay que rehacer la conclusión de §6.4.
            """
        )
    }

    /// El mismo defecto visto desde el otro lado: el `SET` de sesión de un tenant queda en la
    /// conexión de servidor y contamina a quien la coja después — incluido el **plano de
    /// control**, que no había pedido ningún schema de club.
    func testEstrategiaBContaminaLaConexionDeServidor() async throws {
        viaPooler.tenantRoutingStrategy = .dedicatedPool
        _ = try await temporadas(club: slugA)

        let searchPath = try await searchPathDelPoolCompartido()
        evidencia("B · search_path de la conexión de servidor tras la petición: \(searchPath)")
        XCTAssertTrue(
            searchPath.contains(schemaA),
            "esperábamos la contaminación; ya no se produce y hay que revisar §6.4 (search_path: \(searchPath))"
        )
    }

    /// Y la consecuencia con la que hay que perder el sueño: el plano de control, que **no**
    /// fija ningún `search_path`, ejecuta DDL sin cualificar —`_fluent_migrations` es una
    /// tabla sin `space`, igual que las de dominio— y **aterriza dentro del schema de un
    /// club**. Leer mal se arregla reintentando; esto no.
    func testElPlanoDeControlAcabaEscribiendoDentroDeUnSchemaDeClub() async throws {
        let tenant = pinned(.tenant(schemaA))
        _ = try await etiquetas(on: tenant)  // deja club_a puesto en la conexión de servidor

        let control = pinned(.control)
        guard let sql = control as? any SQLDatabase else { throw TenancyError.notASQLDatabase }
        try await sql.raw("CREATE TABLE IF NOT EXISTS \(ident: Self.sonda) (id int)").run()

        let enElClub = try await existeTabla(Self.sonda, en: schemaA)
        let enPublic = try await existeTabla(Self.sonda, en: "public")
        evidencia("B · DDL del plano de control sin cualificar → en \(schemaA): \(enElClub) · en public: \(enPublic)")

        XCTAssertTrue(enElClub, "esperábamos que el DDL del plano de control cayera en el schema del club")
        XCTAssertFalse(enPublic, "no debería estar en public: ése es justamente el problema")
    }

    /// Corolario operativo: **`migrate-tenants` tampoco puede ir por el pooler**. Se apoya en
    /// el mismo `SET` de sesión.
    ///
    /// Este test no provoca el fallo —hacerlo determinista exigiría orquestar una carrera de
    /// DDL, y un DDL a destiempo deja la BD sucia—; comprueba el **mecanismo** del que
    /// dependería: que el `search_path` que el migrador da por puesto deja de estarlo en
    /// cuanto otro cliente toca la conexión.
    func testMigrarPorElPoolerNoEsSeguro() async throws {
        let migrador = pinned(.tenant(schemaA))
        guard let sql = migrador as? any SQLDatabase else { throw TenancyError.notASQLDatabase }

        let alAbrir = try await showSearchPath(on: sql)

        // Otro cliente cualquiera —aquí el plano de control— usa la conexión de servidor.
        _ = try await searchPathDelPoolCompartido(fijandoA: "public")

        // Y ahora el migrador, sin haber hecho nada, ya no está donde creía estar.
        let despues = try await showSearchPath(on: sql)

        evidencia("B · migrador vía pooler: al abrir \(alAbrir) → tras usarla otro cliente \(despues)")
        XCTAssertTrue(alAbrir.contains(schemaA))
        XCTAssertFalse(
            despues.contains(schemaA),
            "el search_path del migrador sobrevivió; si esto pasa siempre, revisar la conclusión"
        )
    }

    // MARK: - Utilidades

    /// Tabla de usar y tirar del test de DDL. Nombre fijo para poder limpiarla en `tearDown`
    /// caiga donde caiga — que es justamente lo que el test no sabe de antemano.
    private static let sonda = "sonda_plano_de_control"

    private func evidencia(_ mensaje: String) {
        print("· EVIDENCIA · \(mensaje)")
    }

    /// Base de datos **fijada a un solo event loop**, igual que `pinnedDatabase()` en
    /// `TenancyTests` y por la misma razón: con `maxConnectionsPerEventLoop: 1` eso significa
    /// **una** conexión de cliente por pool, y con `default_pool_size = 1` en PgBouncer, una
    /// conexión de servidor para todos. Es la única forma de que estos tests sean deterministas.
    ///
    /// Sin fijarlo, `app.db(id)` reparte entre event loops: cada uno abre su propia conexión
    /// con su propio `SET search_path`, y entonces que la fuga aparezca o no depende de en qué
    /// event loop caiga la petición. Eso no es un test, es una moneda al aire — y es, de paso,
    /// una razón más para no querer la estrategia B: su fallo no es reproducible.
    private func pinned(_ id: DatabaseID) -> any Database {
        if case let string = id.string, string.hasPrefix("tenant:") {
            _ = viaPooler.tenantPools.databaseID(for: String(string.dropFirst("tenant:".count)))
        }
        return viaPooler.databases.database(
            id,
            logger: viaPooler.logger,
            on: viaPooler.eventLoopGroup.next()
        )!
    }

    private func etiquetas(on db: any Database) async throws -> [String] {
        try await SeasonRecord.query(on: db).sort(\.$label).all().map(\.label)
    }

    private func existeTabla(_ table: String, en schema: String) async throws -> Bool {
        struct Row: Decodable { let present: Bool }
        guard let sql = direct.db(.control) as? any SQLDatabase else { throw TenancyError.notASQLDatabase }
        let row = try await sql.raw(
            """
            SELECT EXISTS (
                SELECT 1 FROM information_schema.tables
                WHERE table_schema = \(bind: schema) AND table_name = \(bind: table)
            ) AS present
            """
        ).first(decoding: Row.self)
        return row?.present ?? false
    }

    private static func poolerReachable() -> Bool {
        let config = SpikeConfig.viaPooler()
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        do {
            let channel = try ClientBootstrap(group: group)
                .connectTimeout(.seconds(2))
                .connect(host: config.hostname, port: config.port)
                .wait()
            try? channel.close().wait()
            return true
        } catch {
            return false
        }
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
        try await viaPooler.test(.POST, "seasons", headers: headers, body: ByteBuffer(data: body)) { res async in
            XCTAssertEqual(res.status, .created, "\(res.body.string)")
        }
    }

    private func temporadas(club: String) async throws -> [SeasonDTO] {
        var result: [SeasonDTO] = []
        try await viaPooler.test(.GET, "seasons", headers: cabeceras(club: club)) { res async throws in
            XCTAssertEqual(res.status, .ok, "\(res.body.string)")
            result = try res.content.decode([SeasonDTO].self)
        }
        return result
    }

    /// `SHOW search_path` pedido al pool del **plano de control** a través del pooler: no
    /// fija ningún schema, así que refleja el estado en que quedó la conexión de servidor.
    /// - Parameter fijandoA: si se indica, además deja ese `search_path` puesto, para poder
    ///   comprobar el efecto sobre otro cliente.
    @discardableResult
    private func searchPathDelPoolCompartido(fijandoA schema: String? = nil) async throws -> String {
        guard let sql = viaPooler.db(.control) as? any SQLDatabase else { throw TenancyError.notASQLDatabase }
        if let schema {
            try await sql.raw("SET search_path TO \(ident: schema)").run()
        }
        return try await showSearchPath(on: sql)
    }

    private func sembrarDirecto(labels: [String], en schema: String) async throws {
        try await TenantRouting.withSearchPath(schema, on: direct.db(.control)) { db in
            for (i, label) in labels.enumerated() {
                try await SeasonRecord(label: label, federationSeasonID: 500 + i).create(on: db)
            }
        }
    }

    private func limpiar(on app: Application) async throws {
        guard let sql = app.db(.control) as? any SQLDatabase else { throw TenancyError.notASQLDatabase }
        for schema in [schemaA, schemaB] {
            try await sql.raw("DROP SCHEMA IF EXISTS \(ident: schema) CASCADE").run()
        }
        for table in ["tenants", "_fluent_migrations", "seasons", Self.sonda] {
            try await sql.raw("DROP TABLE IF EXISTS public.\(ident: table) CASCADE").run()
        }
    }
}

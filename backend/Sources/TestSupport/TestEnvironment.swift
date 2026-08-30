public import App
public import Application
import Domain
public import HTTPAdapter
import Fluent
import FluentPostgresDriver
import Persistence
import SQLKit
import Tenancy
public import Vapor

/// Andamiaje compartido por los tests de integración (niveles 3 y 4, §8.1).
///
/// **No es código de producción**: no entra en ningún `product` del paquete y
/// solo lo consumen los *targets* de test.
///
/// # Por qué existe una base de datos aparte
///
/// Los tests y el trabajo manual **compartían la base `tfm`**, y el plano de
/// control (`public.tenants`) es una sola tabla para todos. Con eso, un test que
/// use el *slug* `madrid` —perfectamente plausible como club real— borra al
/// terminar el registro del club `madrid` que tuvieras dado de alta a mano: los
/// datos sobreviven en su *schema*, pero el club deja de ser alcanzable, porque
/// la fila que lo enruta ya no está.
///
/// Aislar por prefijo de *slug* no arregla eso: solo hace la colisión menos
/// probable, y una colisión improbable que corrompe datos es peor que una
/// frecuente, porque aparece el día menos oportuno. Así que **los tests corren
/// contra `tfm_test`** y no comparten con `tfm` ni el plano de control.
public enum TestEnvironment {
    public static let databaseName = "tfm_test"

    /// Prepara la base de test: la **crea si no existe** y le aplica la
    /// migración del **plano de control**. Las dos cosas, una sola vez.
    ///
    /// Se hace en código y no en un *script* de arranque del contenedor porque
    /// esos solo corren con el volumen **vacío**: quien ya tuviera datos no los
    /// vería nunca ejecutarse, y el fallo aparecería justo en la máquina de
    /// quien lleva tiempo trabajando.
    ///
    /// **Dos protecciones contra la misma carrera**, porque `swift-testing`
    /// ejecuta las suites en paralelo y todas llaman aquí a la vez:
    ///
    /// 1. Se hace **una vez por proceso** (el actor de abajo). Es lo que evita
    ///    la carrera en el caso normal.
    /// 2. Y aun así se tolera el duplicado, porque el paso 1 no protege de
    ///    **otro proceso** —dos `swift test` a la vez, o CI en paralelo—.
    ///
    /// Sin las dos, la batería falla **la primera vez** contra un Postgres
    /// nuevo y pasa a la segunda: el peor modo de fallo posible, porque invita
    /// a reintentar en vez de a mirar.
    ///
    /// # Y por qué el `autoMigrate` está aquí y no en `withApp`
    ///
    /// Porque la carrera de verdad estaba ahí, no en el `CREATE DATABASE`:
    ///
    /// ```
    /// sqlState: 23505
    /// detail: Key (typname, typnamespace)=(_fluent_migrations, 2200) already exists
    /// ```
    ///
    /// Dos suites llamando a `autoMigrate()` a la vez contra una base recién
    /// creada intentan crear **la misma** `public._fluent_migrations`. Migrar el
    /// plano de control es trabajo de arranque —se hace una vez, no una por
    /// `Application`—, así que su sitio es éste.
    public static func bootstrap() async throws {
        // Con `REQUIRE_DB`/`CI` las suites **no** se omiten, así que si la BD no
        // está el fallo llega aquí. Se dice en una línea en vez de dejar que
        // aflore un `PSQLError` que hay que descifrar: en CI nadie tiene el
        // contexto delante.
        if DatabaseAvailability.isForced, !DatabaseAvailability.isProbeSuccessful {
            throw TestSetupError(underlying: DatabaseAvailability.forcedFailureReason)
        }
        try await DatabaseBootstrap.shared.once {
            let base = DatabaseConfig.fromEnvironment()
            let app = try await Application.make(.testing)
            do {
                app.databases.use(.postgres(configuration: base.sqlConfiguration()), as: .control)
                guard let sql = app.db(.control) as? any SQLDatabase else { return }

                let existing = try await sql.raw(
                    "SELECT 1 AS present FROM pg_database WHERE datname = \(bind: databaseName)"
                ).first()
                var created = false
                if existing == nil {
                    do {
                        // `CREATE DATABASE` no admite ir dentro de una transacción.
                        try await sql.raw("CREATE DATABASE \(ident: databaseName)").run()
                    } catch {
                        // Otro proceso se nos adelantó entre el SELECT y el CREATE.
                        // Que exista es exactamente lo que queríamos.
                        let now = try await sql.raw(
                            "SELECT 1 AS present FROM pg_database WHERE datname = \(bind: databaseName)"
                        ).first()
                        if now == nil { throw error }
                    }
                    created = true
                }
                _ = created
            } catch {
                try? await app.asyncShutdown()
                throw TestSetupError(underlying: String(reflecting: error))
            }
            try await app.asyncShutdown()

            // Ya con la base creada: migrar el plano de control contra ELLA y
            // dejar pizarra limpia.
            let migrator = try await Application.make(.testing)
            do {
                try await configure(migrator, config: config)
                try await migrator.autoMigrate()
                try await dropLeftovers(on: migrator)
                if keepsTestData {
                    // Por `print` y no por el logger: con el nivel por defecto
                    // un aviso de log no se vería, y éste tiene que verse
                    // siempre — es lo que explica por qué la base no queda
                    // vacía al terminar.
                    print("⚠︎ KEEP_TEST_DATA=1 · los schemas de test NO se borrarán al terminar.")
                    print("  Míralos en la base `\(databaseName)`; la siguiente pasada los barre.")
                }
            } catch {
                try? await migrator.asyncShutdown()
                throw TestSetupError(underlying: String(reflecting: error))
            }
            try await migrator.asyncShutdown()
        }
    }

    /// Coordenadas de la base de test: las del entorno, con otra base.
    public static var config: DatabaseConfig {
        var config = DatabaseConfig.fromEnvironment()
        config.database = databaseName
        return config
    }

    /// Presta una `Application` **y espera a su cierre**.
    ///
    /// Un `defer { Task { … } }` no espera a nada: la `Application` puede
    /// destruirse con el cierre en vuelo, y Vapor tiene un `fatalError` para
    /// eso. Se manifiesta como una señal 5 que se lleva la batería entera por
    /// delante, no como un test rojo.
    public static func withApp(
        // F6: los tests de nivel 4 del disparador necesitan un `FederationClient`
        // falseado, o la batería saldría a la red de la federación.
        federationClients: (any FederationClientProvider)? = nil,
        background: (any BackgroundWork)? = nil,
        clock: (any Clock)? = nil,
        _ body: (Application) async throws -> Void
    ) async throws {
        try await bootstrap()
        let app = try await Application.make(.testing)
        applyLogLevel(to: app)
        do {
            try await configure(
                app, config: config,
                federationClients: federationClients ?? CatalogFederationClientProvider(),
                background: background ?? DetachedBackgroundWork(),
                clock: clock ?? SystemClock())
            // Sin `autoMigrate()`: el plano de control ya lo migró `bootstrap()`,
            // una sola vez. Llamarlo aquí es lo que producía la carrera.
            try await body(app)
        } catch {
            try? await app.asyncShutdown()
            throw TestSetupError(underlying: String(reflecting: error))
        }
        try await app.asyncShutdown()
    }

    /// Prefijos de *schema* que usan los targets de test. Todo lo que empiece
    /// por uno de ellos es desechable por definición.
    static let disposableSchemaPrefixes = ["e2e_", "test_"]

    /// Barre lo que dejara una pasada anterior que no terminó bien.
    ///
    /// Cada test limpia lo suyo al empezar y al terminar, y con eso basta
    /// **casi** siempre: un `#expect` que falla no interrumpe el test, así que
    /// su limpieza final se ejecuta igual. Lo que sí lo interrumpe es un error
    /// **lanzado**, y ahí el *schema* sobrevive.
    ///
    /// Se barre **al arrancar** y no con un `defer` por test, por el mismo
    /// motivo que el `SET LOCAL` de §6.2: la corrección no debe depender del
    /// camino de error ni de que cada test nuevo se acuerde. Y garantiza algo
    /// más fuerte que limpiar al salir — **pizarra limpia al entrar**, sin
    /// confiar en que la pasada anterior terminase bien.
    ///
    /// Solo toca `tfm_test`. La base de trabajo (`tfm`) no se abre siquiera.
    static func dropLeftovers(on app: Application) async throws {
        guard let sql = app.db(.control) as? any SQLDatabase else { return }

        let condition = disposableSchemaPrefixes
            .map { "nspname LIKE '\($0)%'" }
            .joined(separator: " OR ")
        let rows = try await sql.raw(
            "SELECT nspname FROM pg_namespace WHERE \(unsafeRaw: condition)"
        ).all()
        let leftovers = rows.compactMap { try? $0.decode(column: "nspname", as: String.self) }

        for schema in leftovers {
            try await sql.raw("DROP SCHEMA IF EXISTS \(ident: schema) CASCADE").run()
        }
        // Y sus registros en el plano de control, que si no quedan apuntando a
        // *schemas* que ya no existen.
        if !leftovers.isEmpty {
            try await TenantRecord.query(on: app.db(.control))
                .filter(\.$schemaName ~~ leftovers)
                .delete()
        }
    }

    /// Hace que `LOG_LEVEL` funcione también en los tests.
    ///
    /// En el servidor lo aplica `LoggingSystem.bootstrap(from:)`, que lee la
    /// variable y el flag `--log`. Los tests no pasan por ahí —montan la
    /// `Application` directamente—, así que sin esto `LOG_LEVEL=debug swift test`
    /// no hacía nada y el SQL de Fluent quedaba invisible justo donde más se
    /// quiere ver: en los tests de integración.
    ///
    /// Se fija el nivel **del logger de la app**, no por `LoggingSystem.bootstrap`,
    /// porque ése solo puede llamarse **una vez por proceso** y aquí se montan
    /// muchas `Application` seguidas.
    static func applyLogLevel(to app: Application) {
        guard let raw = ProcessInfo.processInfo.environment["LOG_LEVEL"],
              let level = Logger.Level(rawValue: raw.lowercased())
        else { return }
        app.logger.logLevel = level
    }

    /// Da de alta un club por **el mismo camino que producción** (§6.3), para que
    /// los tests ejerciten el código real y no una siembra paralela.
    @discardableResult
    public static func provisionClub(
        _ slug: String,
        federation: FederationCode,
        schemaPrefix: String,
        on app: Application
    ) async throws -> String {
        let schema = "\(schemaPrefix)\(slug)"
        try await ProvisionTenantCommand.provision(
            slug: slug, schemaName: schema,
            name: "Club \(slug)", shortName: slug.uppercased(),
            federation: federation, on: app
        )
        return schema
    }

    /// `KEEP_TEST_DATA=1` conserva lo que dejan los tests, para poder abrirlo en
    /// TablePlus después de un fallo.
    ///
    /// Es la alternativa barata al *breakpoint*: cuando un test de integración
    /// falla, lo que quieres ver es **en qué estado quedó la base**, y eso se
    /// mira mejor con una consulta que parando el depurador en mitad de una
    /// transacción — que además, al estar parado, no la ha confirmado todavía.
    ///
    /// **El barrido de arranque sigue corriendo** aunque esté puesta, y es
    /// deliberado: cada pasada empieza limpia y te deja **su** estado, no una
    /// acumulación de todas las anteriores. Si no, a la tercera ejecución ya no
    /// sabrías de qué pasada era cada *schema*.
    public static var keepsTestData: Bool {
        ProcessInfo.processInfo.environment["KEEP_TEST_DATA"] == "1"
    }

    public static func dropClubs(
        _ slugs: [String], schemaPrefix: String, on app: Application
    ) async throws {
        guard !keepsTestData else { return }
        guard let sql = app.db(.control) as? any SQLDatabase else { return }
        for slug in slugs {
            try await sql.raw("DROP SCHEMA IF EXISTS \(ident: "\(schemaPrefix)\(slug)") CASCADE").run()
            try await TenantRecord.query(on: app.db(.control)).filter(\.$slug == slug).delete()
        }
    }
}

/// Ejecuta el arranque **una sola vez por proceso**, aunque lo pidan a la vez
/// todas las suites que corren en paralelo.
///
/// # Por qué guarda una `Task` y no un `Bool`
///
/// Un actor **no** es una sección crítica: se suspende en cada `await` y admite
/// reentrada. La versión ingenua —`guard !completed`, `await work()`,
/// `completed = true`— no protege de nada, porque el segundo llamante entra
/// durante la suspensión del primero, ve `completed == false` y ejecuta el
/// trabajo **también**. Es exactamente lo que hacía fallar la batería la primera
/// vez contra un Postgres nuevo: dos suites creando la misma base a la vez.
///
/// Guardando la `Task` **antes** de esperarla, el segundo llamante encuentra la
/// del primero y se queda esperando a su resultado en vez de duplicar el
/// trabajo. Es el patrón correcto para "hazlo una sola vez" en async.
private actor DatabaseBootstrap {
    static let shared = DatabaseBootstrap()
    private var bootstrap: Task<Void, any Error>?

    func once(_ work: @Sendable @escaping () async throws -> Void) async throws {
        if let bootstrap { return try await bootstrap.value }
        let task = Task { try await work() }
        bootstrap = task
        do {
            try await task.value
        } catch {
            // Un arranque fallido no se cachea: el siguiente lo reintenta.
            bootstrap = nil
            throw error
        }
    }
}

/// Envuelve un fallo de arranque con su mensaje **legible**.
///
/// `PSQLError` esconde su `description` a propósito, para no filtrar datos
/// sensibles en los logs de producción. En un test eso deja *"Generic
/// description…"* y nada más, que es inservible para depurar — y el dato
/// sensible aquí es de mentira. Así que se reexpone con `String(reflecting:)`.
public struct TestSetupError: Error, CustomStringConvertible {
    public let underlying: String
    public var description: String { "fallo montando el entorno de test: \(underlying)" }
}

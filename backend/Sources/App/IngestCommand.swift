import Application
import Domain
import Fluent
import Persistence
import Tenancy
public import Vapor

/// `ingest` — **el adaptador primario de la ingesta** (§2.3-b).
///
/// Es un `AsyncCommand` y no un Controller, y ésa es la razón por la que el
/// módulo de ingesta ha podido construirse entero sin tocar §7: un job de
/// sistema no tiene usuario, ni JWT, ni petición HTTP que autenticar.
///
/// # Lo que este comando **no** decide
///
/// Ni qué competiciones entran, ni qué pasa cuando una falla. Eso es
/// `IngestClubCalendars`, por la misma razón por la que `D-83` puso las
/// fronteras transaccionales en el caso de uso: son reglas que se pueden hacer
/// mal desde fuera. Aquí solo queda lo que sí es del adaptador — **quién es el
/// tenant**, qué se imprime y con qué código se sale.
///
/// # La cadencia no está aquí dentro
///
/// No hay temporizador (`D-87`). La cadencia de §5.6 la pone quien dispara el
/// comando —un cron, una *scheduled machine*—, y lo que el comando trae es la
/// **guarda de antirrebote** (`--min-interval-hours`) para que un disparo de más
/// no repita trabajo. El tope semanal sigue siendo un requisito del calendario
/// de disparos, no algo que este código pueda hacer cumplir por su cuenta.
public struct IngestCommand: AsyncCommand {
    public struct Signature: CommandSignature {
        @Option(name: "tenant", short: "t",
                help: "Sincronizar solo estos clubes (slugs separados por coma).")
        public var tenant: String?

        @Option(name: "season", help: "UUID de la temporada. Por defecto, la vigente (§3.2).")
        public var season: String?

        @Option(name: "competition", short: "c",
                help: "UUIDs de competiciones concretas (separados por coma).")
        public var competition: String?

        @Option(name: "min-interval-hours",
                help: "No repetir lo sincronizado con éxito hace menos de estas horas. Por defecto: \(IngestCommand.defaultMinIntervalHours).")
        public var minIntervalHours: Int?

        @Flag(name: "force", help: "Ignora el intervalo mínimo y sincroniza todo lo que toque.")
        public var force: Bool

        public init() {}
    }

    /// Seis horas: **muy por debajo** del intervalo más corto de la cadencia
    /// (§5.6 pide lunes y fin de semana), para que el antirrebote solo atrape lo
    /// que quiere atrapar —un reintento del cron, dos disparadores solapados— y
    /// nunca una pasada legítima.
    public static let defaultMinIntervalHours = 6

    public var help: String {
        "Sincroniza el calendario de la federación de cada club (§2.3-b)."
    }

    public init() {}

    public func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application

        let scope = try Self.scope(
            season: signature.season,
            competition: signature.competition,
            minIntervalHours: signature.minIntervalHours,
            force: signature.force)

        let outcomes = try await Self.ingest(
            on: app, scope: scope,
            tenantSlugs: signature.tenant.map { Self.list($0) },
            federationClients: CatalogFederationClientProvider())

        guard !outcomes.isEmpty else {
            context.console.warning("No hay tenants registrados en public.tenants.")
            return
        }

        for outcome in outcomes {
            switch outcome.summary {
            case .skipped(let reason):
                context.console.warning("→ \(outcome.slug): \(reason)")
            case .done(let line):
                context.console.info("→ \(outcome.slug): \(line)")
            case .failed(let line):
                context.console.error("→ \(outcome.slug): \(line)")
            }
        }

        // **El código de salida es la única señal que ve el cron.** Un recorrido
        // que continúa tras un fallo (`D-86`) tiene que decirlo por aquí, o la
        // resiliencia se convierte en silencio.
        let failed = Self.incomplete(outcomes)
        guard failed.isEmpty else { throw IngestionIncomplete(slugs: failed) }
        context.console.success("\(outcomes.count) club(es) sincronizados.")
    }

    /// El recorrido por tenant, **sin consola**, para que lo puedan ejecutar los
    /// tests de nivel 3 y —cuando llegue— un disparador que no sea la CLI.
    public static func ingest(
        on app: Application,
        scope: IngestionScope,
        tenantSlugs: [String]? = nil,
        federationClients: any FederationClientProvider,
        clock: any Clock = SystemClock(),
        ids: any UUIDProvider = SystemUUIDProvider()
    ) async throws -> [TenantIngestion] {
        let tenants = try await Self.tenants(on: app, slugs: tenantSlugs)

        let useCase = IngestClubCalendars(
            unitOfWork: FluentTenantUnitOfWork(controlDatabase: app.db(.control)),
            federationClients: federationClients,
            clock: clock,
            ids: ids)

        var outcomes: [TenantIngestion] = []
        for slug in tenants {
            do {
                let report = try await useCase.execute(
                    scope: scope,
                    actor: ActorContext(clubSlug: try Slug(slug), isSystem: true))
                outcomes.append(TenantIngestion(slug: slug, report: report, error: nil))
            } catch {
                // **Un club que revienta no detiene a los demás** (`D-86`), igual
                // que una competición dentro de un club. Aquí caen los fallos que
                // no son de una pasada concreta: un *schema* sin aprovisionar, o
                // una federación sin adaptador (`D-17`).
                outcomes.append(
                    TenantIngestion(
                        slug: slug, report: nil,
                        error: diagnosticText(for: error)))
            }
        }
        return outcomes
    }

    /// Los clubes que **no** terminaron bien, y con ellos el código de salida.
    ///
    /// Está separado de `run` porque es la regla —no el `print`— y probarla no
    /// puede exigir montar una consola. Cuenta las **dos** formas de no terminar
    /// bien, que es lo que la comprobación de mutación encontró que faltaba: el
    /// club que ni llegó a recorrerse (`error`) y el que se recorrió con alguna
    /// competición fallida (`hasFailures`). Contar solo la primera dejaría al
    /// cron viendo verde con media temporada sin sincronizar.
    public static func incomplete(_ outcomes: [TenantIngestion]) -> [String] {
        outcomes.filter { !$0.succeeded }.map(\.slug)
    }

    /// **Qué clubes va a recorrer**, sin recorrer ninguno.
    ///
    /// Es el `public.tenants` de §4.7, el mismo que recorren las migraciones, y
    /// por el mismo motivo: con varios clubes en el proyecto, *"el club"* no
    /// existe. Sin filtro, **todos**.
    ///
    /// Está separado de `ingest` porque *"sin filtro recorre todos"* es una regla
    /// que hay que poder afirmar **sin efectos**: probarla ejecutando la ingesta
    /// significaría escribir en el *schema* de cada club que hubiera en la base,
    /// que en la batería son los de las demás suites corriendo en paralelo.
    public static func tenants(on app: Application, slugs: [String]?) async throws -> [String] {
        let query = TenantRecord.query(on: app.db(.control))
        if let slugs { query.filter(\.$slug ~~ slugs) }
        return try await query.sort(\.$slug).all().map(\.slug)
    }

    /// Traduce **lo que teclea el operador** al ámbito del caso de uso.
    ///
    /// Está fuera de `run` y recibe valores sueltos en vez de la `Signature`
    /// entera por dos motivos, y el segundo es el que importa: una `Signature`
    /// de ConsoleKit no se puede construir a mano en un test, y **esta
    /// traducción no la miraba nadie**. Lo dijo la comprobación de mutación —
    /// romper el `--competition` para que solo cogiera el primer valor no tumbaba
    /// ningún test, porque los del recorrido reciben el ámbito ya construido.
    ///
    /// Aquí viven las dos precedencias que el `--help` no puede explicar:
    /// **`--force` gana sobre `--min-interval-hours`**, y una lista vacía de
    /// competiciones es lo mismo que no pasar ninguna.
    static func scope(
        season: String?, competition: String?, minIntervalHours: Int?, force: Bool
    ) throws -> IngestionScope {
        let competitionIDs = try competition.map { raw in
            try Self.list(raw).map { CompetitionID(raw: try Self.uuid($0, field: "--competition")) }
        }
        return IngestionScope(
            seasonID: try season.map { SeasonID(raw: try Self.uuid($0, field: "--season")) },
            competitionIDs: (competitionIDs?.isEmpty ?? true) ? nil : competitionIDs,
            minInterval: force
                ? nil
                : Double(minIntervalHours ?? Self.defaultMinIntervalHours) * 3600)
    }

    /// Una opción con varios valores separados por coma.
    ///
    /// ConsoleKit no tiene `@Option` repetible, así que la lista viaja en una
    /// cadena. Se usa en `--tenant` y en `--competition` con la **misma** forma:
    /// una asimetría entre las dos sería justo lo que nadie recuerda al escribir
    /// el comando con prisa.
    static func list(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func uuid(_ raw: String, field: String) throws -> UUID {
        guard let value = UUID(uuidString: raw) else {
            throw IngestionArgumentError(field: field, value: raw)
        }
        return value
    }
}

/// Cómo le fue a un club dentro del recorrido.
///
/// Es la misma forma que `ClubIngestionReport` un piso más arriba: se continúa
/// con el siguiente y se apunta lo que pasó con éste (`D-86`).
public struct TenantIngestion: Sendable {
    public let slug: String
    public let report: ClubIngestionReport?
    public let error: String?

    public init(slug: String, report: ClubIngestionReport?, error: String?) {
        self.slug = slug
        self.report = report
        self.error = error
    }

    public var succeeded: Bool {
        error == nil && !(report?.hasFailures ?? false)
    }

    public enum Summary: Sendable {
        case done(String)
        case failed(String)
        case skipped(String)
    }

    public var summary: Summary {
        if let error { return .failed(error) }
        guard let report else { return .skipped("sin recorrido") }
        let synced = report.entries.count { if case .synced = $0.outcome { true } else { false } }
        let failed = report.entries.count - synced
        let line = "\(synced) competición(es) sincronizada(s), \(failed) con fallo"
        return failed == 0 ? .done(line) : .failed(line)
    }
}

/// El recorrido terminó, pero no entero. Lanzarlo es lo que hace que el proceso
/// salga con código distinto de cero.
public struct IngestionIncomplete: Error, CustomStringConvertible {
    public let slugs: [String]
    public var description: String {
        "La ingesta no terminó bien en: \(slugs.joined(separator: ", ")). "
            + "El motivo de cada pasada está en su fila de `ingestion_runs` (D-85)."
    }
}

public struct IngestionArgumentError: Error, CustomStringConvertible {
    public let field: String
    public let value: String
    public var description: String { "\(field) no es un UUID válido: '\(value)'." }
}

import Foundation
import MutateCore

// ─────────────────────────────────────────────────────────────────────────────
// mutate <catálogo.json> [--package-path <dir>] [--only M1,M2] [--dry-run]
//
// Por cada mutación: aplica → compila → prueba → restaura. Antes de la primera
// y después de la última, la batería sin mutar tiene que estar en verde.
//
// El progreso va a stderr y el resumen a stdout **y** a un fichero: en F5 el
// progreso y el resumen salían juntos por stdout, la invocación lo pasaba por
// `tail`, y el resumen se perdió.
// ─────────────────────────────────────────────────────────────────────────────

struct Options {
    var catalog: URL
    var packagePath: URL
    var only: Set<String>?
    var dryRun = false

    static let usage = """
        uso: mutate <catálogo.json> [--package-path <dir>] [--only M1,M2] [--dry-run]

          --package-path  el paquete que se muta y se prueba (por omisión, el directorio actual)
          --only          solo esas mutaciones, por id
          --dry-run       comprueba que cada cambio casa una sola vez, sin compilar ni probar
        """

    static func parse(_ arguments: [String]) throws -> Options {
        var catalog: String?
        var packagePath = FileManager.default.currentDirectoryPath
        var only: Set<String>?
        var dryRun = false
        var rest = arguments[...]
        while let argument = rest.popFirst() {
            switch argument {
            case "--package-path":
                guard let value = rest.popFirst() else { throw Failure(Self.usage) }
                packagePath = value
            case "--only":
                guard let value = rest.popFirst() else { throw Failure(Self.usage) }
                only = Set(value.split(separator: ",").map(String.init))
            case "--dry-run":
                dryRun = true
            case "-h", "--help":
                throw Failure(Self.usage)
            default:
                guard catalog == nil, !argument.hasPrefix("-") else { throw Failure(Self.usage) }
                catalog = argument
            }
        }
        guard let catalog else { throw Failure(Self.usage) }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Options(
            catalog: URL(fileURLWithPath: catalog, relativeTo: cwd).standardizedFileURL,
            packagePath: URL(fileURLWithPath: packagePath, relativeTo: cwd).standardizedFileURL,
            only: only, dryRun: dryRun)
    }
}

struct Failure: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

func progress(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

// MARK: - El fichero en vuelo

/// La copia del fichero original mientras está mutado, **en disco**.
///
/// Si el proceso muere con un fichero mutado —Ctrl-C, un cuelgue—, la
/// siguiente ejecución lo encuentra y lo restaura antes de nada. Y Ctrl-C, que
/// es lo normal, restaura en el acto (ver `installInterruptHandler`).
struct InFlight: Codable {
    var path: String
    var original: String

    static func journal(in package: URL) -> URL {
        package.appendingPathComponent(".mutate-in-flight.json")
    }

    /// Restaura lo que hubiera en vuelo. Devuelve la ruta restaurada, si había.
    @discardableResult
    static func recover(in package: URL) throws -> String? {
        let journal = journal(in: package)
        guard let data = try? Data(contentsOf: journal) else { return nil }
        let inFlight = try JSONDecoder().decode(InFlight.self, from: data)
        try inFlight.original.write(toFile: inFlight.path, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: journal)
        return inFlight.path
    }
}

/// El candado del paquete: un fichero con el pid de la pasada que lo tiene
/// (ver `lockDecision`). Se crea con `O_EXCL`, así que dos que arrancan a la
/// vez no lo toman los dos.
enum RunLock {
    static func url(in package: URL) -> URL {
        package.appendingPathComponent(".mutate.lock")
    }

    static func acquire(in package: URL) throws {
        let path = url(in: package).path
        let ownPID = getpid()
        for _ in 0..<2 {
            let fd = open(path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
            if fd >= 0 {
                _ = "\(ownPID)".withCString { write(fd, $0, strlen($0)) }
                close(fd)
                return
            }
            let holder = (try? String(contentsOfFile: path, encoding: .utf8))
                .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            let decision = lockDecision(holder: holder, ownPID: ownPID) { pid in
                kill(pid, 0) == 0 || errno == EPERM
            }
            switch decision {
            case .refuse(let pid):
                throw Failure("otra pasada de mutate (pid \(pid)) está en curso sobre "
                              + "\(package.path); no se toca nada hasta que acabe")
            case .acquire, .takeOverStale:
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        throw Failure("no se pudo tomar el candado \(path)")
    }

    static func release(in package: URL) {
        try? FileManager.default.removeItem(at: url(in: package))
    }
}

func installInterruptHandler(package: URL) -> [any DispatchSourceSignal] {
    [SIGINT, SIGTERM].map { number in
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler {
            if let path = try? InFlight.recover(in: package) {
                progress("\ninterrumpido: \(path) restaurado")
            }
            RunLock.release(in: package)
            exit(130)
        }
        source.resume()
        return source
    }
}

// MARK: - Procesos

/// Ejecuta `arguments` en `directory` con toda la salida a `log`, y devuelve el
/// código de salida (`128 + señal` si murió por una señal).
func run(_ arguments: [String], in directory: URL, log: URL,
         environment extra: [String: String] = [:]) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.currentDirectoryURL = directory
    process.environment = ProcessInfo.processInfo.environment.merging(extra) { $1 }
    FileManager.default.createFile(atPath: log.path, contents: nil)
    let handle = try FileHandle(forWritingTo: log)
    defer { try? handle.close() }
    process.standardOutput = handle
    process.standardError = handle
    try process.run()
    process.waitUntilExit()
    return process.terminationReason == .exit
        ? process.terminationStatus
        : 128 + process.terminationStatus
}

struct Harness {
    var package: URL
    var reports: URL

    func build(log name: String) throws -> Bool {
        try run(["swift", "build", "--build-tests"], in: package,
                log: reports.appendingPathComponent("\(name).build.log")) == 0
    }

    /// `REQUIRE_DB=1` siempre (`A-7`·H-07): sin la variable, con Docker parado,
    /// los tests de base se **omiten** y la salida es idéntica a la de un verde.
    func test(filter: String?, log name: String) throws -> TestRunVerdict {
        let log = reports.appendingPathComponent("\(name).test.log")
        let xml = reports.appendingPathComponent("\(name).xml")
        var arguments = ["swift", "test", "--skip-build", "--xunit-output", xml.path]
        if let filter { arguments += ["--filter", filter] }
        let code = try run(arguments, in: package, log: log, environment: ["REQUIRE_DB": "1"])

        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        let candidates = [xml, reports.appendingPathComponent("\(name)-swift-testing.xml")]
        let xunit = candidates.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
        return verdict(of: TestRunEvidence(exitCode: code, output: output, xunitReports: xunit))
    }

    /// La batería sin mutar, por cada filtro distinto del catálogo.
    func baseline(filters: [String?], label: String) throws -> Bool {
        guard try build(log: "\(label)") else {
            progress("✘ \(label): el paquete sin mutar no compila")
            return false
        }
        for (index, filter) in filters.enumerated() {
            let verdict = try test(filter: filter, log: "\(label)-\(index + 1)")
            let name = filter ?? "toda la batería"
            guard verdict == .passed else {
                progress("✘ \(label): \(name) sin mutar no está en verde: \(verdict)")
                return false
            }
            progress("✔ \(label): \(name) en verde")
        }
        return true
    }
}

// MARK: - Main

func main() throws -> Int32 {
    let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
    let package = options.packagePath
    guard FileManager.default.fileExists(atPath: package.appendingPathComponent("Package.swift").path)
    else { throw Failure("no hay Package.swift en \(package.path)") }

    // El candado **antes** que el diario: solo es de una ejecución muerta si
    // nadie vivo tiene el candado. También en `--dry-run`, que lee los ficheros
    // y con una pasada en curso los leería mutados.
    try RunLock.acquire(in: package)
    defer { RunLock.release(in: package) }

    if let path = try InFlight.recover(in: package) {
        progress("⚠️ una ejecución anterior dejó \(path) mutado: restaurado")
    }

    let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: options.catalog))
    try catalog.validate()
    var mutations = catalog.mutations
    if let only = options.only {
        let unknown = only.subtracting(mutations.map(\.id))
        guard unknown.isEmpty else { throw Failure("no están en el catálogo: \(unknown.sorted())") }
        mutations = mutations.filter { only.contains($0.id) }
    }

    func source(of mutation: Mutation) -> (URL, String?) {
        let url = package.appendingPathComponent(mutation.file)
        return (url, try? String(contentsOf: url, encoding: .utf8))
    }

    func apply(_ mutation: Mutation, to original: String?) -> Result<String, NotApplied> {
        guard let original else { return .failure(.fileNotFound(mutation.file)) }
        return applying(mutation.edits, to: original)
    }

    if options.dryRun {
        var failures = 0
        for mutation in mutations {
            switch apply(mutation, to: source(of: mutation).1) {
            case .success: print("✔ \(mutation.id) casa")
            case .failure(let reason): failures += 1; print("✘ \(mutation.id): \(reason)")
            }
        }
        return failures == 0 ? 0 : 2
    }

    let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
        .replacingOccurrences(of: ":", with: "")
    let reports = package
        .appendingPathComponent(".build/mutation-reports")
        .appendingPathComponent("\(options.catalog.deletingPathExtension().lastPathComponent)-\(stamp)")
    try FileManager.default.createDirectory(at: reports, withIntermediateDirectories: true)
    let harness = Harness(package: package, reports: reports)
    let interruptHandlers = installInterruptHandler(package: package)
    defer { interruptHandlers.forEach { $0.cancel() } }

    var filters: [String?] = []
    for filter in mutations.map({ catalog.filter(for: $0) }) where !filters.contains(filter) {
        filters.append(filter)
    }

    progress("— \(catalog.title): \(mutations.count) mutaciones; informes en \(reports.path)")
    guard try harness.baseline(filters: filters, label: "baseline-start") else {
        throw Failure("sin un verde de partida no hay nada que medir")
    }

    var results: [MutationResult] = []
    for mutation in mutations {
        let (url, original) = source(of: mutation)
        let filter = catalog.filter(for: mutation)
        let applied = apply(mutation, to: original)
        var compiled = false
        var test: TestRunVerdict?

        if case .success(let mutated) = applied, let original {
            let journal = InFlight.journal(in: package)
            try JSONEncoder().encode(InFlight(path: url.path, original: original)).write(to: journal)
            try mutated.write(to: url, atomically: true, encoding: .utf8)
            defer {
                // Restaurar siempre, y comprobar que lo restaurado es lo original.
                try? original.write(to: url, atomically: true, encoding: .utf8)
                if (try? String(contentsOf: url, encoding: .utf8)) == original {
                    try? FileManager.default.removeItem(at: journal)
                } else {
                    progress("✘ \(mutation.id): no se pudo restaurar \(mutation.file); queda en \(journal.path)")
                }
            }
            progress("· \(mutation.id): compilando…")
            compiled = try harness.build(log: mutation.id)
            if compiled {
                progress("· \(mutation.id): probando \(filter ?? "toda la batería")…")
                test = try harness.test(filter: filter, log: mutation.id)
            }
        }

        let result = MutationResult(
            mutation: mutation, filter: filter,
            outcome: outcome(applied: applied, compiled: compiled, test: test,
                             declaredEquivalent: mutation.equivalent != nil))
        progress("\(result.outcome.label) · \(mutation.id) · \(mutation.description)")
        results.append(result)
    }

    guard try InFlight.recover(in: package) == nil else {
        throw Failure("quedó un fichero mutado tras la pasada; restaurado, pero la pasada no vale")
    }
    let closing = try harness.baseline(filters: filters, label: "baseline-end")
    let summary = Summary(title: catalog.title, results: results, closingBaselinePassed: closing)
    let markdown = summary.markdown()
    let report = reports.appendingPathComponent("summary.md")
    try markdown.write(to: report, atomically: true, encoding: .utf8)
    print(markdown)
    print("Informe: \(report.path)")
    return summary.exitCode
}

do {
    exit(try main())
} catch {
    progress("mutate: \(error)")
    exit(3)
}

import App
public import Foundation
import Synchronization

/// ¿Hay un Postgres escuchando donde los tests lo esperan?
///
/// Los niveles 3 y 4 de la pirámide (§8.1) necesitan Postgres real —nunca
/// SQLite, porque *schema*-por-tenant es exclusivo de Postgres ([D-01])—, y eso
/// significa que el bucle rápido **no puede quedar bloqueado** porque el
/// contenedor esté parado.
///
/// # Cómo se comporta
///
/// | Situación | Qué pasa |
/// |---|---|
/// | Postgres arriba | Todo corre |
/// | Postgres abajo, en local | Las suites de BD **se saltan**, diciendo qué comando falta |
/// | Postgres abajo, con `CI` o `REQUIRE_DB` | **Falla**, y fuerte |
///
/// La guarda de CI es lo que hace que saltar sea aceptable: **verde no puede
/// significar "no probado"** donde nadie va a mirar la lista de omitidos. En
/// local sí se puede: el desarrollador ve el motivo y decide.
public enum DatabaseAvailability {
    /// Fuerza la ejecución aunque no haya BD, para que falle con su error real.
    /// `CI` la exportan GitHub Actions, GitLab y la mayoría por defecto.
    static let forcingVariables = ["CI", "REQUIRE_DB"]

    private static let cached = Mutex<Bool?>(nil)

    /// Se consulta una vez por proceso: once suites preguntando lo mismo no
    /// deben abrir once conexiones, y un resultado que cambie a mitad de la
    /// batería sería peor que cualquiera de los dos valores.
    public static var isReachable: Bool {
        cached.withLock { value in
            if let value { return value }
            let result = isForced || probe()
            value = result
            return result
        }
    }

    /// La sonda **sin** la guarda: `isReachable` devuelve `true` en cuanto hay
    /// `REQUIRE_DB`, que es lo que se quiere para no omitir. Pero para dar un
    /// mensaje decente hace falta saber si además **hay** base de datos.
    public static var isProbeSuccessful: Bool { probe() }

    /// Mensaje cuando la ejecución está forzada y **no** hay base de datos.
    ///
    /// Concatenado y no un literal multilínea: el `\` de continuación de Swift
    /// **conserva la sangría** de la línea siguiente, así que partir el texto
    /// así mete tabuladores dentro del mensaje. Se ve al leerlo, no al escribirlo.
    public static var forcedFailureReason: String {
        let config = DatabaseConfig.fromEnvironment()
        let variable = forcingVariables.first {
            ProcessInfo.processInfo.environment[$0] != nil
        } ?? "REQUIRE_DB"
        return "\(variable) está definida, así que los tests de base de datos no se omiten"
            + " — pero Postgres no responde en \(config.hostname):\(config.port)."
            + " Levántalo con `docker compose up -d db` o revisa DB_HOST/DB_PORT."
    }

    static var isForced: Bool {
        forcingVariables.contains { ProcessInfo.processInfo.environment[$0] != nil }
    }

    /// Texto que ve quien se encuentra la suite omitida. Dice **el comando**,
    /// no solo el síntoma: un `connection refused` con un puerto no le sirve a
    /// nadie que no conozca ya el `docker-compose.yml`.
    public static var skipReason: String {
        let config = DatabaseConfig.fromEnvironment()
        return """
            Postgres no responde en \(config.hostname):\(config.port), así que los tests que \
            necesitan base de datos se omiten. Levántalo con `docker compose up -d db` desde \
            `backend/`. Para que fallen en vez de omitirse —lo que hace CI— define REQUIRE_DB=1.
            """
    }

    /// Sonda TCP a pelo, **síncrona**.
    ///
    /// Síncrona porque `.enabled(if:)` de `swift-testing` evalúa una condición
    /// que no es `async`, y a pelo para no arrastrar el driver de Postgres solo
    /// para preguntar si el puerto está abierto: aquí no interesa si la base
    /// existe ni si las credenciales valen —de eso ya se encarga el arranque—,
    /// solo si hay alguien escuchando.
    private static func probe(timeout: TimeInterval = 1.5) -> Bool {
        let config = DatabaseConfig.fromEnvironment()
        var hints = addrinfo(
            ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
            ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(config.hostname, String(config.port), &hints, &info) == 0,
              let resolved = info
        else { return false }
        defer { freeaddrinfo(info) }

        var candidate: UnsafeMutablePointer<addrinfo>? = resolved
        while let entry = candidate {
            let handle = socket(entry.pointee.ai_family, entry.pointee.ai_socktype, entry.pointee.ai_protocol)
            if handle >= 0 {
                var window = timeval(
                    tv_sec: Int(timeout),
                    tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
                setsockopt(handle, SOL_SOCKET, SO_SNDTIMEO, &window, socklen_t(MemoryLayout<timeval>.size))
                let connected = connect(handle, entry.pointee.ai_addr, entry.pointee.ai_addrlen) == 0
                close(handle)
                if connected { return true }
            }
            candidate = entry.pointee.ai_next
        }
        return false
    }
}

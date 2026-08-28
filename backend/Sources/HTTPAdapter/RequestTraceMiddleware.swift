import Foundation
public import Vapor

/// Vuelca a la consola la petición y la respuesta **completas**, cuerpos
/// incluidos.
///
/// Vapor, ni siquiera en `debug`, registra los cuerpos: da la línea de petición
/// y las cabeceras. Para estudiar qué cruza la frontera —que es lo que hace un
/// adaptador primario (§2.2)— hace falta ver el `PATCH` que entra y el
/// *Problem* que sale.
///
/// # Doble candado, y el segundo no es paranoia
///
/// Se activa **solo** si `HTTP_TRACE=1` **y** el entorno no es producción. El
/// motivo del segundo candado es concreto: los cuerpos de esta API llevan
/// **nombres, fechas de nacimiento y fotos de menores** (§3.2). Un volcado
/// completo en un log de producción es una fuga de datos personales con
/// implicaciones de RGPD, no un log verboso.
///
/// Es la misma lista **blanca** que la cabecera `X-Club` (§6.1): un entorno
/// nuevo nace con la traza **apagada**.
public struct RequestTraceMiddleware: AsyncMiddleware {
    private let isEnabled: Bool

    public init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    /// - Parameter environment: se exige explícitamente para que activar la
    ///   traza sea imposible sin pasar por aquí.
    public static func isEnabled(in environment: Environment) -> Bool {
        guard Environment.get("HTTP_TRACE") == "1" else { return false }
        return environment == .development || environment == .testing
    }

    public func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard isEnabled else { return try await next.respond(to: request) }

        // Se recoge el cuerpo **antes** de seguir. Vapor lo deja bufferizado, así
        // que el handler lo vuelve a leer sin enterarse.
        let body = try await request.body.collect(max: 1 << 20).get()
        log(request: request, body: body.map { String(buffer: $0) }, to: request.logger)

        let response = try await next.respond(to: request)

        // **El cuerpo de la respuesta hay que recogerlo, no leerlo.** El
        // transporte generado la devuelve como *flujo*, así que `body.string` es
        // `nil` y la traza salía sin cuerpo — justo lo que se quería ver. Se
        // recoge y se **repone** bufferizada, para que el cliente la reciba igual.
        if response.body.buffer == nil {
            let collected = try await response.body.collect(on: request.eventLoop).get()
            response.body = collected.map { Response.Body(buffer: $0) } ?? .empty
        }
        log(response: response, to: request.logger)
        return response
    }

    private func log(request: Request, body: String?, to logger: Logger) {
        var lines = ["┌─ → \(request.method.rawValue) \(request.url.path)"]

        // Los parámetros de consulta, aparte de la ruta: son los `page`,
        // `pageSize`, `sort` e `includeArchived` de §5.3, y el *handler* les
        // aplica sus valores por defecto a mano porque el generador ignora
        // `default` (D-65). Verlos aquí es ver qué recibió de verdad.
        if let query = request.url.query, !query.isEmpty {
            for pair in query.split(separator: "&") {
                lines.append("│  ?\(pair)")
            }
        }
        for (name, value) in request.headers where name.lowercased() != "content-length" {
            lines.append("│  \(name): \(value)")
        }
        if let body, !body.isEmpty {
            lines.append("│")
            lines.append(contentsOf: indent(pretty(body)))
        }
        emit(lines, to: logger)
    }

    private func log(response: Response, to logger: Logger) {
        var lines = ["├─ ← \(response.status.code) \(response.status.reasonPhrase)"]
        if let contentType = response.headers.contentType {
            lines.append("│  Content-Type: \(contentType.serialize())")
        }
        let body = response.body.string ?? ""
        if !body.isEmpty {
            lines.append("│")
            lines.append(contentsOf: indent(pretty(body)))
        }
        lines.append("└─")
        emit(lines, to: logger)
    }

    /// Sale por el **logger**, no por `print`.
    ///
    /// `print` escribe en `stdout`, y `stdout` redirigido a un fichero se
    /// bufferiza **por bloques**: la traza no aparecía hasta que el proceso
    /// moría. Con `swift run Run serve > log.txt` —que es justo como se estudia
    /// esto— el efecto era "el middleware no funciona".
    private func emit(_ lines: [String], to logger: Logger) {
        logger.notice("\n\(lines.joined(separator: "\n"))")
    }

    /// Reimprime el JSON con sangrado. Si no es JSON, lo deja tal cual: un
    /// cuerpo mal formado también hay que poder verlo.
    private func pretty(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(
                  withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: formatted, encoding: .utf8)
        else { return raw }
        return text
    }

    private func indent(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { "│  \($0)" }
    }
}

import App
import Vapor

/// Punto de entrada. Deliberadamente sin lógica: la raíz de composición es
/// `configure(_:)` en el target `App` (§2.2).
var environment = try Environment.detect()
try LoggingSystem.bootstrap(from: &environment)

let app = try await Application.make(environment)
do {
    try await configure(app)
    try await app.execute()
} catch {
    app.logger.report(error: error)
    try? await app.asyncShutdown()
    throw error
}
try await app.asyncShutdown()

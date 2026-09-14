import App
import Vapor

/// Punto de entrada. Deliberadamente sin lógica: la raíz de composición es
/// `configure(_:)` en el target `App` (§2.2).
var environment = try Environment.detect()
try LoggingSystem.bootstrap(from: &environment)

let app = try await Application.make(environment)

// **El arranque se reporta aquí; el comando, no** (`A-5`, H-39). Medido: Vapor
// ya reporta el error que sale de `execute()`, así que el
// `app.logger.report(error:)` que había alrededor de las dos llamadas lo
// imprimía **dos** veces. Lo que Vapor no cubre es lo que falle en
// `configure(_:)` —hoy, el registro de los *handlers* del contrato—, y eso sin
// reportar saldría con código 1 y en silencio, que es peor que duplicado. Por
// eso son dos ámbitos y no uno.
do {
    try await configure(app)
} catch {
    app.logger.report(error: error)
    try? await app.asyncShutdown()
    exit(1)
}

do {
    try await app.execute()
} catch {
    try? await app.asyncShutdown()
    // **`exit(1)` y no `throw`** (`A-5`, H-39). Un `throw` desde el nivel
    // superior de un ejecutable de Swift **no** es un fallo ordenado: es
    // `Fatal error: Error raised at top level`, o sea `SIGTRAP` y código de
    // salida **133**, con el error volcado una vez más encima del que ya
    // reportó el logger. En un log de despliegue un 133 es la firma de un
    // programa que se ha caído, así que no se distingue *"la guarda me paró,
    // como estaba previsto"* —el `--revert` sin `--yes`— de un *bug*.
    //
    // Esto vale para **los cinco comandos**, y el que más lo necesita es
    // `ingest`: su código de salida es *"la única señal que ve el cron"*
    // (`D-86`), y la daba lanzando `IngestionIncomplete` — correcto en el
    // *qué* (distinto de cero) y confuso en el *cómo*. Aquí se separan las dos
    // cosas: **el comando decide si falló lanzando; el punto de entrada decide
    // cómo se cuenta.**
    exit(1)
}
try await app.asyncShutdown()

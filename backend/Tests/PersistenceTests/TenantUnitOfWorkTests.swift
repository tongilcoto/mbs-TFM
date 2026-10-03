import Application
import Domain
import Foundation
import Testing
import Vapor

@testable import App
import TestSupport
@testable import Persistence

/// Nivel 3 (§8.1): **el acceso de tenant tiene una sola conexión, a propósito**
/// (`D-100`, A-12·H-77).
///
/// No es un test de rendimiento: es el **testigo de una garantía**. Con una sola
/// conexión, dos ámbitos de tenant nunca están abiertos a la vez, y eso es lo que
/// hoy impide tres carreras de `INSERT` en el enganche —temporada, competición e
/// inscripción— que con dos conexiones darían un `23505` en un 500. Lo que se
/// vigila es que nadie lo cambie **sin darse cuenta**: subir
/// `maxConnectionsPerEventLoop`, o volver a pedir `db(.control)` en cada sitio en
/// vez de compartir `app.tenantUnitOfWork`, pone este test en rojo.
///
/// Si se cambia **a propósito** —la opción B de H-77—, este test se cambia con
/// ello, y antes hay que haber hecho seguras esas tres carreras.
@Suite("TenantUnitOfWork · D-100 · una sola conexión, a propósito",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct TenantUnitOfWorkTests {

    static let prefix = "test_uow_"

    /// Marca de paso, compartida entre las dos tareas.
    actor Flags {
        var firstOpened = false
        var secondEntered = false
        private var release: CheckedContinuation<Void, Never>?
        private var released = false

        func openFirst() { firstOpened = true }
        func enterSecond() { secondEntered = true }
        func holdFirst() async {
            if released { return }
            await withCheckedContinuation { release = $0 }
        }
        func letFirstGo() {
            released = true
            release?.resume()
            release = nil
        }
    }

    @Test("un segundo ámbito de tenant no se abre mientras el primero vive (D-100)")
    func aSecondScopeWaitsForTheFirst() async throws {
        try await TestEnvironment.withApp { app in
            let slug = "uow-one"
            try await TestEnvironment.dropClubs([slug], schemaPrefix: Self.prefix, on: app)
            try await TestEnvironment.provisionClub(
                slug, federation: .rffm, schemaPrefix: Self.prefix, on: app)
            let actor = ActorContext(clubSlug: try Slug(slug), isSystem: true)
            let flags = Flags()

            // **El mismo acceso que usan el servidor y los comandos**, pedido dos
            // veces: si alguien lo convirtiera en uno nuevo por llamada, las dos
            // tareas tendrían cada una el suyo.
            let first = Task {
                try await app.tenantUnitOfWork.withRepositories(actor: actor) { repositories in
                    _ = try await repositories.clubs.current()
                    await flags.openFirst()
                    await flags.holdFirst()
                }
            }
            while !(await flags.firstOpened) { try await Task.sleep(for: .milliseconds(5)) }

            let second = Task {
                try await app.tenantUnitOfWork.withRepositories(actor: actor) { repositories in
                    _ = try await repositories.clubs.current()
                    await flags.enterSecond()
                }
            }

            // Margen de sobra: abrir una conexión nueva cuesta ~10 ms.
            try await Task.sleep(for: .milliseconds(400))
            let enteredWhileFirstLived = await flags.secondEntered

            await flags.letFirstGo()
            try await first.value
            try await second.value

            #expect(enteredWhileFirstLived == false,
                    "dos ámbitos de tenant abiertos a la vez: el acceso ya no es de una conexión (D-100)")
            #expect(await flags.secondEntered, "el segundo tiene que entrar en cuanto el primero cierra")

            try await TestEnvironment.dropClubs([slug], schemaPrefix: Self.prefix, on: app)
        }
    }
}

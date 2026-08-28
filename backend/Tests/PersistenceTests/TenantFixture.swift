import Application
import Domain
import Fluent
import Foundation
import SQLKit
import Vapor
@testable import App
@testable import Persistence
@testable import Tenancy

/// Un club aprovisionado sobre el que trabajar en los tests de nivel 3.
///
/// Existe para hacer **visible la frontera transaccional** de §6.2, que es lo que
/// distingue a este backend de uno de una sola base: cada `scope` abre una
/// transacción con su `SET LOCAL search_path`, exactamente como una petición.
struct TenantFixture: Sendable {
    let app: Application
    let slug: String
    let schema: String

    /// Abre **un** ámbito de tenant y entrega dentro los repositorios.
    ///
    /// Dos consecuencias a tener presentes al escribir un test, y que no son
    /// limitaciones del andamiaje sino el comportamiento correcto de §6.2:
    ///
    /// 1. **Lo escrito aquí dentro no lo ve `raw` hasta que el ámbito cierra**,
    ///    porque son conexiones distintas y la transacción sigue abierta.
    /// 2. **Una violación de restricción aborta la transacción entera**
    ///    (`sqlState 25P02`): lo que venga después en el mismo ámbito falla con
    ///    *"current transaction is aborted"* y no con el error que se quería
    ///    probar — pasaría el `#expect(throws:)` por el motivo equivocado. Cada
    ///    intento que deba reventar va en **su propio** `scope`.
    ///
    /// Escribir los tests así los obliga a parecerse a lo que hace el sistema de
    /// verdad: una petición, un ámbito.
    func scope<T: Sendable>(
        _ work: @escaping @Sendable (any Repositories) async throws -> T
    ) async throws -> T {
        try await FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            .withRepositories(actor: .init(clubSlug: try Slug(slug)), work)
    }

    /// SQL crudo **fuera** de cualquier ámbito, contra el *pool* del plano de
    /// control. Es la vía para mirar lo que el ORM no deja ver —el valor real de
    /// una columna, un `CHECK`— y para atacar la tabla como lo haría un *script*.
    ///
    /// Las tablas hay que cualificarlas con `schema`: aquí no hay `search_path`.
    var raw: any SQLDatabase { app.db(.control) as! any SQLDatabase }
}

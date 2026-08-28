public import Fluent
import SQLKit

/// El **punto único** por el que pasa todo acceso a datos de tenant (§6.2).
///
/// El resto del código no sabe qué hay debajo, y por eso esta elección es
/// reversible.
public enum TenantRouting {
    /// `SET LOCAL search_path` **dentro de la transacción de la petición**.
    ///
    /// **`LOCAL` no es un adorno.** Postgres revierte el ajuste al cerrar la
    /// transacción, así que la conexión vuelve limpia al *pool* **sin código de
    /// reseteo**. El spike ejecutó como control negativo la versión sin `LOCAL`
    /// y la fuga apareció:
    ///
    /// ```
    /// · EVIDENCIA · A′ · search_path tras devolver la conexión (pid 7495): club_a
    /// · EVIDENCIA · A  · search_path tras devolver la conexión (pid 7484): "$user", public
    /// ```
    ///
    /// Lo que importa de esa diferencia: **la corrección deja de depender de que
    /// alguien se acuerde de limpiar en el camino de error**.
    ///
    /// Es además la **única estrategia compatible con el *pooling* en modo
    /// transacción**, que es como Supabase sirve las conexiones (§6.4). La
    /// alternativa —un *pool* por tenant con `searchPath` en la configuración—
    /// cruza filas entre clubes detrás de un *pooler*, medido contra PgBouncer.
    ///
    /// - Note: Todo acceso de tenant queda dentro de una transacción. Para
    ///   escrituras ya lo estaría; para lecturas es una transacción de solo
    ///   lectura, barata, y a cambio da consistencia de instantánea.
    public static func withSearchPath<T: Sendable>(
        _ schema: String,
        on database: any Database,
        _ work: @escaping @Sendable (any Database) async throws -> T
    ) async throws -> T {
        try await database.transaction { transaction in
            guard let sql = transaction as? any SQLDatabase else {
                throw TenancyError.notASQLDatabase
            }
            try await sql.raw("SET LOCAL search_path TO \(ident: schema)").run()
            return try await work(transaction)
        }
    }
}

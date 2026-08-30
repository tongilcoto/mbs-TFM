import Fluent
import SQLKit

extension Database {
    /// Añade un `CHECK` con SQL crudo.
    ///
    /// Fluent no expresa `CHECK`, así que la vía es `SQLKit` (§4.6, Anexo D.1 del
    /// ADR). Aparecerá también en los `CHECK` **entre columnas** que el modelo ya
    /// tiene previstos: `Appearance` (D-42), `Card` (D-45) y los tres de `Goal`.
    func checkConstraint(table: String, name: String, expression: String) async throws {
        guard let sql = self as? any SQLDatabase else { return }
        try await sql.raw(
            "ALTER TABLE \(ident: table) ADD CONSTRAINT \(ident: name) CHECK (\(unsafeRaw: expression))"
        ).run()
    }
}

extension Database {
    /// Crea un índice **no único** con SQL crudo.
    ///
    /// Fluent expresa `.unique(on:)` en el constructor de esquema, pero no un
    /// índice normal sobre columnas ya creadas, así que la vía vuelve a ser
    /// `SQLKit` (§4.6). Lo usarán también los índices explícitos que el modelo
    /// tiene previstos: `Goal.scoring_team_id`, `Goal.conceding_team_id` y los
    /// compuestos de `Match` (§3.5).
    ///
    /// `IF NOT EXISTS` para que la migración sea reejecutable sobre un *schema*
    /// que ya la tuviera a medias.
    func index(table: String, name: String, columns: [String]) async throws {
        guard let sql = self as? any SQLDatabase else { return }
        let columnList = columns.map { "\"\($0)\"" }.joined(separator: ", ")
        try await sql.raw(
            "CREATE INDEX IF NOT EXISTS \(ident: name) ON \(ident: table) (\(unsafeRaw: columnList))"
        ).run()
    }
}

extension Database {
    /// Crea un índice único con `NULLS NOT DISTINCT` (Postgres 15+), en SQL crudo.
    ///
    /// **Fluent no lo expresa**, y la diferencia no es cosmética (§3.5): en
    /// Postgres los `NULL` **no comparan iguales**, así que un `UNIQUE` normal
    /// sobre la clave de `Team` —donde `opponent_club_id` es nulo en **todos**
    /// los equipos propios y `letter` lo es en los clubes sin filial— dejaría
    /// crear dos "Infantil A" propios sin rechistar. `NULLS NOT DISTINCT` hace
    /// que dos nulos cuenten como el mismo valor, que es lo que aquí se quiere.
    ///
    /// **Y es justo el criterio opuesto al de las claves de federación** en la
    /// misma tabla (§3.5): allí el comportamiento por defecto es el bueno —muchas
    /// filas sin código, ningún código repetido— y por eso esas van con
    /// `.unique(on:)` normal.
    ///
    /// `IF NOT EXISTS` por lo mismo que `index(table:name:columns:)`.
    func uniqueIndexNullsNotDistinct(
        table: String, name: String, columns: [String]
    ) async throws {
        guard let sql = self as? any SQLDatabase else { return }
        let columnList = columns.map { "\"\($0)\"" }.joined(separator: ", ")
        try await sql.raw(
            """
            CREATE UNIQUE INDEX IF NOT EXISTS \(ident: name) ON \(ident: table) \
            (\(unsafeRaw: columnList)) NULLS NOT DISTINCT
            """
        ).run()
    }
}

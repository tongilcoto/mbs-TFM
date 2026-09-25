import Fluent
import SQLKit

// **Los tres ayudantes de aquí lanzan si la base no es SQL, y no es celo**
// (`A-5`, H-35). Empezaban por `guard … else { return }`, así que sobre una base
// que no conformara `SQLDatabase` la migración habría creado la tabla y se
// habría saltado **en silencio** los `CHECK`, los índices y el
// `NULLS NOT DISTINCT` — o sea la mitad de las invariantes que `D-28` decidió
// bajar al esquema. Un esquema al que le faltan los `CHECK` **no falla**: acepta
// datos que el Dominio rechaza, que es el reverso exacto del argumento de
// `D-02`. El `as?` gemelo de `ProvisionTenantCommand` ya lanzaba; ésta es la
// asimetría que se cierra.
//
// Hoy no es alcanzable —todo es Postgres— y por eso no tiene test propio:
// fabricar un doble de `Database` cuesta más que el arreglo (§3, regla 2 del
// plan de auditoría). Lo que sí está bajo test es **su consecuencia**: el
// inventario de `MigrationIntegrityTests` ancla los 10 `CHECK` y el
// `NULLS NOT DISTINCT`, así que un ayudante que deje de hacer su trabajo se ve.
extension Database {
    /// Añade un `CHECK` con SQL crudo.
    ///
    /// Fluent no expresa `CHECK`, así que la vía es `SQLKit` (§4.6, Anexo D.1 del
    /// ADR). Aparecerá también en los `CHECK` **entre columnas** que el modelo ya
    /// tiene previstos: `Appearance` (D-42), `Card` (D-45) y los tres de `Goal`.
    func checkConstraint(table: String, name: String, expression: String) async throws {
        guard let sql = self as? any SQLDatabase else {
            throw PersistenceError.schemaHelperNeedsSQL(helper: "checkConstraint", object: name)
        }
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
        guard let sql = self as? any SQLDatabase else {
            throw PersistenceError.schemaHelperNeedsSQL(helper: "index", object: name)
        }
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
        guard let sql = self as? any SQLDatabase else {
            throw PersistenceError.schemaHelperNeedsSQL(
                helper: "uniqueIndexNullsNotDistinct", object: name)
        }
        let columnList = columns.map { "\"\($0)\"" }.joined(separator: ", ")
        try await sql.raw(
            """
            CREATE UNIQUE INDEX IF NOT EXISTS \(ident: name) ON \(ident: table) \
            (\(unsafeRaw: columnList)) NULLS NOT DISTINCT
            """
        ).run()
    }
}

extension Database {
    /// **Rehace** un `CHECK` que ya existe: lo borra si está y lo vuelve a crear.
    ///
    /// # Por qué hace falta, y es una corrección de F8 a una frase que era falsa
    ///
    /// `D-02` dice que el `CHECK` de un enumerado **se deriva y no se teclea**, y
    /// `sqlValueList` lo cumple. De ahí se concluyó —y quedó escrito en
    /// `AddStandingsToIngestionRun`— que *"el caso que F8 añada lo hereda sin
    /// tocar SQL"*. **No lo hereda.**
    ///
    /// La derivación ocurre **una vez**, cuando la migración corre, y lo que queda
    /// en el *schema* es el texto que salió ese día. Medido contra la base de
    /// trabajo antes de escribir esto:
    ///
    /// ```
    /// club_atleti | chk_ingestion_runs_kind
    ///             | CHECK (kind = ANY (ARRAY['calendar'::text, 'standings'::text]))
    /// ```
    ///
    /// Un caso nuevo en el `enum` de Swift **no llega ahí jamás**, por la misma
    /// razón que `D-90`: `_fluent_migrations` guarda el **nombre** de la
    /// migración, no su contenido. Un alta limpia tendría los tres valores y un
    /// club vivo dos, y el club vivo rechazaría la pasada nueva con un `23514`
    /// que nadie relaciona con un `enum`.
    ///
    /// > **La lección, que es la de `D-90` un piso más abajo:** *derivado* no
    /// > significa *vivo*. Un valor derivado en tiempo de migración se congela con
    /// > ella; para que cambie hace falta una migración nueva que lo rehaga.
    ///
    /// # Por qué `DROP … IF EXISTS` y no un `ALTER … VALIDATE`
    ///
    /// Postgres no deja modificar la expresión de un `CHECK`: hay que tirarlo y
    /// ponerlo otra vez. El `IF EXISTS` hace la migración reejecutable y, sobre
    /// todo, la hace válida **en los dos caminos de §4.7** — un alta limpia llega
    /// aquí con el `CHECK` ya bueno (lo puso la migración anterior con el
    /// enumerado de hoy) y lo rehace idéntico; un club vivo llega con el viejo y
    /// lo sustituye. Un solo camino de código para los dos, que es lo que `A-5`
    /// midió que hace que los esquemas converjan byte a byte.
    func replaceCheckConstraint(table: String, name: String, expression: String) async throws {
        guard let sql = self as? any SQLDatabase else {
            throw PersistenceError.schemaHelperNeedsSQL(
                helper: "replaceCheckConstraint", object: name)
        }
        try await sql.raw(
            "ALTER TABLE \(ident: table) DROP CONSTRAINT IF EXISTS \(ident: name)"
        ).run()
        try await sql.raw(
            "ALTER TABLE \(ident: table) ADD CONSTRAINT \(ident: name) CHECK (\(unsafeRaw: expression))"
        ).run()
    }
}

// ── F10-bis · lo que hace falta para AFLOJAR una columna, no para crearla ────
//
// Los cuatro de aquí abajo existen porque [D-90] obliga a corregir con una
// migración **nueva**, y corregir hacia atrás no es lo mismo que crear: Fluent
// expresa bien el alta de una tabla y **nada** de lo que hay que deshacerle
// después a una columna que ya existe. Llevan la misma guarda que sus tres
// hermanos de arriba, y por el mismo motivo (`A-5`, H-35): un esquema al que le
// falta un `CHECK` no falla — acepta lo que el Dominio rechaza.
extension Database {
    /// `DROP NOT NULL`. Lo pide [D-96]: `finished_at` deja de ser obligatoria
    /// porque una pasada **aceptada** todavía no ha acabado.
    func dropNotNull(table: String, column: String) async throws {
        guard let sql = self as? any SQLDatabase else {
            throw PersistenceError.schemaHelperNeedsSQL(helper: "dropNotNull", object: column)
        }
        try await sql.raw(
            "ALTER TABLE \(ident: table) ALTER COLUMN \(ident: column) DROP NOT NULL"
        ).run()
    }

    /// `SET NOT NULL`, que es el camino de vuelta y **solo funciona si no queda
    /// ningún nulo**: quien lo llame tiene que haberlos resuelto antes.
    func setNotNull(table: String, column: String) async throws {
        guard let sql = self as? any SQLDatabase else {
            throw PersistenceError.schemaHelperNeedsSQL(helper: "setNotNull", object: column)
        }
        try await sql.raw(
            "ALTER TABLE \(ident: table) ALTER COLUMN \(ident: column) SET NOT NULL"
        ).run()
    }

    /// Tira un `CHECK` sin volver a ponerlo, que es lo que un `revert` necesita
    /// y `replaceCheckConstraint` no hace.
    func dropCheckConstraint(table: String, name: String) async throws {
        guard let sql = self as? any SQLDatabase else {
            throw PersistenceError.schemaHelperNeedsSQL(
                helper: "dropCheckConstraint", object: name)
        }
        try await sql.raw(
            "ALTER TABLE \(ident: table) DROP CONSTRAINT IF EXISTS \(ident: name)"
        ).run()
    }

    /// Tira un índice creado a mano. Los que nacen con una columna se van con
    /// ella (`deleteField`); éstos no tienen quien se los lleve.
    ///
    /// **Sin cualificar con el *schema***, igual que `index(table:name:columns:)`
    /// al crearlo: la migración corre con el `search_path` del tenant puesto
    /// (§6.2), así que el nombre resuelve donde tiene que resolver. Cualificarlo
    /// aquí y no allí sería pedirle al llamante un dato que el ámbito ya sabe.
    func dropIndex(name: String) async throws {
        guard let sql = self as? any SQLDatabase else {
            throw PersistenceError.schemaHelperNeedsSQL(helper: "dropIndex", object: name)
        }
        try await sql.raw("DROP INDEX IF EXISTS \(ident: name)").run()
    }
}

// ── F10 · `C-D.3` · lo que hace falta para atar DOS columnas a la vez ────────
//
// Fluent expresa `.references(…)` de **una** columna, y la coherencia que
// [D-61] manda bajar al esquema es de dos: *"esta competición es de esta
// temporada"*. Sin esto la alternativa sería una guarda en el caso de uso, que
// es exactamente lo que esa decisión rechaza — la otra puerta a la tabla es el
// `POST /v1/teams` del backoffice y tendría que acordarse de escribirla otra
// vez.
extension Database {
    /// `UNIQUE` como **restricción**, no como índice suelto.
    ///
    /// La diferencia importa aquí y solo aquí: Postgres exige que las columnas
    /// referenciadas por una FK sean las de una restricción `UNIQUE` o `PRIMARY
    /// KEY`, así que `competitions(id, season_id)` necesita la restricción para
    /// que la FK compuesta de abajo pueda apuntarle. Para lo demás, el índice de
    /// `uniqueIndexNullsNotDistinct` es lo que se quiere.
    ///
    /// **Sin `IF NOT EXISTS`**, que `ADD CONSTRAINT` no acepta — igual que
    /// `checkConstraint`, y por el mismo motivo: una migración corre una vez por
    /// *schema* ([D-90]).
    func uniqueConstraint(table: String, name: String, columns: [String]) async throws {
        guard let sql = self as? any SQLDatabase else {
            throw PersistenceError.schemaHelperNeedsSQL(helper: "uniqueConstraint", object: name)
        }
        let columnList = columns.map { "\"\($0)\"" }.joined(separator: ", ")
        try await sql.raw(
            """
            ALTER TABLE \(ident: table) ADD CONSTRAINT \(ident: name) \
            UNIQUE (\(unsafeRaw: columnList))
            """
        ).run()
    }

    /// FK **compuesta**, con su `ON DELETE`.
    ///
    /// # La sutileza que la hace utilizable con una columna anulable
    ///
    /// El comportamiento por defecto de Postgres es `MATCH SIMPLE`: si **alguna**
    /// de las columnas de la FK es nula, la restricción **no se comprueba**. Eso
    /// no es un agujero aquí, es justo lo que `TeamRegistration` necesita — la
    /// fila de junio lleva `competition_id` nulo ([D-68]) y no tiene competición
    /// que validar. Con `MATCH FULL` esa fila no cabría.
    func compositeForeignKey(
        table: String, name: String, columns: [String],
        references: String, referencedColumns: [String], onDelete: String
    ) async throws {
        guard let sql = self as? any SQLDatabase else {
            throw PersistenceError.schemaHelperNeedsSQL(helper: "compositeForeignKey", object: name)
        }
        let from = columns.map { "\"\($0)\"" }.joined(separator: ", ")
        let to = referencedColumns.map { "\"\($0)\"" }.joined(separator: ", ")
        try await sql.raw(
            """
            ALTER TABLE \(ident: table) ADD CONSTRAINT \(ident: name) \
            FOREIGN KEY (\(unsafeRaw: from)) \
            REFERENCES \(ident: references) (\(unsafeRaw: to)) \
            ON DELETE \(unsafeRaw: onDelete)
            """
        ).run()
    }
}

extension Database {
    /// Tira una restricción cualquiera —`UNIQUE`, FK— sin volver a ponerla. Es
    /// lo que un `revert` necesita de `uniqueConstraint` y de
    /// `compositeForeignKey`, que crean lo que Fluent no sabe crear y por tanto
    /// tampoco sabe deshacer.
    func dropConstraint(table: String, name: String) async throws {
        guard let sql = self as? any SQLDatabase else {
            throw PersistenceError.schemaHelperNeedsSQL(helper: "dropConstraint", object: name)
        }
        try await sql.raw(
            "ALTER TABLE \(ident: table) DROP CONSTRAINT IF EXISTS \(ident: name)"
        ).run()
    }
}

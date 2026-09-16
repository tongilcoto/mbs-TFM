import Domain
public import Fluent
import FluentSQL
import Foundation

/// Modelo de persistencia del ranking de goleadores (§4.4, §4.5).
///
/// **Es un modelo de lectura, no un agregado** (§4.2): lo escribe el módulo de
/// ingesta por *upsert* y nadie más. No tiene repositorio de dominio ni `POST`.
public final class LeagueScorerRecord: Model, @unchecked Sendable {
    public static let schema = "league_scorers"

    @ID(key: .id) public var id: UUID?

    /// **La única FK de la tabla**, y ahí está media entidad. `StandingRow` tiene
    /// tres —competición, jornada y equipo— porque es un *snapshot* de una
    /// jornada y de un equipo nuestro; ésta no se liga a `Team` (`D-09`) ni tiene
    /// jornada (§3.2), así que la competición es todo su ámbito.
    @Parent(key: "competition_id") public var competition: CompetitionRecord

    /// La clave del *upsert* (`D-93`).
    @Field(key: "federation_player_id") public var federationPlayerID: String

    @Field(key: "full_name") public var fullName: String
    @Field(key: "team_label") public var teamLabel: String
    @Field(key: "goals") public var goals: Int

    /// Puesto del proveedor. Hoy **siempre nulo**: ninguna de las dos
    /// federaciones lo publica ([Anexo RFFM §F.13], §F.19, [Anexo FCF §C.10.7]).
    @OptionalField(key: "rank") public var rank: Int?

    /// **La marca del *upsert***, y la única columna del modelo cuya función es
    /// **borrar** (`D-94`).
    ///
    /// Anulable en el esquema aunque la pasada siempre la escriba: el `NOT NULL`
    /// haría imposible representar una fila a medio escribir, que no es un estado
    /// que exista, pero también ataría la tabla a que **toda** fila venga de una
    /// pasada — y la retirada se apoya en comparar esta marca, no en confiar en
    /// que esté.
    @OptionalField(key: "synced_at") public var syncedAt: Date?

    @Timestamp(key: "created_at", on: .create) public var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) public var updatedAt: Date?

    public init() {}
}

/// **La entidad 23 del modelo.**
///
/// # Dónde va en el orden de FK de §4.6
///
/// El orden canónico la pone detrás de `Goal`, pero `Player`, `Absence`,
/// `Appearance`, `Card` y `Goal` **no existen todavía**, así que su sitio efectivo
/// es detrás de `StandingRow`. No es una excepción al criterio de `D-90` —*"cada
/// fase añade las suyas al final de la lista **que le toque por FK**"*—: su única
/// dependencia es `Competition`, que lleva aplicada desde F1.
///
/// # Se añade, no se edita nada (`D-90`)
///
/// Ni una línea de las once que ya existían. Intercalarla **no** cambia el esquema
/// resultante —está medido (`A-5`/H-38, `MigrationIntegrityTests`)—: lo que ordena
/// la lista es la dependencia de FK, para que un alta limpia pueda aplicarlas de
/// una pasada; sobre una base ya migrada Fluent aplica solo las que faltan.
public struct CreateLeagueScorer: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(LeagueScorerRecord.schema)
            .id()
            // `CASCADE` como todo el subárbol de `Season` (`D-73`): purgar una
            // temporada se lleva sus rankings, que sin la competición no
            // significan nada.
            //
            // **Y aquí no hay el matiz de `StandingRow`**, que deja el equipo sin
            // cascada porque su fila también es de los otros quince. Ésta no
            // referencia ningún equipo: `team_label` es texto (`D-09`, `D-32`).
            .field("competition_id", .uuid, .required,
                   .references(CompetitionRecord.schema, "id", onDelete: .cascade))
            .field("federation_player_id", .string, .required)
            .field("full_name", .string, .required)
            .field("team_label", .string, .required)
            .field("goals", .int, .required)
            .field("rank", .int)
            .field("synced_at", .datetime)
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            // **La unicidad de `D-93`, que §3.5 no tenía**: era la única entidad
            // de la salida de la ingesta sin clave de negocio declarada, y
            // mientras el ranking no se ingería no se notaba.
            //
            // Va con `.unique(on:)` normal y **no** con `NULLS NOT DISTINCT`: las
            // dos columnas son `NOT NULL`, así que no hay nulos que comparar y no
            // aplica la trampa de §3.5. Y no es parcial: esta tabla no lleva
            // `deleted_at` —lo que sobra se **borra de verdad** (`D-94`)—.
            .unique(on: "competition_id", "federation_player_id")
            .create()

        // El índice de la consulta de la pantalla: el ranking de una competición,
        // en su orden. El `UNIQUE` de arriba ya empieza por `competition_id`, así
        // que el filtro está cubierto; esto ordena, que es lo que el `UNIQUE` no
        // hace — y el orden **es** el dato (§5.1, `D-49`).
        try await database.index(
            table: LeagueScorerRecord.schema, name: "idx_league_scorers_ranking",
            columns: ["competition_id", "goals"])

        // El índice de la **retirada** (`D-94`). Es la única consulta del modelo
        // que borra por comparación de fecha, y sin él sería un recorrido de la
        // tabla entera en cada pasada.
        try await database.index(
            table: LeagueScorerRecord.schema, name: "idx_league_scorers_synced",
            columns: ["competition_id", "synced_at"])

        // Las dos guardas del Dominio bajadas al esquema (`D-28`), que el *spec*
        // declara (`minimum: 0`, `minimum: 1`) y el generador no hace cumplir
        // (`D-65`).
        try await database.checkConstraint(
            table: LeagueScorerRecord.schema, name: "chk_league_scorers_goals",
            expression: "goals >= 0")
        try await database.checkConstraint(
            table: LeagueScorerRecord.schema, name: "chk_league_scorers_rank",
            expression: "rank IS NULL OR rank >= 1")

        // **Y la clave de `D-93` no puede ser la cadena vacía.** Un `NOT NULL` no
        // lo impide, y una fila con la clave a `""` sería peor que una fila sin
        // clave: el `UNIQUE` la dejaría existir **una** vez por competición y
        // cada pasada le escribiría encima los datos de un goleador distinto.
        try await database.checkConstraint(
            table: LeagueScorerRecord.schema, name: "chk_league_scorers_federation_player_id",
            expression: "length(btrim(federation_player_id)) > 0")

        // **Aquí tampoco va un `CHECK` de aritmética**, por lo mismo que en
        // `standing_rows` y con un motivo aún más directo: estos goles son de
        // jugadores ajenos y no hay nada nuestro contra lo que cuadrarlos —`Goal`
        // solo cubre los partidos del club (§3.7)—. No es que la comprobación
        // sería cara: es que no existe.
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(LeagueScorerRecord.schema).delete()
    }
}

/// **Lo que F8 le añade al registro de pasadas — y el `CHECK` que había que
/// rehacer y nadie esperaba.**
///
/// # Los tres contadores
///
/// `league_scorers_created` / `_updated` son el par de siempre, el que tiene cada
/// entidad que la ingesta escribe. **`league_scorers_retired` no tiene hermano en
/// ninguna otra**, porque `LeagueScorer` es la única salida de la ingesta que
/// borra (`D-94`), y es justo el número que hay que poder mirar cuando algo va
/// mal: una pasada que retire 200 de 218 no ha limpiado nada, ha vaciado el
/// ranking.
///
/// # Y el `CHECK` de `kind`, que es el hallazgo de la fase
///
/// `AddStandingsToIngestionRun` dejó escrito que *"el caso que F8 añada lo hereda
/// sin tocar SQL"*, apoyándose en que `sqlValueList` deriva la expresión del
/// enumerado (`D-02`). **Es falso, y se midió antes de escribir esto**: la
/// derivación ocurre **una vez**, cuando la migración corre, y lo que queda en el
/// *schema* es el texto de aquel día —
/// `CHECK (kind = ANY (ARRAY['calendar','standings']))` en `club_atleti`—. Es
/// `D-90` un piso más abajo: **derivado no significa vivo**.
///
/// Sin esta migración, el fallo tendría la forma más fea posible: **un alta limpia
/// aceptaría la pasada de goleadores y un club vivo la rechazaría** con un `23514`
/// que nadie relaciona con un `enum` de Swift — y encima solo al ejecutar, nunca al
/// compilar. Exactamente la divergencia entre caminos que `A-5`/H-38 mide que no
/// debe existir.
///
/// > **Al añadir el cuarto caso a `IngestionKind`** —el acta de `D-57`— hace falta
/// > otra migración como ésta. No se hereda, y ahora hay dos sitios que lo dicen:
/// > éste y el propio enumerado.
///
/// # Lo que NO hay que tocar, y conviene decirlo
///
/// `chk_ingestion_runs_round`, que es `(kind = 'standings') = (round_id IS NOT
/// NULL)`. Admite `scorers` con jornada nula **sin cambiarlo**, porque se escribió
/// diciendo *"solo la clasificación lleva jornada"* y no *"las que no son
/// calendario la llevan"*. Es la diferencia entre enunciar la regla y enumerar los
/// casos conocidos, y aquí salió gratis.
public struct AddScorersToIngestionRun: AsyncMigration {
    public init() {}

    public func prepare(on database: any Database) async throws {
        try await database.schema(IngestionRunRecord.schema)
            // El `DEFAULT` es el *backfill* y es **exacto**, igual que en F7: toda
            // fila existente se escribió cuando no había pasada de goleadores, así
            // que sus tres contadores son cero de verdad y no un relleno prudente.
            .field("league_scorers_created", .int, .required, .sql(.default(0)))
            .field("league_scorers_updated", .int, .required, .sql(.default(0)))
            .field("league_scorers_retired", .int, .required, .sql(.default(0)))
            .update()

        // **Rehacer, no añadir.** Ver arriba, y `replaceCheckConstraint`.
        try await database.replaceCheckConstraint(
            table: IngestionRunRecord.schema, name: "chk_ingestion_runs_kind",
            expression: "kind IN (\(IngestionKind.sqlValueList))")
    }

    public func revert(on database: any Database) async throws {
        try await database.schema(IngestionRunRecord.schema)
            .deleteField("league_scorers_created")
            .deleteField("league_scorers_updated")
            .deleteField("league_scorers_retired")
            .update()

        // **El `CHECK` vuelve a derivarse del enumerado, no al valor anterior
        // tecleado.** Revertir esta migración no revierte el `enum` de Swift, así
        // que un `ARRAY['calendar','standings']` a mano dejaría el *schema*
        // rechazando filas que el código sigue sabiendo escribir. Lo honesto es
        // dejarlo como está hoy (`D-02`).
        try await database.replaceCheckConstraint(
            table: IngestionRunRecord.schema, name: "chk_ingestion_runs_kind",
            expression: "kind IN (\(IngestionKind.sqlValueList))")
    }
}

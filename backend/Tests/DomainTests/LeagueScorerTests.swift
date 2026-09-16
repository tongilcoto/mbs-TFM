import Foundation
import Testing

@testable import Domain

/// Nivel 1 (§8.1): la entidad 23 del modelo, `LeagueScorer` (§3.2, [D-09]).
///
/// # En qué se parece a `StandingRow` y en qué NO, que es lo que esta suite fija
///
/// Las dos son modelos de lectura que escribe solo la ingesta, y las dos vienen
/// de la misma API. Ahí se acaba el parecido, y [D-48] avisa de que aplanarlo
/// sería un error:
///
/// - La clasificación **siempre se puede calcular** desde `Match` ([D-15]); el
///   ranking de goleadores **no**, porque incluye jugadores rivales de los que
///   no hay plantilla ([D-09]). Sin *fallback*, la tabla se queda vacía.
/// - La clasificación es un ***snapshot* por jornada**; esto es **estado vigente
///   único** sin histórico ni columna PREV.
///
/// # Y de ahí sale la invariante que esta entidad sí tiene y la otra no
///
/// `federationPlayerID` es **obligatorio** ([D-93]): es la clave con la que el
/// *upsert* pisa la fila de la semana pasada, y una fila sin ella es una fila
/// que nadie puede volver a encontrar. Es la asimetría deliberada con
/// `federation_team_id` y `federation_match_id`, que sí son anulables porque sus
/// entidades tienen un estado intermedio ([D-31], [D-66]) y ésta no: la escribe
/// la ingesta o no existe.
@Suite("LeagueScorer · el ranking de goleadores (§3.2, D-09, D-93)")
struct LeagueScorerTests {

    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let competition = CompetitionID(raw: UUID())

    static func scorer(
        federationPlayerID: String = "11322891",
        fullName: String = "GEA IRISARRI, LUIS",
        teamLabel: String = "ARAVACA C.F. - CEIBA A",
        goals: Int = 31,
        rank: Int? = nil,
        syncedAt: Date? = nil
    ) throws -> LeagueScorer {
        try LeagueScorer(
            id: LeagueScorerID(raw: UUID()),
            competitionID: competition,
            federationPlayerID: federationPlayerID,
            fullName: fullName,
            teamLabel: teamLabel,
            goals: goals,
            rank: rank,
            syncedAt: syncedAt,
            createdAt: now,
            updatedAt: now)
    }

    // ── La clave de upsert (D-93) ────────────────────────────────────────────

    @Test("el identificador de federación es obligatorio, y vacío no es un valor (D-93)")
    func federationPlayerIDIsRequired() {
        #expect(throws: DomainError.self) { try Self.scorer(federationPlayerID: "") }
        #expect(throws: DomainError.self) { try Self.scorer(federationPlayerID: "   ") }
    }

    @Test("y se guarda tal cual: es texto ajeno, no un número (Anexo RFFM §F.3)")
    func federationPlayerIDIsOpaqueText() throws {
        // §F.3 mide que estos códigos **no tienen longitud fija** —de "109" a
        // "8963337"—, así que convertirlos a `Int` para "normalizarlos" es
        // inventarse una forma que la fuente no promete. Y la FCF los publica
        // igual de opacos ([Anexo FCF §C.10.7]).
        #expect(try Self.scorer(federationPlayerID: "109").federationPlayerID == "109")
        #expect(
            try Self.scorer(federationPlayerID: "0040602472").federationPlayerID == "0040602472")
    }

    // ── Lo estructural del resto de campos ───────────────────────────────────

    @Test("el nombre no puede estar vacío (§3.2)")
    func fullNameIsRequired() {
        #expect(throws: DomainError.self) { try Self.scorer(fullName: "") }
        #expect(throws: DomainError.self) { try Self.scorer(fullName: "  \t ") }
    }

    @Test("la etiqueta de equipo tampoco (§3.2)")
    func teamLabelIsRequired() {
        #expect(throws: DomainError.self) { try Self.scorer(teamLabel: "") }
    }

    @Test("los goles no pueden ser negativos (spec `minimum: 0`)")
    func goalsAreNotNegative() {
        #expect(throws: DomainError.self) { try Self.scorer(goals: -1) }
    }

    @Test("pero cero goles SÍ es una fila válida (§3.2)")
    func zeroGoalsIsValid() throws {
        // No es teórico: nada impide que un proveedor publique en su ranking a
        // quien todavía no ha marcado —la FCF recorta la lista a 50, la RFFM la
        // sirve hasta el que lleva 1—. Una invariante `goals >= 1` sería la
        // aritmética de más que `StandingRow` ya rechazó por el mismo motivo.
        #expect(try Self.scorer(goals: 0).goals == 0)
    }

    @Test("el puesto, si viene, empieza en 1 (spec `minimum: 1`)")
    func rankStartsAtOne() {
        #expect(throws: DomainError.self) { try Self.scorer(rank: 0) }
        #expect(throws: DomainError.self) { try Self.scorer(rank: -2) }
    }

    @Test("y es anulable, que no era una precaución teórica (Anexo RFFM §F.13)")
    func rankIsNullable() throws {
        // **Las dos federaciones lo dejan nulo**: ninguna publica campo de
        // puesto, y el orden de la lista es la única señal. Medido en 426 filas
        // entre §F.13, §F.19 y §C.10.7. El *spec* se comprometió a **respetar el
        // del proveedor** en vez de recalcularlo, así que la ingesta tampoco lo
        // sintetiza desde el índice del array: eso sería inventar un desempate.
        #expect(try Self.scorer(rank: nil).rank == nil)
        #expect(try Self.scorer(rank: 1).rank == 1)
    }

    // ── Lo que esta entidad NO guarda, y es deliberado ───────────────────────

    @Test("no hay invariante de aritmética con los goles (D-75, como StandingRow)")
    func noArithmeticInvariant() throws {
        // El ranking oficial no se puede cuadrar contra nada nuestro: sus goles
        // son de jugadores ajenos y `Goal` solo cubre los partidos del club
        // (§3.7). Una comprobación cruzada aquí tiraría la pasada entera por un
        // dato que no controlamos, que es exactamente lo que `D-75` mide como el
        // error caro.
        #expect(try Self.scorer(goals: 500).goals == 500)
    }

    // ── La marca del upsert (D-94) ───────────────────────────────────────────

    @Test("`syncedAt` es anulable y no lo pone la entidad: lo pone la pasada (D-94)")
    func syncedAtIsTheUpsertMark() throws {
        #expect(try Self.scorer(syncedAt: nil).syncedAt == nil)
        #expect(try Self.scorer(syncedAt: Self.now).syncedAt == Self.now)
    }
}

import Foundation
import Testing

@testable import Domain

/// Nivel 1 (§8.1): **el *fallback* calculado de [D-15]**, cero I/O.
///
/// # Qué es esto y qué no
///
/// [D-15] decidió que cuando no hay clasificación oficial, la clasificación se
/// **calcula desde `Match`** — no se teclea en un formulario. Ésa es la mitad
/// que importa: así `StandingRow` conserva **un único escritor** y no aparece la
/// casilla con dos dueños que [D-21] rechaza en toda la matriz de propiedad.
///
/// Lo que esta suite prueba es la aritmética y **el orden**, que es donde está
/// el riesgo: una tabla que sume bien y ordene mal es una tabla mal.
///
/// # El disparador ya no es el que [D-15] escribió (`D-55`)
///
/// No es *"la federación no publica clasificación"* —las dos publican— sino
/// **"esta jornada es anterior a nuestra primera sincronización"**. Con la FCF,
/// que solo sirve la vigente, todo lo anterior al alta se calcula; con la RFFM,
/// que es histórica, casi nada. El cálculo es el mismo en los dos casos.
///
/// # Lo que el cálculo no puede dar, y está asumido por escrito
///
/// Sin desempate por **enfrentamiento directo** y sin **sanciones
/// administrativas** (`D-55`). Es peor dato que el oficial y se acepta como tal:
/// es el único posible para el histórico previo al alta.
@Suite("StandingTable · la clasificación calculada desde Match (D-15)")
struct StandingTableTests {

    // Cuatro equipos, con ids fijos y **en orden conocido** para poder afirmar
    // el desempate estable sin depender de qué UUID salió hoy.
    static let a = TeamID(raw: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!)
    static let b = TeamID(raw: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!)
    static let c = TeamID(raw: UUID(uuidString: "00000000-0000-0000-0000-0000000000CC")!)
    static let d = TeamID(raw: UUID(uuidString: "00000000-0000-0000-0000-0000000000DD")!)

    static func fixture(
        _ round: Int, _ home: TeamID, _ away: TeamID, _ homeScore: Int? = nil,
        _ awayScore: Int? = nil
    ) throws -> StandingTable.Fixture {
        StandingTable.Fixture(
            roundNumber: round, homeTeamID: home, awayTeamID: away,
            result: try homeScore.flatMap { hs in
                try awayScore.map { try MatchResult(homeScore: hs, awayScore: $0) }
            })
    }

    // ── La aritmética ────────────────────────────────────────────────────────

    @Test("ganar son 3 puntos, empatar 1 y perder 0 (D-15)")
    func theScoringSystemIsThreeOneZero() throws {
        let table = StandingTable.upTo(
            round: 1,
            fixtures: [
                try Self.fixture(1, Self.a, Self.b, 2, 0),
                try Self.fixture(1, Self.c, Self.d, 1, 1),
            ])

        #expect(table.first { $0.teamID == Self.a }?.points == 3)
        #expect(table.first { $0.teamID == Self.b }?.points == 0)
        #expect(table.first { $0.teamID == Self.c }?.points == 1)
        #expect(table.first { $0.teamID == Self.d }?.points == 1)
    }

    @Test("los goles cuentan de los dos lados del partido")
    func goalsCountForBothSides() throws {
        let table = StandingTable.upTo(
            round: 1, fixtures: [try Self.fixture(1, Self.a, Self.b, 3, 1)])

        let home = table.first { $0.teamID == Self.a }
        let away = table.first { $0.teamID == Self.b }
        #expect(home?.goalsFor == 3 && home?.goalsAgainst == 1)
        #expect(away?.goalsFor == 1 && away?.goalsAgainst == 3)
        #expect(home?.won == 1 && home?.lost == 0)
        #expect(away?.won == 0 && away?.lost == 1)
    }

    @Test("un partido sin marcador no se ha jugado (D-56)")
    func aFixtureWithoutAResultDidNotHappen() throws {
        // `result == nil` es *"la fuente no dijo nada"*, que `D-56` distingue de
        // `0-0` con todo el cuidado del mundo. Contarlo como jugado inventaría
        // un empate y le daría un punto a cada uno.
        let table = StandingTable.upTo(
            round: 1, fixtures: [try Self.fixture(1, Self.a, Self.b)])

        #expect(table.allSatisfy { $0.played == 0 })
        #expect(table.allSatisfy { $0.points == 0 })
    }

    @Test("el equipo que aún no ha jugado sale en la tabla con ceros")
    func ateamThatHasNotPlayedStillAppears() throws {
        // La plantilla de la tabla es **el calendario entero**, no los partidos
        // jugados: una clasificación de jornada 1 tiene a los 16 equipos del
        // grupo, no a los que ya jugaron. Por eso las jornadas futuras entran en
        // la lista de `fixtures` aunque no sumen nada.
        let table = StandingTable.upTo(
            round: 1,
            fixtures: [
                try Self.fixture(1, Self.a, Self.b, 1, 0),
                try Self.fixture(2, Self.c, Self.d),
            ])

        #expect(table.count == 4)
        #expect(table.first { $0.teamID == Self.c }?.played == 0)
    }

    // ── El corte por jornada ─────────────────────────────────────────────────

    @Test("la tabla es *snapshot* de una jornada: lo posterior no cuenta (§3.2, D-33)")
    func laterRoundsDoNotCount() throws {
        // Es lo que hace que la fila sea un *snapshot* y no el estado actual.
        // Sin el corte, recalcular el histórico daría treinta veces la tabla
        // final y la columna PREV no significaría nada.
        let fixtures = [
            try Self.fixture(1, Self.a, Self.b, 1, 0),
            try Self.fixture(2, Self.b, Self.a, 5, 0),
        ]

        #expect(StandingTable.upTo(round: 1, fixtures: fixtures).first?.teamID == Self.a)
        #expect(StandingTable.upTo(round: 2, fixtures: fixtures).first?.teamID == Self.b)
    }

    // ── El orden, que es donde está el riesgo ────────────────────────────────

    @Test("primero los puntos (D-15)")
    func pointsComeFirst() throws {
        let table = StandingTable.upTo(
            round: 2,
            fixtures: [
                try Self.fixture(1, Self.a, Self.b, 1, 0),
                try Self.fixture(2, Self.a, Self.c, 1, 0),
                try Self.fixture(1, Self.c, Self.d, 9, 0),
            ])

        // `c` tiene +9 de diferencia y 3 puntos; `a` tiene +2 y 6. Mandan los
        // puntos: si no, una goleada valdría más que una victoria.
        #expect(table.map(\.teamID).prefix(2) == [Self.a, Self.c])
        #expect(table.map(\.position).prefix(2) == [1, 2])
    }

    @Test("a igualdad de puntos, la diferencia de goles (D-15)")
    func goalDifferenceBreaksTies() throws {
        let table = StandingTable.upTo(
            round: 1,
            fixtures: [
                try Self.fixture(1, Self.a, Self.b, 1, 0),
                try Self.fixture(1, Self.c, Self.d, 4, 0),
            ])

        #expect(table.map(\.teamID).prefix(2) == [Self.c, Self.a])
    }

    @Test("a igualdad de puntos y diferencia, los goles a favor (D-15)")
    func goalsForBreakTheNextTie() throws {
        let table = StandingTable.upTo(
            round: 1,
            fixtures: [
                try Self.fixture(1, Self.a, Self.b, 1, 0),
                try Self.fixture(1, Self.c, Self.d, 3, 2),
            ])

        // Los dos ganaron y los dos tienen +1. Gana el que marcó más, que es el
        // tercer criterio del reglamento y el último que se puede calcular
        // **sin** el enfrentamiento directo que `D-55` deja fuera.
        #expect(table.map(\.teamID).prefix(2) == [Self.c, Self.a])
    }

    @Test("el empate que no se puede deshacer se ordena estable, no al azar (D-55)")
    func anUnbreakableTieIsStillDeterministic() throws {
        // `D-55` deja **fuera** el enfrentamiento directo, así que dos equipos
        // exactamente iguales están de verdad empatados y cualquier orden es
        // igual de malo deportivamente. Lo que **no** puede pasar es que el
        // orden cambie entre dos pasadas: la tabla se guarda como *snapshot* y
        // `previousPosition` se calcula comparando con ella, así que un orden
        // que baile inventa subidas y bajadas que no ocurrieron.
        let fixtures = [
            try Self.fixture(1, Self.a, Self.b, 2, 0),
            try Self.fixture(1, Self.c, Self.d, 2, 0),
        ]
        let first = StandingTable.upTo(round: 1, fixtures: fixtures)
        let reversed = StandingTable.upTo(round: 1, fixtures: fixtures.reversed())

        // Mismo resultado aunque los partidos lleguen en otro orden: el criterio
        // final es el id del equipo, que es arbitrario **y estable**, no el
        // orden en que la base devolvió las filas.
        #expect(first.map(\.teamID) == reversed.map(\.teamID))
        #expect(first.map(\.teamID).prefix(2) == [Self.a, Self.c])
    }

    @Test("las posiciones son 1..N sin huecos ni repeticiones")
    func positionsAreDense() throws {
        let table = StandingTable.upTo(
            round: 1,
            fixtures: [
                try Self.fixture(1, Self.a, Self.b, 2, 0),
                try Self.fixture(1, Self.c, Self.d, 2, 0),
            ])

        // Aunque dos equipos estén empatados a todo, la tabla numera del 1 al N:
        // el *spec* pide `position` obligatoria y `minimum: 1`, y la lista se
        // sirve en ese orden (§5.1). No hay posiciones compartidas.
        #expect(table.map(\.position) == [1, 2, 3, 4])
    }

    // ── Lo que el cálculo garantiza y la fila ingerida no ────────────────────

    @Test("lo calculado sí cumple las dos identidades que la fila no exige")
    func theComputedTableIsArithmeticallyClosed() throws {
        let table = StandingTable.upTo(
            round: 2,
            fixtures: [
                try Self.fixture(1, Self.a, Self.b, 1, 0),
                try Self.fixture(2, Self.a, Self.c, 2, 2),
            ])

        // `StandingRow` **no** exige `played == G+E+P` ni `points == 3G+E`,
        // porque la tabla oficial puede llevar sanciones. Aquí las construimos
        // nosotros, así que se cumplen — y conviene que un test lo diga, para
        // que quede claro que lo de allí es una decisión y no un olvido.
        for line in table {
            #expect(line.played == line.won + line.drawn + line.lost)
            #expect(line.points == line.won * 3 + line.drawn)
        }
    }

    @Test("sin partidos no hay tabla, y eso no es un error")
    func noFixturesIsAnEmptyTable() {
        #expect(StandingTable.upTo(round: 1, fixtures: []).isEmpty)
    }
}

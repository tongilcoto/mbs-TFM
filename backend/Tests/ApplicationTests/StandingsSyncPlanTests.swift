import Domain
import Foundation
import Testing

@testable import Application

/// Nivel 1 (§8.1): **qué jornadas entran en una pasada de clasificación y de
/// dónde sale cada una**. Cero I/O.
///
/// # La regla que `D-15` y `D-55` dejaron enunciada y sin escribir
///
/// `D-15` dice que la clasificación que no se puede ingerir **se calcula desde
/// `Match`**. `D-55` corrigió **cuándo**: el disparador no es *"la federación no
/// publica"* —se midió y las dos publican— sino **"esta jornada es anterior a
/// nuestra primera sincronización"**, y lo que separa a las dos fuentes es si
/// pueden servir **una jornada pasada**.
///
/// Traducido a código, eso son dos preguntas distintas y aquí están las dos:
/// **qué jornadas** hay que sincronizar, y **de dónde sale** cada una.
@Suite("StandingsSyncPlan · qué jornadas y de dónde (D-15, D-55)")
struct StandingsSyncPlanTests {

    static let home = TeamID(raw: UUID())
    static let away = TeamID(raw: UUID())

    static func round(_ number: Int) -> StandingsSyncPlan.RoundRef {
        StandingsSyncPlan.RoundRef(id: RoundID(raw: UUID()), number: number)
    }

    /// Un partido de esa jornada, jugado o no.
    static func fixture(_ round: Int, played: Bool) throws -> StandingTable.Fixture {
        StandingTable.Fixture(
            roundNumber: round, homeTeamID: home, awayTeamID: away,
            result: played ? try MatchResult(homeScore: 1, awayScore: 0) : nil)
    }

    static func plan(
        rounds: [StandingsSyncPlan.RoundRef],
        fixtures: [StandingTable.Fixture],
        stored: Set<RoundID> = [],
        providesRoundStandings: Bool = true
    ) -> [StandingsSyncPlan.Step] {
        StandingsSyncPlan.steps(
            rounds: rounds, fixtures: fixtures, alreadyStored: stored,
            providesRoundStandings: providesRoundStandings)
    }

    // ── Qué jornadas entran ──────────────────────────────────────────────────

    @Test("una jornada sin ningún partido jugado no tiene clasificación (D-56)")
    func aroundWithNoPlayedMatchIsNotSynced() throws {
        let first = Self.round(1), second = Self.round(2)

        let steps = Self.plan(
            rounds: [first, second],
            fixtures: [
                try Self.fixture(1, played: true),
                try Self.fixture(2, played: false),
            ])

        // La jornada 2 está en el calendario y aún no se ha jugado. Sincronizarla
        // pediría a la federación una tabla que no existe, y calcularla daría
        // dieciséis filas a cero con cara de dato.
        #expect(steps.map(\.round.number) == [1])
    }

    @Test("una jornada que ya tiene *snapshot* no se vuelve a pedir (D-33)")
    func astoredRoundIsNotFetchedAgain() throws {
        let first = Self.round(1), second = Self.round(2), third = Self.round(3)

        let steps = Self.plan(
            rounds: [first, second, third],
            fixtures: [
                try Self.fixture(1, played: true),
                try Self.fixture(2, played: true),
                try Self.fixture(3, played: true),
            ],
            stored: [first.id, second.id])

        // El *snapshot* de una jornada pasada **no cambia**: es la foto de cómo
        // quedó la tabla. Volver a pedirla cada semana serían treinta peticiones
        // por competición y por pasada para reescribir lo mismo.
        #expect(steps.map(\.round.number) == [3])
    }

    @Test("la última jugada se refresca siempre, aunque ya esté guardada")
    func thelatestPlayedRoundIsAlwaysRefreshed() throws {
        let first = Self.round(1), second = Self.round(2)

        let steps = Self.plan(
            rounds: [first, second],
            fixtures: [
                try Self.fixture(1, played: true),
                try Self.fixture(2, played: true),
            ],
            stored: [first.id, second.id])

        // Es la excepción a la regla de arriba, y la que hace que el sistema se
        // corrija solo: el resultado de un partido de la jornada en curso cambia
        // —un acta que se cierra tarde, una alegación— y con él toda la tabla.
        // Sin esto, la clasificación se congelaría en la primera versión que se
        // llegara a guardar.
        #expect(steps.map(\.round.number) == [2])
    }

    @Test("la primera pasada de un alta a mitad de temporada las trae todas")
    func afirstPassMidSeasonBackfillsEverything() throws {
        let rounds = (1...5).map { Self.round($0) }

        let steps = Self.plan(
            rounds: rounds,
            fixtures: try (1...5).map { try Self.fixture($0, played: true) })

        // Es el caso que `D-55` describe como *"la ventana de arranque"*: un club
        // que engancha su competición en noviembre no tiene ni una jornada
        // guardada, y las anteriores son justamente las que hay que recomponer.
        #expect(steps.map(\.round.number) == [1, 2, 3, 4, 5])
    }

    @Test("el orden es ascendente, y no es cosmético (D-33)")
    func thestepsGoInAscendingOrder() throws {
        // La columna PREV de la jornada N se calcula contra la tabla de la N−1,
        // así que una pasada que recompusiera el histórico al revés tendría que
        // resolver cada PREV contra una tabla que todavía no ha construido.
        let rounds = [Self.round(3), Self.round(1), Self.round(2)]

        let steps = Self.plan(
            rounds: rounds,
            fixtures: try (1...3).map { try Self.fixture($0, played: true) })

        #expect(steps.map(\.round.number) == [1, 2, 3])
    }

    @Test("sin jornadas jugadas no hay nada que hacer, y no es un error")
    func nothingPlayedIsAnEmptyPlan() throws {
        let steps = Self.plan(
            rounds: [Self.round(1)], fixtures: [try Self.fixture(1, played: false)])

        // Una competición recién dada de alta en agosto. La pasada del calendario
        // sí tiene trabajo —trae 240 partidos sin jugar—; ésta no.
        #expect(steps.isEmpty)
    }

    // ── De dónde sale cada una ───────────────────────────────────────────────

    @Test("con federación que sirve jornadas pasadas, todas se piden (D-55)")
    func ahistoricalProviderIsAskedForEveryRound() throws {
        let steps = Self.plan(
            rounds: (1...3).map { Self.round($0) },
            fixtures: try (1...3).map { try Self.fixture($0, played: true) },
            providesRoundStandings: true)

        // La RFFM sirve la jornada 9 dos años después, así que el histórico se
        // ingiere **oficial** en vez de calcularse. Es mejor dato: lleva las
        // sanciones administrativas y el desempate por enfrentamiento directo,
        // que es justo lo que el cálculo no puede dar (`D-92`).
        #expect(steps.map(\.source) == [.fetch, .fetch, .fetch])
    }

    @Test("con federación que solo sirve la vigente, lo anterior se calcula (D-55, D-15)")
    func acurrentOnlyProviderGetsTheFallbackForThePast() throws {
        let steps = Self.plan(
            rounds: (1...3).map { Self.round($0) },
            fixtures: try (1...3).map { try Self.fixture($0, played: true) },
            providesRoundStandings: false)

        // La FCF publica **solo la clasificación vigente**, así que la pide para
        // la jornada en curso y la guarda como su *snapshot*; lo anterior al alta
        // no se recupera jamás de la fuente y es donde entra el cálculo de
        // `D-15`. La jornada que se pide es **la última**, no la primera.
        #expect(steps.map(\.source) == [.compute, .compute, .fetch])
        #expect(steps.last?.round.number == 3)
    }

    @Test("y aun así pide una sola vez: la vigente, no una por jornada")
    func acurrentOnlyProviderIsAskedOnlyOnce() throws {
        let steps = Self.plan(
            rounds: (1...10).map { Self.round($0) },
            fixtures: try (1...10).map { try Self.fixture($0, played: true) },
            providesRoundStandings: false)

        // Pedirle diez veces la misma tabla —porque ignora el parámetro— serían
        // nueve peticiones para escribir nueve veces lo mismo en jornadas
        // distintas, que además sería **falso**: la tabla vigente no es la foto
        // de la jornada 3.
        #expect(steps.filter { $0.source == .fetch }.count == 1)
    }

    @Test("la capacidad no cambia qué jornadas entran, solo de dónde salen")
    func thecapabilityDoesNotChangeWhichRoundsAreSynced() throws {
        let rounds = (1...4).map { Self.round($0) }
        let fixtures = try (1...4).map { try Self.fixture($0, played: true) }

        let historical = Self.plan(
            rounds: rounds, fixtures: fixtures, providesRoundStandings: true)
        let currentOnly = Self.plan(
            rounds: rounds, fixtures: fixtures, providesRoundStandings: false)

        // Son **dos decisiones separadas** y conviene que se rompan por separado:
        // `D-15` dice que la fila existe siempre, y `D-55` solo de dónde viene.
        #expect(historical.map(\.round.number) == currentOnly.map(\.round.number))
    }
}

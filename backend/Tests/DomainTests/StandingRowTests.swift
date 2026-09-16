import Foundation
import Testing

@testable import Domain

/// Nivel 1 (§8.1): `StandingRow`, la **entidad 9** de §3.2.
///
/// # Lo que esta suite fija, y es una decisión y no una omisión
///
/// `StandingRow` guarda **lo estructural** —una posición empieza en 1, un
/// contador no es negativo— y **no guarda la aritmética**. No es descuido: el
/// *spec* se comprometió con ello en `points` (*"no se recalcula en el BFF a
/// partir de G/E/P: si la federación publica la clasificación, el dato bueno es
/// el suyo"*), y la fuente publica `puntos_sancion` ([Anexo RFFM §F.8]) — una
/// tabla con puntos descontados por sanción **no** cumple `points == 3·G + E`, y
/// es la tabla oficial.
///
/// La regla de fondo es la de [D-75] aplicada a una fila en vez de a un campo:
/// los dos errores no cuestan lo mismo. Una invariante aritmética de más
/// convierte *"la federación hace cuentas que no controlamos"* en una excepción
/// que **tira la clasificación entera de la jornada**; una de menos deja pasar
/// una fila rara que la pasada siguiente reescribe.
@Suite("StandingRow · la fila de clasificación (§3.2, D-15)")
struct StandingRowTests {

    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let competition = CompetitionID(raw: UUID())
    static let round = RoundID(raw: UUID())
    static let team = TeamID(raw: UUID())

    static func row(
        position: Int = 1,
        previousPosition: Int? = nil,
        played: Int = 9,
        won: Int = 8,
        drawn: Int = 1,
        lost: Int = 0,
        goalsFor: Int = 81,
        goalsAgainst: Int = 18,
        points: Int = 25
    ) throws -> StandingRow {
        try StandingRow(
            id: StandingRowID(raw: UUID()),
            competitionID: competition,
            roundID: round,
            teamID: team,
            position: position,
            previousPosition: previousPosition,
            played: played, won: won, drawn: drawn, lost: lost,
            goalsFor: goalsFor, goalsAgainst: goalsAgainst,
            points: points,
            createdAt: now, updatedAt: now)
    }

    // ── Lo estructural, que sí se guarda ─────────────────────────────────────

    @Test("la posición empieza en 1 (§3.2, spec `minimum: 1`)")
    func positionStartsAtOne() {
        #expect(throws: DomainError.self) { try Self.row(position: 0) }
        #expect(throws: DomainError.self) { try Self.row(position: -3) }
    }

    @Test("`previousPosition` también empieza en 1 cuando viene (D-33)")
    func previousPositionStartsAtOneToo() {
        // Su ausencia **no** es un error —primera jornada, o alta a mitad de
        // temporada—, pero un 0 sí: significaría una posición que no existe.
        #expect(throws: DomainError.self) { try Self.row(previousPosition: 0) }
        #expect(throws: Never.self) { try Self.row(previousPosition: nil) }
    }

    @Test("ningún contador es negativo (spec `minimum: 0`)")
    func countersAreNotNegative() throws {
        #expect(throws: DomainError.self) { try Self.row(played: -1) }
        #expect(throws: DomainError.self) { try Self.row(won: -1) }
        #expect(throws: DomainError.self) { try Self.row(drawn: -1) }
        #expect(throws: DomainError.self) { try Self.row(lost: -1) }
        #expect(throws: DomainError.self) { try Self.row(goalsFor: -1) }
        #expect(throws: DomainError.self) { try Self.row(goalsAgainst: -1) }
        #expect(throws: DomainError.self) { try Self.row(points: -1) }
    }

    @Test("el campo que falla se dice por su nombre (§5.4)")
    func theFailingFieldIsNamed() {
        // El adaptador traduce `invalidValue` a 422 y publica el `field` (§5.4);
        // un error que no diga cuál de los siete contadores era manda al que
        // depura a mirar los siete.
        #expect(throws: DomainError.invalidValue(field: "goalsAgainst", reason: "no puede ser negativo")) {
            try Self.row(goalsAgainst: -1)
        }
        // Y las dos guardas de posición, cada una con **su** nombre: son dos
        // columnas distintas del mockup —la actual y la PREV— y decir
        // *"position"* cuando la mala era la anterior manda a mirar la fila
        // equivocada. Lo pidió la mutación: cambiar el rótulo no tumbaba nada.
        #expect(throws: DomainError.invalidValue(
            field: "position", reason: "la clasificación se numera desde 1")) {
            try Self.row(position: 0)
        }
        #expect(throws: DomainError.invalidValue(
            field: "previousPosition", reason: "la clasificación se numera desde 1")) {
            try Self.row(previousPosition: 0)
        }
    }

    // ── La aritmética, que a propósito NO se guarda ──────────────────────────

    @Test("una fila con puntos de sanción se admite (spec `points`, Anexo RFFM §F.8)")
    func sanctionedPointsAreAccepted() throws {
        // 8 victorias y 1 empate son 25 puntos; con tres descontados por sanción
        // la federación publica 22, y **ésa es la tabla oficial**. Rechazarla
        // sería preferir nuestra aritmética a la del que organiza la liga.
        let sanctioned = try Self.row(played: 9, won: 8, drawn: 1, lost: 0, points: 22)
        #expect(sanctioned.points == 22)
    }

    @Test("`played` no tiene que ser `won + drawn + lost` (Anexo RFFM §F.8)")
    func playedIsNotForcedToMatchTheBreakdown() throws {
        // La clasificación *"a jornada N"* refleja los partidos **realmente
        // disputados**: en la muestra de §F.8, `jugados` vale 8 en nueve equipos
        // y 9 en cuatro dentro de la misma jornada. Si además la fuente arrastra
        // un aplazado mal contado, la fila sigue siendo la tabla oficial.
        let odd = try Self.row(played: 9, won: 7, drawn: 1, lost: 0)
        #expect(odd.played == 9)
    }

    @Test("una fila normal se construye y conserva lo que le dieron")
    func aPlainRowSurvives() throws {
        let row = try Self.row(position: 1, previousPosition: 2)
        #expect(row.position == 1)
        #expect(row.previousPosition == 2)
        #expect(row.goalDifference == 63)
    }

    @Test("la diferencia de goles se deriva y puede ser negativa")
    func goalDifferenceIsDerived() throws {
        // Se deriva y no se guarda: es resta de dos columnas que ya están, y el
        // *spec* no la publica (§5.1). Existe porque la ordenación del *fallback*
        // calculado la necesita ([D-15]).
        #expect(try Self.row(goalsFor: 3, goalsAgainst: 11).goalDifference == -8)
    }
}

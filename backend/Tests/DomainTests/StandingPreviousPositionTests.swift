import Foundation
import Testing

@testable import Domain

/// Nivel 1 (§8.1): **la columna PREV** (`D-33`, [Anexo RFFM §F.8]).
///
/// # Por qué hace falta código para esto
///
/// El *spec* dice que `previousPosition` **se almacena, no se deriva**, y eso
/// suena a que no hay nada que calcular. Lo hay: la RFFM **no publica** la
/// posición anterior ([Anexo RFFM §F.8], la fila con ❌ de la tabla de mapeo), y
/// la FCF tampoco. Lo que `D-33` decide es que **no se derive en la lectura**
/// —diferenciando *snapshots* al servir la tabla—, porque eso fallaría en un
/// alta a mitad de temporada. Se calcula **una vez, al ingerir**, y se guarda.
///
/// # Y es aquí, en la misma puerta para las dos fuentes (`D-15`)
///
/// La tabla ingerida de la federación y la calculada desde `Match` producen las
/// mismas `Line`, así que la columna PREV se resuelve **una sola vez** para las
/// dos. Si viviera en el adaptador de la RFFM, el *fallback* calculado se
/// quedaría sin ella y la pantalla pintaría *"–"* en todo el histórico previo al
/// alta — justo las jornadas que `D-55` dice que se calculan.
@Suite("StandingTable · la columna PREV (D-33)")
struct StandingPreviousPositionTests {

    static let a = TeamID(raw: UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!)
    static let b = TeamID(raw: UUID(uuidString: "00000000-0000-0000-0000-0000000000BB")!)
    static let c = TeamID(raw: UUID(uuidString: "00000000-0000-0000-0000-0000000000CC")!)

    static func line(_ team: TeamID, _ position: Int) -> StandingTable.Line {
        StandingTable.Line(
            teamID: team, position: position,
            played: 1, won: 1, drawn: 0, lost: 0,
            goalsFor: 1, goalsAgainst: 0, points: 3)
    }

    @Test("PREV es la posición del equipo en el snapshot anterior (D-33)")
    func previousIsThePositionInTheEarlierSnapshot() {
        let previous = [Self.line(Self.a, 1), Self.line(Self.b, 2), Self.line(Self.c, 3)]
        let current = [Self.line(Self.c, 1), Self.line(Self.a, 2), Self.line(Self.b, 3)]

        let resolved = StandingTable.resolvingPreviousPositions(current, previous: previous)

        #expect(resolved.map(\.teamID) == [Self.c, Self.a, Self.b])
        #expect(resolved.map(\.previousPosition) == [3, 1, 2])
    }

    @Test("sin jornada anterior, PREV es nula y no es un error (D-33)")
    func withoutAnEarlierRoundPrevIsNil() {
        // Los dos casos que `D-33` nombra: la primera jornada de la competición
        // y la primera jornada ingerida de un alta tardía. El cliente pinta "–".
        let current = [Self.line(Self.a, 1), Self.line(Self.b, 2)]

        let resolved = StandingTable.resolvingPreviousPositions(current, previous: nil)

        #expect(resolved.allSatisfy { $0.previousPosition == nil })
    }

    @Test("un equipo que no estaba en la anterior tampoco tiene PREV")
    func ateamAbsentFromTheEarlierSnapshotHasNoPrev() {
        // Pasa de verdad: una tabla ingerida a mitad de temporada puede no
        // traer a un equipo que la federación añadió después, y el *fallback*
        // calculado solo incluye a los que aparecen en el calendario. Inventarle
        // un PREV sería inventar una subida.
        let previous = [Self.line(Self.a, 1)]
        let current = [Self.line(Self.a, 1), Self.line(Self.b, 2)]

        let resolved = StandingTable.resolvingPreviousPositions(current, previous: previous)

        #expect(resolved.first { $0.teamID == Self.a }?.previousPosition == 1)
        #expect(resolved.first { $0.teamID == Self.b }?.previousPosition == nil)
    }

    @Test("resolver PREV no reordena ni toca ningún otro campo")
    func resolvingPrevChangesNothingElse() {
        let current = [Self.line(Self.b, 1), Self.line(Self.a, 2)]

        let resolved = StandingTable.resolvingPreviousPositions(current, previous: nil)

        // El orden es el de la tabla, que ya lo decidió quien la construyó. Esta
        // función añade **una** columna: si además ordenara, habría dos sitios
        // decidiendo el orden y uno de los dos sobraría.
        #expect(resolved.map(\.teamID) == current.map(\.teamID))
        #expect(resolved.map(\.position) == [1, 2])
        #expect(resolved.map(\.points) == current.map(\.points))
    }

    @Test("la tabla calculada entra por la misma puerta que la ingerida (D-15)")
    func theComputedTableGoesThroughTheSameDoor() throws {
        // `D-15` dice que la fila es **agnóstica a la fuente**. Aquí se ve como
        // código: lo que sale de `upTo` —el cálculo— y lo que se construya desde
        // el DTO de la federación son las mismas `Line`, así que la columna PREV
        // la resuelve la misma función para las dos.
        let fixtures = [
            StandingTable.Fixture(
                roundNumber: 1, homeTeamID: Self.a, awayTeamID: Self.b,
                result: try MatchResult(homeScore: 1, awayScore: 0))
        ]
        let computed = StandingTable.upTo(round: 1, fixtures: fixtures)

        let resolved = StandingTable.resolvingPreviousPositions(
            computed, previous: [Self.line(Self.b, 1), Self.line(Self.a, 2)])

        #expect(resolved.map(\.teamID) == [Self.a, Self.b])
        #expect(resolved.map(\.previousPosition) == [2, 1])
    }

    @Test("esta función es la dueña de la columna: una PREV vieja no sobrevive")
    func theFunctionOwnsTheColumn() {
        // Es la propiedad que hace que se pueda llamar dos veces sin miedo: lo
        // que decide la columna PREV es **el argumento `previous`**, no lo que
        // la línea trajera puesto. Sin esto, recalcular la clasificación de un
        // alta tardía —donde la jornada anterior no existe— dejaría en la fila
        // un PREV heredado de otro cálculo, y la pantalla pintaría una subida
        // que nadie hizo.
        let stale = StandingTable.Line(
            teamID: Self.a, position: 1,
            played: 1, won: 1, drawn: 0, lost: 0,
            goalsFor: 1, goalsAgainst: 0, points: 3,
            previousPosition: 7)

        #expect(StandingTable.resolvingPreviousPositions([stale], previous: nil)
            .map(\.previousPosition) == [nil])
        #expect(StandingTable.resolvingPreviousPositions(
            [stale], previous: [Self.line(Self.a, 2)]).map(\.previousPosition) == [2])
    }

    @Test("una tabla recién calculada todavía no tiene PREV")
    func afreshlyComputedTableHasNoPrevYet() throws {
        // `upTo` hace aritmética, no historia: no recibe la jornada anterior, así
        // que no puede inventarse la columna. Quien la quiera, la resuelve.
        let computed = StandingTable.upTo(
            round: 1,
            fixtures: [
                StandingTable.Fixture(
                    roundNumber: 1, homeTeamID: Self.a, awayTeamID: Self.b,
                    result: try MatchResult(homeScore: 1, awayScore: 0))
            ])

        #expect(computed.allSatisfy { $0.previousPosition == nil })
    }
}

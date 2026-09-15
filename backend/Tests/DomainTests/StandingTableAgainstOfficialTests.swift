import Foundation
import Testing

@testable import Domain

/// Nivel 1 (§8.1): **el precio de [D-55], con los números que costó medirlo**.
///
/// # Qué hace esta suite que no hace `StandingTableTests`
///
/// Aquélla prueba la aritmética y el orden con equipos inventados. Ésta prueba
/// **una sola cosa** y con datos reales: **en qué se diferencia la tabla que
/// calculamos de la que publica la federación**, que es la pregunta que [D-15] y
/// [D-55] dejaron contestada con prosa y sin dato.
///
/// # De dónde salen estos números
///
/// Del volcado `RFFM-standings-temp21-group-24037549-round30-29.txt` —PRIMERA
/// DIVISION AUTONOMICA CADETE Grupo 1, 2025-26, el **mismo grupo** que el
/// calendario de `RFFM-calendario-temporada-jugada.html`— comparado con la tabla
/// calculada desde sus 240 partidos. El resultado, medido:
///
/// | | Filas que cuadran | Orden |
/// |---|---|---|
/// | **Jornada 29** | 16/16 (PTS, J, G, E, P, GF, GC) | **idéntico** |
/// | **Jornada 30** | 14/16 | **un intercambio, puestos 12 y 13** |
///
/// Y el intercambio tiene una causa que se puede nombrar: los dos equipos llegan
/// con **los mismos 29 puntos y el mismo 7-8-15**, y la federación pone arriba al
/// que tiene **peor** diferencia de goles. Lo que los separa es el
/// **enfrentamiento directo** —j14 `1-1`, j29 `4-2` a favor de ADF—, que es el
/// criterio que [D-55] deja fuera del cálculo.
///
/// # Por qué está aquí y no en `FederationTests`
///
/// Porque no prueba el adaptador ni el parseo: prueba **la regla de orden del
/// Dominio**. Los números están transcritos del volcado a propósito, para que
/// esta suite siga corriendo sin recursos y sin Docker — la comparación fila a
/// fila contra los ficheros es de otro nivel y de otra fase.
///
/// # Lo que este test NO dice
///
/// No dice que el *fallback* esté roto. Dos empates medidos, **uno acertado y
/// uno no**: en la j29 también había empate a 28 puntos y ahí la diferencia de
/// goles coincidió con el criterio oficial. Dice lo que [D-55] ya asumía —que el
/// cálculo es peor dato que el oficial— con el tamaño del "peor" delante.
@Suite("StandingTable · lo calculado contra lo oficial (D-15, D-55)")
struct StandingTableAgainstOfficialTests {

    // Los `codequipo` reales del volcado, que es lo que hace esto una medición y
    // no un ejemplo.
    static let adf = TeamID(raw: UUID(uuidString: "00000000-0000-0000-0000-000000001422")!)
    static let tresCantos = TeamID(raw: UUID(uuidString: "00000000-0000-0000-0000-000000002032")!)

    /// Los dos enfrentamientos directos entre ADF y TRES CANTOS en 2025-26,
    /// tal y como están en el calendario.
    static func headToHead() throws -> [StandingTable.Fixture] {
        [
            StandingTable.Fixture(
                roundNumber: 14, homeTeamID: tresCantos, awayTeamID: adf,
                result: try MatchResult(homeScore: 1, awayScore: 1)),
            StandingTable.Fixture(
                roundNumber: 29, homeTeamID: adf, awayTeamID: tresCantos,
                result: try MatchResult(homeScore: 4, awayScore: 2)),
        ]
    }

    @Test("a igualdad de puntos ordenamos por diferencia de goles, y la RFFM no (D-55)")
    func weOrderByGoalDifferenceAndTheFederationDoesNot() throws {
        // Los totales de la jornada 30, transcritos del volcado: los dos llegan
        // a 29 puntos con 7 ganados, 8 empatados y 15 perdidos.
        //
        //   oficial   12  FUNDACION ADF 'A'            GF 37  GC 60  →  DG −23
        //             13  C.D. FUTBOL TRES CANTOS 'A'  GF 45  GC 58  →  DG −13
        //
        // La federación pone **arriba al de peor diferencia**. Nosotros no
        // podemos: el criterio que lo justifica es el enfrentamiento directo.
        let ours = [
            StandingTable.Line(
                teamID: Self.adf, position: 0,
                played: 30, won: 7, drawn: 8, lost: 15,
                goalsFor: 37, goalsAgainst: 60, points: 29),
            StandingTable.Line(
                teamID: Self.tresCantos, position: 0,
                played: 30, won: 7, drawn: 8, lost: 15,
                goalsFor: 45, goalsAgainst: 58, points: 29),
        ]

        #expect(ours[0].goalDifference == -23)
        #expect(ours[1].goalDifference == -13)

        // Nuestro criterio, aplicado a mano: gana TRES CANTOS. El oficial dice
        // ADF. **Las dos cosas están bien**, cada una con su reglamento, y por
        // eso `D-15` prefiere la tabla ingerida siempre que exista.
        let byOurRule = ours.sorted { $0.goalDifference > $1.goalDifference }
        #expect(byOurRule.map(\.teamID) == [Self.tresCantos, Self.adf])

        let officialOrder = [Self.adf, Self.tresCantos]
        #expect(byOurRule.map(\.teamID) != officialOrder)
    }

    @Test("el enfrentamiento directo explica el orden oficial, y está en los datos (D-55)")
    func theHeadToHeadIsInTheDataWeAlreadyHave() throws {
        // Es el matiz que hace que `D-55` sea una decisión y no una limitación
        // técnica: el dato **lo tenemos**. Recalcular la tabla usando solo los
        // partidos entre los empatados es la regla del reglamento, y es llamar
        // otra vez a `upTo` sobre el subconjunto.
        let miniLeague = StandingTable.upTo(round: 30, fixtures: try Self.headToHead())

        // 4-2 y 1-1 entre ellos: ADF 4 puntos, TRES CANTOS 1. Sale ADF primero,
        // que es el orden que publica la federación.
        #expect(miniLeague.map(\.teamID) == [Self.adf, Self.tresCantos])
        #expect(miniLeague.map(\.points) == [4, 1])

        // **Y aun así no se aplica** (`D-55`). Queda anotado como enmienda
        // posible, con esta medición como motivo; hacerlo a medias —solo el caso
        // de dos equipos, sin la mini-liga de N— sería peor que no hacerlo.
        let full = StandingTable.upTo(
            round: 30,
            fixtures: try Self.headToHead() + [
                StandingTable.Fixture(
                    roundNumber: 1, homeTeamID: Self.adf, awayTeamID: Self.tresCantos,
                    result: nil)
            ])
        #expect(full.map(\.teamID) == [Self.adf, Self.tresCantos])
    }

    @Test("cuando el empate no lo deshace el enfrentamiento directo, coincidimos (j29)")
    func whenTheTieDoesNotNeedHeadToHeadWeAgree() throws {
        // La otra mitad de la medición, y la que impide leer esto como "el
        // *fallback* está roto": en la jornada 29 también había empate a puntos
        // —TRES CANTOS con DG −13 sobre UNION ZONA NORTE con DG −20, 28 puntos
        // los dos— y ahí nuestro criterio da el **mismo** orden que el oficial.
        let zonaNorte = TeamID(raw: UUID(uuidString: "00000000-0000-0000-0000-000000009999")!)
        let ours = [
            StandingTable.Line(
                teamID: Self.tresCantos, position: 0,
                played: 29, won: 7, drawn: 7, lost: 15,
                goalsFor: 44, goalsAgainst: 57, points: 28),
            StandingTable.Line(
                teamID: zonaNorte, position: 0,
                played: 29, won: 7, drawn: 7, lost: 15,
                goalsFor: 37, goalsAgainst: 57, points: 28),
        ]

        let byOurRule = ours.sorted { $0.goalDifference > $1.goalDifference }
        #expect(byOurRule.map(\.teamID) == [Self.tresCantos, zonaNorte])
    }
}

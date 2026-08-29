import Foundation
import Testing
@testable import Domain

/// Nivel 1 (§8.1), **cero I/O**: los dos *Value Objects* sobre los que se apoya
/// la política de *upsert* de F3.
@Suite("Kickoff · D-30 · el calendario nace provisional")
struct KickoffTests {

    static let sabado = Date(timeIntervalSince1970: 1_789_171_200)  // sábado 2026-09-12

    /// `D-30`: la confirmación **se deriva** de que haya hora. No hay columna, y
    /// por eso no puede contradecir al dato.
    @Test("sin hora, el horario está sin confirmar; con hora, confirmado (D-30)")
    func confirmationIsDerivedFromTheTime() {
        let provisional = Kickoff(date: Self.sabado, time: nil)
        let confirmado = Kickoff(date: Self.sabado, time: WallClockTime(hour: 12, minute: 0))

        #expect(provisional.isConfirmed == false)
        #expect(confirmado.isConfirmed == true)
    }
}

/// Nivel 1 (§8.1). El VO que responde *"¿se ha jugado?"*, del que cuelga la
/// desambiguación de `D-56`.
@Suite("MatchResult · §4.1 · un marcador válido o ninguno")
struct MatchResultTests {

    /// §4.1: el *init* **valida y lanza**; un VO que existe es siempre válido.
    /// Un marcador negativo solo puede venir de un fallo de parseo — y el
    /// adaptador de la RFFM preserva el signo a propósito ([Anexo RFFM §F.11]),
    /// así que un `-3` llega hasta aquí en vez de convertirse en `3`.
    @Test("un marcador negativo no es un marcador (§4.1)")
    func rejectsNegativeScores() throws {
        #expect(throws: DomainError.self) { try MatchResult(homeScore: -3, awayScore: 0) }
        #expect(throws: DomainError.self) { try MatchResult(homeScore: 1, awayScore: -1) }
    }

    /// Y el límite por el otro lado: **`0-0` es un marcador**, no la ausencia de
    /// uno. Es la misma frontera que `RFFMValue.score` defiende en el adaptador
    /// (§F.11): colapsar `""` con `"0"` escribiría ceros en toda la liga.
    @Test("el cero a cero es un marcador, no un hueco (§F.11)")
    func zeroIsAResult() throws {
        let empate = try MatchResult(homeScore: 0, awayScore: 0)
        #expect(empate.homeScore == 0)
        #expect(empate.awayScore == 0)
    }
}

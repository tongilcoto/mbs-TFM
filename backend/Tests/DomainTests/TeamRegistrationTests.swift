import Foundation
import Testing

@testable import Domain

/// Nivel 1 (§8.1): la inscripción del equipo en una temporada (`D-68`).
@Suite("TeamRegistration · §3.2 · lo que el club afirma antes de que haya calendario")
struct TeamRegistrationTests {

    static func team(opponentClubID: OpponentClubID? = nil) throws -> Team {
        try Team(
            id: TeamID(raw: UUID()),
            opponentClubID: opponentClubID,
            category: .cadete,
            letter: "A",
            gender: .masculino,
            modality: .futbol11,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // ── C-A.1 · la terna, y solo para equipos propios (D-68) ────────────────

    /// `D-68`: la fila es `(equipo, temporada, competición?)`, y la competición
    /// es **anulable a propósito** — es el estado de junio, cuando el club ya ha
    /// inscrito pero la federación todavía no publica calendario. El enganche de
    /// `D-67` la completa después.
    @Test("la inscripción es la terna, y en junio la competición todavía no se sabe (D-68)")
    func theRegistrationIsTheTripleWithAnOpenCompetition() throws {
        let team = try Self.team()
        let seasonID = SeasonID(raw: UUID())

        let registration = try TeamRegistration(
            id: TeamRegistrationID(raw: UUID()),
            team: team,
            seasonID: seasonID,
            createdAt: Date(),
            updatedAt: Date()
        )

        #expect(registration.teamID == team.id)
        #expect(registration.seasonID == seasonID)
        #expect(registration.competitionID == nil)
    }

    /// La otra mitad de la terna: la enmienda de `D-68` le añadió
    /// `competition_id` para que la portada del backoffice pueda leer
    /// equipo↔competición **desde el mismo `202`**, sin esperar al primer
    /// `Match` — que es la única arista que el modelo tenía.
    @Test("con el enganche hecho, la inscripción dice también de qué competición (D-68)")
    func theRegistrationCarriesItsCompetition() throws {
        let team = try Self.team()
        let competitionID = CompetitionID(raw: UUID())

        let registration = try TeamRegistration(
            id: TeamRegistrationID(raw: UUID()),
            team: team,
            seasonID: SeasonID(raw: UUID()),
            competitionID: competitionID,
            createdAt: Date(),
            updatedAt: Date()
        )

        #expect(registration.competitionID == competitionID)
    }

    /// **El alcance de `D-68`, literal: *"solo equipos propios — un rival no se
    /// inscribe en tu sistema"*.**
    ///
    /// Y no es una restricción por gusto: `?seasonId=` es una **unión
    /// asimétrica** donde el rival sale derivado de `Match` (`D-27`). Un rival
    /// con inscripción aparecería por los dos sumandos, que es exactamente el
    /// equipo duplicado en pantalla que la enmienda de `D-68` evita con su
    /// invariante.
    ///
    /// **Por qué el `init` pide el `Team` entero y no su `TeamID`**: la propiedad
    /// se *deriva* de `opponentClubID` (`D-03`, no hay columna `is_own`), así que
    /// con solo el id la regla sería incomprobable aquí y tendría que vivir en el
    /// caso de uso, donde nada obliga a acordarse. Es el mismo movimiento que
    /// `Team.candidate(opponentClubName:)`.
    @Test("un equipo rival no se inscribe: aparece porque juega (D-68, D-27)")
    func anOpponentTeamCannotBeRegistered() throws {
        let opponent = try Self.team(opponentClubID: OpponentClubID(raw: UUID()))

        #expect(throws: DomainError.invalidValue(
            field: "teamId",
            reason: "un equipo rival no se inscribe: aparece porque juega"
        )) {
            try TeamRegistration(
                id: TeamRegistrationID(raw: UUID()),
                team: opponent,
                seasonID: SeasonID(raw: UUID()),
                createdAt: Date(),
                updatedAt: Date()
            )
        }
    }
}

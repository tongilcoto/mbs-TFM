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
    /// `Team.candidate(opponentClubName:ownCode:)`.
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

    // ── D-101 · el código de la federación es de la inscripción ─────────────

    static func registration(
        competitionID: CompetitionID? = CompetitionID(raw: UUID()),
        federationTeamID: String? = nil
    ) throws -> TeamRegistration {
        try TeamRegistration(
            id: TeamRegistrationID(raw: UUID()),
            team: try Self.team(),
            seasonID: SeasonID(raw: UUID()),
            competitionID: competitionID,
            federationTeamID: federationTeamID,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// El número de la federación es la **plaza** del club en una división, no
    /// su «Juvenil A» ([Anexo FCF §C.13]): por eso va en la fila de cada
    /// competición y no en el equipo (`D-101`).
    @Test("la inscripción en una competición lleva el código del equipo en ella (D-101)")
    func theRegistrationCarriesTheFederationCode() throws {
        let registration = try Self.registration(federationTeamID: "33712")

        #expect(registration.federationTeamID == "33712")
    }

    /// La fila de junio no tiene competición, así que no hay grupo donde ese
    /// código signifique algo. El `CHECK` del esquema dice lo mismo.
    @Test("la fila de junio, sin competición, no lleva código (D-101)")
    func theJuneRowCannotCarryACode() throws {
        #expect(throws: DomainError.self) {
            try Self.registration(competitionID: nil, federationTeamID: "33712")
        }
    }

    // ── C-A.2 · enganchar es una transición, no un `merging` (D-67, D-101) ───

    /// El camino feliz de `D-67`: la inscripción de esa competición, sin código
    /// todavía, recibe el que el administrador eligió en el `/preview`.
    @Test("la inscripción sin enganchar recibe su código (D-67, D-101)")
    func anUnlinkedRegistrationTakesItsFederationCode() throws {
        let registration = try Self.registration()

        let linked = try registration.linked(toFederationTeamID: "3349086")

        #expect(linked.federationTeamID == "3349086")
        #expect(linked.id == registration.id)
    }

    /// **Por qué esto no es `merging`.** La ingesta calla ante un código
    /// distinto (`D-76`); el enganche es un administrador afirmando *"este es mi
    /// equipo"*, y callar le devolvería un `202` mientras la inscripción se queda
    /// con otro código. **Dentro de la misma competición**, otro código se para.
    @Test("en la misma competición, otro código no se re-engancha: se para (D-67, D-101)")
    func aRegistrationAlreadyLinkedElsewhereRefuses() throws {
        let registration = try Self.registration(federationTeamID: "33710")

        #expect(throws: DomainError.alreadyLinkedToFederation(
            existing: "33710", incoming: "33712"
        )) {
            try registration.linked(toFederationTeamID: "33712")
        }
    }

    /// Reenviar lo que ya hay es idempotente: es lo que hace seguro reintentar
    /// el `202`.
    @Test("re-enganchar con el mismo código es idempotente (D-67)")
    func relinkingWithTheSameCodeIsIdempotent() throws {
        let registration = try Self.registration(federationTeamID: "3349086")

        let relinked = try registration.linked(toFederationTeamID: "3349086")

        #expect(relinked == registration)
    }

    /// La fila de junio no se engancha: primero se completa con su competición,
    /// que es lo que hace la cascada.
    @Test("la fila de junio no se engancha sin competición (D-101)")
    func theJuneRowCannotBeLinked() throws {
        let registration = try Self.registration(competitionID: nil)

        #expect(throws: DomainError.self) {
            try registration.linked(toFederationTeamID: "3349086")
        }
    }
}

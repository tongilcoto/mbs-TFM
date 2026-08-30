import Foundation
import Testing

@testable import Domain

/// Nivel 1 (§8.1): el equipo, su política de *upsert* y su proyección a la
/// cadena de §3.7.
@Suite("Team · §3.7 · la excepción de D-66 y lo que la ingesta no puede tocar")
struct TeamTests {

    static func team(
        opponentClubID: OpponentClubID? = nil,
        category: TeamCategory = .cadete,
        letter: String? = "A",
        gender: Gender = .masculino,
        modality: Modality = .futbol11,
        federationTeamID: String? = nil
    ) throws -> Team {
        try Team(
            id: TeamID(raw: UUID()),
            opponentClubID: opponentClubID,
            category: category,
            letter: letter,
            gender: gender,
            modality: modality,
            federationTeamID: federationTeamID,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // ── De propiedad: la ingesta no reasigna el club (§3.7, D-20) ────────────

    /// §3.7, clase **de propiedad**: `opponent_club_id` es del BFF. El caso que
    /// esta regla existe para impedir es exacto: el administrador reclama un
    /// equipo con `/ownership` —pasa a propio, `opponentClubID` nulo— y **la
    /// pasada del lunes lo devuelve a rival**, porque la federación sigue
    /// diciendo que ese `codigo_equipo` pertenece a ese club.
    @Test("la ingesta no devuelve a rival un equipo ya reclamado (§3.7, D-20)")
    func ownershipIsNeverReassigned() throws {
        let claimed = try Self.team(opponentClubID: nil, federationTeamID: "821")

        let merged = try claimed.merging(
            opponentClubID: OpponentClubID(raw: UUID()), federationTeamID: nil)

        #expect(merged.opponentClubID == nil)
        #expect(merged.isOwn)
    }

    /// El reverso, y no es simétrico con `D-76`: aquí un `nil` **no es un
    /// hueco**, es una decisión del administrador. `UpsertPolicy.owned` devuelve
    /// `existing` aunque sea nulo, justo por esto.
    @Test("tampoco reasigna a un rival el club que la fuente diga (§3.7, D-20)")
    func opponentIsNeverMovedToAnotherClub() throws {
        let celtic = OpponentClubID(raw: UUID())
        let stored = try Self.team(opponentClubID: celtic, federationTeamID: "821")

        let merged = try stored.merging(
            opponentClubID: OpponentClubID(raw: UUID()), federationTeamID: nil)

        #expect(merged.opponentClubID == celtic)
    }

    // ── De emparejamiento (§3.7, D-76) ──────────────────────────────────────

    /// Misma regla que en `OpponentClub`, y hace falta aquí también porque son
    /// dos claves distintas: `federation_team_id` es el **equipo**
    /// (`codigo_equipo`) y `federation_club_id` es el **club**. El mismo club
    /// tiene un código distinto en cada categoría (§3.7).
    @Test("un codigo_equipo distinto no reescribe el que ya emparejaba (§3.7)")
    func federationTeamKeyIsNotOverwritten() throws {
        let matched = try Self.team(federationTeamID: "821")

        let merged = try matched.merging(opponentClubID: nil, federationTeamID: "304468")

        #expect(merged.federationTeamID == "821")
    }

    /// `D-76` en el sitio donde más importa: es exactamente lo que le pasa a un
    /// equipo **propio** entre que el club lo crea (`D-66`) y el administrador lo
    /// engancha (`D-67`). Nace sin clave; la recibe.
    @Test("un equipo sin codigo_equipo lo recibe cuando la fuente lo publica (D-76)")
    func federationTeamKeyFillsTheGap() throws {
        let unlinked = try Self.team(federationTeamID: nil)

        let merged = try unlinked.merging(opponentClubID: nil, federationTeamID: "821")

        #expect(merged.federationTeamID == "821")
    }

    // ── Proyección a la cadena de §3.7 (Plan §4.6) ──────────────────────────

    /// El "mapeo trivial pero deliberado" que Plan §4.6 dejó de deber a F5: la
    /// entidad se proyecta al candidato, que lleva **solo claves de
    /// emparejamiento**. Un rival se proyecta con el nombre de su club, que es
    /// lo que el paso 2 compara.
    @Test("un equipo rival se proyecta con el nombre de su club (§3.7, paso 2)")
    func opponentProjectsWithItsClubName() throws {
        let team = try Self.team(opponentClubID: OpponentClubID(raw: UUID()))

        let candidate = try team.candidate(
            opponentClubName: NormalizedName("CELTIC CASTILLA C.F."))

        // Las dos grafías —la de la fuente y la que corregiría el
        // administrador— dan la misma clave. Eso es `NormalizedName`, y se
        // apoya aquí para que la aserción no dependa de cómo normaliza.
        #expect(candidate.ownership == .opponent(clubName: NormalizedName("Celtic Castilla C.F.")))
    }

    /// La frontera de `D-66`/`D-76` hecha tipo: `.own` **no lleva nombre de
    /// club**, así que el paso 2 no puede alcanzar a un equipo propio sin
    /// enganchar. Aquí solo se comprueba que la proyección lo produce.
    @Test("un equipo propio se proyecta sin nombre de club (D-66, D-76)")
    func ownTeamProjectsAsOwn() throws {
        let team = try Self.team(opponentClubID: nil)

        let candidate = try team.candidate(opponentClubName: nil)

        #expect(candidate.ownership == .own)
    }

    /// Y el caso que **no** puede degradar en silencio: un rival cuyo club no
    /// aparece. Proyectarlo a `.own` lo escondería del paso 2 y la ingesta
    /// **daría de alta un duplicado**, que es peor que parar.
    @Test("un rival sin el nombre de su club no se proyecta: se para (§3.7)")
    func opponentWithoutClubNameThrows() throws {
        let team = try Self.team(opponentClubID: OpponentClubID(raw: UUID()))

        #expect(throws: DomainError.self) {
            try team.candidate(opponentClubName: nil)
        }
    }
}

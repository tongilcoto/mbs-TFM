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

    // ── C-A.2 · enganchar es una transición, no un `merging` (D-67) ──────────

    /// El camino feliz de `D-67`, y el único estado desde el que sale: el equipo
    /// que el club creó **sin ningún dato de federación** —el que `seed-team`
    /// siembra— recibe su `codigo_equipo`.
    @Test("el equipo sin enganchar recibe su código (D-67)")
    func anUnlinkedTeamTakesItsFederationCode() throws {
        let team = try Self.team(federationTeamID: nil)

        let linked = try team.linked(toFederationTeamID: "3349086")

        #expect(linked.federationTeamID == "3349086")
        #expect(linked.id == team.id)
    }

    /// **Por qué esto no puede ser `merging`, que es la regla de este ciclo.**
    ///
    /// `UpsertPolicy.matching` rellena hueco y **calla** cuando ya hay valor
    /// (`D-76`), que es exactamente lo que la ingesta necesita: un `codigo_equipo`
    /// distinto llegando en la pasada del lunes no debe pisar el que ya está. Pero
    /// el enganche **no es la ingesta**: es un administrador afirmando *"este es
    /// mi equipo"*, y callar ahí le devolvería un `202` mientras el equipo se
    /// queda enganchado a otro sitio. La ingesta no puede fallar por un dato de
    /// la fuente; el enganche **tiene** que fallar por un dato del usuario.
    @Test("un equipo ya enganchado a otro código no se re-engancha: se para (D-67)")
    func aTeamAlreadyLinkedElsewhereRefuses() throws {
        let team = try Self.team(federationTeamID: "821")

        #expect(throws: DomainError.alreadyLinkedToFederation(
            existing: "821", incoming: "3349086"
        )) {
            try team.linked(toFederationTeamID: "3349086")
        }
    }

    /// **Y el mismo código NO es conflicto, que es la mitad que se olvida.**
    ///
    /// El enganche es **aditivo**: un equipo juega liga *y* copa (`D-12`), así que
    /// se engancha una vez por competición — y su `codigo_equipo` identifica al
    /// **equipo**, no a la competición (§3.7), de modo que el segundo enganche
    /// llega con el mismo valor. Tratarlo como 409 dejaría la copa inenganchable.
    ///
    /// Mismo criterio que `Competition.requireUnchanged`: reenviar lo que ya hay
    /// es idempotente, no un conflicto.
    @Test("re-enganchar con el mismo código es idempotente: la copa se engancha aparte (D-12)")
    func relinkingWithTheSameCodeIsIdempotent() throws {
        let team = try Self.team(federationTeamID: "3349086")

        let relinked = try team.linked(toFederationTeamID: "3349086")

        #expect(relinked.federationTeamID == "3349086")
    }

    // ── C-A.3 · la identidad tiene que cuadrar (D-66, D-58) ──────────────────

    static func scope(
        ageCategory: TeamCategory = .cadete,
        gender: Gender = .masculino,
        modality: Modality = .futbol11
    ) -> CompetitionScope {
        CompetitionScope(ageCategory: ageCategory, gender: gender, modality: modality)
    }

    /// El caso feliz: la competición propone lo mismo que el equipo tiene
    /// congelado desde su alta, así que confirmar el enganche es seguro.
    @Test("si la competición dice lo mismo que el equipo tiene congelado, cuadra (D-66)")
    func identityMatchesWhenTheCompetitionAgrees() throws {
        let team = try Self.team(category: .cadete, gender: .masculino, modality: .futbol11)

        #expect(team.identityMatches(Self.scope()))
    }

    /// **La tercera pieza de la terna, y la que faltaba** (§3.2, `D-58`).
    ///
    /// §3.2 declara `age_category` *"mismo enumerado que `Team.category`* → permite
    /// **validar** que un equipo solo participe en una competición de su edad, **de
    /// su modalidad y de su género**", y `D-58` lo repite: *"la validación se amplía
    /// por tercera vez"*. La cadena de emparejamiento de la ingesta **ya filtraba
    /// por las tres** (`MatchingChain.swift:101-107`, con este mismo
    /// `CompetitionScope`); lo que no lo hacía era la puerta del enganche, que es
    /// donde un humano afirma la correspondencia a mano.
    ///
    /// **Lo que pasaba sin esto**: enganchar el Cadete A a una competición
    /// **juvenil** cuadraba, se confirmaba, y la ingesta heredaba `juvenil` a cada
    /// equipo que creara desde ella (`D-07`). Con `category` también en la clave
    /// única (§3.5), el choque llega después y en otro sitio — que es el peor de
    /// los finales y el que `D-58` describe como *"no degrada, colisiona"*.
    @Test("una categoría de edad distinta de la congelada no cuadra (§3.2, D-58)")
    func identityDoesNotMatchOnAgeCategory() throws {
        let team = try Self.team(category: .cadete, gender: .masculino, modality: .futbol11)

        #expect(!team.identityMatches(Self.scope(ageCategory: .juvenil)))
    }

    /// **El caso que `D-58` existe para atrapar, y por eso el género va primero.**
    ///
    /// La federación **no publica el género como campo**: lo embebe en el nombre
    /// de la competición, así que el `/preview` lo **infiere y lo propone**
    /// (`C-A.7`). Una inferencia equivocada —el anexo avisa de que el truncado a
    /// 40 caracteres puede comerse el marcador `FEMENINO` sin dar error— haría
    /// que el equipo femenino se enganchara a la competición masculina. Esto es
    /// lo que se lo dice al administrador **antes** de confirmar, en vez de
    /// dejarle chocar con el 409.
    @Test("un género distinto del congelado no cuadra (D-66, D-58)")
    func identityDoesNotMatchOnGender() throws {
        let team = try Self.team(gender: .femenino, modality: .futbol11)

        #expect(!team.identityMatches(Self.scope(gender: .masculino)))
    }

    /// Y la modalidad, que es el otro campo congelado de la pareja (§3.5): el
    /// "Infantil A" de fútbol-11 y el de fútbol-sala son equipos **distintos**,
    /// no el mismo equipo con otro rótulo.
    @Test("una modalidad distinta de la congelada tampoco cuadra (D-66, §3.5)")
    func identityDoesNotMatchOnModality() throws {
        let team = try Self.team(gender: .masculino, modality: .futbolSala)

        #expect(!team.identityMatches(Self.scope(modality: .futbol11)))
    }
}

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
        let claimed = try Self.team(opponentClubID: nil)

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
        let matched = try Self.team(
            opponentClubID: OpponentClubID(raw: UUID()), federationTeamID: "821")

        let merged = try matched.merging(opponentClubID: nil, federationTeamID: "304468")

        #expect(merged.federationTeamID == "821")
    }

    /// `D-76`: un rival que nació sin código —la fuente no lo publicó esa vez—
    /// lo recibe en cuanto la fuente lo publica.
    @Test("un rival sin codigo_equipo lo recibe cuando la fuente lo publica (D-76)")
    func federationTeamKeyFillsTheGap() throws {
        let unlinked = try Self.team(
            opponentClubID: OpponentClubID(raw: UUID()), federationTeamID: nil)

        let merged = try unlinked.merging(opponentClubID: nil, federationTeamID: "821")

        #expect(merged.federationTeamID == "821")
    }

    /// **Y a un equipo propio no se lo escribe nunca** (`D-101`). Su código es
    /// el de su inscripción en cada competición: el «Juvenil A» puede ser el
    /// `33710` un año y el `33712` el siguiente ([Anexo FCF §C.13]). Si la
    /// pasada se lo pegara al equipo, la temporada siguiente no casaría.
    @Test("la ingesta no le escribe código a un equipo propio (D-101)")
    func anOwnTeamNeverTakesTheIncomingCode() throws {
        let own = try Self.team(opponentClubID: nil)

        let merged = try own.merging(opponentClubID: nil, federationTeamID: "821")

        #expect(merged.federationTeamID == nil)
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
            opponentClubName: NormalizedName("CELTIC CASTILLA C.F."), ownCode: nil)

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

        let candidate = try team.candidate(opponentClubName: nil, ownCode: nil)

        #expect(candidate.ownership == .own)
    }

    /// **El código del propio llega de fuera**, de su inscripción en la
    /// competición que se está pasando (`D-101`): es lo que el paso 1 de la
    /// cadena compara.
    @Test("un equipo propio se proyecta con el código de su inscripción (D-101)")
    func ownTeamProjectsWithItsRegistrationCode() throws {
        let team = try Self.team(opponentClubID: nil)

        let candidate = try team.candidate(opponentClubName: nil, ownCode: "33712")

        #expect(candidate.federationTeamID == "33712")
    }

    /// Un rival no tiene inscripción (`D-68`): su código es el suyo. Pasarle
    /// otro es un error del llamante, y se para en vez de elegir uno.
    @Test("a un rival no se le pasa código de inscripción: se para (D-101)")
    func opponentRefusesARegistrationCode() throws {
        let team = try Self.team(
            opponentClubID: OpponentClubID(raw: UUID()), federationTeamID: "821")

        #expect(throws: DomainError.self) {
            try team.candidate(
                opponentClubName: NormalizedName("CELTIC CASTILLA C.F."), ownCode: "33712")
        }
    }

    /// Y el caso que **no** puede degradar en silencio: un rival cuyo club no
    /// aparece. Proyectarlo a `.own` lo escondería del paso 2 y la ingesta
    /// **daría de alta un duplicado**, que es peor que parar.
    @Test("un rival sin el nombre de su club no se proyecta: se para (§3.7)")
    func opponentWithoutClubNameThrows() throws {
        let team = try Self.team(opponentClubID: OpponentClubID(raw: UUID()))

        #expect(throws: DomainError.self) {
            try team.candidate(opponentClubName: nil, ownCode: nil)
        }
    }

    // ── D-101 · un equipo propio no lleva código ────────────────────────────

    /// El código del equipo propio es de su **inscripción** en cada competición
    /// (`D-101`), y el enganche ya no lo escribe aquí. Que un propio lo lleve es
    /// el modelo de antes, y el `CHECK` del esquema dice lo mismo.
    @Test("un equipo propio con código de federación no existe (D-101)")
    func anOwnTeamWithAFederationCodeIsInvalid() throws {
        #expect(throws: DomainError.self) {
            try Self.team(opponentClubID: nil, federationTeamID: "821")
        }
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

    // ── C-C.15 · la misma regla, negándose (D-58, §3.2) ─────────────────────

    /// **La guarda vive junto al dato que protege**, no en quien la invoca
    /// —mismo idioma que `Competition.requireSameSource` y
    /// `Season.requireOwnsCalendar`—. Con solo el predicado, la negativa vivía
    /// en el caso de uso, y la siguiente puerta que afirme esta correspondencia
    /// a mano —`POST /teams` + `PUT /registrations`, del backoffice, que sigue
    /// sin fase— tendría que acordarse de volver a escribirla.
    ///
    /// El error lleva **las dos ternas enteras** porque quien lo lee es un
    /// administrador mirando dos rótulos: con los dos lados delante no hace
    /// falta un campo que diga cuál de los tres falla.
    @Test("la guarda dice las dos ternas, no cuál de las tres falla (D-58, C-C.15)")
    func requiringTheIdentityNamesBothSides() throws {
        let team = try Self.team(category: .cadete, gender: .masculino, modality: .futbol11)

        #expect(throws: DomainError.competitionIdentityMismatch(
            team: "cadete/masculino/futbol_11",
            competition: "juvenil/masculino/futbol_11")) {
            try team.requireIdentityMatches(Self.scope(ageCategory: .juvenil))
        }
    }

    /// Y la otra mitad de toda guarda, que es la que impide que un *"no"* fijo
    /// pase por regla (lección de `M6`, Bloque B): lo que sí cuadra, pasa.
    @Test("y lo que cuadra no se rechaza (D-66, C-C.15)")
    func requiringTheIdentityLetsAMatchThrough() throws {
        let team = try Self.team(category: .cadete, gender: .masculino, modality: .futbol11)

        #expect(throws: Never.self) {
            try team.requireIdentityMatches(Self.scope())
        }
    }
}

public import struct Foundation.Date

/// El partido (§3.2). **Raíz de agregado** (§4.2) y el sitio del que cuelga todo
/// el dominio manual: `Goal`, `Card` y `Appearance` referencian su `id`.
///
/// Es **salida de la ingesta**: no tiene `POST`, no tiene `DELETE` y **tampoco
/// `PATCH`** (§5.1). Esa última es la que hace que equivocarse aquí no se pueda
/// corregir a mano, y por eso `D-75` decide como decide.
public struct Match: Identifiable, Equatable, Sendable {
    public let id: MatchID

    /// Se guarda aunque `Round` ya la fije, porque es la FK por la que se
    /// consulta. **La clave única de §3.5 no la lleva**, justamente por eso.
    public let competitionID: CompetitionID

    /// **Volátil**: un partido reubicado cambia de jornada y hay que seguirlo,
    /// no duplicarlo (`D-31`).
    public let roundID: RoundID

    /// Fecha y hora, separadas (`D-30`). El VO es de F3.
    public let kickoff: Kickoff

    // Identidad, junto con `roundID`: son la clave del paso 2 de la cadena
    // (§3.5, §3.7). **No se fusionan**.
    public let homeTeamID: TeamID
    public let awayTeamID: TeamID

    /// `nil` ⇒ no se ha jugado, o la fuente no lo dijo — que a efectos de
    /// escritura es lo mismo (`D-56`).
    public let result: MatchResult?

    public let status: MatchStatus

    /// Texto libre (§3.2): el modelo no tiene entidad de campo de juego, aunque
    /// la fuente publique un `codigo_campo` (Plan §7.4).
    public let venue: String?

    /// El `codacta` de la RFFM. **Anulable y no exigible** (`D-31`): es un campo
    /// de un proveedor y no del contrato genérico de federación, y puede faltar
    /// incluso dentro de la RFFM en una respuesta parcial.
    ///
    /// El motivo que esta línea daba —*"la FCF no publica identificador de
    /// partido en absoluto"*— **caducó con `D-74`**: su web nueva lo trae en 240
    /// de 240 ([Anexo FCF §C.10.4]). La anulabilidad no cambia; su defensa sí.
    public let federationMatchID: String?

    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: MatchID,
        competitionID: CompetitionID,
        roundID: RoundID,
        kickoff: Kickoff,
        homeTeamID: TeamID,
        awayTeamID: TeamID,
        result: MatchResult? = nil,
        status: MatchStatus,
        venue: String? = nil,
        federationMatchID: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        guard homeTeamID != awayTeamID else {
            throw DomainError.invalidValue(
                field: "awayTeamID", reason: "un equipo no juega contra sí mismo"
            )
        }

        self.id = id
        self.competitionID = competitionID
        self.roundID = roundID
        self.kickoff = kickoff
        self.homeTeamID = homeTeamID
        self.awayTeamID = awayTeamID
        self.result = result
        self.status = status
        self.venue = venue
        self.federationMatchID = federationMatchID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// **Derivado, no almacenado** (`D-30`): `kickoff_time` no nulo.
    public var isKickoffConfirmed: Bool { kickoff.isConfirmed }

    /// La proyección al candidato de la cadena de §3.7 (F4).
    ///
    /// **Deja fuera la fecha y la hora**, que es media regla de §3.7 hecha tipo:
    /// `MatchCandidate` no tiene dónde ponerlas. Aquí eso se ve como lo que es —
    /// una proyección que se queda con cuatro campos de diez.
    public var candidate: MatchCandidate {
        MatchCandidate(
            id: id,
            federationMatchID: federationMatchID,
            roundID: roundID,
            homeTeamID: homeTeamID,
            awayTeamID: awayTeamID
        )
    }
}

extension Match {
    /// El *upsert* del partido (§3.7). Es la entidad con más campos de la fase y
    /// **la única sin `PATCH`**, así que aquí no hay red de seguridad manual.
    ///
    /// | Campo | Clase | Qué hace |
    /// |---|---|---|
    /// | `roundID`, `result`, `venue`, `kickoff` | **volátil** | la fuente gana cuando dice algo (`D-56`) |
    /// | `status` | **derivado** | del marcador **ya fusionado** (`D-57`) |
    /// | `federationMatchID` | **de emparejamiento** | no sobrescribe; rellena hueco (`D-76`) |
    /// | `homeTeamID`, `awayTeamID`, `competitionID` | **identidad** | no están en la firma |
    ///
    /// `roundID` es volátil y no identidad, aunque entre en la clave única de
    /// §3.5: un partido reubicado se reconoce por su `codacta` y **cambia de
    /// jornada** (`D-31`). Si fuese inmutable, la alternativa sería duplicarlo.
    public func merging(
        roundID incomingRoundID: RoundID?,
        date: Date?,
        time: WallClockTime?,
        result incomingResult: MatchResult?,
        venue incomingVenue: String?,
        federationMatchID incomingFederationMatchID: String?
    ) throws -> Match {
        // Se calcula **una vez** y se reparte, en vez de recalcularlo en cada
        // sitio que lo necesita: `Kickoff` y `MatchStatus` tienen que ver el
        // mismo marcador o `D-56` y `D-57` pueden discrepar sobre si el partido
        // se jugó. `Kickoff.merging` lo vuelve a fusionar por dentro con los dos
        // que recibe, que es su firma de F3 y no se toca.
        let mergedResult = UpsertPolicy.volatile(existing: result, incoming: incomingResult)

        return try Match(
            id: id,
            competitionID: competitionID,
            roundID: incomingRoundID ?? roundID,
            kickoff: kickoff.merging(
                date: date, time: time,
                existingResult: result, incomingResult: incomingResult),
            homeTeamID: homeTeamID,
            awayTeamID: awayTeamID,
            result: mergedResult,
            status: MatchStatus.derived(from: mergedResult),
            venue: UpsertPolicy.volatile(existing: venue, incoming: incomingVenue),
            federationMatchID: UpsertPolicy.matching(
                existing: federationMatchID, incoming: incomingFederationMatchID),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

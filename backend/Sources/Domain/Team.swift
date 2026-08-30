public import struct Foundation.Date

/// El equipo (§3.2). **La excepción deliberada del modelo** (`D-66`): es la única
/// entidad tocada por la ingesta que el club también puede crear, porque el club
/// forma el equipo, lo inscribe, y **solo entonces** la federación publica
/// calendario. La federación es fuente de verdad del *calendario*, no del
/// *equipo*.
public struct Team: Identifiable, Equatable, Sendable {
    public let id: TeamID

    /// **Nulo ⇒ equipo propio** (§3.6, `D-03`). No hay columna `is_own`: se
    /// deriva.
    ///
    /// Es campo **de propiedad** (§3.7): lo escribe el BFF por `/ownership`
    /// (`D-20`) y la ingesta no lo toca jamás en un UPDATE — si no, la primera
    /// sincronización tras reclamar un equipo lo devolvería a rival.
    public let opponentClubID: OpponentClubID?

    // ── Identidad (§3.5) ─────────────────────────────────────────────────────
    // Las cuatro forman la clave única junto con `opponentClubID`, y **ninguna
    // es parámetro de `merging`**: son de alta y nunca del `PATCH` (`D-66`,
    // `D-58`). Cuando el equipo lo crea la ingesta, las tres últimas las hereda
    // de la `Competition` (`D-07`, `D-58`).

    public let category: TeamCategory
    /// Lo que distingue el "Infantil A" del "Infantil B" del mismo club
    /// (`D-77`). Opcional: hay clubes sin filial, y ese `nil` **es un valor**
    /// —«el único equipo»—, por eso la clave se declara `NULLS NOT DISTINCT`.
    public let letter: String?
    public let gender: Gender
    public let modality: Modality

    /// El `codigo_equipo` de la federación: identifica al **equipo**, no al club
    /// (§3.7). **Anulable**: un equipo vive sin él desde que el club lo crea
    /// hasta que se engancha (`D-66`, `D-67`).
    public let federationTeamID: String?

    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: TeamID,
        opponentClubID: OpponentClubID? = nil,
        category: TeamCategory,
        letter: String? = nil,
        gender: Gender,
        modality: Modality,
        federationTeamID: String? = nil,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        if let letter, letter.trimmed.isEmpty {
            throw DomainError.invalidValue(
                field: "letter",
                reason: "la letra es opcional, pero si viene no puede estar en blanco"
            )
        }

        self.id = id
        self.opponentClubID = opponentClubID
        self.category = category
        self.letter = letter
        self.gender = gender
        self.modality = modality
        self.federationTeamID = federationTeamID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// **Derivado, no almacenado** (§3.6, `D-03`).
    public var isOwn: Bool { opponentClubID == nil }

    /// La proyección al candidato de la cadena de §3.7 (F4).
    ///
    /// # Por qué pide el nombre del club por fuera
    ///
    /// El paso 2 compara el **nombre del club**, y `Team` no lo tiene: lo tiene
    /// su `OpponentClub` (§3.6). Quien las junta es el caso de uso, que ha
    /// cargado las dos listas.
    ///
    /// # Y por qué lanza en vez de degradar a `.own`
    ///
    /// Porque `.own` **es inalcanzable para el paso 2** por diseño (`D-76`): si
    /// un equipo rival se proyectara a `.own` por no haber encontrado su nombre,
    /// la cadena no lo reconocería y la ingesta **daría de alta un duplicado**.
    /// Es el peor final posible de los tres, y es silencioso. Un equipo rival
    /// cuyo club no aparece en la lista es corrupción de datos, no un caso de
    /// negocio, y se para.
    public func candidate(opponentClubName: NormalizedName?) throws -> TeamCandidate {
        let ownership: TeamOwnership
        switch (opponentClubID, opponentClubName) {
        case (nil, _):
            ownership = .own
        case (_?, let name?):
            ownership = .opponent(clubName: name)
        case (_?, nil):
            throw DomainError.invalidValue(
                field: "opponentClubName",
                reason: "un equipo rival no se puede proyectar sin el nombre de su club"
            )
        }

        return TeamCandidate(
            id: id,
            federationTeamID: federationTeamID,
            ownership: ownership,
            category: category,
            letter: letter,
            gender: gender,
            modality: modality
        )
    }
}

extension Team {
    /// El *upsert* del equipo (§3.7), y son solo dos campos.
    ///
    /// | Campo | Clase | Qué hace |
    /// |---|---|---|
    /// | `opponentClubID` | **de propiedad** | la ingesta no lo toca **nunca** (`D-20`) |
    /// | `federationTeamID` | **de emparejamiento** | no sobrescribe; rellena hueco (`D-76`) |
    ///
    /// Los otros cuatro —`category`, `letter`, `gender`, `modality`— **no están
    /// en la firma** porque son identidad (§3.5): no se fusionan, se empareja
    /// **por** ellos. Un equipo que cambiara de categoría no es el mismo equipo.
    public func merging(
        opponentClubID incomingOpponentClubID: OpponentClubID?,
        federationTeamID incomingFederationTeamID: String?
    ) throws -> Team {
        try Team(
            id: id,
            opponentClubID: UpsertPolicy.owned(
                existing: opponentClubID, incoming: incomingOpponentClubID),
            category: category,
            letter: letter,
            gender: gender,
            modality: modality,
            federationTeamID: UpsertPolicy.matching(
                existing: federationTeamID, incoming: incomingFederationTeamID),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

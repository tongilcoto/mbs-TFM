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

    /// **¿La competición dice lo mismo que este equipo tiene congelado?**
    /// (`D-66`, `D-58`).
    ///
    /// # Por qué es una pregunta y no una guarda que lanza
    ///
    /// Porque el que la hace primero es el `/preview`, que **no persiste nada**:
    /// su trabajo es que el administrador vea el desajuste **antes** de
    /// confirmar, y entonces enganche otro equipo o corrija el género propuesto.
    /// Un `throw` aquí no dejaría enseñar la pantalla. Quien convierte el `false`
    /// en **409** es la confirmación, que es el momento en que sí hay algo que
    /// impedir.
    ///
    /// # Las TRES, y son las tres que la competición presta
    ///
    /// §3.2 declara `age_category` como *"mismo enumerado que `Team.category`* →
    /// permite **validar** que un equipo solo participe en una competición de su
    /// edad, **de su modalidad y de su género**", y `D-58` lo remacha: *"la
    /// validación se amplía por tercera vez"*. Son exactamente las tres piezas de
    /// la clave única de §3.5 que la fuente **no publica por equipo** y que el
    /// equipo hereda de la competición (`D-07`, `D-58`) — por eso son las tres
    /// que pueden acabar contradiciendo a un equipo propio ya existente.
    ///
    /// `letter` es la cuarta pieza de la clave y **no** entra aquí: no se hereda
    /// de nada, la trae el propio equipo dentro del grupo, y es precisamente lo
    /// que el administrador elige al reconocer su club en `teams[]`.
    ///
    /// # La enmienda, y por qué la edad faltaba
    ///
    /// Este método nació comparando dos, siguiendo al *spec* — que declaraba
    /// `identityMatches` como *"el `gender` y la `modality`"*—. **El `spec` era lo
    /// que estaba corto, no la decisión**: `D-58` y §3.2 dicen tres desde el
    /// principio, y la cadena de emparejamiento de la ingesta ya filtraba por las
    /// tres con **este mismo `CompetitionScope`** (`MatchingChain`, paso 2). Lo
    /// que no lo hacía era la puerta del enganche, que es donde un humano afirma
    /// la correspondencia a mano.
    ///
    /// Sin la edad, enganchar el Cadete A a una competición **juvenil** cuadraba,
    /// se confirmaba, y la ingesta heredaba `juvenil` a cada equipo que creara
    /// desde ella. Con `category` también en la clave única, el choque llega
    /// después y en otro sitio: *"un error aquí no da un dato feo, da un 409"*.
    ///
    /// # Toma el `scope` y no una `Competition`, a propósito
    ///
    /// En el `/preview` **todavía no hay competición**: puede que se cree en la
    /// cascada. Lo que hay son los tres valores que la fuente propone, y uno de
    /// ellos —el género— es literalmente una **inferencia** sobre el nombre
    /// (`C-A.7`). Pedir la entidad obligaría a fabricar una para preguntar. Y
    /// `CompetitionScope` ya existía para decir justo esto: *"lo que la
    /// `Competition` le presta al equipo para identificarlo"*.
    public func identityMatches(_ scope: CompetitionScope) -> Bool {
        category == scope.ageCategory
            && gender == scope.gender
            && modality == scope.modality
    }

    /// **La misma regla, pero negándose** (`C-C.15`, `D-58`, §3.2).
    ///
    /// # Por qué hacen falta las dos formas
    ///
    /// Las dos puertas del enganche preguntan lo mismo y hacen cosas distintas:
    /// el `/preview` quiere el **veredicto** para enseñarlo —`identityMatches`
    /// viaja en su respuesta (`C-C.4`)— y el enganche tiene que **pararse**. Con
    /// solo el predicado, la negativa vivía en el caso de uso y la siguiente
    /// puerta que afirme esta correspondencia a mano —`POST /teams` +
    /// `PUT /registrations`, del backoffice, que sigue sin fase— tendría que
    /// acordarse de escribirla otra vez.
    ///
    /// Es el mismo idioma que `Competition.requireSameSource` y
    /// `Season.requireOwnsCalendar`: **la guarda vive junto al dato que
    /// protege**, no en quien la invoca.
    ///
    /// # Y por qué el error lleva las dos ternas enteras
    ///
    /// Porque el que lo lee es un administrador mirando dos rótulos, no un
    /// programa: *"tu equipo es cadete y esta competición es juvenil"* se dice
    /// con los dos lados delante. Un campo que dijera **cuál** de los tres falla
    /// no haría falta — los tres valores ya están.
    public func requireIdentityMatches(_ scope: CompetitionScope) throws {
        guard !identityMatches(scope) else { return }
        throw DomainError.competitionIdentityMismatch(
            team: "\(category.rawValue)/\(gender.rawValue)/\(modality.rawValue)",
            competition: "\(scope.ageCategory.rawValue)/\(scope.gender.rawValue)/"
                + "\(scope.modality.rawValue)")
    }

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
    /// **El enganche de `D-67`: una transición, no una fusión.**
    ///
    /// # Por qué no es `merging`, que es la pregunta entera
    ///
    /// `federationTeamID` es campo **de emparejamiento** (§3.7) y su política es
    /// `UpsertPolicy.matching`: rellena hueco y **calla** cuando ya hay valor
    /// (`D-76`). Eso es lo correcto para la ingesta — un `codigo_equipo` distinto
    /// llegando en la pasada del lunes no puede pisar el que ya está — y es lo
    /// contrario de lo correcto aquí: el enganche no es la fuente hablando, es un
    /// **administrador afirmando** *"este es mi equipo"*. Callar le devolvería un
    /// `202` mientras el equipo se queda enganchado a otro sitio.
    ///
    /// La misma columna con dos escritores y dos reglas, que es lo que §5.1 llama
    /// la frontera de propiedad. De ahí que sea un método aparte y no un
    /// parámetro más de `merging`.
    ///
    /// # El mismo código no es conflicto
    ///
    /// El enganche es **aditivo**: un equipo juega liga *y* copa (`D-12`) y se
    /// engancha una vez por competición, pero su `codigo_equipo` identifica al
    /// **equipo** y no a la competición (§3.7) — así que el segundo enganche
    /// llega con el mismo valor. Rechazarlo dejaría la copa inenganchable. Mismo
    /// criterio que `Competition.requireUnchanged`: repetir lo que ya hay es
    /// idempotente.
    ///
    /// # Y no se llega aquí desde un equipo rival
    ///
    /// No hace falta comprobarlo: `D-66` fija `opponentClubID` como campo del
    /// BFF, y quien decide *qué* equipo se engancha es la ruta —desde la página
    /// del equipo propio—. Lo que sí se comprueba es lo que esta fila puede
    /// contradecir por sí sola.
    public func linked(toFederationTeamID incoming: String) throws -> Team {
        if let federationTeamID, federationTeamID != incoming {
            throw DomainError.alreadyLinkedToFederation(
                existing: federationTeamID, incoming: incoming)
        }

        return try Team(
            id: id,
            opponentClubID: opponentClubID,
            category: category,
            letter: letter,
            gender: gender,
            modality: modality,
            federationTeamID: incoming,
            createdAt: createdAt,
            updatedAt: updatedAt
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

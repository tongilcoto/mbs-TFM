/// La cadena de emparejamiento de §3.7, con degradación.
///
/// # Qué resuelve
///
/// La ingesta recibe filas de una fuente ajena y tiene que decidir, para cada
/// una, **a qué fila nuestra corresponde**. Las claves externas que lo harían
/// trivial son **anulables** (§3.7): el proveedor puede no publicarlas —la FCF
/// no tiene identificador de partido (`D-31`)— o nosotros podemos no lograr
/// extraerlas —el `federation_club_id` sale de *parsear el nombre de un fichero*
/// ([Anexo RFFM §F.4])—. Así que la cadena **degrada**, y cada escalón dice de sí
/// mismo si es exacto.
///
/// # Está en el Dominio, con `UpsertPolicy`
///
/// Las dos son §3.7 y las dos son puras. Decidir si dos filas son la misma
/// entidad es una regla de **identidad**, no de orquestación: cargar los
/// candidatos y escribir el resultado es de F5, y por eso aquí entran ya como
/// argumento. Es el dividendo de `D-01` otra vez — la regla más delicada del
/// diseño se prueba en milisegundos y sin contenedor.
///
/// # Los candidatos son tipos de aquí, no las entidades de F5
///
/// Y no es por adelantarse a F5: es porque llevan **solo las claves de
/// emparejamiento**. §3.7 dice *"ni la fecha ni la hora entran nunca en la
/// cadena"*; con un `Match` completo eso sería disciplina, y con
/// `MatchCandidate` —que no tiene fecha— es **estructural**: el fallo no se
/// puede escribir. Es el mismo argumento con el que `UpsertPolicy.descriptive`
/// declara un `incoming` que no usa.
public enum MatchingChain {

    // ── Clubes ───────────────────────────────────────────────────────────────

    /// La cadena de §3.7 para un **club rival**.
    ///
    /// Tres escalones: `federation_club_id`, nombre normalizado, alta nueva.
    ///
    /// **El paso 2 aquí es solo el nombre**, sin la categoría que sí lleva el de
    /// equipos, y no es una omisión: un club **no tiene** categoría —la tiene
    /// cada uno de sus equipos (§3.6)— y su nombre sí lo distingue de otro club.
    /// La trampa de §F.3 —*"casar por nombre habría fusionado dos equipos
    /// distintos"*— es de equipos, precisamente porque los dos equipos del Celtic
    /// Castilla comparten club.
    public static func opponentClub(
        _ incoming: IncomingOpponentClub,
        among candidates: [OpponentClubCandidate]
    ) -> MatchOutcome<OpponentClubID> {
        // Paso 1.
        if let matched = byFederationKey(incoming.federationClubID, among: candidates) {
            return .matched(matched, by: .federationKey)
        }

        // Paso 2. El *"si no"* de §3.7 es **"si el paso anterior no resolvió"**,
        // no *"si el dato no viene"*: con la segunda lectura, una fila que nació
        // sin clave no la recibiría jamás y `D-76` se quedaría sin un solo caso
        // en el que aplicarse.
        //
        // Y **no puede contradecir al paso 1**: si el candidato ya tiene clave y
        // es otra, la fuente dice que son dos clubes distintos. Solo entran los
        // que no tienen nada que contradecir, que es justo el conjunto al que
        // `D-76` quiere llegar.
        let byName = candidates.filter {
            $0.name == incoming.name
                && ($0.federationClubID == nil
                    || $0.federationClubID == incoming.federationClubID)
        }
        if let outcome = resolve(byName, by: .normalizedName) { return outcome }

        // Paso 3.
        return .unmatched
    }

    // ── Equipos ──────────────────────────────────────────────────────────────

    /// La cadena de §3.7 para un **equipo**.
    public static func team(
        _ incoming: IncomingTeam,
        in scope: CompetitionScope,
        among candidates: [TeamCandidate]
    ) -> MatchOutcome<TeamID> {
        // Paso 1. **Mira también a los equipos propios**, y es deliberado: el que
        // el administrador enganchó (`D-67`) tiene clave y hay que reconocerlo,
        // o cada pasada lo daría de alta como rival. Lo que el paso 2 no puede
        // hacer es alcanzar a los propios **sin** enganchar, y de eso se encarga
        // `TeamOwnership`, no una guarda.
        if let matched = byFederationKey(incoming.federationTeamID, among: candidates) {
            return .matched(matched, by: .federationKey)
        }

        // Paso 2: nombre del club más categoría **y letra**.
        //
        // La letra enmienda a §3.7, que se queda en *"nombre más categoría"*: sin
        // ella el "Infantil A" y el "Infantil B" del mismo club son
        // indistinguibles y la cadena devolvería `.ambiguous` para los dos.
        //
        // Y aquí `nil == nil` **sí** es lo correcto, al revés que con la clave de
        // federación de más arriba: un club sin filial no tiene letra, y eso es
        // un valor —«el único equipo»—, no un hueco. Es la misma distinción que
        // `D-76` hace entre un campo de propiedad y uno de emparejamiento: mismo
        // `nil`, dos lecturas opuestas. La letra está en la clave única de §3.5,
        // que además se declara `NULLS NOT DISTINCT` justo por esto.
        let byName = candidates.filter {
            $0.ownership == .opponent(clubName: incoming.clubName)
                && $0.category == scope.ageCategory
                && $0.letter == incoming.letter
                && $0.gender == scope.gender
                && $0.modality == scope.modality
        }
        if let outcome = resolve(byName, by: .normalizedName) { return outcome }

        return .unmatched
    }

    // ── Partidos ─────────────────────────────────────────────────────────────

    /// La cadena de §3.7 para un **partido**.
    public static func match(
        _ incoming: IncomingMatch,
        among candidates: [MatchCandidate]
    ) -> MatchOutcome<MatchID> {
        // Paso 1.
        if let matched = byFederationKey(incoming.federationMatchID, among: candidates) {
            return .matched(matched, by: .federationKey)
        }

        // Paso 2, y **aquí no se descarta al candidato cuya clave contradice**,
        // al revés que en la cadena de clubes. La asimetría es la de `D-31`: allí
        // el paso 2 es el nombre, **inexacto**, así que una clave distinta es
        // prueba en contra y se cede el sitio a la fusión (§9); aquí el paso 2
        // son FK internas y un índice único (§3.5), así que es **exacto** — una
        // clave distinta solo puede significar que la federación reemplazó el
        // acta. Descartarlo daría de alta un partido que el `UNIQUE(round_id,
        // home_team_id, away_team_id)` rechazaría de todas formas.
        let byCoordinates = candidates.filter {
            $0.roundID == incoming.roundID
                && $0.homeTeamID == incoming.homeTeamID
                && $0.awayTeamID == incoming.awayTeamID
        }
        if let outcome = resolve(byCoordinates, by: .coordinates) { return outcome }

        // No hay paso 3 (`D-31`): esto no es una degradación más, es un partido
        // que no habíamos visto.
        return .unmatched
    }
}

/// Un partido tal y como lo publica la fuente, reducido a sus claves.
///
/// **Sin fecha y sin hora, y ahí está media regla de §3.7**: *"ni la fecha ni la
/// hora entran nunca en la cadena: son el dato que cambia cada semana (`D-30`),
/// así que casar por fecha duplicaría el partido en cuanto se moviese"*. Con un
/// `Match` completo eso sería una advertencia en un comentario; aquí el dato no
/// existe, y el fallo no se puede escribir.
///
/// Los equipos llegan como `TeamID`, **ya emparejados**, y eso también es de
/// §3.7: *"los equipos ya están emparejados cuando se llega al partido"*. Es lo
/// que hace que el paso 2 sea exacto y que no haga falta un tercer escalón.
public struct IncomingMatch: Equatable, Sendable {
    /// `codacta` en la RFFM. **Anulable porque el contrato genérico de
    /// federación no lo garantiza** (`D-31`): es un campo de un proveedor, y
    /// hasta dentro de la propia RFFM puede faltar en una respuesta parcial.
    ///
    /// **Lo que ya no es cierto es el motivo que se citaba aquí.** Decía *"`nil`
    /// en la FCF, que no publica identificador de partido en absoluto"*, con
    /// [Anexo FCF §C.3] detrás — y esa sección describe el sitio **antiguo** y
    /// está obsoleta. La web nueva trae `CODACTA` en **240 de 240** partidos, no
    /// vacío y único, y hasta se llama igual que en Madrid
    /// ([Anexo FCF §C.10.4], `D-74`). Así que el paso 1 de esta cadena resuelve
    /// en las dos federaciones y el paso 2 es red de seguridad, no el camino
    /// normal de una de ellas. La anulabilidad se mantiene; su razón es la de
    /// arriba.
    public let federationMatchID: String?
    public let roundID: RoundID
    public let homeTeamID: TeamID
    public let awayTeamID: TeamID

    public init(
        federationMatchID: String?,
        roundID: RoundID,
        homeTeamID: TeamID,
        awayTeamID: TeamID
    ) {
        self.federationMatchID = federationMatchID
        self.roundID = roundID
        self.homeTeamID = homeTeamID
        self.awayTeamID = awayTeamID
    }
}

/// Un partido ya almacenado, reducido a sus claves. Sin fecha, por lo mismo.
public struct MatchCandidate: Equatable, Sendable {
    public let id: MatchID
    public let federationMatchID: String?
    public let roundID: RoundID
    public let homeTeamID: TeamID
    public let awayTeamID: TeamID

    public init(
        id: MatchID,
        federationMatchID: String?,
        roundID: RoundID,
        homeTeamID: TeamID,
        awayTeamID: TeamID
    ) {
        self.id = id
        self.federationMatchID = federationMatchID
        self.roundID = roundID
        self.homeTeamID = homeTeamID
        self.awayTeamID = awayTeamID
    }
}

/// Un equipo tal y como lo publica la fuente, reducido a sus claves.
///
/// **No trae categoría, género ni modalidad**, y no es un olvido: la fuente no
/// los publica por equipo (§F.3 — *"el nombre **no lleva la categoría**"*) y
/// `D-58` los hace heredar de la `Competition`. Por eso van en el `scope`.
public struct IncomingTeam: Equatable, Sendable {
    public let federationTeamID: String?

    /// El nombre del **club**, sin la letra: la separa el adaptador (F2,
    /// `RFFMValue.teamName`).
    public let clubName: NormalizedName

    /// La letra que iba embebida en el nombre. Opcional: hay clubes sin filial.
    public let letter: String?

    public init(federationTeamID: String?, clubName: NormalizedName, letter: String?) {
        self.federationTeamID = federationTeamID
        self.clubName = clubName
        self.letter = letter
    }
}

/// Lo que la `Competition` le presta al equipo para identificarlo (`D-07`,
/// `D-58`): las tres piezas de su clave única que la fuente no publica.
public struct CompetitionScope: Equatable, Sendable {
    public let ageCategory: TeamCategory
    public let gender: Gender
    public let modality: Modality

    public init(ageCategory: TeamCategory, gender: Gender, modality: Modality) {
        self.ageCategory = ageCategory
        self.gender = gender
        self.modality = modality
    }
}

/// Un equipo ya almacenado, reducido a sus claves.
public struct TeamCandidate: Equatable, Sendable {
    public let id: TeamID
    public let federationTeamID: String?
    public let ownership: TeamOwnership
    public let category: TeamCategory
    public let letter: String?
    public let gender: Gender
    public let modality: Modality

    public init(
        id: TeamID,
        federationTeamID: String?,
        ownership: TeamOwnership,
        category: TeamCategory,
        letter: String?,
        gender: Gender,
        modality: Modality
    ) {
        self.id = id
        self.federationTeamID = federationTeamID
        self.ownership = ownership
        self.category = category
        self.letter = letter
        self.gender = gender
        self.modality = modality
    }
}

/// De quién es el equipo (§3.6, `D-03`): `isOwn` es derivado de que
/// `opponent_club_id` sea nulo, y aquí se modela como los dos casos que es.
///
/// **Es un `enum` y no un `Bool` más un nombre opcional** por la misma razón que
/// los candidatos no llevan fecha: un equipo propio **no tiene** nombre de club
/// rival con el que emparejar, y con dos campos sueltos esa combinación
/// imposible sería representable — y el paso 2 podría leerla.
public enum TeamOwnership: Equatable, Sendable {
    /// `opponent_club_id` nulo. Lo creó el club (`D-66`).
    case own
    /// El nombre normalizado de su `OpponentClub`.
    case opponent(clubName: NormalizedName)
}

/// Un club rival tal y como lo publica la fuente, reducido a sus claves.
public struct IncomingOpponentClub: Equatable, Sendable {
    public let federationClubID: String?
    public let name: NormalizedName

    public init(federationClubID: String?, name: NormalizedName) {
        self.federationClubID = federationClubID
        self.name = name
    }
}

/// Un club rival ya almacenado, reducido a sus claves.
public struct OpponentClubCandidate: Equatable, Sendable {
    public let id: OpponentClubID
    public let federationClubID: String?
    public let name: NormalizedName

    public init(id: OpponentClubID, federationClubID: String?, name: NormalizedName) {
        self.id = id
        self.federationClubID = federationClubID
        self.name = name
    }
}


// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Lo que los tres escalones tienen en común
//
// Los pasos 1 y 3 son **la misma regla tres veces**, y escribirlos tres veces es
// cómo se acaba con tres versiones de la guarda del opcional —de las cuales dos
// funcionan y una empareja clubes al azar—. Es el mismo argumento con el que
// `UpsertPolicy` existe en vez de un `if` en cada entidad.
// ─────────────────────────────────────────────────────────────────────────────

/// Lo mínimo que la cadena necesita de un candidato, sea de la clase que sea.
protocol MatchingCandidate {
    associatedtype MatchedID: Hashable & Sendable
    var matchingID: MatchedID { get }
    var federationKey: String? { get }
}

extension OpponentClubCandidate: MatchingCandidate {
    var matchingID: OpponentClubID { id }
    var federationKey: String? { federationClubID }
}

extension TeamCandidate: MatchingCandidate {
    var matchingID: TeamID { id }
    var federationKey: String? { federationTeamID }
}

extension MatchCandidate: MatchingCandidate {
    var matchingID: MatchID { id }
    var federationKey: String? { federationMatchID }
}

extension MatchingChain {

    /// **Paso 1**, el escalón exacto: la clave de la federación.
    ///
    /// El `guard let` es la regla, y no es cosmética: comparar los dos opcionales
    /// con `==` haría que una fila entrante **sin** clave —el caso que toda la
    /// degradación existe para atender— casara con el primer candidato que
    /// tampoco la tenga. No tienen por qué ser la misma entidad, y a partir de
    /// ahí `D-76` le estamparía a una la clave de la otra.
    ///
    /// Devuelve **el primero** sin comprobar si hay más: estas claves son
    /// `UNIQUE` por §3.5, así que un segundo no puede existir. La ambigüedad es
    /// del paso 2, que es el inexacto.
    static func byFederationKey<Candidate: MatchingCandidate>(
        _ key: String?,
        among candidates: [Candidate]
    ) -> Candidate.MatchedID? {
        guard let key else { return nil }
        return candidates.first { $0.federationKey == key }?.matchingID
    }

    /// Convierte la lista corta de un escalón en su desenlace.
    ///
    /// `nil` significa **"este escalón no resolvió, sigue al siguiente"**, que es
    /// lo que hace que la cadena se lea como una cadena. Que uno sea `nil` y no
    /// `.unmatched` importa: `.unmatched` es el **final**, y solo el último
    /// escalón puede producirlo.
    static func resolve<Candidate: MatchingCandidate>(
        _ shortlist: [Candidate],
        by key: MatchingKey
    ) -> MatchOutcome<Candidate.MatchedID>? {
        switch shortlist.count {
        case 0: nil
        case 1: .matched(shortlist[0].matchingID, by: key)
        default: .ambiguous(shortlist.map(\.matchingID))
        }
    }
}

public import Domain
import struct Foundation.Date
import struct Foundation.UUID

/// Caso de uso: **el primer paso del enganche** (`D-67`, §2.3-c).
///
/// # Lo que hace, y lo que deliberadamente no hace
///
/// Recibe la URL pegada del navegador, **la lee por el puerto** —el llamante no
/// sabe de qué federación es ([D-97], `C-B.1`)—, pregunta a la federación en
/// línea y devuelve lo que hay ahí. **No escribe nada** (`C-C.1`).
///
/// # ESQUELETO en curso (Bloque C)
///
/// Cuatro campos siguen devolviendo un valor fijo y equivocado a propósito:
/// `exists` (`C-C.2`), `alreadyRegistered` (`C-C.3`), `identityMatches`
/// (`C-C.4`) y `teams` (`C-C.5`).
public struct PreviewFederationLink: Sendable {
    private let unitOfWork: any TenantUnitOfWork
    private let federationClients: any FederationClientProvider

    public init(
        unitOfWork: any TenantUnitOfWork,
        federationClients: any FederationClientProvider
    ) {
        self.unitOfWork = unitOfWork
        self.federationClients = federationClients
    }

    public func execute(
        teamID: TeamID, calendarURL: String, actor: ActorContext
    ) async throws -> FederationLinkPreview {
        let found = try await unitOfWork.withRepositories(actor: actor) { repositories in
            guard let club = try await repositories.clubs.current() else {
                throw ApplicationError.tenantNotProvisioned(slug: actor.clubSlug.value)
            }
            guard let team = try await repositories.teams.find(teamID) else {
                throw ApplicationError.teamNotFound(id: "\(teamID.raw)")
            }
            return (club: club, team: team)
        }

        guard let client = federationClients.client(for: found.club.federation) else {
            throw ApplicationError.federationAdapterMissing(
                federation: found.club.federation.rawValue)
        }

        let coordinate = try client.coordinate(fromCalendarURL: calendarURL)
        let calendar = try await client.fetchCalendar(coordinate)

        // **`C-C.1`: de aquí no sale una sola escritura.** El atajo natural es
        // adelantar la cascada —la temporada que falta está en la mano, y
        // pedirla otra vez en el enganche cuesta una petición más—. Lo que lo
        // hace inaceptable no es el coste: es que **entre esta respuesta y el
        // enganche hay un humano** que todavía no ha reconocido su club en
        // `teams[]` (`D-16`) y que puede cerrar la pestaña. Una `Season` creada
        // aquí quedaría dada de alta por una URL que nadie confirmó.
        //
        // El segundo ámbito es de **lectura**, y es lo único que hace: mirar si
        // la temporada y la competición ya están.
        let existing = try await unitOfWork.withRepositories(actor: actor) {
            repositories in
            let season = try await repositories.seasons
                .findByFederationID(coordinate.federationSeasonID)
            // **Sin temporada no puede haber competición** (§3.5): la fila se
            // identifica por `season_id` **+** `federation_group_id`, así que
            // preguntar sin lo primero no tiene sentido — y la respuesta ya se
            // sabe.
            guard let season else { return (season: nil as Season?, competition: nil as Competition?) }
            let competition = try await repositories.competitions.findByFederationGroup(
                seasonID: season.id, federationGroupID: coordinate.federationGroupID)
            return (season: season, competition: competition)
        }
        let existingSeason = existing.season

        // **`C-C.8`, la misma regla en la primera puerta.** El `/preview` no
        // tiene cuerpo que traiga la etiqueta —recibe solo la URL—, así que sin
        // etiqueta en la fuente y con temporada nueva no hay nada honesto que
        // enseñar: el contrato declara `label` **obligatoria y no anulable**, y
        // una cadena vacía sería *"una fila que miente"*, que es el defecto que
        // `D-96` acaba de corregir en `finishedAt`.
        guard let label = existingSeason?.label ?? calendar.seasonLabel else {
            throw ApplicationError.seasonLabelUnavailable(
                federationSeasonID: coordinate.federationSeasonID)
        }

        // **Los tres que la competición presta** (`C-A.3`, `C-C.4`), y de dónde
        // salen es la decisión de este ciclo.
        //
        // Si la fila **ya existe**, son los suyos: es la que la cascada va a
        // reutilizar (`C-C.7`), así que es la que decide el 409. Si **no
        // existe**, la cascada la va a crear y los tres se proponen: la edad
        // desde el **equipo** —es el único sitio del que puede salir, porque la
        // federación no la publica y el cuerpo del enganche no la lleva—, la
        // modalidad desde la coordenada (`tipojuego`) y el género desde la
        // inferencia sobre el nombre (`C-A.7`, `D-58`).
        //
        // La consecuencia, escrita para que nadie la lea como un descuido: en el
        // alta nueva **la edad cuadra por construcción** y las dos que de verdad
        // se comprueban son las otras. La tercera se cobra cuando la competición
        // ya está, que es justo el caso que `D-58` describe.
        let scope = existing.competition.map {
            CompetitionScope(
                ageCategory: $0.ageCategory, gender: $0.gender, modality: $0.modality)
        } ?? CompetitionScope(
            ageCategory: found.team.category,
            gender: Gender.proposed(fromFederationName: calendar.competitionName ?? ""),
            modality: coordinate.modality)

        return FederationLinkPreview(
            season: .init(
                federationSeasonID: coordinate.federationSeasonID,
                // **La etiqueta de la que ya existe es la nuestra, no la de la
                // fuente** (`C-C.2`): la temporada ya está dada de alta y su
                // rótulo es dato del club. La de la fuente solo hace falta
                // cuando hay que proponer una que no existe.
                //
                label: label.value,
                // **`C-C.2`**: se pregunta por el **código** de la coordenada y
                // no por la etiqueta, igual que `seed-competition`. La etiqueta
                // es rótulo —y en la RFFM, el eco de nuestro propio parámetro
                // ([Anexo RFFM §F.16])—; el código es la coordenada.
                exists: existingSeason != nil),
            competition: .init(
                // **La identidad, de la fila cuando la hay; los rótulos, de la
                // fuente siempre.** No es una mezcla caprichosa: los rótulos
                // están para que un humano **reconozca** su grupo tal y como lo
                // ve en la web de la federación (`D-16`), y la identidad para
                // **decidir** si esto va a dar un 409.
                modality: scope.modality,
                gender: scope.gender,
                ageCategory: scope.ageCategory,
                divisionLabel: calendar.competitionName ?? "Sin división",
                groupLabel: calendar.groupLabel ?? "Grupo Único",
                federationCompetitionID: coordinate.federationCompetitionID,
                federationGroupID: coordinate.federationGroupID,
                roundCount: calendar.rounds.count,
                teams: Self.teams(in: calendar),
                // **`C-C.3`**: se pregunta por el **grupo**, que es lo que
                // identifica la fila (§3.5). El código de competición designa la
                // liga entera, y con él el Grupo 5 daría `true` siendo otra fila.
                alreadyRegistered: existing.competition != nil),
            // **`C-C.4`**: el veredicto de `C-A.3` cruzando la puerta. En
            // `false`, confirmar devuelve **409**; enseñarlo aquí es lo que
            // convierte un choque en una corrección.
            identityMatches: found.team.identityMatches(scope))
    }

    /// Los equipos del grupo, **sacados del calendario** y desduplicados
    /// (`C-C.5`).
    ///
    /// # Por qué hay que componerlos y no vienen dados
    ///
    /// El sobre de la federación no trae lista de equipos: trae jornadas con
    /// partidos, y cada equipo aparece tantas veces como partidos juega. Lo que
    /// la pantalla necesita es el **conjunto**, en el orden en que aparece, que
    /// es el de la primera jornada y por tanto el más reconocible.
    ///
    /// # Y por qué la clave de desduplicar tiene dos mitades
    ///
    /// Por el código cuando lo hay —es lo que identifica al equipo (§3.7)— y
    /// por el nombre cuando no, que es lo único que queda. **El que no lo trae
    /// no se descarta**: desaparecer de esta lista es desaparecer de la pantalla
    /// donde un humano reconoce su club, y elegirlo como propio ya lo impide la
    /// otra puerta, donde `ownTeamFederationId` es obligatorio (`D-67`).
    ///
    /// Dos equipos distintos **sin código y con el mismo nombre** se fundirían
    /// en uno. No se corrige aquí: esto es una lista de pantalla, no una
    /// escritura, y el emparejamiento de verdad es la cadena de §3.7 — que tiene
    /// su propio escalón para el nombre ambiguo (`D-79`).
    private static func teams(in calendar: FederationCalendar) -> [FederationLinkPreview.Team] {
        var seen: Set<String> = []
        var teams: [FederationLinkPreview.Team] = []
        for reference in calendar.rounds.flatMap(\.matches).flatMap({ [$0.home, $0.away] }) {
            guard seen.insert(reference.federationTeamID ?? reference.name).inserted else {
                continue
            }
            teams.append(FederationLinkPreview.Team(
                federationTeamID: reference.federationTeamID,
                // **En crudo y con la letra embebida**: se enseña tal cual para
                // que el administrador lo reconozca como lo ve en la web de la
                // federación. Separar club y letra es de la ingesta (§3.7).
                rawName: reference.name,
                crestURL: reference.crestURL))
        }
        return teams
    }
}

/// Lo que hay en la coordenada, **sin persistir nada**.
///
/// Es un dato de **pantalla**: existe para que un humano reconozca su club en
/// `competition.teams` antes de confirmar. Por eso lleva rótulos en crudo y no
/// entidades del Dominio — nada de esto se ha escrito ni se va a comparar con
/// nada todavía.
public struct FederationLinkPreview: Equatable, Sendable {
    public let season: Season
    public let competition: Competition
    public let identityMatches: Bool

    public init(season: Season, competition: Competition, identityMatches: Bool) {
        self.season = season
        self.competition = competition
        self.identityMatches = identityMatches
    }

    /// La temporada leída de `seasons[]`, que va **incrustado en la propia
    /// página del calendario**: la RFFM no tiene endpoint de temporadas
    /// ([Anexo RFFM §F.7]).
    public struct Season: Equatable, Sendable {
        public let federationSeasonID: String
        public let label: String
        /// `false` ⇒ al confirmar **se creará** en cascada.
        public let exists: Bool

        public init(federationSeasonID: String, label: String, exists: Bool) {
            self.federationSeasonID = federationSeasonID
            self.label = label
            self.exists = exists
        }
    }

    public struct Competition: Equatable, Sendable {
        public let modality: Modality
        /// **Propuesta, no hecho** (`D-58`): sale del nombre de la competición.
        public let gender: Gender
        public let ageCategory: TeamCategory
        public let divisionLabel: String
        public let groupLabel: String
        public let federationCompetitionID: String
        public let federationGroupID: String
        public let roundCount: Int
        public let teams: [Team]
        /// `true` si ese grupo ya está dado de alta en esa temporada (§3.5).
        public let alreadyRegistered: Bool

        public init(
            modality: Modality, gender: Gender, ageCategory: TeamCategory,
            divisionLabel: String, groupLabel: String,
            federationCompetitionID: String, federationGroupID: String,
            roundCount: Int, teams: [Team], alreadyRegistered: Bool
        ) {
            self.modality = modality
            self.gender = gender
            self.ageCategory = ageCategory
            self.divisionLabel = divisionLabel
            self.groupLabel = groupLabel
            self.federationCompetitionID = federationCompetitionID
            self.federationGroupID = federationGroupID
            self.roundCount = roundCount
            self.teams = teams
            self.alreadyRegistered = alreadyRegistered
        }
    }

    /// Un equipo **tal y como lo publica la federación**, sin normalizar.
    public struct Team: Equatable, Sendable {
        /// `codigo_equipo` (§3.7). **Anulable**: la fuente publica equipos sin
        /// código (F9-bis), y ése no desaparece de la lista (`C-C.5`).
        public let federationTeamID: String?
        /// Nombre tal cual llega, **con la letra embebida**.
        public let rawName: String
        public let crestURL: String?

        public init(federationTeamID: String?, rawName: String, crestURL: String?) {
            self.federationTeamID = federationTeamID
            self.rawName = rawName
            self.crestURL = crestURL
        }
    }
}

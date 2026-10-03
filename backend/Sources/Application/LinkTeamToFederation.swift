public import Domain
import struct Foundation.Date

/// Caso de uso: **el enganche** (`D-67`, §2.3-c) — el único camino que lleva a
/// sincronizar.
///
/// # ESQUELETO del Bloque C — está mal a propósito, y en nueve sitios
///
/// Cada uno es el esqueleto del ciclo que lo sustituye: crear siempre la
/// temporada (`C-C.6`) y la competición (`C-C.7`), inventarse la etiqueta
/// (`C-C.8`), abrir un ámbito por escritura (`C-C.9`), omitir la inscripción
/// (`C-C.10`), no escribir la fila aceptada (`C-C.11`), contestar `202` sin
/// adaptador (`C-C.12`) y no comprobar ninguna de las dos guardas (`C-C.13`,
/// `C-C.14`).
public struct LinkTeamToFederation: Sendable {
    private let unitOfWork: any TenantUnitOfWork
    private let federationClients: any FederationClientProvider
    private let clock: any Clock
    private let ids: any UUIDProvider

    public init(
        unitOfWork: any TenantUnitOfWork,
        federationClients: any FederationClientProvider,
        clock: any Clock,
        ids: any UUIDProvider
    ) {
        self.unitOfWork = unitOfWork
        self.federationClients = federationClients
        self.clock = clock
        self.ids = ids
    }

    public func execute(
        _ request: FederationLinkRequest, actor: ActorContext
    ) async throws -> FederationLinkResult {
        // TODO(§7): aquí va la comprobación de **rol elevado** que el *spec*
        // promete —con su `403`— y que hoy no tiene dónde caer (`A-14`·H-66).
        //
        // **Y no es solo la de `UpdateClub`, es la de `IngestClubCalendars`
        // también** (`A-6`·H-41): esto escribe `Season`, `Competition` y
        // `TeamRegistration` —administración del club, §7.3— y **encola una
        // ingesta con el actor de la persona** (`FederationLinkHandler`), que
        // escribe `Team` y `Match`, y §7.3 se los atribuye al actor de sistema.
        // Cómo se expresa *"una persona pide una escritura de la ingesta"* es la
        // decisión que H-41 dejó a F10 y F10 no tomó. Tomarla aquí y en
        // `IngestClubCalendars` a la vez, que es el mismo caso.
        let found = try await unitOfWork.withRepositories(actor: actor) { repositories in
            guard let club = try await repositories.clubs.current() else {
                throw ApplicationError.tenantNotProvisioned(slug: actor.clubSlug.value)
            }
            guard let team = try await repositories.teams.find(request.teamID) else {
                throw ApplicationError.teamNotFound(id: "\(request.teamID)")
            }
            return (club: club, team: team)
        }

        // **`C-C.12`: sin adaptador se para aquí, antes del `202`** (`D-95`,
        // `H-28`).
        //
        // La federación está en el catálogo del Dominio —que **declara sus
        // capacidades**, como `D-17` pide— y la raíz de composición devuelve
        // `nil` a propósito. Las dos cosas a la vez son el diseño.
        //
        // Encolar trabajo que nadie sabe hacer dejaría una fila `accepted` que
        // **jamás cierra**: un `202` mudo, que es lo que `D-88` dice que
        // planificar antes de responder existe para evitar. La consecuencia de
        // negocio, sin adornos: hasta que exista el adaptador de la FCF, un club
        // catalán no se puede enganchar con ingesta — y lo que F10 hace es que
        // **se vea bien**.
        guard let client = federationClients.client(for: found.club.federation) else {
            throw ApplicationError.federationAdapterMissing(
                federation: found.club.federation.rawValue)
        }

        let coordinate = try client.coordinate(fromCalendarURL: request.calendarURL)
        let calendar = try await client.fetchCalendar(coordinate)
        let now = clock.now()

        // **El código propio tiene que ser de un equipo de este calendario**
        // (A-12·H-74), y se mira aquí, antes de abrir el ámbito que escribe.
        //
        // La web enseñará nombres, pero el contrato es el *endpoint*. `D-67` hizo
        // el campo obligatorio para que el equipo propio no naciera rival, y con
        // un código que no está en el grupo nace exactamente así: la primera
        // pasada no lo encuentra en ningún partido y da de alta a los dieciséis
        // como rivales, el propio incluido. Medido contra la RFFM real antes de
        // esto: **202** con un código inventado, 240 partidos y ninguno del
        // equipo del club.
        //
        // El equipo que la fuente publica **sin** código no cuenta: su
        // `federationTeamID` es `nil`, y no hay valor que lo designe (`C-C.5`).
        let codes = Set(
            calendar.rounds.flatMap(\.matches)
                .flatMap { [$0.home, $0.away] }
                .compactMap(\.federationTeamID))
        guard codes.contains(request.ownTeamFederationID) else {
            throw DomainError.ownTeamNotInCalendar(
                code: request.ownTeamFederationID,
                federationGroupID: coordinate.federationGroupID)
        }

        // ── El ámbito 2 de `D-83`: la cascada entera, o nada (`C-C.9`) ──────
        //
        // Un enganche a medias no es un dato incompleto: es un equipo
        // enganchado a una competición que no existe, o una fila `accepted`
        // prometiendo una pasada sobre una competición que el `rollback` se
        // llevó. El `202` promete **algo que consultar** (`D-96`), y esa promesa
        // solo se sostiene si lo que se consulta se escribió con lo demás.
        return try await unitOfWork.withRepositories(actor: actor) { repositories in
            // ── 0. El equipo, otra vez y bloqueado (A-12·H-73) ──────────────
            //
            // **Lo que se decide aquí se decide con lo que hay AHORA**, no con lo
            // que leyó el ámbito 1. Entre los dos está la llamada a la federación
            // —de 0,4 a 20 s—, y en ese rato otro enganche del mismo equipo puede
            // haber escrito su código. Con la copia de antes, `linked(…)` no lo
            // veía y `save` lo pisaba: medido contra la RFFM real, el mismo equipo
            // enganchado a dos grupos a la vez daba **dos 202 y dos cascadas**.
            //
            // **Bloqueado, y no solo releído**: hoy dos ámbitos de tenant no
            // pueden estar abiertos a la vez (H-77) y releer bastaría, pero eso es
            // una cifra del *pool*, no un diseño. Con el bloqueo, el segundo
            // espera al primero y ve su código.
            //
            // **Y la transición se comprueba antes de escribir nada**: el
            // `alreadyLinkedToFederation` no depende de la temporada ni de la
            // competición, así que no hay motivo para dejarlo detrás de ellas.
            guard let team = try await repositories.teams.lock(request.teamID) else {
                throw ApplicationError.teamNotFound(id: "\(request.teamID)")
            }
            let linked = try team.linked(toFederationTeamID: request.ownTeamFederationID)

            // ── 1. La temporada ─────────────────────────────────────────────
            //
            // **`C-C.6`: se reutiliza por su código.** No es una optimización —
            // `federation_season_id` es la coordenada con la que se llama a la
            // federación, así que dos filas con el mismo código son dos
            // temporadas que dicen ser la misma. Y el segundo enganche de una
            // temporada es el caso **normal**: la acción es del equipo, y el
            // club tiene equipos en muchas categorías.
            //
            // **`C-C.8`: la etiqueta no se inventa.** `Season.label` deriva la
            // ventana de fechas que la guarda de `D-91` usa como evidencia
            // (§3.2), así que ponerla a ojo no da un rótulo feo — **desarma la
            // comprobación de al lado**. El orden de las dos fuentes no es
            // indiferente: manda el cuerpo, que es lo que el administrador
            // confirmó sobre la propuesta del `/preview`; el sobre es el valor
            // por defecto de esa propuesta.
            let season: Season
            if let existing = try await repositories.seasons
                .findByFederationID(coordinate.federationSeasonID)
            {
                season = existing
            } else {
                guard let label = request.seasonLabel ?? calendar.seasonLabel else {
                    throw ApplicationError.seasonLabelUnavailable(
                        federationSeasonID: coordinate.federationSeasonID)
                }
                season = try Season(
                    id: SeasonID(raw: ids.next()), label: label,
                    federationSeasonID: coordinate.federationSeasonID,
                    createdAt: now, updatedAt: now)
                try await repositories.seasons.save(season)
            }

            // **`C-C.14`, la guarda de `D-91`, y va en cuanto hay temporada.**
            //
            // La del nombre (abajo) caza *"me equivoqué de competición"* y es
            // **ciega** al error que ocurre cada verano —traerse los códigos del
            // año pasado—, porque los rótulos son idénticos entre temporadas
            // ([Anexo RFFM §F.17]) y la etiqueta de temporada es el eco de
            // nuestro propio parámetro (§F.16). Lo único que no puede ser eco
            // son **las fechas**, que en un desfase de temporada se van doce
            // meses.
            //
            // Aquí pesa más que en la pasada: allí la temporada ya estaba
            // elegida; éste es el momento en que un humano acaba de pegar la
            // URL. Se le pasan **todas** las fechas y la decisión —la mediana—
            // es del Dominio.
            try season.requireOwnsCalendar(
                matchDates: calendar.rounds.flatMap(\.matches).compactMap(\.date))

            // ── 2. La competición ───────────────────────────────────────────
            //
            // **`C-C.7`: se reutiliza si ese grupo ya está en esa temporada.**
            // El caso que lo obliga es concreto —el Infantil A y el Infantil B
            // del mismo club caen en el mismo grupo (`D-67`)— y sin esto no
            // habría dos filas: habría un **409 de unicidad** por una acción
            // correcta. Se busca por `(season_id, federation_group_id)`, que es
            // la unicidad de §3.5; por el código de **competición**, el Grupo 5
            // reutilizaría la fila del Grupo 4, que es otra liga.
            //
            // **Los tres campos de identidad, cuando se crea**: la edad **del
            // nombre** de la competición (A-12·H-75), la modalidad de la
            // coordenada (`tipojuego`) y el género **del cuerpo**, que es la
            // confirmación de lo que el `/preview` propuso (`D-58`).
            //
            // La edad se tomaba del equipo, y entonces la guarda de identidad de
            // abajo comparaba el equipo consigo mismo: el Infantil A enganchado a
            // *"PRIMERA CADETE"* daba 202 y la ingesta creaba dieciséis rivales
            // "infantil" de una liga cadete (`D-07`). Del equipo solo se toma
            // cuando el nombre no dice ninguna, que es lo que el `/preview` avisa
            // con `ageCategoryChecked: false`.
            let competition: Competition
            if let existing = try await repositories.competitions.findByFederationGroup(
                seasonID: season.id, federationGroupID: coordinate.federationGroupID)
            {
                // **`C-C.13`, la guarda de `D-84`, y va ANTES de escribir.** Una
                // coordenada equivocada no falla: la RFFM ignora el parámetro
                // `temporada` y con códigos inexistentes responde `200` con el
                // calendario a `null` ([Anexo RFFM §F.16]), así que un dígito
                // cambiado trae un calendario **perfectamente parseable de otra
                // liga**.
                //
                // La pasada ya se protege con esto desde F5; lo que falta es la
                // guarda **en la puerta por la que entra el humano**, que es
                // donde el dígito se equivoca. Sin ella el equipo queda
                // enganchado a un grupo que no es el suyo y el error no aparece
                // hasta tres días después, en `ingestion_runs`.
                //
                // **Solo en esta rama**: la competición que se crea abajo nace
                // con el nombre del propio calendario, así que compararla
                // consigo misma no diría nada (`D-72`, primera pasada).
                try existing.requireSameSource(as: calendar.competitionName)
                competition = existing
            } else {
                competition = try Competition(
                    id: CompetitionID(raw: ids.next()),
                    seasonID: season.id,
                    modality: coordinate.modality,
                    gender: request.gender,
                    federationCompetitionID: coordinate.federationCompetitionID,
                    federationGroupID: coordinate.federationGroupID,
                    ageCategory: TeamCategory.proposed(
                        fromFederationName: calendar.competitionName ?? "")
                        ?? team.category,
                    divisionLabel: calendar.competitionName ?? "Sin división",
                    groupLabel: calendar.groupLabel ?? "Grupo Único",
                    // **La evidencia se guarda ya** (`D-72`): sin este valor, la
                    // guarda de `D-84` no tiene con qué comparar en la pasada
                    // siguiente.
                    federationName: calendar.competitionName,
                    createdAt: now, updatedAt: now)
                try await repositories.competitions.save(competition)
            }

            // **`C-C.15`: la identidad tiene que cuadrar, y aquí se para.**
            //
            // `C-C.4` lo enseña en el `/preview` para que el administrador
            // enganche otro equipo en vez de chocar; esto es lo que convierte el
            // aviso en regla. Sin ello, `identityMatches: false` sería un adorno
            // —el cliente puede confirmar igual— y el `409` que el contrato
            // declara no lo levantaría nadie.
            //
            // Va con la competición ya resuelta y **antes de escribir**: la
            // terna que decide es la de la fila que se va a reutilizar o crear,
            // que es la misma que `C-C.4` enseñó.
            try team.requireIdentityMatches(
                CompetitionScope(
                    ageCategory: competition.ageCategory,
                    gender: competition.gender,
                    modality: competition.modality))

            // ── 3. La inscripción (`C-C.10`) ────────────────────────────────
            //
            // Lo que esto compra no es una fila más: es que **todo equipo propio
            // con calendario esté inscrito por construcción** (`D-68`), y por
            // tanto que las dos mitades del filtro `?seasonId=` no se puedan
            // contradecir. Sin ella queda el agujero que la decisión describe —
            // entre el `202` y la primera pasada no existe ni un `Match` del que
            // derivar la participación (`D-27`).
            //
            // **La fila de junio se completa, no se duplica.** Si el club ya
            // había inscrito al equipo —`(equipo, temporada, nil)`, que es lo
            // que existe antes de que la federación publique calendario—, aquí
            // se le rellena la competición conservando su `id`. Añadir otra
            // dejaría al equipo inscrito dos veces en la misma temporada, que es
            // lo que el `UNIQUE` con `NULLS NOT DISTINCT` de `C-D.3` rechaza.
            //
            // **Y es aditivo**: un equipo juega liga *y* copa (`D-12`), así que
            // la fila de **otra** competición no se toca — se enganchan una por
            // una y cada una deja la suya.
            let registrations = try await repositories.teamRegistrations.list(
                teamID: team.id, seasonID: season.id)
            if !registrations.contains(where: { $0.competitionID == competition.id }) {
                let open = registrations.first { $0.competitionID == nil }
                try await repositories.teamRegistrations.save(
                    try TeamRegistration(
                        id: open?.id ?? TeamRegistrationID(raw: ids.next()),
                        team: team,
                        seasonID: season.id,
                        competitionID: competition.id,
                        createdAt: open?.createdAt ?? now,
                        updatedAt: now))
            }

            // ── 4. El enganche ──────────────────────────────────────────────
            //
            // **`C-E.10`: el código tiene que estar libre, y se pregunta antes de
            // escribir.** `federation_team_id` es `UNIQUE` (§3.5), así que sin
            // esto el choque lo daba Postgres — un `23505` que salía por HTTP
            // como **500 con el SQL en crudo**, donde el *spec* declara **409**.
            //
            // No es un caso raro: es el desenlace **normal de enganchar tarde**.
            // Por [D-66] la ingesta no crea equipos propios, así que el equipo
            // del club que nadie enganchó antes de la primera pasada **ya existe
            // como rival** con ese mismo código. Medido contra la base de trabajo
            // el 2026-09-24: los 16 equipos del grupo ya estaban escritos.
            //
            // **Se pregunta por la lista y no por un puerto nuevo**: es lo que la
            // cadena de emparejamiento hace en cada pasada (§3.7), así que el
            // coste ya está pagado y el puerto no se ensancha por un caso de
            // guarda.
            //
            // **Y el propio equipo no cuenta**: volver a enganchar al mismo
            // código es idempotente, que es lo que hace que reintentar el `202`
            // sea seguro.
            if let holder = try await repositories.teams.list().first(where: {
                $0.federationTeamID == request.ownTeamFederationID && $0.id != team.id
            }) {
                throw DomainError.federationTeamIDTaken(
                    code: request.ownTeamFederationID,
                    owner: "\(holder.id)")
            }

            // La transición ya se comprobó al empezar el ámbito, con el equipo
            // bloqueado (paso 0).
            try await repositories.teams.save(linked)

            // ── 5. La constancia, ANTES de responder (`C-C.11`, `D-96`) ─────
            //
            // El `jobId` que vuelve **tiene que tener algo detrás**. Sin esta
            // fila, la única forma que tendría el backoffice de enterarse sería
            // comparar marcas de tiempo contra la lista de pasadas: el N+1 que
            // `D-89` rechazó a propósito, y que además no cubre el caso medido
            // en `H-27` — detrás del `202` no lo ve nadie, literalmente.
            //
            // **Es enmienda a `D-88`, no contradicción**: el cuerpo sigue sin
            // llevar ni un campo de la pasada. Lo que se crea no es el
            // resultado, es la constancia de que **se lo pidieron**.
            //
            // `startedAt` es cuándo **se pidió** —lo que el `202` deja para
            // consultar, y la clave por la que el registro ordena (`C-D.6`)—, y
            // no hay `finishedAt` porque una pasada aceptada todavía no ha
            // acabado (`C-A.5`). Quien la cierra es la pasada (`C-A.6`).
            //
            // **Y si ya hay una abierta en esa competición, el `jobId` es ésa**
            // (A-12·H-62). La pasada cierra **una**, la más antigua
            // (`findAccepted`), así que abrir otra dejaba la del `jobId` recién
            // devuelto abierta hasta la pasada siguiente —que por H-57 puede no
            // llegar—. Bastaba el A y el B del mismo grupo enganchados a la vez.
            // Es lo que `IngestClubCalendars.accept` hace en la otra puerta del
            // `202`: aceptar dos veces no deja dos filas.
            let accepted: IngestionRun
            if let open = try await repositories.ingestionRuns.findAccepted(
                competitionID: competition.id, kind: .calendar)
            {
                accepted = open
            } else {
                accepted = try IngestionRun(
                    id: IngestionRunID(raw: ids.next()),
                    competitionID: competition.id,
                    kind: .calendar,
                    startedAt: now, finishedAt: nil,
                    outcome: .accepted)
                try await repositories.ingestionRuns.record(accepted)
            }

            return FederationLinkResult(
                jobID: accepted.id, teamID: linked.id,
                competitionID: competition.id, seasonID: season.id)
        }
    }
}

/// Lo que el administrador confirma (`D-67`).
///
/// **La URL vuelve a enviarse** porque el `/preview` no persistió nada
/// (`C-C.1`), y con ella el equipo del grupo que ha reconocido como suyo.
public struct FederationLinkRequest: Equatable, Sendable {
    public let teamID: TeamID
    public let calendarURL: String
    /// `federationTeamID` del equipo propio dentro de este grupo, tomado de
    /// `competition.teams` del `/preview`. **Obligatorio** (`D-67`).
    public let ownTeamFederationID: String
    /// Confirmación del género **propuesto** por el `/preview` (`D-58`): el
    /// administrador puede —y a veces debe— cambiarlo. Se almacena en la
    /// `Competition`; el equipo ya lo tiene congelado desde su alta.
    public let gender: Gender
    /// Etiqueta de la temporada, **solo si hay que crearla**. La propone el
    /// `/preview` leyéndola de la página del calendario.
    public let seasonLabel: SeasonLabel?

    public init(
        teamID: TeamID, calendarURL: String, ownTeamFederationID: String,
        gender: Gender, seasonLabel: SeasonLabel? = nil
    ) {
        self.teamID = teamID
        self.calendarURL = calendarURL
        self.ownTeamFederationID = ownTeamFederationID
        self.gender = gender
        self.seasonLabel = seasonLabel
    }
}

/// El trabajo de primera ingesta **encolado** (`D-67`): el enganche ya está
/// escrito.
///
/// `jobID` es el `id` de la fila `accepted` que la cascada deja en
/// `ingestion_runs` **antes de responder** (`D-96`, `C-C.11`), que es lo que el
/// backoffice consulta para enterarse leyendo.
public struct FederationLinkResult: Equatable, Sendable {
    public let jobID: IngestionRunID
    public let teamID: TeamID
    public let competitionID: CompetitionID
    public let seasonID: SeasonID

    public init(
        jobID: IngestionRunID, teamID: TeamID,
        competitionID: CompetitionID, seasonID: SeasonID
    ) {
        self.jobID = jobID
        self.teamID = teamID
        self.competitionID = competitionID
        self.seasonID = seasonID
    }
}

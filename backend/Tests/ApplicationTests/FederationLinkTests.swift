import Domain
import Foundation
import Testing

@testable import Application

/// Nivel 2 (§8.1): **el enganche** (`D-67`) — la cascada, con los puertos
/// falseados y cero I/O.
///
/// Lo que se prueba aquí es lo que la cascada **decide**: qué se reutiliza, qué
/// se crea, en cuántos ámbitos y con qué guardas. Lo que se escriba de verdad en
/// Postgres es del nivel 3 (Bloque D), y lo que salga por HTTP, del 4 (Bloque E).
@Suite("LinkTeamToFederation · D-67 · la cascada del enganche")
struct FederationLinkTests {

    /// **Las mismas fixtures que el `/preview`, a propósito**: las dos puertas
    /// hablan de la misma coordenada, el mismo equipo y el mismo calendario, y
    /// duplicarlas sería dejar que se separaran sin que nadie se entere.
    typealias Fixture = FederationLinkPreviewTests

    static let actor = Fixture.actor

    static func request(
        teamID: TeamID,
        ownTeamFederationID: String = "3349086",
        gender: Gender = .masculino,
        seasonLabel: String? = "2025/26"
    ) throws -> FederationLinkRequest {
        FederationLinkRequest(
            teamID: teamID, calendarURL: Fixture.url,
            ownTeamFederationID: ownTeamFederationID, gender: gender,
            seasonLabel: try seasonLabel.map { try SeasonLabel($0) })
    }

    static func useCase(
        store: IngestionStore, federation: any FederationClient,
        code: FederationCode = .rffm
    ) -> LinkTeamToFederation {
        LinkTeamToFederation(
            unitOfWork: FakeUnitOfWork(store: store),
            federationClients: FakeFederationClientProvider([code: federation]),
            clock: FixedClock(instant: Fixture.now),
            ids: SequentialUUIDProvider())
    }

    static func client(
        _ calendar: FederationCalendar? = nil
    ) -> SpyFederationClient {
        SpyFederationClient(
            returning: calendar ?? Fixture.calendar(), readingURLAs: Fixture.coordinate)
    }

    // ── C-C.6 · la temporada se reutiliza, no se duplica ─────────────────────

    /// **`Season` se busca por `federationSeasonID` y se reutiliza** (`D-67`,
    /// paso 1 de la cascada).
    ///
    /// No es una optimización: `federation_season_id` es la coordenada con la
    /// que se llama a la federación, y dos filas con el mismo código son dos
    /// temporadas que dicen ser la misma. El club tiene equipos en muchas
    /// categorías y **cada uno se engancha por su lado** —la acción es del
    /// equipo, no del club—, así que el segundo enganche de la temporada llega
    /// siempre: es el caso normal, no el raro.
    ///
    /// Es la misma cascada que `seed-competition` ya ensayó, y por eso este
    /// ciclo se apoya en ella en vez de inventar otra.
    @Test("el enganche reutiliza la temporada que ya está, por su código (D-67)")
    func theLinkReusesTheSeason() async throws {
        let team = try Fixture.team()
        let season = try Fixture.season(federationSeasonID: "21")
        let store = IngestionStore()
        await store.seed(club: try Fixture.club())
        await store.seed(seasons: [season], teams: [team])

        let result = try await Self.useCase(store: store, federation: Self.client())
            .execute(try Self.request(teamID: team.id), actor: Self.actor)

        #expect(result.seasonID == season.id)
        #expect(await store.seasons.count == 1)
    }

    // ── C-C.7 · la competición se reutiliza: dos equipos en el mismo grupo ───

    /// **`Competition` se reutiliza si ese grupo ya está en esa temporada**
    /// (`D-67`, paso 2), y el caso que lo obliga es concreto: el **Infantil A y
    /// el Infantil B del mismo club caen en el mismo grupo**. El segundo pegado
    /// no puede volver a crearla.
    ///
    /// Se busca por `(season_id, federation_group_id)`, que es la unicidad que
    /// §3.5 declara — no por el código de competición, que designa la liga
    /// entera y haría que el Grupo 5 reutilizara la fila del Grupo 4.
    ///
    /// Y sin esto no es que hubiera dos filas: habría un **409 de unicidad** en
    /// la cara del administrador, por una acción que es correcta.
    @Test("dos equipos del club en el mismo grupo comparten competición (D-67, §3.5)")
    func theLinkReusesTheCompetition() async throws {
        let infantilB = try Fixture.team(category: .cadete)
        let season = try Fixture.season(federationSeasonID: "21")
        let competition = try Fixture.competition(
            seasonID: season.id, federationGroupID: "24037549")
        let store = IngestionStore()
        await store.seed(club: try Fixture.club())
        await store.seed(
            seasons: [season], competitions: [competition], teams: [infantilB])

        let result = try await Self.useCase(store: store, federation: Self.client())
            .execute(try Self.request(teamID: infantilB.id), actor: Self.actor)

        #expect(result.competitionID == competition.id)
        #expect(await store.competitions.count == 1)
    }

    // ── C-C.8 · sin etiqueta no se inventa una temporada ─────────────────────

    /// **Sin etiqueta y con temporada nueva, se para** (`D-91`, F6-bis·H-08).
    ///
    /// No es ceremonia de validación: **`Season.label` deriva la ventana de
    /// fechas** que la guarda de `D-91` usa como evidencia (§3.2), así que
    /// inventarse la etiqueta envenena la comprobación que viene justo después
    /// —`C-C.14`—. Una temporada rotulada «2000/01» acepta cualquier calendario
    /// o rechaza todos, y en los dos casos la guarda deja de significar algo.
    ///
    /// El sobre **no promete la etiqueta**: es opcional porque la FCF no la
    /// publica y porque en la RFFM es el eco de nuestro propio parámetro
    /// ([Anexo RFFM §F.16]). Por eso el cuerpo del enganche la lleva — la
    /// propone el `/preview` y el administrador la confirma.
    ///
    /// **Y la otra mitad, que es la que impide que esto sea un «no» fijo**: con
    /// la temporada ya dada de alta, la etiqueta no hace ninguna falta y el
    /// enganche sigue.
    @Test("sin etiqueta y con temporada nueva no se inventa: se para (D-91, H-08)")
    func anUnlabelledNewSeasonStopsTheCascade() async throws {
        let team = try Fixture.team()
        let mute = Self.client(Fixture.calendar(seasonLabel: nil))

        let fresh = IngestionStore()
        await fresh.seed(club: try Fixture.club())
        await fresh.seed(teams: [team])

        await #expect(throws: ApplicationError.seasonLabelUnavailable(
            federationSeasonID: "21")) {
            try await Self.useCase(store: fresh, federation: mute)
                .execute(
                    try Self.request(teamID: team.id, seasonLabel: nil),
                    actor: Self.actor)
        }
        // Y no deja nada a medias: se para **antes** de escribir.
        #expect(await fresh.writes == 0)

        // La otra mitad: la temporada ya está, así que no hay etiqueta que
        // proponer y el enganche sigue.
        let season = try Fixture.season(federationSeasonID: "21")
        let seeded = IngestionStore()
        await seeded.seed(club: try Fixture.club())
        await seeded.seed(seasons: [season], teams: [team])

        let result = try await Self.useCase(store: seeded, federation: mute)
            .execute(
                try Self.request(teamID: team.id, seasonLabel: nil), actor: Self.actor)

        #expect(result.seasonID == season.id)
    }

    // ── C-C.9 · la cascada entera en UN ámbito ───────────────────────────────

    /// **`D-83` aplicado al enganche: dos ámbitos, y la red fuera de los dos.**
    ///
    /// 1. **Leer** el club y el equipo. Se cierra **antes** de llamar a la
    ///    federación: con un ámbito solo, una caída del proveedor dejaría una
    ///    transacción abierta esperando, que es como se agota el *pool* de §6.4.
    /// 2. **Escribir**, entero. Temporada, competición, inscripción, equipo y la
    ///    fila aceptada, o ninguna de las cinco.
    ///
    /// **Por qué la de arriba importa más aquí que en la pasada.** Un enganche a
    /// medias no es un dato incompleto: es un equipo enganchado a una
    /// competición que no existe, o —peor— una fila `accepted` prometiendo una
    /// pasada sobre una competición que el `rollback` se llevó. El `202` promete
    /// algo que consultar (`D-96`), y esa promesa solo se puede cumplir si lo
    /// que se consulta se escribió con lo demás.
    ///
    /// **Y por eso la fila aceptada va DENTRO, al revés que en `D-85`.** Allí el
    /// registro de la pasada vive en su propio ámbito **precisamente** para que
    /// el `rollback` de la pasada fallida no se lo lleve — es la constancia del
    /// fallo. Aquí no hay fallo que constatar: es la constancia de que **esto**
    /// se ha aceptado, y sin la cascada no hay nada que aceptar.
    ///
    /// Se cuenta el número de ámbitos porque es lo que el nivel 2 puede afirmar:
    /// estos dobles no tienen transacción, así que *"o todo o nada"* es del
    /// nivel 3. Mismo criterio —y mismo doble— que `opensExactlyThreeScopes`.
    @Test("el enganche abre dos ámbitos y la red queda fuera de los dos (D-83)")
    func theCascadeWritesInASingleScope() async throws {
        let team = try Fixture.team()
        let store = IngestionStore()
        await store.seed(club: try Fixture.club())
        await store.seed(teams: [team])

        _ = try await Self.useCase(store: store, federation: Self.client())
            .execute(try Self.request(teamID: team.id), actor: Self.actor)

        #expect(await store.scopesOpened == 2)
    }

    // ── C-C.10 · la inscripción se escribe en la cascada ─────────────────────

    /// **Paso 2.b de la cascada** (`D-68` y su enmienda): el enganche escribe la
    /// inscripción del equipo **en esa temporada y en esa competición**.
    ///
    /// Lo que esto compra no es una fila más: es que **todo equipo propio con
    /// calendario esté inscrito por construcción**, y por tanto que las dos
    /// mitades del filtro `?seasonId=` no se puedan contradecir. Sin ella queda
    /// el agujero que `D-68` describe — el instante en que el sistema sabe que
    /// un equipo va con una competición y **no lo puede leer**: entre el `202` y
    /// la primera pasada no existe ni un `Match` del que derivarlo (`D-27`).
    ///
    /// **Y la fila de junio se completa, no se duplica.** Si el club ya había
    /// inscrito al equipo —`(equipo, temporada, nil)`, que es lo que existe
    /// antes de que la federación publique calendario—, el enganche **rellena su
    /// competición**. Añadir una segunda dejaría al equipo inscrito dos veces en
    /// la misma temporada, que es justo lo que el `UNIQUE` de tres columnas con
    /// `NULLS NOT DISTINCT` de `C-D.3` va a rechazar.
    @Test("la cascada inscribe el equipo, y completa la fila de junio (D-68)")
    func theCascadeWritesTheRegistration() async throws {
        let team = try Fixture.team()
        let season = try Fixture.season(federationSeasonID: "21")

        // Sin inscripción previa: la escribe entera.
        let fresh = IngestionStore()
        await fresh.seed(club: try Fixture.club())
        await fresh.seed(seasons: [season], teams: [team])

        let onFresh = try await Self.useCase(store: fresh, federation: Self.client())
            .execute(try Self.request(teamID: team.id), actor: Self.actor)

        let written = await fresh.teamRegistrations
        #expect(written.count == 1)
        #expect(written.first?.teamID == team.id)
        #expect(written.first?.seasonID == season.id)
        #expect(written.first?.competitionID == onFresh.competitionID)

        // Con la fila de junio: se completa, y sigue siendo **una**.
        let june = try TeamRegistration(
            id: TeamRegistrationID(raw: UUID()), team: team, seasonID: season.id,
            competitionID: nil, createdAt: Fixture.now, updatedAt: Fixture.now)
        let seeded = IngestionStore()
        await seeded.seed(club: try Fixture.club())
        await seeded.seed(seasons: [season], teams: [team])
        await seeded.seed(teamRegistrations: [june])

        let onSeeded = try await Self.useCase(store: seeded, federation: Self.client())
            .execute(try Self.request(teamID: team.id), actor: Self.actor)

        let completed = await seeded.teamRegistrations
        #expect(completed.count == 1)
        #expect(completed.first?.id == june.id)
        #expect(completed.first?.competitionID == onSeeded.competitionID)
    }

    // ── C-C.11 · la fila `accepted` se escribe ANTES de responder ────────────

    /// **`D-96`: el `202` deja fila desde que se acepta.**
    ///
    /// El `jobId` que vuelve en la respuesta **tiene que tener algo detrás**. Sin
    /// esta fila, la única forma que tendría el backoffice de enterarse de lo
    /// que pasó sería comparar marcas de tiempo contra la lista de pasadas: el
    /// N+1 que `D-89` rechazó a propósito, y que además **no cubre el caso
    /// medido** en `H-27` — detrás del `202` no lo ve nadie, literalmente.
    ///
    /// **Enmienda a `D-88`**, que decía *"el `POST` no crea la fila"*: sigue sin
    /// llevar ni un campo de la pasada. Lo que crea no es el resultado, es la
    /// **constancia de que se lo pidieron**.
    ///
    /// Y la fila nace como `D-96` manda: `accepted`, **sin `finishedAt`** —una
    /// pasada aceptada todavía no ha acabado, `C-A.5`— y con `startedAt` puesto
    /// a cuándo **se pidió**, que es lo que el `202` dejó para consultar y la
    /// clave por la que el registro va a ordenar (`C-D.6`).
    @Test("el jobId devuelto ya tiene su fila `accepted` escrita (D-96, C-A.5)")
    func theAcceptedRunIsWrittenBeforeAnswering() async throws {
        let team = try Fixture.team()
        let store = IngestionStore()
        await store.seed(club: try Fixture.club())
        await store.seed(teams: [team])

        let result = try await Self.useCase(store: store, federation: Self.client())
            .execute(try Self.request(teamID: team.id), actor: Self.actor)

        let runs = await store.ingestionRuns
        #expect(runs.count == 1)
        let run = try #require(runs.first)
        // El `jobId` de la respuesta **es** esa fila: es lo que hace consultable
        // la promesa del `202`.
        #expect(run.id == result.jobID)
        #expect(run.competitionID == result.competitionID)
        #expect(run.outcome == .accepted)
        #expect(run.finishedAt == nil)
        #expect(run.startedAt == Fixture.now)
        // **De calendario**: lo que se encola es la primera pasada del grupo,
        // que es de lo que cuelga todo lo demás (§3.7).
        #expect(run.kind == .calendar)
    }

    /// **Con una fila `accepted` ya abierta en esa competición, el `jobId` es
    /// ésa** (A-12·H-62).
    ///
    /// La pasada cierra **una** fila, la más antigua (`findAccepted`). Abrir otra
    /// dejaba la del `jobId` recién devuelto abierta hasta la pasada siguiente
    /// —que por H-57 puede no llegar—, y bastaba el caso canónico de `D-67`: el A
    /// y el B del mismo grupo, enganchados a la vez. Es lo que `accept` ya hacía en
    /// la otra puerta del `202` (`IngestClubCalendars`): **aceptar dos veces no
    /// deja dos filas**.
    @Test("con una aceptada ya abierta en la competición, el jobId es ésa (A-12·H-62)")
    func anOpenAcceptedRunIsTheJob() async throws {
        let team = try Fixture.team()
        let season = try Fixture.season(federationSeasonID: "21")
        let competition = try Fixture.competition(
            seasonID: season.id, federationGroupID: "24037549")
        let open = try IngestionRun(
            id: IngestionRunID(raw: UUID()), competitionID: competition.id,
            kind: .calendar, startedAt: Fixture.now.addingTimeInterval(-30),
            finishedAt: nil, outcome: .accepted)
        let store = IngestionStore()
        await store.seed(club: try Fixture.club())
        await store.seed(seasons: [season], competitions: [competition], teams: [team])
        await store.record(open)

        let result = try await Self.useCase(store: store, federation: Self.client())
            .execute(try Self.request(teamID: team.id), actor: Self.actor)

        #expect(result.jobID == open.id)
        #expect(await store.ingestionRuns.map(\.id) == [open.id])
    }

    // ── A-12·H-73 · el equipo se decide con lo que hay DESPUÉS de la red ─────

    /// Un cliente que, **mientras la petición está en la red**, deja que otra
    /// escriba: es lo que hace una segunda petición que confirma antes que ésta.
    struct InterleavingClient: FederationClient {
        let calendar: FederationCalendar
        let meanwhile: @Sendable () async -> Void

        func coordinate(fromCalendarURL url: String) throws -> FederationCoordinate {
            Fixture.coordinate
        }
        func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
            await meanwhile()
            return calendar
        }
        func fetchStandings(
            _ coordinate: FederationCoordinate, round: Int
        ) async throws -> FederationStanding {
            throw NotStubbed(client: "InterleavingClient", operation: "fetchStandings")
        }
        func fetchScorers(_ coordinate: FederationCoordinate) async throws -> FederationScorerTable {
            throw NotStubbed(client: "InterleavingClient", operation: "fetchScorers")
        }
    }

    /// **Lo que otro enganche escribió mientras éste esperaba a la federación,
    /// manda** (A-12·H-73).
    ///
    /// El equipo se leía en el ámbito 1, antes de la red, y el ámbito 2 decidía
    /// con **esa copia**: `linked(…)` no veía el código que otra petición acababa
    /// de escribir, y `save` lo pisaba. Medido contra la RFFM real: el mismo
    /// equipo enganchado a dos grupos a la vez → **dos 202 y dos cascadas**, con
    /// la ventana entera de la llamada a la federación para que ocurra. Ahora el
    /// ámbito que escribe empieza **bloqueando y releyendo** el equipo, y el
    /// segundo recibe el 409 que habría recibido de llegar después.
    @Test("lo que otro enganche escribió mientras éste estaba en la red, manda (A-12·H-73)")
    func aLinkWrittenMeanwhileWins() async throws {
        let team = try Fixture.team()
        let store = IngestionStore()
        await store.seed(club: try Fixture.club())
        await store.seed(teams: [team])
        let elsewhere = try team.linked(toFederationTeamID: "3349087")
        let client = InterleavingClient(calendar: Fixture.calendar()) {
            await store.save(elsewhere)
        }

        await #expect(throws: DomainError.alreadyLinkedToFederation(
            existing: "3349087", incoming: "3349086")) {
            try await Self.useCase(store: store, federation: client)
                .execute(try Self.request(teamID: team.id), actor: Self.actor)
        }
        // Se para **antes** de escribir nada de la cascada, y el equipo queda con
        // lo que escribió el otro.
        #expect(await store.seasons.isEmpty)
        #expect(await store.teamRegistrations.isEmpty)
        #expect(await store.ingestionRuns.isEmpty)
        #expect(await store.teams.first?.federationTeamID == "3349087")
        // Y lo releyó **bloqueándolo**, que es lo que lo mantiene cierto el día
        // que dos ámbitos puedan estar abiertos a la vez (H-77).
        #expect(await store.teamLocks == [team.id])
    }

    // ── C-C.12 · sin adaptador se para ANTES del 202 ─────────────────────────

    /// **`H-28` en la segunda puerta, y la que `D-95` anunció.**
    ///
    /// La federación del club está en el catálogo del Dominio —el catálogo
    /// **declara sus capacidades**, que es lo que `D-17` pide— y su adaptador no
    /// existe: la raíz de composición devuelve `nil` **a propósito** (`D-95`).
    /// Las dos cosas a la vez son el diseño, no una incoherencia.
    ///
    /// **Se comprueba antes del `202`, no después.** El enganche encola una
    /// primera ingesta, y encolar trabajo que nadie sabe hacer dejaría una fila
    /// `accepted` que **jamás cierra** — un `202` mudo, que es justo lo que
    /// `D-88` dice que planificar antes de responder existe para evitar.
    ///
    /// La consecuencia de negocio, sin adornos: hasta que exista el adaptador de
    /// la FCF, **un club catalán no se puede enganchar con ingesta**. Lo que F10
    /// hace es que eso **se vea bien** — un 501 que dice *"vuelve cuando esté"*,
    /// no un 500 que invita a abrir una incidencia.
    @Test("sin adaptador no hay 202: se para, y no escribe nada (D-95, H-28)")
    func aFederationWithoutAnAdapterStopsBeforeTheAcceptance() async throws {
        let team = try Fixture.team()
        let store = IngestionStore()
        await store.seed(club: try Fixture.club(federation: .fcf))
        await store.seed(teams: [team])

        // El catálogo tiene la federación; el proveedor, solo el adaptador de la
        // RFFM. Es el cableado real de hoy.
        let useCase = Self.useCase(store: store, federation: Self.client(), code: .rffm)

        await #expect(throws: ApplicationError.federationAdapterMissing(
            federation: "fcf")) {
            try await useCase.execute(try Self.request(teamID: team.id), actor: Self.actor)
        }
        #expect(await store.writes == 0)
    }

    // ── C-C.13 · la guarda de D-84, en la puerta del enganche ────────────────

    /// **`D-84`: una coordenada equivocada no falla — devuelve el calendario de
    /// otra competición.**
    ///
    /// Está medido: la RFFM **ignora el parámetro `temporada`** y con
    /// `competicion`/`grupo` inexistentes responde `200` con `calendar: null`
    /// ([Anexo RFFM §F.16]). No hay tercera opción implícita, así que un dígito
    /// cambiado en la URL trae un calendario **perfectamente parseable de otra
    /// liga**.
    ///
    /// La pasada ya se protege con esto desde F5 (`CalendarPass`). Lo que este
    /// ciclo añade es la guarda **en la puerta por la que entra el humano**, que
    /// es donde el dígito se equivoca: aquí, pegando la URL. Sin ella, el
    /// enganche escribe el equipo contra un grupo que no es el suyo y el error
    /// no aparece hasta tres días después, en `ingestion_runs`.
    ///
    /// **Los dos silencios no paran nada, y es deliberado**: sin nombre guardado
    /// es la primera vez y no hay con qué comparar; si la fuente no publica
    /// nombre, callar no es contradecir (`D-56`).
    @Test("enganchar a un grupo que dice llamarse otra cosa se para (D-84)")
    func theSourceNameGuardStopsTheLink() async throws {
        let team = try Fixture.team()
        let season = try Fixture.season(federationSeasonID: "21")
        // La competición ya está, y guarda como evidencia el nombre con el que
        // se dio de alta (`D-72`).
        let competition = try Fixture.competition(
            seasonID: season.id, federationName: "PRIMERA INFANTIL")
        let store = IngestionStore()
        await store.seed(club: try Fixture.club())
        await store.seed(seasons: [season], competitions: [competition], teams: [team])

        // Y la fuente, con esa misma coordenada, dice otra cosa.
        let elsewhere = Self.client(Fixture.calendar(competitionName: "PRIMERA CADETE"))

        await #expect(throws: DomainError.federationSourceMismatch(
            expected: "PRIMERA INFANTIL", found: "PRIMERA CADETE")) {
            try await Self.useCase(store: store, federation: elsewhere)
                .execute(try Self.request(teamID: team.id), actor: Self.actor)
        }
        // El equipo **no queda enganchado**: la guarda va antes de escribir.
        #expect(await store.teams.first?.federationTeamID == nil)

        // La otra mitad: el mismo nombre no para nada.
        let agreeing = Self.client(Fixture.calendar(competitionName: "PRIMERA INFANTIL"))
        let result = try await Self.useCase(store: store, federation: agreeing)
            .execute(try Self.request(teamID: team.id), actor: Self.actor)

        #expect(result.competitionID == competition.id)
    }

    // ── C-C.14 · la guarda de D-91: la mediana de las fechas ─────────────────

    /// **`D-91`: hacen falta dos guardas y no una.**
    ///
    /// La de arriba compara el **nombre**, y eso caza *"me equivoqué de
    /// competición"*. Es **ciega** al error que ocurre cada verano —copiar los
    /// códigos del año pasado al dar de alta la temporada nueva— porque los
    /// rótulos `competicion` y `grupo` son **idénticos entre temporadas**,
    /// medido el 2026-09-13 sobre PRIMERA CADETE G4 ([Anexo RFFM §F.17]). Y la
    /// etiqueta de temporada tampoco sirve: es **el eco de nuestro propio
    /// parámetro** (§F.16), así que compararla sería comparar un dato consigo
    /// mismo.
    ///
    /// Lo único que no puede ser eco son **las fechas de los partidos**, que en
    /// un desfase de temporada se van doce meses. La regla es que **la mediana**
    /// caiga en la ventana de la `Season` — ni *"todas dentro"*, que tumbaría la
    /// competición para siempre por un aplazado a julio, ni *"que solapen"*, que
    /// ese mismo aplazado haría pasar.
    ///
    /// **Y aquí pesa más que en la pasada**, porque en la pasada la temporada ya
    /// estaba elegida: éste es el momento en que un humano acaba de pegar la URL
    /// del año pasado.
    @Test("un calendario del año pasado no se engancha a esta temporada (D-91)")
    func theSeasonWindowGuardStopsTheLink() async throws {
        let team = try Fixture.team()
        // 2025/26 va del 1 de julio de 2025 al 30 de junio de 2026 (§3.2).
        let season = try Fixture.season("2025/26", federationSeasonID: "21")
        let store = IngestionStore()
        await store.seed(club: try Fixture.club())
        await store.seed(seasons: [season], teams: [team])

        // El calendario que sirve esa misma coordenada es el de **2024/25**: la
        // URL que el administrador se trajo del verano pasado.
        let lastYear = Self.client(Fixture.calendar(rounds: [
            FederationRound(number: 1, matches: [
                Self.match("1", date: Fixture.instant("2024-09-14")),
                Self.match("2", date: Fixture.instant("2024-10-19")),
                Self.match("3", date: Fixture.instant("2024-11-23"))
            ])
        ]))

        await #expect(throws: DomainError.federationSeasonMismatch(
            seasonLabel: "2025/26",
            calendarMedian: Fixture.instant("2024-10-19"))) {
            try await Self.useCase(store: store, federation: lastYear)
                .execute(try Self.request(teamID: team.id), actor: Self.actor)
        }
        #expect(await store.teams.first?.federationTeamID == nil)

        // La otra mitad: el calendario de esta temporada pasa, **y pasa con un
        // aplazado fuera de la ventana** — que es lo que la mediana compra
        // frente a *"todas dentro"*.
        let thisYear = Self.client(Fixture.calendar(rounds: [
            FederationRound(number: 1, matches: [
                Self.match("1", date: Fixture.instant("2025-09-13")),
                Self.match("2", date: Fixture.instant("2025-10-18")),
                Self.match("3", date: Fixture.instant("2026-07-15"))
            ])
        ]))

        let result = try await Self.useCase(store: store, federation: thisYear)
            .execute(try Self.request(teamID: team.id), actor: Self.actor)

        #expect(result.seasonID == season.id)
    }

    // ── C-C.15 · el enganche RECHAZA la identidad que no cuadra ──────────────

    /// **El 409 que el contrato declara y que no lo levantaba nadie.**
    ///
    /// `C-A.3` escribió el predicado en el Dominio y `C-C.4` lo hizo viajar en
    /// el `/preview`. Faltaba lo que convierte el aviso en regla: que **la
    /// segunda puerta se niegue**. Sin esto, `identityMatches: false` es un
    /// adorno de pantalla —el cliente puede ignorarlo y confirmar igual— y el
    /// `409` que el *spec* declara para el enganche **no lo levantaría nunca
    /// nadie**.
    ///
    /// Lo que pasa sin él es lo que `D-58` llama *"no degrada, colisiona"*: el
    /// Cadete A queda enganchado a una competición **juvenil**, y la ingesta
    /// hereda `juvenil` a cada equipo que cree desde ella (`D-07`). Con
    /// `category` en la clave única de `Team` (§3.5), el choque llega **después
    /// y en otro sitio**, donde ya no se puede explicar.
    ///
    /// **A diferencia del 409 de `D-21`, éste tiene salida**: se engancha otro
    /// equipo, o se corrige antes de confirmar. Por eso el `/preview` lo enseña.
    @Test("enganchar un cadete a una competición juvenil se rechaza (D-58, §3.2)")
    func theLinkRefusesAnIdentityThatDoesNotMatch() async throws {
        let cadete = try Fixture.team(category: .cadete)
        let season = try Fixture.season(federationSeasonID: "21")
        let juvenil = try Fixture.competition(seasonID: season.id, ageCategory: .juvenil)
        let store = IngestionStore()
        await store.seed(club: try Fixture.club())
        await store.seed(seasons: [season], competitions: [juvenil], teams: [cadete])

        await #expect(throws: DomainError.competitionIdentityMismatch(
            team: "cadete/masculino/futbol_11",
            competition: "juvenil/masculino/futbol_11")) {
            try await Self.useCase(store: store, federation: Self.client())
                .execute(try Self.request(teamID: cadete.id), actor: Self.actor)
        }
        // Y no queda enganchado a medias: la guarda va antes de escribir.
        #expect(await store.teams.first?.federationTeamID == nil)
        #expect(await store.ingestionRuns.isEmpty)
    }

    /// Un partido con fecha y nada más: lo que la guarda de `D-91` mira.
    static func match(_ id: String, date: Date) -> FederationMatch {
        FederationMatch(
            federationMatchID: id,
            home: Fixture.teamRef("3349086", "C.D. EJEMPLO 'A'"),
            away: Fixture.teamRef("3349087", "C.D. GALAPAGAR 'B'"),
            homeScore: nil, awayScore: nil, date: date, kickoff: nil,
            venue: nil, venueCode: nil)
    }
}

import APIContract
import Application
import Domain
import Fluent
import Foundation
import HTTPAdapter
import SQLKit
import Testing
import Vapor
import VaporTesting
@testable import App
import TestSupport
@testable import Persistence
@testable import Tenancy

/// Nivel 4 (§8.1): **las dos puertas del enganche** (`D-67`), que es la
/// superficie HTTP que F10 estrena.
///
/// Hasta aquí la ingesta no pasaba por HTTP —su adaptador primario es un
/// `AsyncCommand` (§2.3-b)—, así que esta *suite* es el primer sitio donde se
/// puede afirmar lo que de verdad cruza la frontera: la ruta, el DTO y el
/// código. Las reglas ya están probadas en los niveles 2 y 3; aquí se prueba
/// **el borde**.
@Suite("FederationLink · D-67 · las dos puertas del enganche",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct FederationLinkEndpointTests {

    static let prefix = "e2e_"
    static let slug = "linkclub"
    static let now = instant("2026-03-02")

    static func instant(_ yyyyMMdd: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: yyyyMMdd)!
    }

    struct FixedClock: Clock {
        let instant: Date
        func now() -> Date { instant }
    }

    // ── La fuente, falseada ──────────────────────────────────────────────────

    /// La URL que el administrador pega del navegador. **El que la lee es el
    /// adaptador** ([D-97], `C-B.1`), así que aquí es solo el sobre: lo que el
    /// doble devuelve es la coordenada de abajo.
    static let url =
        "https://www.rffm.es/competicion/calendario"
        + "?temporada=21&tipojuego=1&competicion=24037548&grupo=24037549"

    static let coordinate = FederationCoordinate(
        federationSeasonID: "21",
        federationCompetitionID: "24037548",
        federationGroupID: "24037549",
        modality: .futbol11)

    /// **El escudo viaja de verdad en uno de ellos, y es deliberado.**
    ///
    /// Medido el 2026-09-25: **todos** los montajes del proyecto pasaban
    /// `crestURL: nil`, así que el campo cruzaba el `/preview` sin que nada lo
    /// mirara — y es el que hace reconocible la lista de equipos en la pantalla
    /// donde un humano identifica su club (`D-16`). Contra la RFFM de verdad
    /// viene siempre: 16 de 16 en el grupo que se probó a mano.
    static func teamRef(
        _ id: String?, _ name: String, crest: String? = nil
    ) -> FederationTeamRef {
        FederationTeamRef(
            federationTeamID: id, name: name, letter: nil,
            federationClubID: nil, crestURL: crest)
    }

    /// El escudo tal y como lo publica la fuente: **absoluto**, porque el *host*
    /// no es constante nuestra y lo compone el adaptador.
    static let crest =
        "https://appweb.rffm.es/pnfg/pimg/Clubes/00100_0010940034_ESC_EJEMPLO.png"

    /// Una jornada con un partido: lo mínimo con lo que `teams[]` dice algo.
    ///
    /// **Las fechas caen dentro de la ventana de 2025/26** a propósito: la
    /// guarda de [D-91] (`C-C.14`) pide que la mediana del calendario caiga
    /// dentro de la temporada, y un *fixture* fuera de ventana haría fallar la
    /// segunda puerta por un motivo que no es el suyo.
    /// **Y el tercer equipo llega SIN código a propósito** (`C-C.5`, F9-bis).
    ///
    /// No es adorno del *fixture*: es el caso que la regla protege. La fuente
    /// publica equipos sin `codigo_equipo` —medido— y ése **no desaparece de la
    /// lista**, porque desaparecer de `teams[]` es desaparecer de la pantalla
    /// donde un humano reconoce su club. Sin él en el montaje, un `/preview` que
    /// filtrara a los que no tienen código pasaría por verde: **la mutación M9 lo
    /// demostró sobreviviendo**.
    static let calendar = FederationCalendar(
        seasonLabel: try! SeasonLabel("2025/26"),
        competitionName: "PRIMERA CADETE",
        groupLabel: "Grupo 4",
        currentRound: 1,
        rounds: [
            FederationRound(number: 1, matches: [
                FederationMatch(
                    federationMatchID: "1",
                    home: teamRef("3349086", "C.D. EJEMPLO 'A'", crest: crest),
                    away: teamRef("3349087", "C.D. GALAPAGAR 'B'"),
                    homeScore: nil, awayScore: nil,
                    date: instant("2025-11-15"), kickoff: nil,
                    venue: nil, venueCode: nil),
                FederationMatch(
                    federationMatchID: "2",
                    home: teamRef(nil, "C.D. SIN CODIGO"),
                    away: teamRef("3349088", "A.D. TORRELODONES 'A'"),
                    homeScore: nil, awayScore: nil,
                    date: instant("2025-11-22"), kickoff: nil,
                    venue: nil, venueCode: nil)
            ])
        ])

    /// **Devuelve `nil` para la FCF a propósito**, que es lo que hace la raíz de
    /// composición de verdad ([D-95]): el catálogo del Dominio **declara** sus
    /// capacidades y el proveedor **no tiene adaptador que dar**. Las dos cosas a
    /// la vez son el diseño, no una incoherencia.
    /// El mismo calendario **sin la etiqueta de temporada**, que es lo que la
    /// RFFM devuelve cuando la temporada pedida no es una suya
    /// ([Anexo RFFM §F.16]).
    static let unlabelledCalendar = FederationCalendar(
        seasonLabel: nil,
        competitionName: "PRIMERA CADETE",
        groupLabel: "Grupo 4",
        currentRound: 1,
        rounds: calendar.rounds)

    struct StubProvider: FederationClientProvider {
        let client: StubClient
        func client(for code: FederationCode) -> (any FederationClient)? {
            code == .fcf ? nil : client
        }
    }

    struct StubClient: FederationClient {
        /// Lo que la fuente hace mal, cuando el test quiere que lo haga
        /// (`C-E.1`). `nil` es el camino feliz.
        var failure: FederationError?

        /// La URL que el adaptador no sabe leer (`C-B.2`, `C-E.8`). **Es del
        /// adaptador y no del caso de uso** ([D-97]): el llamante llega por club
        /// → `Club.federation` → proveedor, y **no sabe de qué federación es lo
        /// que le han pegado**.
        var unreadableURL = false

        /// El calendario sin etiqueta de temporada, que es lo que deja a la
        /// primera puerta sin nada honesto que enseñar (`C-C.8`, `C-E.8`).
        var withoutSeasonLabel = false

        func coordinate(fromCalendarURL url: String) throws -> FederationCoordinate {
            if unreadableURL {
                throw DomainError.unreadableFederationURL(
                    url: url, reason: "Esa URL no es de la RFFM")
            }
            return FederationLinkEndpointTests.coordinate
        }

        func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
            if let failure { throw failure }
            if withoutSeasonLabel { return FederationLinkEndpointTests.unlabelledCalendar }
            return FederationLinkEndpointTests.calendar
        }

        /// **Lanza**, y puede: `IngestStandings` no siempre pregunta — sin
        /// jornadas jugadas su plan sale vacío y no toca la red—. Así, un test
        /// que llegue aquí por accidente falla en vez de pasar por el motivo
        /// equivocado (`H-07`).
        func fetchStandings(
            _ coordinate: FederationCoordinate, round: Int
        ) async throws -> FederationStanding {
            throw NotStubbed(client: "StubClient", operation: "fetchStandings")
        }

        /// **Devuelve vacío en vez de lanzar, y la asimetría con su vecina es del
        /// código, no del doble** — la misma que `IngestionEndpointTests` dejó
        /// escrita.
        ///
        /// `IngestScorers` no tiene el filtro de jornadas: el ranking es de la
        /// competición entera (§3.2), así que **toda** pasada pregunta. Un doble
        /// que lanzara aquí tumbaría el recorrido entero por un motivo que no es
        /// el suyo — y lo hizo: el primer rojo de `C-E.4` fue este `throw`
        /// cerrando en `failed` una pasada de goleadores que nadie estaba
        /// probando. Vacío **no es mentira**: es lo que devuelve una liga recién
        /// empezada, que es exactamente el estado en que queda un enganche
        /// (`D-48`).
        func fetchScorers(
            _ coordinate: FederationCoordinate
        ) async throws -> FederationScorerTable {
            FederationScorerTable(competitionName: nil, rows: [])
        }
    }

    // ── El montaje ───────────────────────────────────────────────────────────

    /// El *schema* del club con **un equipo propio sin enganchar**, que es el
    /// único estado desde el que [D-67] engancha.
    ///
    /// Se siembra **por repositorio y no por HTTP**: `POST /v1/teams` es del
    /// bloque del backoffice y no existe (§1.3 del plan de F10). El precedente
    /// es F1, y la herramienta equivalente es `seed-team` (`C-F.1`).
    static func withSeededTeam(
        category: TeamCategory = .cadete,
        gender: Gender = .masculino,
        modality: Modality = .futbol11,
        federationTeamID: String? = nil,
        federation: FederationCode = .rffm,
        federationFailure: FederationError? = nil,
        unreadableURL: Bool = false,
        withoutSeasonLabel: Bool = false,
        _ body: @escaping @Sendable (Application, TeamID) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp(
            federationClients: StubProvider(client: StubClient(
                failure: federationFailure,
                unreadableURL: unreadableURL,
                withoutSeasonLabel: withoutSeasonLabel)),
            background: InlineBackgroundWork(),
            clock: FixedClock(instant: now)
        ) { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(
                slug, federation: federation, schemaPrefix: prefix, on: app)

            let teamID = TeamID(raw: UUID())
            try await unitOfWork(app).withRepositories(actor: actor()) { repositories in
                try await repositories.teams.save(
                    try Team(
                        id: teamID, opponentClubID: nil,
                        category: category, letter: "A", gender: gender, modality: modality,
                        federationTeamID: federationTeamID,
                        createdAt: now, updatedAt: now))
            }

            try await body(app, teamID)
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func unitOfWork(_ app: Application) -> FluentTenantUnitOfWork {
        FluentTenantUnitOfWork(controlDatabase: app.db(.control))
    }

    static func actor() -> ActorContext {
        ActorContext(clubSlug: try! Slug(slug))
    }

    /// Cuenta filas de una tabla del *schema* del club, **en crudo**.
    ///
    /// Fuera de todo ámbito de tenant a propósito: el ámbito *es* una
    /// transacción (§6.2), así que contar desde dentro no distingue lo escrito
    /// de lo confirmado.
    static func rowCount(_ table: String, on app: Application) async throws -> Int {
        let sql = app.db(.control) as! any SQLDatabase
        return try await sql.raw(
            "SELECT count(*) AS n FROM \(ident: "\(prefix)\(slug)").\(ident: table)"
        ).first(decodingColumn: "n", as: Int.self) ?? 0
    }

    static func header(_ request: inout TestingHTTPRequest) {
        request.headers.add(name: "X-Club", value: slug)
    }

    /// El cuerpo se codifica con **el tipo generado del *spec***, no con un JSON
    /// a mano: si el contrato y lo que el test manda divergieran, esto no
    /// compilaría (`D-65`).
    static func previewBody(_ request: inout TestingHTTPRequest, url: String = url) throws {
        let payload = Components.Schemas.FederationLinkPreviewRequest(federationCalendarUrl: url)
        request.headers.contentType = .json
        request.body = ByteBuffer(
            string: String(decoding: try JSONEncoder().encode(payload), as: UTF8.self))
    }

    static func decodePreview(_ response: TestingHTTPResponse) throws
        -> Components.Schemas.FederationLinkPreviewResponse
    {
        try JSONDecoder().decode(
            Components.Schemas.FederationLinkPreviewResponse.self,
            from: Data(response.body.readableBytesView))
    }

    /// El cuerpo de la **segunda** puerta: la URL otra vez —el `/preview` no
    /// persistió nada— y el equipo del grupo que el administrador ha reconocido
    /// como suyo (`D-67`).
    static func linkBody(
        _ request: inout TestingHTTPRequest,
        url: String = url,
        ownTeamFederationID: String = "3349086",
        gender: Components.Schemas.Gender = .masculino,
        seasonLabel: String? = "2025/26"
    ) throws {
        let payload = Components.Schemas.FederationLinkRequest(
            federationCalendarUrl: url,
            ownTeamFederationId: ownTeamFederationID,
            gender: .init(value1: gender),
            seasonLabel: seasonLabel)
        request.headers.contentType = .json
        request.body = ByteBuffer(
            string: String(decoding: try JSONEncoder().encode(payload), as: UTF8.self))
    }

    static func decodeJob(_ response: TestingHTTPResponse) throws
        -> Components.Schemas.IngestJobResponse
    {
        try JSONDecoder().decode(
            Components.Schemas.IngestJobResponse.self,
            from: Data(response.body.readableBytesView))
    }

    // ─────────────────────────────────────────────────────────────────────────

    /// `C-E.3`: **el `/preview` enseña lo que hay en la coordenada** (`D-67`,
    /// §2.3-c).
    ///
    /// Es la única ruta síncrona con latencia de terceros: llama a la federación
    /// **dentro de la petición** y devuelve lo que hay ahí, para que un humano
    /// reconozca su club en `teams[]` antes de confirmar (`D-16`).
    ///
    /// Lo que este test fija es que la respuesta es **la del caso de uso** y no
    /// la del esqueleto que el Bloque 0 dejó puesto para mantener el *build*
    /// verde: los tres rótulos, la coordenada, el recuento de jornadas y la
    /// lista de equipos salen del calendario de la fuente.
    @Test("el /preview enseña lo que hay en la coordenada (200, D-67 · C-E.3)")
    func previewShowsWhatIsInTheCoordinate() async throws {
        try await Self.withSeededTeam { app, teamID in
            try await app.testing().test(
                .POST,
                "/v1/teams/\(teamID.raw.uuidString.lowercased())/federation-link/preview",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.previewBody(&request)
                }
            ) { response async throws in
                #expect(response.status == .ok)
                let preview = try Self.decodePreview(response)

                // La temporada: el **código** de la coordenada y la etiqueta que
                // la fuente publica. `exists: false` ⇒ al confirmar se creará en
                // cascada (`C-C.2`).
                #expect(preview.season.federationSeasonId == "21")
                #expect(preview.season.label == "2025/26")
                #expect(preview.season.exists == false)

                // La competición: los rótulos de la fuente y la coordenada
                // entera, que es lo que el administrador reconoce en la web de
                // la federación (`D-16`).
                #expect(preview.competition.divisionLabel == "PRIMERA CADETE")
                #expect(preview.competition.groupLabel == "Grupo 4")
                #expect(preview.competition.federationCompetitionId == "24037548")
                #expect(preview.competition.federationGroupId == "24037549")
                #expect(preview.competition.roundCount == 1)
                #expect(preview.competition.alreadyRegistered == false)

                // **La razón de ser del endpoint**: los equipos del grupo, en el
                // orden en que aparecen, con el código que luego viaja como
                // `ownTeamFederationId` (`C-C.5`).
                #expect(preview.competition.teams.map(\.federationTeamId)
                    == ["3349086", "3349087", nil, "3349088"])
                #expect(preview.competition.teams.first?.rawName == "C.D. EJEMPLO 'A'")

                // **Y el que no trae código viaja igual, con el campo nulo.**
                // Filtrarlo aquí escondería el caso justo en la pantalla donde un
                // humano tiene que reconocer su club; elegirlo como propio ya lo
                // impide la otra puerta, donde `ownTeamFederationId` es
                // obligatorio (`D-67`).
                let unidentified = preview.competition.teams.first { $0.federationTeamId == nil }
                #expect(unidentified?.rawName == "C.D. SIN CODIGO")

                // **Y el escudo llega entero cuando la fuente lo da**, que es lo
                // que hace la lista reconocible: es una pantalla donde alguien
                // busca su club, y un nombre en mayúsculas sin escudo se parece
                // demasiado al de al lado. Va **en el origen**, sin descargar
                // (`D-19`): bajarlo a Storage es de la ingesta, no de esto.
                #expect(preview.competition.teams.first?.crestUrl == Self.crest)

                // Y nulo cuando no lo da — la otra mitad, sin la cual un mapeo
                // que devolviera siempre la misma URL pasaría por verde.
                #expect(unidentified?.crestUrl == nil)

                // La identidad: competición nueva ⇒ los tres se proponen y la
                // edad sale del equipo, así que cuadra por construcción
                // (`C-C.4`, Bloque C).
                #expect(preview.competition.ageCategory == .cadete)
                #expect(preview.competition.modality == .futbol_11)
                #expect(preview.identityMatches == true)
            }
        }
    }

    /// `C-E.3`, la otra mitad: **de aquí no sale una sola escritura** (`C-C.1`).
    ///
    /// El atajo natural es adelantar la cascada —la temporada que falta está en
    /// la mano—, y lo que lo hace inaceptable no es el coste: es que **entre
    /// esta respuesta y el enganche hay un humano** que todavía no ha
    /// reconocido su club en `teams[]` y que puede cerrar la pestaña. Una
    /// `Season` creada aquí quedaría dada de alta por una URL que nadie
    /// confirmó.
    ///
    /// El nivel 2 ya lo afirma con un repositorio que cuenta; esto lo afirma
    /// **contra Postgres y por la ruta HTTP**, que es donde un `save` de más en
    /// el adaptador no lo vería nadie.
    @Test("y el /preview no deja una sola fila escrita (C-C.1 · C-E.3)")
    func previewWritesNothing() async throws {
        try await Self.withSeededTeam { app, teamID in
            try await app.testing().test(
                .POST,
                "/v1/teams/\(teamID.raw.uuidString.lowercased())/federation-link/preview",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.previewBody(&request)
                }
            ) { response async throws in
                #expect(response.status == .ok)
            }

            // **Fuera del ámbito de la petición**, que es lo que hace que esto
            // signifique algo: el ámbito de tenant *es* una transacción (§6.2),
            // así que preguntar desde dentro no distinguiría lo escrito de lo
            // confirmado.
            try await Self.unitOfWork(app).withRepositories(actor: Self.actor()) { repositories in
                let seasons = try await repositories.seasons.list(includingArchived: true)
                #expect(seasons.isEmpty, "el /preview ha dado de alta una temporada")

                // Y el equipo sigue **sin enganchar**: lo que engancha es la
                // segunda puerta, y solo tras la confirmación de un humano.
                let team = try await repositories.teams.find(teamID)
                #expect(team?.federationTeamID == nil)

            }

            // La constancia de [D-96] es de la puerta que **acepta trabajo**, no
            // de la que solo mira: una fila `accepted` aquí prometería una pasada
            // que nadie ha pedido. Se cuenta en crudo porque el repositorio solo
            // sabe listar **por competición**, y aquí lo que hay que afirmar es
            // que no hay ninguna de nadie.
            #expect(try await Self.rowCount("ingestion_runs", on: app) == 0)
        }
    }
}

extension FederationLinkEndpointTests {

    /// `C-E.4`: **el enganche responde 202 con algo que consultar** (`D-67`,
    /// `D-96`).
    ///
    /// `202` y no `201` porque la primera ingesta **no puede ser síncrona**: en
    /// la RFFM el calendario es una petición, pero detrás vienen ~240 partidos
    /// y un escudo por club que descargar (`D-19`). Lo que el cuerpo trae no es
    /// el resultado: es **con qué seguirlo**.
    ///
    /// Los cuatro identificadores tienen que apuntar a filas de verdad —la
    /// temporada y la competición que la cascada acaba de crear, el equipo que
    /// se acaba de enganchar y la fila `accepted` que deja el rastro—, que es
    /// justo lo que el esqueleto del Bloque 0 no podía hacer: devolvía los
    /// cuatro a ceros.
    @Test("el enganche responde 202 con el trabajo encolado (D-67 · C-E.4)")
    func linkingAcceptsAndSaysWhatToFollow() async throws {
        try await Self.withSeededTeam { app, teamID in
            try await app.testing().test(
                .POST,
                "/v1/teams/\(teamID.raw.uuidString.lowercased())/federation-link",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.linkBody(&request)
                }
            ) { response async throws in
                #expect(response.status == .accepted)
                let job = try Self.decodeJob(response)

                #expect(job.teamId == teamID.raw.uuidString.lowercased())
                #expect(job.status == .encolado)

                // **Los ids son de filas que existen**, no de un eco del cuerpo:
                // la temporada y la competición las acaba de crear la cascada
                // (`C-C.6`, `C-C.7`) y el `jobId` es la fila `accepted` que
                // `D-96` exige escribir **antes** de responder.
                let season = try #require(UUID(uuidString: job.seasonId))
                let competition = try #require(UUID(uuidString: job.competitionId))
                let jobID = try #require(UUID(uuidString: job.jobId))
                #expect(season != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))

                try await Self.unitOfWork(app).withRepositories(actor: Self.actor()) {
                    repositories in
                    let stored = try await repositories.seasons.find(SeasonID(raw: season))
                    #expect(stored?.federationSeasonID == "21")
                    #expect(stored?.label.value == "2025/26")

                    let group = try await repositories.competitions
                        .find(CompetitionID(raw: competition))
                    #expect(group?.federationGroupID == "24037549")
                    #expect(group?.seasonID.raw == season)

                    // El enganche propiamente dicho: el equipo sale de aquí con
                    // el código que el administrador reconoció en `teams[]`.
                    let team = try await repositories.teams.find(teamID)
                    #expect(team?.federationTeamID == "3349086")

                    // Y la inscripción de [D-68], que la cascada escribe para que
                    // **todo equipo propio con calendario esté inscrito por
                    // construcción**.
                    let registrations = try await repositories.teamRegistrations
                        .list(teamID: teamID, seasonID: SeasonID(raw: season))
                    #expect(registrations.count == 1)
                    #expect(registrations.first?.competitionID?.raw == competition)

                    let runs = try await repositories.ingestionRuns.list(
                        competitionID: CompetitionID(raw: competition), limit: 10)
                    #expect(runs.contains { $0.id.raw == jobID })
                }
            }
        }
    }
}

extension FederationLinkEndpointTests {

    /// `C-E.4`, la otra mitad: **la primera ingesta queda encolada de verdad**
    /// (`D-67`), y la pasada **cierra la fila que el `202` abrió** en vez de
    /// escribir una segunda (F10-bis).
    ///
    /// Es lo que separa este `202` de un *"202 mudo"*: sin el encolado, la fila
    /// `accepted` de `D-96` no cerraría jamás y `ingestionHealth` (`D-89`) se
    /// quedaría mirando una pasada que nadie hizo. Y que la fila sea **una** es
    /// lo que hace que el `jobId` que se devolvió siga sirviendo después: si la
    /// pasada abriera la suya, el identificador que tiene el backoffice apuntaría
    /// para siempre a una fila `accepted`.
    ///
    /// El trabajo de fondo corre **en línea** (`InlineBackgroundWork`): la misma
    /// ruta de código que en producción, sin carrera que arbitrar.
    @Test("y detrás del 202 la pasada corre y cierra ESA fila (D-96 · C-E.4)")
    func theAcceptedRunIsTheOneThatCloses() async throws {
        try await Self.withSeededTeam { app, teamID in
            var jobID: String?
            try await app.testing().test(
                .POST,
                "/v1/teams/\(teamID.raw.uuidString.lowercased())/federation-link",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.linkBody(&request)
                }
            ) { response async throws in
                #expect(response.status == .accepted)
                jobID = try Self.decodeJob(response).jobId
            }

            let id = try #require(jobID.flatMap { UUID(uuidString: $0) })
            try await Self.unitOfWork(app).withRepositories(actor: Self.actor()) { repositories in
                let seasons = try await repositories.seasons.list(includingArchived: true)
                let seasonID = try #require(seasons.first?.id)
                let competition = try #require(
                    try await repositories.competitions.list(seasonID: seasonID).first)
                let runs = try await repositories.ingestionRuns.list(
                    competitionID: competition.id, limit: 10)

                // **Una del calendario, no dos**: la pasada adopta la `accepted`
                // que la cascada dejó (`IngestCalendar` la busca antes de abrir
                // la suya). Se filtra por `kind` porque el recorrido de un club
                // es **tres** pasadas —calendario, clasificación y goleadores—,
                // así que "cuántas filas hay" no es la pregunta.
                let calendarRuns = runs.filter { $0.kind == .calendar }
                #expect(calendarRuns.count == 1)

                let run = try #require(calendarRuns.first)
                #expect(run.id.raw == id, "la pasada abrió una fila nueva en vez de cerrar la aceptada")
                // Cerrada: `accepted` es un estado de tránsito, no un desenlace.
                #expect(run.outcome == .succeeded)
                #expect(run.finishedAt != nil)

                // Y el calendario está escrito, que es para lo que se encoló —
                // **los dos partidos**, incluido el del equipo que la fuente
                // publica sin código: ése se escribe **cojo y no ausente**
                // (F9-bis), y por eso no se cuentan las líneas de `skipped`.
                #expect(try await repositories.matches.list(
                    competitionID: competition.id).count == 2)
            }
        }
    }
}

extension FederationLinkEndpointTests {

    static func decodeProblem(_ response: TestingHTTPResponse) throws
        -> Components.Schemas.Problem
    {
        try JSONDecoder().decode(
            Components.Schemas.Problem.self, from: Data(response.body.readableBytesView))
    }

    /// `C-E.5`: **el equipo que ya está enganchado da 409** (`D-66`, `C-A.2`).
    ///
    /// `409` y no `422`: el `codigo_equipo` que llega es perfectamente válido —
    /// lo que no lo es es el **estado** del equipo. Y a diferencia del 409 de
    /// `D-21`, éste **tiene salida**: se engancha otro equipo, o se corrige la
    /// URL antes de confirmar.
    @Test("enganchar un equipo ya emparejado es 409 (D-66 · C-E.5)")
    func relinkingIsRejected() async throws {
        try await Self.withSeededTeam(federationTeamID: "1111111") { app, teamID in
            try await app.testing().test(
                .POST,
                "/v1/teams/\(teamID.raw.uuidString.lowercased())/federation-link",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.linkBody(&request, ownTeamFederationID: "3349086")
                }
            ) { response async throws in
                #expect(response.status == .conflict)
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == "ALREADY_LINKED_TO_FEDERATION")
                #expect(problem.status == 409)
                // El `detail` lleva **los dos códigos**: quien lo lee es el
                // administrador, y sin ellos no sabría cuál de sus equipos es.
                #expect(problem.detail?.contains("1111111") == true)
                #expect(problem.detail?.contains("3349086") == true)
            }

            // Y no se ha escrito nada: el 409 llega **antes** de la cascada.
            #expect(try await Self.rowCount("seasons", on: app) == 0)
        }
    }
}

extension FederationLinkEndpointTests {

    /// Siembra la temporada y la competición del grupo **que la URL apunta**,
    /// para los casos en que la cascada tiene que **reutilizar** en vez de crear.
    static func seedExistingCompetition(
        ageCategory: TeamCategory,
        gender: Gender = .masculino,
        modality: Modality = .futbol11,
        on app: Application
    ) async throws -> CompetitionID {
        let seasonID = SeasonID(raw: UUID())
        let competitionID = CompetitionID(raw: UUID())
        try await unitOfWork(app).withRepositories(actor: actor()) { repositories in
            try await repositories.seasons.save(
                try Season(
                    id: seasonID, label: try SeasonLabel("2025/26"),
                    federationSeasonID: "21", createdAt: now, updatedAt: now))
            try await repositories.competitions.save(
                try Competition(
                    id: competitionID, seasonID: seasonID,
                    modality: modality, gender: gender,
                    federationCompetitionID: "24037548", federationGroupID: "24037549",
                    ageCategory: ageCategory, divisionLabel: "Primera División Autonómica",
                    groupLabel: "Grupo 4", federationName: "PRIMERA CADETE",
                    createdAt: now, updatedAt: now))
        }
        return competitionID
    }

    /// `C-E.5`, la otra mitad: **la identidad que no cuadra también es 409**
    /// (`C-C.15`, `D-58`).
    ///
    /// Es el caso que `D-58` describe: el Cadete A enganchado a una competición
    /// **juvenil** que otro equipo del club dio de alta. La edad solo muerde
    /// cuando la competición **ya existe** — en un alta nueva la presta el propio
    /// equipo y cuadra por construcción.
    ///
    /// Y lo que de verdad prueba este test es que el 409 **no deja nada a
    /// medias**: la guarda vive dentro del ámbito de la cascada, que es una
    /// transacción (§6.2), así que la inscripción y el enganche que ya se habían
    /// intentado se van con el `rollback`.
    @Test("enganchar a una competición de otra edad es 409 y no escribe (D-58 · C-E.5)")
    func identityMismatchIsRejected() async throws {
        try await Self.withSeededTeam(category: .cadete) { app, teamID in
            _ = try await Self.seedExistingCompetition(ageCategory: .juvenil, on: app)

            try await app.testing().test(
                .POST,
                "/v1/teams/\(teamID.raw.uuidString.lowercased())/federation-link",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.linkBody(&request)
                }
            ) { response async throws in
                #expect(response.status == .conflict)
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == "COMPETITION_IDENTITY_MISMATCH")
                // **Las dos ternas enteras**: quien lo lee es un administrador
                // mirando dos rótulos, así que no hace falta un campo que diga
                // cuál de los tres falla.
                #expect(problem.detail?.contains("cadete") == true)
                #expect(problem.detail?.contains("juvenil") == true)
            }

            try await Self.unitOfWork(app).withRepositories(actor: Self.actor()) { repositories in
                // El equipo sigue sin enganchar y sin inscribir: el `rollback` se
                // llevó las dos escrituras que la cascada ya había hecho.
                let team = try await repositories.teams.find(teamID)
                #expect(team?.federationTeamID == nil)
            }
            #expect(try await Self.rowCount("team_registrations", on: app) == 0)
            #expect(try await Self.rowCount("ingestion_runs", on: app) == 0)
        }
    }

    /// `C-E.6`: **el equipo que no existe es 404** (`D-67`).
    ///
    /// El id lo puso quien llama, así que es un dato **suyo** que no existe — no
    /// un *schema* roto, que es el criterio opuesto de `seasonNotFound`. Tiene
    /// suelo desde `C-D.1`: `find` devuelve `nil` cuando no hay fila, y sin esa
    /// mitad la ruta no podría distinguir *"ese equipo no existe"* de *"existe y
    /// no lo encuentro"*.
    @Test("un equipo inexistente es 404 en las dos puertas (C-E.6)")
    func unknownTeamIsNotFound() async throws {
        try await Self.withSeededTeam { app, _ in
            let ghost = UUID().uuidString.lowercased()

            for path in ["/federation-link/preview", "/federation-link"] {
                try await app.testing().test(
                    .POST, "/v1/teams/\(ghost)\(path)",
                    beforeRequest: { request async throws in
                        Self.header(&request)
                        if path.hasSuffix("preview") {
                            try Self.previewBody(&request)
                        } else {
                            try Self.linkBody(&request)
                        }
                    }
                ) { response async throws in
                    #expect(response.status == .notFound, "\(path)")
                    let problem = try Self.decodeProblem(response)
                    #expect(problem.code == "TEAM_NOT_FOUND", "\(path)")
                    // **Comparado EXACTO, y eso es lo que `F10-ter` compró.**
                    // Hasta entonces el `detail` llevaba el UUID en mayúsculas
                    // —`"\(id.raw)"`, que es lo que hace Foundation— mientras que
                    // todo identificador de un cuerpo viaja en minúsculas
                    // (RFC 4122 §3), así que esta línea tenía que bajar la caja
                    // para pasar. Ahora la forma la decide el tipo y esto puede
                    // exigir lo que un cliente exigiría: que el error diga **el
                    // mismo id** que él envió.
                    #expect(problem.detail == ghost, "\(path)")
                }
            }
        }
    }

    /// `C-E.7`: **el administrador catalán recibe 501, con cuerpo RFC 7807**
    /// ([D-95], `H-28`).
    ///
    /// `501` y no `500`: no se ha roto nada. La federación **está en el
    /// catálogo** —`D-17` pide que declare sus capacidades— y lo que no existe
    /// es su adaptador. Un 500 invitaría a reintentar y a abrir una incidencia;
    /// el 501 dice la verdad: vuelve cuando esté.
    ///
    /// Se comprueba en **las dos** puertas y por motivos distintos: el
    /// `/preview` llama a la federación en línea, así que sin adaptador no hay
    /// nada que enseñar; el enganche encola trabajo, y encolar lo que nadie sabe
    /// hacer dejaría una fila `accepted` que **jamás cierra** (`C-C.12`).
    @Test("un club sin adaptador de federación recibe 501 (D-95 · C-E.7)")
    func aClubWithoutAdapterGetsNotImplemented() async throws {
        try await Self.withSeededTeam(federation: .fcf) { app, teamID in
            for path in ["/federation-link/preview", "/federation-link"] {
                try await app.testing().test(
                    .POST, "/v1/teams/\(teamID.raw.uuidString.lowercased())\(path)",
                    beforeRequest: { request async throws in
                        Self.header(&request)
                        if path.hasSuffix("preview") {
                            try Self.previewBody(&request)
                        } else {
                            try Self.linkBody(&request)
                        }
                    }
                ) { response async throws in
                    #expect(response.status == .notImplemented, "\(path)")
                    let problem = try Self.decodeProblem(response)
                    #expect(problem.code == "FEDERATION_ADAPTER_MISSING", "\(path)")
                    #expect(problem.detail?.contains("fcf") == true, "\(path)")
                }
            }

            // **El `202` mudo que esto evita**: sin la guarda, el enganche habría
            // dejado una fila `accepted` prometiendo una pasada que nadie puede
            // hacer.
            #expect(try await Self.rowCount("ingestion_runs", on: app) == 0)
        }
    }
}

extension FederationLinkEndpointTests {

    /// `C-E.1`: **las cuatro señales de `FederationError` dejan de ser el mismo
    /// 500** (`A-6`·H-15).
    ///
    /// # Por qué importa aquí y no antes
    ///
    /// Porque el `/preview` llama a la federación **dentro de la petición**
    /// (§2.3-c). Hasta F10 la ingesta no cruzaba HTTP y el `202` respondía antes
    /// de llamar, así que las cuatro caían en el `default` del `switch` y nadie
    /// lo notaba. El propio fichero justificaba la taxonomía —*"un caso de uso
    /// tiene que poder distinguir «la fuente no contesta» de «la fuente contesta
    /// algo que no entiendo»"*— y **en producción no la distinguía nadie**.
    ///
    /// # El reparto, y el que costó decidirlo
    ///
    /// El *spec* declara dos códigos y dice qué significa cada uno: **504** es
    /// *"no respondió dentro del timeout"* y **502** *"respondió con un error o
    /// con un cuerpo no interpretable"*. Eso coloca solo a tres.
    ///
    /// El cuarto, `coordinateNotFound`, es el que tiene dos lecturas y se
    /// resolvió **midiendo**: para cuando se pregunta a la fuente, la URL ya pasó
    /// por `coordinate(fromCalendarURL:)`, que rechaza con **400** la que no se
    /// puede leer (`C-B.2`). Así que los cuatro parámetros están bien formados y
    /// lo que falla es la respuesta. Y por [D-84] **no se puede afirmar que la
    /// coordenada no exista**: la RFFM devuelve `200` con `calendar: null` tanto
    /// para una coordenada inventada como para lo que hoy no publique. Un `400`
    /// diría al administrador *"tu URL está mal"* afirmando algo que está medido
    /// que no se sabe.
    @Test("los cuatro fallos de la federación tienen su propio código (A-6/H-15 · C-E.1)",
          arguments: [
            (FederationError.transportFailure(url: "https://www.rffm.es", reason: "timeout"),
             HTTPStatus.gatewayTimeout, "FEDERATION_UNREACHABLE"),
            (FederationError.malformedResponse(field: "calendar.rounds[3]", reason: "falta"),
             HTTPStatus.badGateway, "FEDERATION_MALFORMED_RESPONSE"),
            (FederationError.unexpectedStatus(status: 503, url: "https://www.rffm.es"),
             HTTPStatus.badGateway, "FEDERATION_UNEXPECTED_STATUS"),
            (FederationError.coordinateNotFound(detail: "21/24037548/24037549"),
             HTTPStatus.badGateway, "FEDERATION_COORDINATE_NOT_FOUND"),
          ])
    func federationFailuresAreTold(
        failure: FederationError, expected: HTTPStatus, code: String
    ) async throws {
        try await Self.withSeededTeam(federationFailure: failure) { app, teamID in
            try await app.testing().test(
                .POST,
                "/v1/teams/\(teamID.raw.uuidString.lowercased())/federation-link/preview",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.previewBody(&request)
                }
            ) { response async throws in
                #expect(response.status == expected)
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == code)
                // **El motivo viaja**: es un 5xx, así que el `detail` se calla
                // fuera de desarrollo (`exposesInternalDetail`), pero el `code` y
                // el `title` son lo que distingue *"la RFFM está caída"* de *"la
                // RFFM cambió de formato"* — que es la distinción entera.
                #expect(problem.title.isEmpty == false)
            }
        }
    }
}

extension FederationLinkEndpointTests {

    /// `C-E.8`: **los dos `Problem` que la fase estrena y que todavía no
    /// afirmaba nadie** (`A-7`·H-46).
    ///
    /// El hallazgo que abrió H-46 es que las aserciones de error fijan **el
    /// tipo** y no **el caso**, cuando cada caso es un código HTTP razonado
    /// aparte: intercambiar dos deja la batería en verde. Su medida de fondo era
    /// que de los códigos `Problem` que el middleware puede emitir, **tres** los
    /// afirmaba algún test. F10 estrena seis más, y los otros cuatro ya viajan
    /// con su ciclo —el 409 doble, el 404, el 501 y los cuatro de la federación—.
    ///
    /// Estos dos son los que quedaban sueltos, y los dos son **400**: uno porque
    /// el sobre no se puede abrir, el otro porque dentro falta lo que hacía
    /// falta. El criterio es el mismo y lo escribió `invalidValue` en su día —
    /// *"el 400 se reserva para lo que ni siquiera se pudo decodificar"*— con la
    /// otra mitad puesta por el contrato: **las dos puertas declaran 400 y no
    /// declaran 422** (`C-0.5`).
    @Test("la URL que no es de la federación del club es 400 (D-97 · C-B.2 · C-E.8)")
    func anUnreadableURLIsRejected() async throws {
        try await Self.withSeededTeam(unreadableURL: true) { app, teamID in
            try await app.testing().test(
                .POST,
                "/v1/teams/\(teamID.raw.uuidString.lowercased())/federation-link/preview",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.previewBody(&request, url: "https://www.fcf.cat/calendari")
                }
            ) { response async throws in
                #expect(response.status == .badRequest)
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == "UNREADABLE_FEDERATION_URL")
                // **El motivo y la URL van enteros**: es un 4xx, así que el
                // `detail` no se calla, y quien lo lee es el administrador que
                // acaba de pegarla.
                #expect(problem.detail?.contains("no es de la RFFM") == true)
                #expect(problem.detail?.contains("fcf.cat") == true)
            }
        }
    }

    /// `C-E.8`, el segundo: **la temporada que la fuente no rotula**.
    ///
    /// `Season.label` no es cosmético — de él sale la ventana de fechas que la
    /// guarda de [D-91] usa como evidencia (`C-C.14`), así que inventarlo no da
    /// un rótulo feo: **desarma la comprobación de al lado**. El `/preview` no
    /// tiene cuerpo que traiga la etiqueta, así que sin ella y con temporada
    /// nueva no hay nada honesto que enseñar.
    ///
    /// Y el `detail` **dice qué hacer**, no solo qué pasó: la salida —dar de alta
    /// la temporada antes— no es deducible del título.
    @Test("sin etiqueta de temporada y con temporada nueva, 400 (D-91 · C-E.8)")
    func aSeasonWithoutLabelIsRejected() async throws {
        try await Self.withSeededTeam(withoutSeasonLabel: true) { app, teamID in
            try await app.testing().test(
                .POST,
                "/v1/teams/\(teamID.raw.uuidString.lowercased())/federation-link/preview",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.previewBody(&request)
                }
            ) { response async throws in
                #expect(response.status == .badRequest)
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == "SEASON_LABEL_UNAVAILABLE")
                #expect(problem.detail?.contains("21") == true)
                #expect(problem.detail?.contains("Da de alta la temporada") == true)
            }
        }
    }

    /// Y la otra mitad de la regla anterior: **con la temporada ya dada de alta,
    /// la etiqueta es la nuestra y no hace falta la de la fuente** (`C-C.2`).
    ///
    /// Sin este test, el de arriba pasaría también con un `/preview` que
    /// rechazara **siempre**, que es la mutación obvia de toda guarda.
    @Test("pero con la temporada ya dada de alta, el rótulo es el nuestro (C-C.2 · C-E.8)")
    func anExistingSeasonSuppliesItsOwnLabel() async throws {
        try await Self.withSeededTeam(withoutSeasonLabel: true) { app, teamID in
            _ = try await Self.seedExistingCompetition(ageCategory: .cadete, on: app)

            try await app.testing().test(
                .POST,
                "/v1/teams/\(teamID.raw.uuidString.lowercased())/federation-link/preview",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.previewBody(&request)
                }
            ) { response async throws in
                #expect(response.status == .ok)
                let preview = try Self.decodePreview(response)
                #expect(preview.season.label == "2025/26")
                #expect(preview.season.exists == true)
                #expect(preview.competition.alreadyRegistered == true)
            }
        }
    }
}

extension FederationLinkEndpointTests {

    /// `C-E.10`: **ese `federationTeamId` ya es de otro equipo → 409**, no 500.
    ///
    /// # Por qué existe este ciclo, que el plan no traía
    ///
    /// Lo encontró la verificación **contra la base de trabajo** que §3 manda
    /// (2026-09-24), y ningún test de la batería podía verlo: en todos los
    /// montajes el código estaba libre. Contra `club_atleti`, con la ingesta ya
    /// pasada, los **16** equipos del grupo estaban escritos como rivales, y
    /// enganchar el equipo propio a cualquiera de sus códigos devolvía
    /// **`500 INTERNAL`** con el `23505` de Postgres y el `UPDATE` entero en el
    /// `detail`.
    ///
    /// Y no es un caso raro, es **el desenlace normal de enganchar tarde**: por
    /// [D-66] la ingesta no crea equipos propios, así que el equipo que nadie
    /// enganchó antes de la primera pasada ya existe **como rival**.
    ///
    /// El *spec* lo declara desde siempre como la tercera causa del mismo 409 —
    /// *"El equipo ya está emparejado con otro grupo, **ese `federationTeamId` ya
    /// pertenece a otro equipo**, o la identidad no cuadra"*— y era la única de
    /// las tres que no levantaba nadie. `C-E.5` cubrió las otras dos.
    ///
    /// **Lo que este 409 no hace es fundir las dos filas**: eso es §9.5 y está
    /// sin diseñar. Lo que hace es decir **quién** lo tiene, que es lo que
    /// permite ir a `/ownership` (`D-20`).
    @Test("un código que ya es de otro equipo es 409, no un 23505 (D-67 · C-E.10)")
    func aTakenFederationCodeIsRejected() async throws {
        try await Self.withSeededTeam { app, teamID in
            // El vecino que ya tiene el código. En la base de trabajo era un
            // **rival** creado por la pasada; aquí basta otro equipo del club,
            // que choca contra el mismo `uq:teams.federation_team_id`.
            let neighbour = TeamID(raw: UUID())
            try await Self.unitOfWork(app).withRepositories(actor: Self.actor()) {
                repositories in
                try await repositories.teams.save(
                    try Team(
                        id: neighbour, opponentClubID: nil,
                        category: .infantil, letter: "A",
                        gender: .masculino, modality: .futbol11,
                        federationTeamID: "3349086",
                        createdAt: Self.now, updatedAt: Self.now))
            }

            try await app.testing().test(
                .POST,
                "/v1/teams/\(teamID.raw.uuidString.lowercased())/federation-link",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.linkBody(&request, ownTeamFederationID: "3349086")
                }
            ) { response async throws in
                #expect(response.status == .conflict)
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == "FEDERATION_TEAM_ID_TAKEN")
                #expect(problem.detail?.contains("3349086") == true)
                #expect(problem.detail?.contains(neighbour.raw.uuidString.lowercased()) == true)
            }

            // Y la cascada **no dejó nada**: la guarda va dentro del ámbito, así
            // que la temporada y la competición que se habían creado se van con
            // el `rollback`.
            #expect(try await Self.rowCount("seasons", on: app) == 0)
            #expect(try await Self.rowCount("ingestion_runs", on: app) == 0)
        }
    }

    /// Y la otra mitad de la guarda: **volver a enganchar al mismo código no es
    /// un choque consigo mismo**.
    ///
    /// Sin esto, la mutación obvia —comparar solo el código y no el `id`— pasaría
    /// por verde, y lo que rompería es lo que hace seguro reintentar el `202`:
    /// un reenganche idempotente.
    @Test("pero reenganchar al MISMO código sigue siendo idempotente (C-E.10)")
    func relinkingToTheSameCodeIsIdempotent() async throws {
        try await Self.withSeededTeam(federationTeamID: "3349086") { app, teamID in
            try await app.testing().test(
                .POST,
                "/v1/teams/\(teamID.raw.uuidString.lowercased())/federation-link",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.linkBody(&request, ownTeamFederationID: "3349086")
                }
            ) { response async throws in
                #expect(response.status == .accepted)
            }
        }
    }
}

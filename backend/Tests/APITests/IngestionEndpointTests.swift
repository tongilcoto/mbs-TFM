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

/// Nivel 4 (§8.1): los **dos primeros endpoints desde F0**. Pocos y selectivos —
/// las reglas del recorrido ya están probadas en los niveles 2 y 3; aquí se
/// prueba el **borde**: ruta, DTO y código de respuesta.
@Suite("Ingestion · §5.6 · el registro y el disparador",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct IngestionEndpointTests {

    static let prefix = "e2e_"
    static let slug = "ingclub"
    static let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// Dentro de la temporada 2025/26, que es la que se siembra. **El reloj se
    /// fija** para que "la vigente" no dependa del día en que corra la batería.
    static let syncInstant = instant("2026-03-02")

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

    static let emptyCalendar = FederationCalendar(
        seasonLabel: try! SeasonLabel("2025/26"),
        competitionName: nil, groupLabel: "Grupo 1",
        currentRound: 1, rounds: [])

    /// Nunca sale a la red: es la regla de Plan §4.4 —la batería determinista, el
    /// canario aparte—.
    struct StubProvider: FederationClientProvider {
        let failing: Bool
        // `nil` para la FCF, como el catálogo de producción (`D-95`): es lo que
        // hace que un club catalán pueda recibir su 501 aquí (H-28).
        func client(for code: FederationCode) -> (any FederationClient)? {
            code == .fcf ? nil : StubClient(failing: failing)
        }
    }

    struct StubClient: FederationClient {
        let failing: Bool
        struct Broken: Error {}
        func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
            if failing { throw Broken() }
            return IngestionEndpointTests.emptyCalendar
        }

    /// Ni F7 ni F8 las usan en este doble: **lanza en vez de devolver vacío**, para que un
    /// test futuro que llegue a cualquiera de las dos por accidente falle en vez de pasar por el
    /// motivo equivocado.
    func fetchStandings(
        _ coordinate: FederationCoordinate, round: Int
    ) async throws -> FederationStanding {
        throw NotStubbed(client: "StubClient", operation: "fetchStandings")
    }

    /// **Devuelve el ranking vacío en vez de lanzar, al revés que sus dos
    /// vecinas — y la asimetría es del código, no del doble.**
    ///
    /// `fetchStandings` puede lanzar tranquilamente porque `IngestStandings`
    /// **no siempre la llama**: si ninguna jornada se ha jugado, su plan sale
    /// vacío y no toca la red. `IngestScorers` no tiene ese filtro —el ranking
    /// es de la competición entera, sin jornadas que mirar (§3.2)—, así que
    /// **toda** pasada pregunta, y un doble que lanzara aquí tumbaría cualquier
    /// test del recorrido por un motivo que no es el suyo.
    ///
    /// Vacío **no es mentira**: es lo que devuelve una liga recién empezada, y
    /// el *spec* dice que eso es un 200 y no un error (`D-48`).
    func fetchScorers(
        _ coordinate: FederationCoordinate
    ) async throws -> FederationScorerTable {
        FederationScorerTable(competitionName: nil, rows: [])
    }

        /// `C-B.1`: leer la URL es del adaptador de verdad, y este doble no lo es.
        ///
        /// **El puerto lo exige a todos y no trae implementación por defecto**, que es
        /// lo que hace que el adaptador de la FCF no pueda nacer sin ella ([D-97]).
        /// Aquí se lanza, con el mismo criterio que las otras operaciones sin preparar:
        /// un doble que devolviera una coordenada cualquiera dejaría pasar un test
        /// escrito sobre el doble equivocado (`H-07`).
        func coordinate(fromCalendarURL url: String) throws -> FederationCoordinate {
            throw NotStubbed(client: "StubClient", operation: "coordinate(fromCalendarURL:)")
        }
    }

    /// El *schema* del club, con la **entrada** de la ingesta sembrada (`D-16`).
    static func withSeededClub(
        failingFederation: Bool = false,
        federation: FederationCode = .rffm,
        _ body: @escaping @Sendable (Application, SeasonID, CompetitionID, CompetitionID) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp(
            federationClients: StubProvider(failing: failingFederation),
            background: InlineBackgroundWork(),
            clock: FixedClock(instant: syncInstant)
        ) { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(
                slug, federation: federation, schemaPrefix: prefix, on: app)

            let seasonID = SeasonID(raw: UUID())
            let competitionID = CompetitionID(raw: UUID())
            // La segunda es el "Infantil A" de la pantalla: el club tiene varios
            // equipos y la lista de casillas tiene más de una fila.
            let otherCompetitionID = CompetitionID(raw: UUID())
            let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            let actor = ActorContext(clubSlug: try Slug(slug))
            try await unitOfWork.withRepositories(actor: actor) { repositories in
                try await repositories.seasons.save(
                    try Season(
                        id: seasonID, label: try SeasonLabel("2025/26"),
                        federationSeasonID: "21", createdAt: now, updatedAt: now))
                try await repositories.competitions.save(
                    try Competition(
                        id: competitionID, seasonID: seasonID,
                        modality: .futbol11, gender: .masculino,
                        federationCompetitionID: "24037548", federationGroupID: "24037549",
                        ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
                        groupLabel: "Grupo 1", createdAt: now, updatedAt: now))
                try await repositories.competitions.save(
                    try Competition(
                        id: otherCompetitionID, seasonID: seasonID,
                        modality: .futbol11, gender: .masculino,
                        federationCompetitionID: "24037550", federationGroupID: "24037551",
                        ageCategory: .infantil, divisionLabel: "Primera División Autonómica",
                        groupLabel: "Grupo 2", createdAt: now, updatedAt: now))
            }

            try await body(app, seasonID, competitionID, otherCompetitionID)
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func decodeRuns(_ response: TestingHTTPResponse) throws
        -> [Components.Schemas.IngestionRunResponse]
    {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            [Components.Schemas.IngestionRunResponse].self,
            from: Data(response.body.readableBytesView))
    }

    static func decodeRun(_ response: TestingHTTPResponse) throws
        -> Components.Schemas.IngestionRunResponse
    {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            Components.Schemas.IngestionRunResponse.self,
            from: Data(response.body.readableBytesView))
    }

    static func header(_ request: inout TestingHTTPRequest) {
        request.headers.add(name: "X-Club", value: slug)
    }

    /// Codifica el cuerpo con el **tipo generado del spec**, no con un JSON a
    /// mano: si el contrato y lo que el test manda divergieran, esto no
    /// compilaría — que es el punto entero de *design-first* (`D-65`).
    static func body(
        _ request: inout TestingHTTPRequest,
        seasonId: String? = nil, competitionIds: [String]? = nil
    ) throws {
        let payload = Components.Schemas.TriggerIngestionRequest(
            seasonId: seasonId, competitionIds: competitionIds)
        request.headers.contentType = .json
        request.body = ByteBuffer(
            string: String(decoding: try JSONEncoder().encode(payload), as: UTF8.self))
    }

    // ─────────────────────────────────────────────────────────────────────────

    @Test("con `competitionId` la pasada se hace y se devuelve (200, §2.3-c)")
    func aSingleCompetitionSyncsInline() async throws {
        try await Self.withSeededClub { app, _, competitionID, _ in
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.body(
                        &request, competitionIds: [competitionID.raw.uuidString.lowercased()])
                }
            ) { response async throws in
                // **200 y no 202**: una petición a la federación y el calendario
                // de un grupo caben dentro de una respuesta HTTP, y devolver la
                // pasada ya hecha es lo que hace útil el botón de la ficha.
                #expect(response.status == .ok)
                let run = try Self.decodeRun(response)
                #expect(run.competitionId == competitionID.raw.uuidString.lowercased())
                #expect(run.outcome == .succeeded)
            }
        }
    }

    @Test("sin `competitionId` se acepta el recorrido y se dice qué entra (202, D-67)")
    func awholeSeasonIsAccepted() async throws {
        try await Self.withSeededClub { app, _, competitionID, _ in
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.body(&request)
                }
            ) { response async throws in
                // **202 y no 200**: una temporada son decenas de competiciones y
                // ~240 partidos cada una. Es el mismo argumento de `D-67`.
                #expect(response.status == .accepted)
                let accepted = try JSONDecoder().decode(
                    Components.Schemas.IngestionAcceptedResponse.self,
                    from: Data(response.body.readableBytesView))
                #expect(accepted.competitionIds.count == 2)
                #expect(accepted.competitionIds.contains(competitionID.raw.uuidString.lowercased()))
            }
        }
    }

    @Test("un POST sin cuerpo es 400, y por eso el cuerpo es obligatorio (D-65)")
    func aBodylessPostIsRejected() async throws {
        try await Self.withSeededClub { app, _, _, _ in
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in Self.header(&request) }
            ) { response async in
                // El *spec* declaraba `required: false` y prometía que el cuerpo
                // se podía omitir. **Era falso**: el servidor generado lo parsea
                // igual. Se corrigió el contrato —`required: true`, `{}` para la
                // temporada vigente— y este test es lo que impide que la promesa
                // vuelva a escribirse. Es `D-65` otra vez: el generador emite
                // tipos, no comportamiento, y lo que el YAML dice hay que ir a
                // comprobarlo.
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("con dos competiciones marcadas es 202, no 200 (D-88)")
    func twoCompetitionsAreAccepted() async throws {
        try await Self.withSeededClub { app, _, cadete, infantil in
            let ids = [cadete, infantil].map { $0.raw.uuidString.lowercased() }
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.body(&request, competitionIds: ids)
                }
            ) { response async throws in
                // **El código lo decide la petición, no los datos.** Una son ~240
                // partidos; dos ya no caben en una respuesta HTTP (`D-67`).
                #expect(response.status == .accepted)
                let accepted = try JSONDecoder().decode(
                    Components.Schemas.IngestionAcceptedResponse.self,
                    from: Data(response.body.readableBytesView))
                // Y en el orden pedido, que es el de las casillas marcadas.
                #expect(accepted.competitionIds == ids)
            }

            // Las dos se sincronizaron de verdad: el 202 no es un "quizá".
            for id in ids {
                try await app.testing().test(
                    .GET, "/v1/ingestion-runs?competitionId=\(id)",
                    beforeRequest: { request async throws in Self.header(&request) }
                ) { response async throws in
                    // **No vacío**, no "exactamente una": el 202 promete que la
                    // competición se sincronizó, y cuántas pasadas deja eso
                    // depende de cuántas clases haya (tres desde F8).
                    #expect(try !Self.decodeRuns(response).isEmpty, "id \(id)")
                }
            }
        }
    }

    @Test("una lista vacía no significa «todas»: 400 (D-88)")
    func anEmptySelectionIsRejected() async throws {
        try await Self.withSeededClub { app, _, _, _ in
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.body(&request, competitionIds: [])
                }
            ) { response async in
                // Adivinar por el cliente aquí significa lanzar el recorrido
                // entero del club por una casilla sin marcar.
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("el registro se lee de la más reciente a la más antigua (D-85)")
    func theRegistryReadsNewestFirst() async throws {
        try await Self.withSeededClub { app, _, competitionID, _ in
            // Dos pasadas, para que el orden signifique algo.
            for _ in 0..<2 {
                try await app.testing().test(
                    .POST, "/v1/ingestion-runs",
                    beforeRequest: { request async throws in
                        Self.header(&request)
                        try Self.body(
                            &request, competitionIds: [competitionID.raw.uuidString.lowercased()])
                    }
                ) { _ async in }
            }

            try await app.testing().test(
                .GET, "/v1/ingestion-runs?competitionId=\(competitionID.raw.uuidString.lowercased())",
                beforeRequest: { request async throws in Self.header(&request) }
            ) { response async throws in
                #expect(response.status == .ok)
                let runs = try Self.decodeRuns(response)

                // **Dos disparos, y cada uno deja las pasadas de su competición.**
                // Cuántas son por disparo depende de cuántas clases de pasada
                // existan —una en F6, dos en F7, tres en F8—, así que lo que se
                // afirma es que hay más de un disparo y que vienen ordenadas.
                #expect(runs.count >= 2)

                // La pregunta que esta tabla contesta es *"¿qué pasó la última
                // vez?"*, así que el orden es parte del contrato, no un detalle.
                // **Por parejas y no con `sorted`**: en este test el reloj está
                // fijo, así que todas las pasadas comparten `finishedAt` y
                // `sorted` —que no es estable— devuelve otra permutación igual de
                // válida. Lo que hay que afirmar es que la secuencia no sube.
                //
                // **`finishedAt` es anulable desde `D-96`** (`C-0.4`), y aquí eso
                // es un dato que afirmar, no un estorbo que tapar con un `??`:
                // estas pasadas ya corrieron, así que ninguna puede traerlo nulo
                // — el nulo es exclusivo de `accepted`.
                //
                // **`C-D.6` vuelve a este renglón**: el orden del registro pasa a
                // `started_at`, porque un `NULL` en la clave de orden deja al
                // motor decidiendo dónde cae la fila recién aceptada.
                let finishes = runs.compactMap(\.finishedAt)
                #expect(finishes.count == runs.count,
                        "una pasada que ya corrió no puede venir sin `finishedAt`")
                #expect(zip(finishes, finishes.dropFirst()).allSatisfy { $0 >= $1 },
                        "el registro no llega de la más reciente a la más antigua")
            }
        }
    }

    /// **F9-bis, y es el primer test de la batería que afirma un motivo de
    /// descarte al otro lado de la frontera** (`A-7`·H-46). `IngestionSkip.Reason`
    /// tiene un **enumerado espejo** en el *spec* y una traducción a mano entre los
    /// dos (`IngestionHandler.toContract()`), y esa traducción **no es cosmética**:
    /// el Dominio se serializa tal cual dentro del `jsonb` desde F5 y el contrato
    /// usa `snake_case` (§5.2), así que los dos lados tienen que divergir a
    /// propósito. El `switch` es exhaustivo, de modo que el compilador obliga a
    /// **escribir** la línea del caso nuevo — pero no a escribirla **bien**:
    /// mapearlo al valor del vecino compila igual de bien y llega al backoffice
    /// como otra cosa.
    ///
    /// La pasada se escribe por el puerto y no ejecutando una ingesta: lo que se
    /// prueba aquí es la **traducción**, y hacerla llegar por una pasada de verdad
    /// la mezclaría con el doble de la federación.
    @Test("el motivo nuevo cruza la frontera con su propio valor (F9-bis, A-7/H-46)")
    func theNewSkipReasonCrossesTheBoundary() async throws {
        try await Self.withSeededClub { app, _, competitionID, _ in
            let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            let actor = ActorContext(clubSlug: try Slug(Self.slug))
            try await unitOfWork.withRepositories(actor: actor) { repositories in
                var run = try IngestionRun(
                    id: IngestionRunID(raw: UUID()), competitionID: competitionID,
                    kind: .calendar, startedAt: Self.now, finishedAt: Self.now,
                    outcome: .succeeded)
                run.skipped = [
                    IngestionSkip(
                        reason: .unidentifiedTeam, detail: "CELTIC CASTILLA C.F. \"A\"")
                ]
                try await repositories.ingestionRuns.record(run)
            }

            try await app.testing().test(
                .GET, "/v1/ingestion-runs?competitionId=\(competitionID.raw.uuidString.lowercased())",
                beforeRequest: { request async throws in Self.header(&request) }
            ) { response async throws in
                #expect(response.status == .ok)
                let skipped = try #require(try Self.decodeRuns(response).first?.skipped)

                #expect(skipped.count == 1)
                #expect(skipped.first?.reason == .unidentified_team)
                // Y el detalle llega entero: es lo que una persona copia para ir
                // a buscar la fila en la web de la federación.
                #expect(skipped.first?.detail == "CELTIC CASTILLA C.F. \"A\"")
            }
        }
    }

    /// **`roundId` cruza la frontera, y hasta hoy no lo afirmaba nadie**
    /// (`A-7`·H-46, hueco encontrado el 2026-09-25).
    ///
    /// Es el único identificador del `IngestionRunResponse` **anulable**, y eso
    /// es justo lo que lo dejó sin arnés: los otros dos se afirman de paso en
    /// cualquier test del registro, y éste solo aparece cuando la pasada es de
    /// **clasificación** —`(kind = 'standings') = (round_id IS NOT NULL)`, que el
    /// esquema hace cumplir con un `CHECK`—, y ninguna de las que la *suite*
    /// provoca lo es: con un calendario vacío no hay jornada jugada, así que el
    /// plan de `IngestStandings` sale vacío y no escribe fila.
    ///
    /// Por eso la pasada se siembra **a mano**, como en el test de F9-bis de
    /// arriba: lo que se prueba aquí no es el recorrido —eso es nivel 3— sino
    /// **el borde**, que un `RoundID` salga al JSON como un UUID y con la forma
    /// canónica.
    ///
    /// # Y la mitad que hace el test honesto: el nulo también se afirma
    ///
    /// Sin ella, `roundId` podría devolver siempre algo y nadie lo notaría. Una
    /// pasada de calendario **tiene que traerlo a `null`**, que es lo que
    /// distingue *"esta pasada no va de una jornada"* de *"va de una que no sé
    /// cuál es"*.
    @Test("el `roundId` de una pasada de clasificación cruza la frontera (F7, A-7/H-46)")
    func theRoundIDCrossesTheBoundary() async throws {
        try await Self.withSeededClub { app, _, competitionID, _ in
            let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            let actor = ActorContext(clubSlug: try Slug(Self.slug))
            let roundID = RoundID(raw: UUID())

            try await unitOfWork.withRepositories(actor: actor) { repositories in
                // La jornada existe de verdad: `round_id` es una FK con
                // `ON DELETE CASCADE`, así que una inventada no entra.
                try await repositories.rounds.save(
                    try Round(
                        id: roundID, competitionID: competitionID, number: 7,
                        startDate: Self.instant("2026-02-28"),
                        endDate: Self.instant("2026-03-01"),
                        createdAt: Self.now, updatedAt: Self.now))

                try await repositories.ingestionRuns.record(
                    try IngestionRun(
                        id: IngestionRunID(raw: UUID()), competitionID: competitionID,
                        kind: .standings, roundID: roundID,
                        startedAt: Self.now, finishedAt: Self.now,
                        outcome: .succeeded))

                // Y su vecina de calendario, que es la que tiene que decir `null`.
                try await repositories.ingestionRuns.record(
                    try IngestionRun(
                        id: IngestionRunID(raw: UUID()), competitionID: competitionID,
                        kind: .calendar,
                        startedAt: Self.now, finishedAt: Self.now,
                        outcome: .succeeded))
            }

            try await app.testing().test(
                .GET, "/v1/ingestion-runs?competitionId=\(competitionID)",
                beforeRequest: { request async throws in Self.header(&request) }
            ) { response async throws in
                #expect(response.status == .ok)
                let runs = try Self.decodeRuns(response)

                let standings = try #require(runs.first { $0.kind == .standings })
                #expect(standings.roundId == "\(roundID)")

                let calendar = try #require(runs.first { $0.kind == .calendar })
                #expect(calendar.roundId == nil)
            }
        }
    }

    /// **Los trece contadores cruzan la frontera cada uno por su sitio**
    /// (`A-7`·H-46, hueco encontrado el 2026-09-25).
    ///
    /// # Qué estaba sin cubrir, y por qué importa justo aquí
    ///
    /// Los contadores se afirman en los niveles 1, 2 y 3 —la **entidad** los
    /// lleva bien—, pero el salto de entidad a DTO **no lo miraba nadie**: son
    /// trece asignaciones a mano, escritas en columna, con nombres que van por
    /// parejas (`Created`/`Updated`) y que se repiten en cinco familias. Cambiar
    /// dos de sitio **compila**, pasa la batería entera y llega al backoffice
    /// como otra cosa: una pasada que creó 300 partidos diciendo que actualizó
    /// 300, que es lo contrario de lo que se mira cuando algo va mal.
    ///
    /// Es la misma familia que `C-E.9` —lo que el compilador obliga a escribir
    /// no lo obliga a escribirlo **bien**— y la misma que el `roundId` de aquí
    /// arriba.
    ///
    /// # Los trece valores son DISTINTOS, y es la mitad que hace el test
    ///
    /// Con ceros, o con el mismo número repetido, una permutación es
    /// **invisible**: el test pasaría igual con los trece campos cruzados. Por
    /// eso van 1..13, y por eso esta fila **no podría existir en producción**
    /// —una pasada de calendario no escribe goleadores—: lo que está bajo prueba
    /// es **el mapeo**, no la pasada. La pasada tiene sus propios tests en los
    /// niveles 2 y 3.
    @Test("los trece contadores llegan cada uno a su campo (F7, F8, A-7/H-46)")
    func everyCounterReachesItsOwnField() async throws {
        try await Self.withSeededClub { app, _, competitionID, _ in
            let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            let actor = ActorContext(clubSlug: try Slug(Self.slug))

            try await unitOfWork.withRepositories(actor: actor) { repositories in
                var run = try IngestionRun(
                    id: IngestionRunID(raw: UUID()), competitionID: competitionID,
                    kind: .calendar, startedAt: Self.now, finishedAt: Self.now,
                    outcome: .succeeded)
                run.opponentClubsCreated = 1
                run.opponentClubsUpdated = 2
                run.teamsCreated = 3
                run.teamsUpdated = 4
                run.roundsCreated = 5
                run.roundsUpdated = 6
                run.matchesCreated = 7
                run.matchesUpdated = 8
                run.standingRowsCreated = 9
                run.standingRowsUpdated = 10
                run.leagueScorersCreated = 11
                run.leagueScorersUpdated = 12
                run.leagueScorersRetired = 13
                try await repositories.ingestionRuns.record(run)
            }

            try await app.testing().test(
                .GET, "/v1/ingestion-runs?competitionId=\(competitionID)",
                beforeRequest: { request async throws in Self.header(&request) }
            ) { response async throws in
                #expect(response.status == .ok)
                let counters = try #require(try Self.decodeRuns(response).first?.counters)

                #expect(counters.opponentClubsCreated == 1)
                #expect(counters.opponentClubsUpdated == 2)
                #expect(counters.teamsCreated == 3)
                #expect(counters.teamsUpdated == 4)
                #expect(counters.roundsCreated == 5)
                #expect(counters.roundsUpdated == 6)
                #expect(counters.matchesCreated == 7)
                #expect(counters.matchesUpdated == 8)
                #expect(counters.standingRowsCreated == 9)
                #expect(counters.standingRowsUpdated == 10)
                #expect(counters.leagueScorersCreated == 11)
                #expect(counters.leagueScorersUpdated == 12)
                // **El que no tiene hermano en ninguna otra entidad**: solo los
                // goleadores se retiran (`D-94`), y es el número que hay que
                // poder mirar cuando una pasada vacía la tabla.
                #expect(counters.leagueScorersRetired == 13)
            }
        }
    }

    @Test("la pasada que falla también se puede leer (D-85)")
    func aFailedPassIsReadable() async throws {
        try await Self.withSeededClub(failingFederation: true) { app, _, competitionID, _ in
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.body(
                        &request, competitionIds: [competitionID.raw.uuidString.lowercased()])
                }
            ) { response async in
                // **502**: el fallo no es del cliente, es del tercero (§5.4, y el
                // mismo criterio que `D-84` en `ProblemMiddleware`).
                #expect(response.status == .badGateway)
            }

            try await app.testing().test(
                .GET, "/v1/ingestion-runs?competitionId=\(competitionID.raw.uuidString.lowercased())",
                beforeRequest: { request async throws in Self.header(&request) }
            ) { response async throws in
                let runs = try Self.decodeRuns(response)
                // Es **toda la razón de ser** de `D-85`: la pasada que falla es la
                // que nadie ve, y se escribe fuera de la transacción que se
                // deshizo para que quede algo que leer.
                #expect(runs.count == 1)
                #expect(runs.first?.outcome == .failed)
                #expect(runs.first?.error != nil)
            }
        }
    }

    @Test("sin `competitionId` el registro no se sirve: 400 (§5.3)")
    func theRegistryDemandsItsScope() async throws {
        try await Self.withSeededClub { app, _, _, _ in
            try await app.testing().test(
                .GET, "/v1/ingestion-runs",
                beforeRequest: { request async throws in Self.header(&request) }
            ) { response async in
                #expect(response.status == .badRequest)
            }
        }
    }

    @Test("un `limit` fuera de rango es 400, no un recorte silencioso (§5.5)")
    func anOutOfRangeLimitIsRejected() async throws {
        try await Self.withSeededClub { app, _, competitionID, _ in
            let id = competitionID.raw.uuidString.lowercased()
            for limit in ["0", "101"] {
                try await app.testing().test(
                    .GET, "/v1/ingestion-runs?competitionId=\(id)&limit=\(limit)",
                    beforeRequest: { request async throws in Self.header(&request) }
                ) { response async in
                    // **El generador ignora `minimum`/`maximum`** (`D-65`, tabla de
                    // reparto de §5.5), así que esto lo hace cumplir el handler o no
                    // lo hace nadie. Y recortar en silencio sería peor que un 400:
                    // el cliente creería haber pedido lo que no pidió.
                    #expect(response.status == .badRequest, "limit=\(limit)")
                }
            }
        }
    }

    @Test("una competición de otro club no existe para esta consulta: 404 (§6, §7.5)")
    func anotherClubsCompetitionIsNotFound() async throws {
        try await Self.withSeededClub { app, _, _, _ in
            let alien = UUID().uuidString.lowercased()
            try await app.testing().test(
                .GET, "/v1/ingestion-runs?competitionId=\(alien)",
                beforeRequest: { request async throws in Self.header(&request) }
            ) { response async throws in
                // 404 **literal**, no el defensivo de §7.5: el `search_path` no
                // alcanza la fila, así que para esta consulta no existe.
                #expect(response.status == .notFound)
                // **Por código, no solo por status** (H-46): desde `A-14`·H-63
                // este 404 lo decide un solo sitio, el middleware.
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == "COMPETITION_NOT_FOUND")
                #expect(problem.detail == alien)
            }
        }
    }

    @Test("una competición que no existe, pedida sola, es 404 y no 502 (D-88 · A-14/H-63)")
    func anUnknownSingleCompetitionIsNotFound() async throws {
        try await Self.withSeededClub { app, _, _, _ in
            let alien = UUID().uuidString.lowercased()
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.body(&request, competitionIds: [alien])
                }
            ) { response async throws in
                #expect(response.status == .notFound)
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == "COMPETITION_NOT_FOUND")
                #expect(problem.detail == alien)
            }
        }
    }

    @Test("una temporada que no existe no cae a la vigente: 404 (D-84)")
    func anUnknownSeasonIsNotFound() async throws {
        try await Self.withSeededClub { app, _, _, _ in
            let alien = UUID().uuidString.lowercased()
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.body(&request, seasonId: alien)
                }
            ) { response async throws in
                #expect(response.status == .notFound)
                // `SEASON_NOT_FOUND` es también el código del **500** de
                // `seasonNotFound` (el *schema* roto); aquí tiene que salir el 404
                // de `unknownSeason`, que es lo que el `status` de arriba fija.
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == "SEASON_NOT_FOUND")
                #expect(problem.detail == alien)
            }
        }
    }

    /// **La otra puerta del club catalán** (`H-28`, remedido en A-12): el
    /// enganche ya tenía su 501 bajo arnés (`C-E.7`); `/ingestion-runs`, no.
    @Test("un club sin adaptador de federación recibe 501 al disparar (H-28 · A-14/H-63)")
    func aClubWithoutAdapterGets501() async throws {
        try await Self.withSeededClub(federation: .fcf) { app, _, _, _ in
            try await app.testing().test(
                .POST, "/v1/ingestion-runs",
                beforeRequest: { request async throws in
                    Self.header(&request)
                    try Self.body(&request)
                }
            ) { response async throws in
                #expect(response.status == .notImplemented)
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == "FEDERATION_ADAPTER_MISSING")
                #expect(problem.detail?.contains("fcf") == true)
            }
        }
    }

    static func decodeProblem(_ response: TestingHTTPResponse) throws
        -> Components.Schemas.Problem
    {
        try JSONDecoder().decode(
            Components.Schemas.Problem.self, from: Data(response.body.readableBytesView))
    }

    @Test("lo que el 202 aceptó y no llegó a hacerse se dice por el log (H-27)")
    func acceptedWorkThatVanishesIsReported() async throws {
        try await Self.withSeededClub { app, seasonID, competitionID, otherID in
            // Los ámbitos de **aceptar** pasan; el siguiente no. Es la forma
            // exacta de H-27 medida a mano: el cliente recibe su `202` y la base
            // se cae detrás. El mismo patrón que A-3 usó para H-24, y por lo
            // mismo: parar el contenedor desde un test de esta suite se lo
            // llevaría por delante a las demás.
            //
            // **Eran dos ámbitos y ahora son tres, y el cambio es la mitad buena
            // de F10-bis**: aceptar ya no es solo planificar —ámbito 1—, también
            // **deja la fila** que el cliente va a consultar —ámbito 2—, así que
            // el trabajo de fondo empieza en el 3. Si el corte se dejara en el 2,
            // este test mediría otra cosa: un `POST` que falla **antes** de
            // responder, que es un caso mejor y no el que `H-27` describe.
            let spy = LogSpy()
            let handler = APIHandler(
                unitOfWork: CollapsingUnitOfWork(
                    inner: FluentTenantUnitOfWork(controlDatabase: app.db(.control)),
                    collapse: Collapse(failsFromScope: 3)),
                federationClients: StubProvider(failing: false),
                clock: FixedClock(instant: Self.syncInstant),
                background: InlineBackgroundWork(),
                logger: Logger(label: "test") { _ in CapturingLogHandler(spy: spy) })

            let tenant = try await TenantResolver(database: app.db(.control))
                .resolve(slug: Self.slug)
            let output = try await TenantContext.$current.withValue(tenant) {
                try await handler.triggerIngestion(
                    .init(body: .json(.init(seasonId: seasonID.raw.uuidString.lowercased()))))
            }

            // **El `202` se mantiene, y es lo correcto**: la planificación sí
            // ocurrió y el cliente no tiene culpa de lo que pase después. Lo que
            // se audita es que el fallo no se quede sin contar.
            guard case .accepted = output else {
                Issue.record("se esperaba 202, llegó \(output)")
                return
            }

            // La ingesta no dejó fila —la base es lo que falló (H-23)—, así que el
            // log es la única señal posible. Sin esto, el trabajo aceptado
            // desaparece y `ingestionHealth` sigue diciendo `ok` (`D-89`).
            let errors = spy.messages(at: .error)
            #expect(errors.count == 1)
            #expect(errors.first?.contains("no se hizo") == true)
            // Y dice **cuáles**: los dos ids que el `202` prometió.
            #expect(errors.first?.contains(competitionID.raw.uuidString.lowercased()) == true)
            #expect(errors.first?.contains(otherID.raw.uuidString.lowercased()) == true)
        }
    }

    @Test("el recorrido que se para a mitad detrás de un 202 también se dice (H-27, H-23)")
    func anAbortedTraversalBehindA202IsReported() async throws {
        try await Self.withSeededClub { app, seasonID, _, _ in
            // La base aguanta la primera competición y se cae al ir por la
            // segunda: es `abortedByInfrastructure`, la bandera que A-3 creó para
            // que el llamante pudiera distinguir *"falló una"* de *"el recorrido
            // no siguió"*. Por la ruta del `202` ese llamante es un `Task { }`, y
            // antes de esto la bandera se tiraba sin leerla.
            let collapse = Collapse()
            let spy = LogSpy()
            let handler = APIHandler(
                unitOfWork: CollapsingUnitOfWork(
                    inner: FluentTenantUnitOfWork(controlDatabase: app.db(.control)),
                    collapse: collapse),
                federationClients: CollapsingProvider(
                    collapse: collapse, fetches: Collapse(failsFromScope: 2)),
                clock: FixedClock(instant: Self.syncInstant),
                background: InlineBackgroundWork(),
                logger: Logger(label: "test") { _ in CapturingLogHandler(spy: spy) })

            let tenant = try await TenantResolver(database: app.db(.control))
                .resolve(slug: Self.slug)
            _ = try await TenantContext.$current.withValue(tenant) {
                try await handler.triggerIngestion(
                    .init(body: .json(.init(seasonId: seasonID.raw.uuidString.lowercased()))))
            }

            // **`error` y no `warning`**: de esto no queda constancia en ningún
            // otro sitio. La fila de `D-85` no se pudo escribir —la base es lo que
            // falló— así que si esto no se dice, no se dice en ninguna parte.
            let errors = spy.messages(at: .error)
            #expect(errors.count == 1)
            #expect(errors.first?.contains("se paró") == true)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dobles de este fichero. No van a `TestSupport` a propósito: los usa una sola
// suite y moverlos allí sería API compartida por un caso (§3, regla 2).

/// Cuenta ámbitos de tenant y deja de abrirlos a partir del que se le diga.
///
/// Es *"la base se cae detrás del `202`"* sin tocar el contenedor: las suites
/// corren en paralelo y `docker compose stop db` desde aquí sería una carrera
/// contra las demás — la lección de arnés que F6 dejó escrita.
struct CollapsingUnitOfWork: TenantUnitOfWork {
    let inner: any TenantUnitOfWork
    let collapse: Collapse

    struct DatabaseIsGone: Error {}

    func withRepositories<T: Sendable>(
        actor: ActorContext,
        _ work: @escaping @Sendable (any Repositories) async throws -> T
    ) async throws -> T {
        guard !collapse.openScope() else { throw DatabaseIsGone() }
        return try await inner.withRepositories(actor: actor, work)
    }
}

/// El momento de la caída, con **dos gatillos** porque las dos ramas de H-27
/// necesitan momentos distintos.
///
/// - `failsFromScope` — *"la base ya no está cuando vuelva a abrirse un ámbito"*.
///   Sirve para el fallo **antes de empezar**: el plan del `202` pasa (ámbito 1)
///   y el del recorrido, no.
/// - `force()` — *"cáete ahora"*, llamado desde el doble de la federación entre
///   una competición y la siguiente. Es el fallo **a mitad**, y es la forma
///   literal del experimento con que A-3 midió H-23.
final class Collapse: @unchecked Sendable {
    private let lock = NSLock()
    private var scopes = 0
    private var forced = false
    private let failsFromScope: Int?

    init(failsFromScope: Int? = nil) {
        self.failsFromScope = failsFromScope
    }

    func force() {
        lock.lock()
        defer { lock.unlock() }
        forced = true
    }

    /// `true` si este ámbito ya no se puede abrir.
    func openScope() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        scopes += 1
        if forced { return true }
        if let failsFromScope { return scopes >= failsFromScope }
        return false
    }
}

/// Tumba la base **entre una competición y la siguiente**, desde el sitio donde
/// A-3 la tumbó: justo antes de devolver el calendario.
struct CollapsingProvider: FederationClientProvider {
    let collapse: Collapse
    /// Su propio contador, con su propio umbral: **el del test, no uno estático**.
    /// Un contador compartido entre casos sería estado global en una batería
    /// paralela, que es la lección de arnés de F6.
    let fetches: Collapse

    func client(for code: FederationCode) -> (any FederationClient)? {
        CollapsingClient(collapse: collapse, fetches: fetches)
    }
}

struct CollapsingClient: FederationClient {
    let collapse: Collapse
    let fetches: Collapse

    func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
        // `openScope` cuenta llamadas y dice si toca caerse; aquí las llamadas son
        // *fetches*, que es lo mismo con otro nombre.
        if fetches.openScope() { collapse.force() }
        return IngestionEndpointTests.emptyCalendar
    }

    /// Ni F7 ni F8 las usan en este doble: **lanza en vez de devolver vacío**, para que un
    /// test futuro que llegue a cualquiera de las dos por accidente falle en vez de pasar por el
    /// motivo equivocado.
    func fetchStandings(
        _ coordinate: FederationCoordinate, round: Int
    ) async throws -> FederationStanding {
        throw NotStubbed(client: "CollapsingClient", operation: "fetchStandings")
    }

    /// **Devuelve el ranking vacío en vez de lanzar, al revés que sus dos
    /// vecinas — y la asimetría es del código, no del doble.**
    ///
    /// `fetchStandings` puede lanzar tranquilamente porque `IngestStandings`
    /// **no siempre la llama**: si ninguna jornada se ha jugado, su plan sale
    /// vacío y no toca la red. `IngestScorers` no tiene ese filtro —el ranking
    /// es de la competición entera, sin jornadas que mirar (§3.2)—, así que
    /// **toda** pasada pregunta, y un doble que lanzara aquí tumbaría cualquier
    /// test del recorrido por un motivo que no es el suyo.
    ///
    /// Vacío **no es mentira**: es lo que devuelve una liga recién empezada, y
    /// el *spec* dice que eso es un 200 y no un error (`D-48`).
    func fetchScorers(
        _ coordinate: FederationCoordinate
    ) async throws -> FederationScorerTable {
        FederationScorerTable(competitionName: nil, rows: [])
    }

    /// `C-B.1`: leer la URL es del adaptador de verdad, y este doble no lo es.
    ///
    /// **El puerto lo exige a todos y no trae implementación por defecto**, que es
    /// lo que hace que el adaptador de la FCF no pueda nacer sin ella ([D-97]).
    /// Aquí se lanza, con el mismo criterio que las otras operaciones sin preparar:
    /// un doble que devolviera una coordenada cualquiera dejaría pasar un test
    /// escrito sobre el doble equivocado (`H-07`).
    func coordinate(fromCalendarURL url: String) throws -> FederationCoordinate {
        throw NotStubbed(client: "CollapsingClient", operation: "coordinate(fromCalendarURL:)")
    }
}

/// Recoge lo que se registra, para que una aserción pueda mirarlo.
///
/// **Con *lock* y no `actor`**, aunque el proyecto prefiera `actor`: `LogHandler.log`
/// es síncrono, así que desde dentro no se puede `await`. Un `Task { }` para
/// entregarle el mensaje dejaría la aserción corriendo contra él — que es
/// exactamente la carrera que este bloque vino a no arbitrar.
final class LogSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(Logger.Level, String)] = []

    func record(_ level: Logger.Level, _ message: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.append((level, message))
    }

    func messages(at level: Logger.Level) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries.filter { $0.0 == level }.map(\.1)
    }
}

struct CapturingLogHandler: LogHandler {
    let spy: LogSpy
    var metadata = Logger.Metadata()
    var logLevel = Logger.Level.trace

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logger.Level, message: Logger.Message, metadata: Logger.Metadata?,
        source: String, file: String, function: String, line: UInt
    ) {
        // El mensaje y los metadatos se aplanan juntos: lo que se afirma es
        // *qué se dijo*, y los ids de competición viajan en los metadatos.
        let flattened = ((metadata ?? [:]).merging(self.metadata) { a, _ in a })
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: " ")
        spy.record(level, "\(message) \(flattened)")
    }
}

/// Un doble al que se le ha pedido la clasificación sin haberla preparado.
///
/// Existe para que el hueco **se vea**: devolver una tabla vacía haría que un test
/// de F7 escrito sobre el doble equivocado pasara sin sincronizar nada.
struct StandingsNotStubbed: Error, CustomStringConvertible {
    let client: String
    var description: String {
        "\(client) no prepara `fetchStandings`: usa un doble que sí lo haga (F7)."
    }
}


/// El mismo `NotStubbed` de `ApplicationTests`, declarado aquí porque los
/// *targets* de test no se importan entre sí. Ver allí el porqué de llevar la
/// operación dentro (F8).
struct NotStubbed: Error, CustomStringConvertible {
    let client: String
    let operation: String
    var description: String {
        "\(client) no prepara `\(operation)`: usa un doble que sí lo haga."
    }
}

// ── A-11 · H-55 · el doble clic no lanza dos pasadas ────────────────────────

extension IngestionEndpointTests {
    /// Un trabajo de fondo que **se queda en la cola** hasta que el test lo suelta:
    /// es la forma de tener *"el primero sigue corriendo"* sin arbitrar relojes.
    actor HeldBackgroundWork: BackgroundWork {
        private var queue: [@Sendable () async -> Void] = []
        var pending: Int { queue.count }
        func enqueue(_ work: @escaping @Sendable () async -> Void) async { queue.append(work) }
        func runAll() async {
            let jobs = queue
            queue = []
            for job in jobs { await job() }
        }
    }

    static func handler(background: any BackgroundWork, app: Application) -> APIHandler {
        APIHandler(
            unitOfWork: FluentTenantUnitOfWork(controlDatabase: app.db(.control)),
            federationClients: StubProvider(failing: false),
            clock: FixedClock(instant: Self.syncInstant),
            background: background)
    }

    static func trigger(
        _ handler: APIHandler, seasonID: SeasonID, app: Application
    ) async throws -> Operations.triggerIngestion.Output {
        let tenant = try await TenantResolver(database: app.db(.control)).resolve(slug: Self.slug)
        return try await TenantContext.$current.withValue(tenant) {
            try await handler.triggerIngestion(
                .init(body: .json(.init(seasonId: seasonID.raw.uuidString.lowercased()))))
        }
    }

    /// **Dos pulsaciones, una pasada** (A-11·H-55). Medido antes: `accept`
    /// deduplicaba la fila pero el `202` encolaba el trabajo otra vez, y las dos
    /// pasadas escribían sobre la misma fila `accepted`. La segunda pulsación
    /// sigue recibiendo su `202` con todo lo aceptado —lo está—, pero no lanza
    /// nada mientras la primera corre; cuando termina, la siguiente sí.
    @Test("un segundo 202 con el primero en marcha no lanza otra pasada (A-11·H-55)")
    func aSecondClickWhileTheFirstRunsEnqueuesNothing() async throws {
        try await Self.withSeededClub { app, seasonID, _, _ in
            let held = HeldBackgroundWork()
            let handler = Self.handler(background: held, app: app)

            let first = try await Self.trigger(handler, seasonID: seasonID, app: app)
            let second = try await Self.trigger(handler, seasonID: seasonID, app: app)
            guard case .accepted(let one) = first, case .accepted(let two) = second else {
                Issue.record("se esperaban dos 202: \(first) · \(second)")
                return
            }
            #expect(try one.body.json.competitionIds.count == 2)
            #expect(try two.body.json.competitionIds.count == 2)
            #expect(await held.pending == 1, "el doble clic lanzó dos pasadas")

            // Termina la primera: la pulsación siguiente vuelve a lanzar.
            await held.runAll()
            _ = try await Self.trigger(handler, seasonID: seasonID, app: app)
            #expect(await held.pending == 1)
        }
    }

    /// **Y una huérfana se puede reintentar** (A-11·H-55, H-57). Si el proceso
    /// muere detrás del `202`, la fila se queda `accepted`; un proceso nuevo no
    /// tiene nada en marcha, así que el botón vuelve a lanzar y la pasada la
    /// adopta. Negarse por *"ya hay fila abierta"* la habría dejado así para
    /// siempre desde la pantalla.
    @Test("tras un reinicio, el 202 vuelve a lanzar lo que quedó aceptado (A-11·H-55)")
    func afterARestartTheOrphanIsRunAgain() async throws {
        try await Self.withSeededClub { app, seasonID, competitionID, _ in
            // El proceso que muere: acepta, y su trabajo no llega a correr.
            _ = try await Self.trigger(
                Self.handler(background: HeldBackgroundWork(), app: app),
                seasonID: seasonID, app: app)

            let restarted = HeldBackgroundWork()
            _ = try await Self.trigger(
                Self.handler(background: restarted, app: app), seasonID: seasonID, app: app)
            #expect(await restarted.pending == 1, "la huérfana no se puede reintentar")

            await restarted.runAll()
            let runs = try await FluentTenantUnitOfWork(controlDatabase: app.db(.control))
                .withRepositories(actor: ActorContext(clubSlug: try Slug(Self.slug))) {
                    try await $0.ingestionRuns.list(competitionID: competitionID, limit: 10)
                }
            #expect(runs.filter { $0.kind == .calendar }.allSatisfy { $0.outcome == .succeeded })
        }
    }
}

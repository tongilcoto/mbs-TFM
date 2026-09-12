import Application
import Domain
import Federation
import Fluent
import Foundation
import SQLKit
import Testing
import Vapor

@testable import App
import TestSupport
@testable import Persistence
@testable import Tenancy

/// Nivel 3 (§8.1) y **la rebanada que da nombre a F5**: el volcado real pasa por
/// el parser real (F2), por la cadena real (F4) y por la política real (F3), y
/// acaba en Postgres.
///
/// Lo único falseado es el **transporte**: se le da el fichero en vez de la red.
/// Eso es a propósito — la batería tiene que ser determinista (Plan §4.4), y la
/// pregunta *"¿han cambiado ellos?"* la contesta el canario, no esto.
@Suite("Ingesta end-to-end · §2.3-b · el volcado real hasta Postgres",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct CalendarIngestionEndToEndTests {

    static let prefix = "test_e2e_"
    static let syncInstant = Date(timeIntervalSince1970: 1_790_000_000)

    /// Los volcados viven en `Tests/FederationTests/Fixtures/` y **no se copian
    /// aquí**: son 380 KB cada uno y ya hay dos copias en el repositorio (la de
    /// `docs/`, que es la evidencia, y la del *target* que los empaqueta como
    /// recurso). Una tercera sería la que se queda desfasada.
    ///
    /// Se leen por ruta relativa al fichero fuente, que es lo que permite
    /// compartirlos entre *targets* sin duplicar.
    static func fixture(_ name: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let url = here
            .deletingLastPathComponent()
            .appendingPathComponent("FederationTests/Fixtures/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// El transporte falseado: devuelve el fichero. Es el **único** doble de este
    /// test.
    struct FixtureTransport: FederationTransport {
        let body: String
        func get(_ url: String) async throws -> String { body }
    }

    static func withTenant(
        _ slug: String, _ body: @escaping @Sendable (TenantFixture) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(
                slug, federation: .rffm, schemaPrefix: prefix, on: app)
            try await body(TenantFixture(app: app, slug: slug, schema: "\(prefix)\(slug)"))
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    /// Siembra la **entrada** de la ingesta (`D-16`) con la coordenada real del
    /// volcado, y devuelve el caso de uso cableado contra Postgres.
    static func prepare(
        _ tenant: TenantFixture, fixture name: String, app: Vapor.Application
    ) async throws -> (IngestCalendar, CompetitionID) {
        let season = try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
            federationSeasonID: "21", createdAt: Date(), updatedAt: Date())
        let competition = try Competition(
            id: CompetitionID(raw: UUID()), seasonID: season.id,
            modality: .futbol11, gender: .masculino,
            federationCompetitionID: "24037548", federationGroupID: "24037549",
            ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
            groupLabel: "Grupo 1", createdAt: Date(), updatedAt: Date())
        try await tenant.scope {
            try await $0.seasons.save(season)
            try await $0.competitions.save(competition)
        }

        let useCase = IngestCalendar(
            unitOfWork: FluentTenantUnitOfWork(controlDatabase: app.db(.control)),
            federation: RFFMFederationClient(
                transport: FixtureTransport(body: try fixture(name))),
            clock: FixedInstantClock(instant: syncInstant),
            ids: SystemUUIDProvider())
        return (useCase, competition.id)
    }

    // ── La temporada jugada: 30 jornadas, 240 partidos ─────────────────────

    /// El volcado que Plan §4.3 daba por pendiente, entero. **Los 240 partidos
    /// vienen con marcador y con hora**, así que ésta es la primera vez que la
    /// rama de "partido jugado" se ejercita con dato real de calendario.
    @Test("ingiere el calendario de una temporada jugada de punta a punta (§2.3-b)")
    func ingestsAPlayedSeason() async throws {
        try await Self.withTenant("e2e-jugada") { tenant in
            let (useCase, competitionID) = try await Self.prepare(
                tenant, fixture: "RFFM-calendario-temporada-jugada.html", app: tenant.app)

            let report = try await useCase.execute(
                competitionID: competitionID,
                actor: .init(clubSlug: try Slug("e2e-jugada"), isSystem: true))

            #expect(report.skipped.isEmpty)
            #expect(report.roundsCreated == 30)
            #expect(report.matchesCreated == 240)

            let stored = try await tenant.scope { repositories in
                (rounds: try await repositories.rounds.list(competitionID: competitionID),
                 matches: try await repositories.matches.list(competitionID: competitionID),
                 teams: try await repositories.teams.list(),
                 clubs: try await repositories.opponentClubs.list(),
                 competition: try await repositories.competitions.find(competitionID))
            }

            #expect(stored.rounds.count == 30)
            #expect(stored.matches.count == 240)

            // 16 equipos jugando 30 jornadas a 8 partidos por jornada.
            #expect(stored.teams.count == 16)
            #expect(stored.clubs.count == 16)
            // `D-66`: la ingesta no crea equipos propios. **Los 16 son rivales**.
            #expect(stored.teams.allSatisfy { !$0.isOwn })
            // `D-07`, `D-58`: las tres piezas las presta la competición.
            #expect(stored.teams.allSatisfy {
                $0.category == .cadete && $0.gender == .masculino
                    && $0.modality == .futbol11
            })

            // La rama de "partido jugado", con dato real por primera vez.
            #expect(stored.matches.allSatisfy { $0.result != nil })
            #expect(stored.matches.allSatisfy { $0.status == .finalizado })
            #expect(stored.matches.allSatisfy { $0.isKickoffConfirmed })

            // `D-81` sobre el reparto real: 26 de las 30 jornadas ocupan dos días.
            let twoDaySpans = stored.rounds.filter { $0.startDate != $0.endDate }
            #expect(twoDaySpans.count == 26)

            #expect(stored.competition?.lastSyncedAt == Self.syncInstant)
            #expect(stored.competition?.federationName
                    == "PRIMERA DIVISION AUTONOMICA CADETE")
        }
    }

    // ── La temporada sin arrancar: la otra mitad de cada regla ─────────────

    /// El mismo recorrido sobre el volcado sin arrancar: **306 partidos, ninguno
    /// con marcador y ninguno con hora**. Es lo que demuestra que `D-56` no está
    /// escribiendo ceros ni medianoches.
    ///
    /// Y `D-81` en su otro extremo: los 306 comparten fecha, así que **las 34
    /// jornadas duran un día**. La competición de este volcado es senior y juega
    /// en **domingo**, lo que de paso desmiente el *"el calendario nace en
    /// sábado"* de [Anexo RFFM §F.5].
    @Test("ingiere un calendario sin arrancar sin inventar marcador ni hora (D-56, D-81)")
    func ingestsAnUnstartedSeason() async throws {
        try await Self.withTenant("e2e-sinjugar") { tenant in
            let (useCase, competitionID) = try await Self.prepare(
                tenant, fixture: "RFFM-calendario-temporada-sin-jugar.html",
                app: tenant.app)

            let report = try await useCase.execute(
                competitionID: competitionID,
                actor: .init(clubSlug: try Slug("e2e-sinjugar"), isSystem: true))

            #expect(report.skipped.isEmpty)
            #expect(report.roundsCreated == 34)
            #expect(report.matchesCreated == 306)

            let stored = try await tenant.scope { repositories in
                (rounds: try await repositories.rounds.list(competitionID: competitionID),
                 matches: try await repositories.matches.list(competitionID: competitionID))
            }

            #expect(stored.matches.allSatisfy { $0.result == nil })
            #expect(stored.matches.allSatisfy { $0.status == .programado })
            #expect(stored.matches.allSatisfy { !$0.isKickoffConfirmed })
            #expect(stored.rounds.allSatisfy { $0.startDate == $0.endDate })
        }
    }

    // ── Idempotencia contra las restricciones de verdad ────────────────────

    /// El nivel 2 ya prueba que la segunda pasada no duplica, **pero con dobles
    /// que no tienen restricciones**. Aquí las hay: si la pasada intentara
    /// reinsertar cualquiera de las 240 filas, el `UNIQUE` de §3.5 la pararía y
    /// la transacción entera reventaría.
    ///
    /// Es la diferencia entre "el caso de uso cree que no duplica" y "no
    /// duplica", y es la razón por la que F5 tiene los dos niveles.
    ///
    /// **Y los cuatro `…Updated` a cero, que los añadió `A-2` (H-19).** Sin ellos
    /// el test decía *"no se creó nada"*, que es más flojo de lo que parece: si
    /// cualquiera de las columnas volátiles no diese la vuelta fiel —el `date` de
    /// Postgres contra el `Date` en UTC, el `HH:mm` como texto, el `venue` vuelto
    /// a limpiar—, `merged != existing` sería cierto en las **240** filas y la
    /// pasada del lunes reescribiría el calendario entero sin que el verde se
    /// moviese. Con los contadores, una sola columna que derive tumba esto.
    @Test("la segunda pasada no choca con ninguna restricción de §3.5, y no escribe")
    func secondPassIsIdempotentAgainstRealConstraints() async throws {
        try await Self.withTenant("e2e-idem") { tenant in
            let (useCase, competitionID) = try await Self.prepare(
                tenant, fixture: "RFFM-calendario-temporada-jugada.html", app: tenant.app)
            let actor = ActorContext(clubSlug: try Slug("e2e-idem"), isSystem: true)

            _ = try await useCase.execute(competitionID: competitionID, actor: actor)
            let second = try await useCase.execute(competitionID: competitionID, actor: actor)

            #expect(second.matchesCreated == 0)
            #expect(second.roundsCreated == 0)
            #expect(second.opponentClubsCreated == 0)
            #expect(second.teamsCreated == 0)
            #expect(second.skipped.isEmpty)

            // Lo que no se crea **ni se reescribe**: el mismo volcado dos veces
            // deja la base byte a byte igual, y eso es lo que hace barata la
            // cadencia semanal de §5.6.
            #expect(second.matchesUpdated == 0)
            #expect(second.roundsUpdated == 0)
            #expect(second.opponentClubsUpdated == 0)
            #expect(second.teamsUpdated == 0)

            let stored = try await tenant.scope { repositories in
                (matches: try await repositories.matches.list(competitionID: competitionID),
                 teams: try await repositories.teams.list())
            }
            #expect(stored.matches.count == 240)
            #expect(stored.teams.count == 16)
        }
    }

    // ── D-83: una pasada, un ámbito, y un fallo no deja nada ───────────────

    /// **La propiedad que el nivel 2 no puede probar**, porque sus dobles no
    /// tienen transacción: cuando algo revienta a mitad de la pasada, lo que ya
    /// se había escrito **se deshace**.
    ///
    /// El fallo se provoca con un partido de un equipo contra sí mismo, que la
    /// invariante de `Match` (§3.5) rechaza. Para cuando eso ocurre, la pasada ya
    /// ha escrito el club, el equipo y la jornada del **primer** partido — así
    /// que si no hubiera transacción, quedarían.
    ///
    /// Y la otra mitad, que es lo que pidió el desarrollador: **no se borra
    /// nada**. La competición sembrada antes de la pasada sigue ahí, y sigue sin
    /// `last_synced_at`, que es como se sabe que la sincronización no tuvo éxito.
    @Test("un fallo a mitad de pasada no deja nada escrito, y no borra lo que había (D-83)")
    func aFailedPassLeavesNothingBehind() async throws {
        try await Self.withTenant("e2e-rollback") { tenant in
            let season = try Season(
                id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
                federationSeasonID: "21", createdAt: Date(), updatedAt: Date())
            let competition = try Competition(
                id: CompetitionID(raw: UUID()), seasonID: season.id,
                modality: .futbol11, gender: .masculino,
                federationCompetitionID: "24037548", federationGroupID: "24037549",
                ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
                groupLabel: "Grupo 1", createdAt: Date(), updatedAt: Date())
            try await tenant.scope {
                try await $0.seasons.save(season)
                try await $0.competitions.save(competition)
            }

            let useCase = IngestCalendar(
                unitOfWork: FluentTenantUnitOfWork(controlDatabase: tenant.app.db(.control)),
                federation: StubFederationClient(returning: Self.brokenCalendar()),
                clock: FixedInstantClock(instant: Self.syncInstant),
                ids: SystemUUIDProvider())

            await #expect(throws: DomainError.self) {
                try await useCase.execute(
                    competitionID: competition.id,
                    actor: .init(clubSlug: try Slug("e2e-rollback"), isSystem: true))
            }

            let after = try await tenant.scope { repositories in
                (clubs: try await repositories.opponentClubs.list(),
                 teams: try await repositories.teams.list(),
                 rounds: try await repositories.rounds.list(competitionID: competition.id),
                 matches: try await repositories.matches.list(competitionID: competition.id),
                 competition: try await repositories.competitions.find(competition.id))
            }

            // Nada de la pasada sobrevive, ni siquiera lo del primer partido,
            // que llegó a escribirse antes de que reventara el segundo.
            #expect(after.clubs.isEmpty)
            #expect(after.teams.isEmpty)
            #expect(after.rounds.isEmpty)
            #expect(after.matches.isEmpty)
            // Y nada de lo que había se pierde.
            #expect(after.competition != nil)
            #expect(after.competition?.lastSyncedAt == nil)
        }
    }

    // ── D-85: el registro sobrevive a lo que la pasada no ──────────────────

    /// **La prueba que justifica que el registro vaya en su propio ámbito.**
    ///
    /// El nivel 2 puede afirmar que se llama a `record`, pero no que la fila
    /// sobreviva: sus dobles no tienen transacción. Aquí sí. La pasada revienta a
    /// mitad, el `rollback` se lleva clubes, equipos, jornadas y partidos — **y el
    /// registro se queda**, que es el único sitio donde va a constar que esa noche
    /// la ingesta falló.
    ///
    /// Si el `record` viviera dentro del ámbito de escritura, este test pasaría
    /// en el nivel 2 y fallaría aquí. Es exactamente la clase de cosa que Plan §5
    /// pone en el nivel 3.
    @Test("el registro de la pasada fallida sobrevive al rollback (D-85)")
    func theRunRecordSurvivesTheRollback() async throws {
        try await Self.withTenant("e2e-log") { tenant in
            let season = try Season(
                id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
                federationSeasonID: "21", createdAt: Date(), updatedAt: Date())
            let competition = try Competition(
                id: CompetitionID(raw: UUID()), seasonID: season.id,
                modality: .futbol11, gender: .masculino,
                federationCompetitionID: "24037548", federationGroupID: "24037549",
                ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
                groupLabel: "Grupo 1", createdAt: Date(), updatedAt: Date())
            try await tenant.scope {
                try await $0.seasons.save(season)
                try await $0.competitions.save(competition)
            }

            let useCase = IngestCalendar(
                unitOfWork: FluentTenantUnitOfWork(controlDatabase: tenant.app.db(.control)),
                federation: StubFederationClient(returning: Self.brokenCalendar()),
                clock: FixedInstantClock(instant: Self.syncInstant),
                ids: SystemUUIDProvider())

            await #expect(throws: DomainError.self) {
                try await useCase.execute(
                    competitionID: competition.id,
                    actor: .init(clubSlug: try Slug("e2e-log"), isSystem: true))
            }

            let after = try await tenant.scope { repositories in
                (teams: try await repositories.teams.list(),
                 runs: try await repositories.ingestionRuns.list(
                    competitionID: competition.id, limit: 10))
            }

            // Lo de la pasada, deshecho.
            #expect(after.teams.isEmpty)
            // El registro, no.
            #expect(after.runs.count == 1)
            #expect(after.runs.first?.outcome == .failed)
            #expect(after.runs.first?.error?.isEmpty == false)
            #expect(after.runs.first?.matchesCreated == 0)
        }
    }

    /// Ida y vuelta del registro con **descartes dentro**, que es donde vive el
    /// `jsonb`.
    ///
    /// Se prueba aquí y no en el nivel 2 por lo mismo que lo anterior: la forma
    /// del documento es cosa del driver, y Postgres ya cazó una vez que un array
    /// de Swift se enlaza como `jsonb[]` y no como `jsonb`.
    @Test("el registro guarda y recupera sus descartes (D-85, §4.4)")
    func theRunRecordRoundTripsItsSkips() async throws {
        try await Self.withTenant("e2e-skips") { tenant in
            let season = try Season(
                id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
                federationSeasonID: "21", createdAt: Date(), updatedAt: Date())
            let competition = try Competition(
                id: CompetitionID(raw: UUID()), seasonID: season.id,
                modality: .futbol11, gender: .masculino,
                federationCompetitionID: "24037548", federationGroupID: "24037549",
                ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
                groupLabel: "Grupo 1", createdAt: Date(), updatedAt: Date())
            try await tenant.scope {
                try await $0.seasons.save(season)
                try await $0.competitions.save(competition)
            }

            let useCase = IngestCalendar(
                unitOfWork: FluentTenantUnitOfWork(controlDatabase: tenant.app.db(.control)),
                federation: StubFederationClient(returning: Self.calendarWithADatelessMatch()),
                clock: FixedInstantClock(instant: Self.syncInstant),
                ids: SystemUUIDProvider())

            _ = try await useCase.execute(
                competitionID: competition.id,
                actor: .init(clubSlug: try Slug("e2e-skips"), isSystem: true))

            let runs = try await tenant.scope {
                try await $0.ingestionRuns.list(competitionID: competition.id, limit: 10)
            }

            #expect(runs.count == 1)
            #expect(runs.first?.outcome == .succeeded)
            #expect(runs.first?.matchesCreated == 1)
            #expect(runs.first?.skipped == [IngestionSkip(
                reason: .missingMatchDate,
                detail: "[2] E.F.M.O. BOADILLA - LAS ROZAS C.F.")])
        }
    }

    // ── §3.7 contra la columna: lo que una pasada muda NO hace ─────────────
    //
    // Los tres tests de aquí abajo los trajo el bloque `A-2` del plan de
    // auditoría (H-17). Lo que les faltaba al proyecto no era una regla: era la
    // **medición** de que la regla llega a la columna.
    //
    // El nivel 1 prueba las cuatro clases de campo de §3.7 en milisegundos, y el
    // nivel 2 recorre el sentido bueno —la fuente calla primero y habla después—.
    // El sentido que **destruye datos** no lo probaba nada: ni con dobles ni
    // contra Postgres. Y es el único fallo del sistema que pierde algo que no
    // vuelve, porque `Match` no tiene `PATCH` (`D-75`).
    //
    // **Dos decisiones de forma, y las dos son de §6.2.** Se lee **en crudo y
    // fuera del ámbito**, porque lo que se comprueba es la columna y no el
    // `Record` que la mapea; y se afirma sobre **los cuatro contadores de
    // `IngestionRun`**, porque *«no se creó nada»* no es *«no se escribió
    // nada»* — un `UPDATE` que pisa un dato bueno no crea filas, no rompe
    // ninguna restricción y no mueve ningún recuento.

    /// **La pasada muda, que es la del lunes siguiente a que la fuente se calle.**
    ///
    /// Primera pasada: la fuente lo dice todo —marcador, hora, campo, `codacta`,
    /// clave de club—. Luego el administrador corrige lo que §5.1 le deja
    /// corregir. Y segunda pasada con **el mismo calendario mudo**: sin marcador,
    /// sin hora, sin campo, sin `codacta`.
    ///
    /// Lo que tiene que pasar es **nada**: ni un `INSERT`, ni un `UPDATE`, ni un
    /// valor movido. Si `volatile` se convirtiera en *"pisar siempre"* —la
    /// implementación que `D-56` existe para prohibir—, aquí se caerían siete
    /// aserciones de columna y cuatro de contador.
    ///
    /// La clave de club **sí** va en la segunda pasada, y no es descuido: sin ella
    /// el paso 2 de la cadena tendría que emparejar por el nombre *corregido*, que
    /// es el caso de **H-21** y no lo que este test mide.
    @Test("una pasada muda no borra nada de lo que la anterior escribió (D-56, D-75)")
    func aSilentPassDestroysNothing() async throws {
        try await Self.withTenant("e2e-muda") { tenant in
            let competitionID = try await Self.seedEntry(tenant)
            let actor = ActorContext(clubSlug: try Slug("e2e-muda"), isSystem: true)

            _ = try await Self.useCase(tenant, Self.calendar(
                homeScore: 3, awayScore: 1,
                kickoff: WallClockTime(hour: 10, minute: 45),
                venue: "CANAL ISABEL II",
                federationMatchID: "5374968")
            ).execute(competitionID: competitionID, actor: actor)

            // La corrección del administrador (§5.1) sobre los tres campos
            // **descriptivos** del club, `crest_key` incluido. El nombre sale del
            // `slug` porque `name` lleva `UNIQUE` (§3.5) y los dos clubes se
            // corrigen en el mismo ámbito: repetirlo aborta la transacción entera.
            try await tenant.scope { repositories in
                for club in try await repositories.opponentClubs.list() {
                    try await repositories.opponentClubs.save(try OpponentClub(
                        id: club.id,
                        name: "Corregido \(club.slug.value)",
                        shortName: "Corregido",
                        slug: club.slug,
                        federationClubID: club.federationClubID,
                        crestKey: "clubs/\(club.slug.value)/crest.png",
                        createdAt: club.createdAt, updatedAt: club.updatedAt))
                }
            }

            // La fuente se calla en todo lo que puede callar.
            let second = try await Self.useCase(tenant, Self.calendar())
                .execute(competitionID: competitionID, actor: actor)

            // (a) La pasada muda no escribe. Los ocho contadores a cero.
            #expect(second.matchesCreated == 0)
            #expect(second.matchesUpdated == 0)
            #expect(second.roundsCreated == 0)
            #expect(second.roundsUpdated == 0)
            #expect(second.teamsCreated == 0)
            #expect(second.teamsUpdated == 0)
            #expect(second.opponentClubsCreated == 0)
            #expect(second.opponentClubsUpdated == 0)
            #expect(second.skipped.isEmpty)

            // (b) Las columnas volátiles del partido, tal como las dejó la
            // primera. **Se descodifican como opcionales a propósito**: si la
            // regla se rompiera, la columna vendría `NULL` y un tipo obligatorio
            // daría un rojo de descodificación en vez de uno de aserción — que es
            // justo lo que Plan §5.1 no quiere, porque no dice qué se perdió.
            let match = try #require(try await tenant.raw.raw("""
                SELECT home_score, away_score, kickoff_time, venue,
                       federation_match_id, status, match_date::text AS day
                FROM \(ident: tenant.schema).\(ident: "matches")
                """).first())
            #expect(try match.decode(column: "home_score", as: Int?.self) == 3)
            #expect(try match.decode(column: "away_score", as: Int?.self) == 1)
            #expect(try match.decode(column: "kickoff_time", as: String?.self) == "10:45")
            #expect(try match.decode(column: "venue", as: String?.self) == "CANAL ISABEL II")
            #expect(try match.decode(column: "federation_match_id", as: String?.self)
                    == "5374968")
            #expect(try match.decode(column: "status", as: String?.self) == "finalizado")
            #expect(try match.decode(column: "day", as: String?.self) == "2025-09-27")

            // (c) Lo descriptivo del club y su clave de emparejamiento.
            let clubs = try await tenant.scope { try await $0.opponentClubs.list() }
            #expect(clubs.count == 2)
            #expect(clubs.allSatisfy { $0.name.hasPrefix("Corregido ") })
            #expect(clubs.allSatisfy { $0.shortName == "Corregido" })
            #expect(clubs.allSatisfy { $0.crestKey?.hasSuffix("/crest.png") == true })
            #expect(clubs.allSatisfy { $0.federationClubID != nil })

            // (d) Y la clave de emparejamiento del equipo, que la pasada muda
            // tampoco publica.
            let teams = try await tenant.scope { try await $0.teams.list() }
            #expect(teams.count == 2)
            #expect(teams.allSatisfy { $0.federationTeamID != nil })
        }
    }

    /// **La otra mitad, sin la cual la anterior pasaría con un fallo peor.**
    ///
    /// Un test que solo compruebe *"no borra"* lo aprobaría también una regla que
    /// **nunca** escriba `nil`, y eso rompería `D-30`: una suspensión tiene que
    /// poder devolver el horario a provisional. Lo que desambigua es el marcador
    /// **fusionado** (`D-56`), así que aquí el partido sigue sin jugarse en las dos
    /// pasadas y la hora que desaparece **sí** se escribe.
    ///
    /// Se comprueba con `IS NULL` en crudo: por el mapeo, una cadena vacía y un
    /// `NULL` volverían los dos como `nil` y son cosas distintas en la columna.
    @Test("sin marcador, la hora que desaparece sí vacía la columna (D-30, D-56)")
    func withoutAScoreTheVanishingKickoffClearsTheColumn() async throws {
        try await Self.withTenant("e2e-provisional") { tenant in
            let competitionID = try await Self.seedEntry(tenant)
            let actor = ActorContext(clubSlug: try Slug("e2e-provisional"), isSystem: true)

            _ = try await Self.useCase(tenant, Self.calendar(
                kickoff: WallClockTime(hour: 12, minute: 0),
                federationMatchID: "5374968")
            ).execute(competitionID: competitionID, actor: actor)

            let second = try await Self.useCase(tenant, Self.calendar(
                federationMatchID: "5374968")
            ).execute(competitionID: competitionID, actor: actor)

            // Esta vez sí hay `UPDATE`: la hora se va, que es el dato real.
            #expect(second.matchesUpdated == 1)

            let match = try #require(try await tenant.raw.raw("""
                SELECT kickoff_time IS NULL AS sin_hora, status,
                       home_score IS NULL AS sin_marcador,
                       match_date::text AS day
                FROM \(ident: tenant.schema).\(ident: "matches")
                """).first())
            #expect(try match.decode(column: "sin_hora", as: Bool.self))
            // Y lo que **no** se mueve: la fecha sigue, y el estado con ella.
            #expect(try match.decode(column: "sin_marcador", as: Bool.self))
            #expect(try match.decode(column: "status", as: String.self) == "programado")
            #expect(try match.decode(column: "day", as: String.self) == "2025-09-27")
        }
    }

    /// **El hueco que se rellena, contra las restricciones de verdad** (`D-76`).
    ///
    /// El espejo de la regla volátil: la clave de emparejamiento no se sobrescribe
    /// nunca, pero **sí llega donde no había nada**. Sin esto, una fila que nació
    /// sin clave —porque la inferencia sobre el nombre del escudo falló
    /// ([Anexo RFFM §F.4])— se quedaría emparejándose por el paso inexacto para
    /// siempre.
    ///
    /// Y contra Postgres tiene una mitad que el nivel 1 no puede tener: las tres
    /// claves que se rellenan están bajo `UNIQUE` (§3.5), incluida la de `codacta`.
    /// Rellenar el hueco es el único momento en que la ingesta **escribe** una de
    /// esas columnas sobre una fila que ya existe.
    ///
    /// La primera pasada empareja por el paso 2 en los tres niveles —equipo, club
    /// y partido— porque no hay clave con la que hacerlo por el paso 1. Eso es
    /// `D-78` ejecutándose: el *"si no"* es *"si el escalón anterior no
    /// resolvió"*.
    @Test("la clave que faltaba se rellena en la pasada siguiente (D-76, D-78)")
    func theMatchingHoleIsFilledOnTheNextPass() async throws {
        try await Self.withTenant("e2e-hueco") { tenant in
            let competitionID = try await Self.seedEntry(tenant)
            let actor = ActorContext(clubSlug: try Slug("e2e-hueco"), isSystem: true)

            // Pasada 1: la fuente no publica ninguna de las tres claves.
            let first = try await Self.useCase(tenant, Self.calendar(
                federationMatchID: nil,
                federationClubIDs: false,
                federationTeamIDs: false)
            ).execute(competitionID: competitionID, actor: actor)
            #expect(first.matchesCreated == 1)
            #expect(first.opponentClubsCreated == 2)
            #expect(first.teamsCreated == 2)

            // Pasada 2: ahora sí. Ni se duplica nada ni se crea nada.
            let second = try await Self.useCase(tenant, Self.calendar(
                federationMatchID: "5374968")
            ).execute(competitionID: competitionID, actor: actor)
            #expect(second.matchesCreated == 0)
            #expect(second.opponentClubsCreated == 0)
            #expect(second.teamsCreated == 0)
            #expect(second.matchesUpdated == 1)
            #expect(second.opponentClubsUpdated == 2)
            #expect(second.teamsUpdated == 2)
            #expect(second.skipped.isEmpty)

            let stored = try await tenant.scope { repositories in
                (matches: try await repositories.matches.list(competitionID: competitionID),
                 teams: try await repositories.teams.list(),
                 clubs: try await repositories.opponentClubs.list())
            }
            #expect(stored.matches.count == 1)
            #expect(stored.matches.first?.federationMatchID == "5374968")
            #expect(stored.teams.count == 2)
            #expect(stored.teams.compactMap(\.federationTeamID).sorted() == ["304468", "821"])
            #expect(stored.clubs.count == 2)
            #expect(stored.clubs.compactMap(\.federationClubID).sorted()
                    == ["0010940034", "0011078749"])
        }
    }

    // ── Andamiaje de los tres de arriba ────────────────────────────────────

    /// Siembra la **entrada** de la ingesta (`D-16`) y devuelve su competición.
    ///
    /// Es `prepare` sin el volcado: estos tests necesitan **dos** calendarios
    /// distintos sobre el mismo tenant, así que el cliente de federación se monta
    /// aparte con `useCase(_:_:)`.
    static func seedEntry(_ tenant: TenantFixture) async throws -> CompetitionID {
        let season = try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
            federationSeasonID: "21", createdAt: Date(), updatedAt: Date())
        let competition = try Competition(
            id: CompetitionID(raw: UUID()), seasonID: season.id,
            modality: .futbol11, gender: .masculino,
            federationCompetitionID: "24037548", federationGroupID: "24037549",
            ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
            groupLabel: "Grupo 1", createdAt: Date(), updatedAt: Date())
        try await tenant.scope {
            try await $0.seasons.save(season)
            try await $0.competitions.save(competition)
        }
        return competition.id
    }

    /// Una pasada cableada contra Postgres que devuelve **este** calendario.
    static func useCase(
        _ tenant: TenantFixture, _ calendar: FederationCalendar
    ) -> IngestCalendar {
        IngestCalendar(
            unitOfWork: FluentTenantUnitOfWork(controlDatabase: tenant.app.db(.control)),
            federation: StubFederationClient(returning: calendar),
            clock: FixedInstantClock(instant: syncInstant),
            ids: SystemUUIDProvider())
    }

    /// El 27-09-2025, construido **en UTC** por lo mismo que `RFFMValue.matchDate`:
    /// la columna es `date` y con huso local la medianoche caería el día anterior.
    static let matchDay = Date(timeIntervalSince1970: 1_758_931_200)

    /// Un calendario de una jornada y un partido, **con todo lo que la fuente
    /// puede decir como parámetro** — que es lo que permite repetirlo mudo.
    ///
    /// Los valores por defecto son el silencio: así una segunda pasada se escribe
    /// como `Self.calendar()` y se lee como *"la fuente no dijo nada"*.
    static func calendar(
        homeScore: Int? = nil,
        awayScore: Int? = nil,
        kickoff: WallClockTime? = nil,
        venue: String? = nil,
        federationMatchID: String? = nil,
        federationClubIDs: Bool = true,
        federationTeamIDs: Bool = true
    ) -> FederationCalendar {
        func ref(_ teamID: String, _ clubID: String, _ name: String) -> FederationTeamRef {
            FederationTeamRef(
                federationTeamID: federationTeamIDs ? teamID : nil,
                name: name, letter: "A",
                federationClubID: federationClubIDs ? clubID : nil,
                crestURL: nil)
        }
        return FederationCalendar(
            seasonLabel: try! SeasonLabel("2025/26"),
            competitionName: "PRIMERA DIVISION AUTONOMICA CADETE",
            groupLabel: "Grupo 1", currentRound: 1,
            rounds: [FederationRound(number: 1, label: "1 (27-09-2025)", matches: [
                FederationMatch(
                    federationMatchID: federationMatchID,
                    home: ref("821", "0010940034", "CELTIC CASTILLA C.F."),
                    away: ref("304468", "0011078749", "C.D. GALAPAGAR"),
                    homeScore: homeScore, awayScore: awayScore,
                    date: matchDay, kickoff: kickoff,
                    venue: venue, venueCode: "103"),
            ])])
    }

    /// Una jornada con un partido bueno y otro **sin fecha**, que la pasada deja
    /// fuera y reporta (`D-75`).
    static func calendarWithADatelessMatch() -> FederationCalendar {
        func ref(_ id: String, _ name: String) -> FederationTeamRef {
            FederationTeamRef(
                federationTeamID: id, name: name, letter: "A",
                federationClubID: "club-\(id)", crestURL: nil)
        }
        func match(
            _ acta: String, _ home: FederationTeamRef, _ away: FederationTeamRef, _ date: Date?
        ) -> FederationMatch {
            FederationMatch(
                federationMatchID: acta, home: home, away: away,
                homeScore: nil, awayScore: nil, date: date, kickoff: nil,
                venue: nil, venueCode: nil)
        }
        return FederationCalendar(
            seasonLabel: try! SeasonLabel("2025/26"),
            competitionName: nil, groupLabel: "Grupo 1", currentRound: 1,
            rounds: [FederationRound(number: 1, label: "1", matches: [
                match("1", ref("821", "CELTIC CASTILLA C.F."),
                      ref("304468", "C.D. GALAPAGAR"),
                      Date(timeIntervalSince1970: 1_758_931_200)),
                match("2", ref("900", "E.F.M.O. BOADILLA"),
                      ref("901", "LAS ROZAS C.F."), nil),
            ])])
    }

    /// Una jornada con dos partidos: el primero es bueno y el segundo enfrenta a
    /// un equipo consigo mismo, que `Match` rechaza (§3.5).
    static func brokenCalendar() -> FederationCalendar {
        func ref(_ id: String, _ name: String) -> FederationTeamRef {
            FederationTeamRef(
                federationTeamID: id, name: name, letter: "A",
                federationClubID: "club-\(id)", crestURL: nil)
        }
        let date = Date(timeIntervalSince1970: 1_758_931_200)
        func match(_ acta: String, _ home: FederationTeamRef, _ away: FederationTeamRef)
            -> FederationMatch
        {
            FederationMatch(
                federationMatchID: acta, home: home, away: away,
                homeScore: nil, awayScore: nil, date: date, kickoff: nil,
                venue: nil, venueCode: nil)
        }
        let celtic = ref("821", "CELTIC CASTILLA C.F.")
        let galapagar = ref("304468", "C.D. GALAPAGAR")
        let boadilla = ref("900", "E.F.M.O. BOADILLA")

        return FederationCalendar(
            seasonLabel: try! SeasonLabel("2025/26"),
            competitionName: nil, groupLabel: "Grupo 1", currentRound: 1,
            rounds: [FederationRound(number: 1, label: "1", matches: [
                match("1", celtic, galapagar),
                match("2", boadilla, boadilla),
            ])])
    }
}

/// Devuelve el calendario que se le dé, sin tocar el parser. Para el caso de
/// rollback hace falta un calendario **imposible**, y ningún volcado real lo es.
struct StubFederationClient: FederationClient {
    let calendar: FederationCalendar
    init(returning calendar: FederationCalendar) { self.calendar = calendar }
    func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
        calendar
    }
}

/// El reloj fijo del nivel 3. Los dobles del nivel 2 viven en `ApplicationTests`
/// y ese *target* no lo ve éste.
struct FixedInstantClock: Clock {
    let instant: Date
    func now() -> Date { instant }
}

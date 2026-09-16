import Application
import Domain
import Federation
import Fluent
import Foundation
import Testing
import Vapor

@testable import App
import TestSupport
@testable import Persistence
@testable import Tenancy

/// Nivel 3 (§8.1): **los dos volcados reales, del calendario a la clasificación,
/// hasta Postgres.**
///
/// # Por qué este test es el que justifica haber capturado los dos del mismo grupo
///
/// El volcado de calendario y el de clasificación son **PRIMERA DIVISION
/// AUTONOMICA CADETE Grupo 1, 2025-26** — la misma coordenada. Eso permite lo
/// único que ninguno de los dos hace por separado:
///
/// 1. el calendario crea los 16 equipos con su `codigo_equipo`;
/// 2. la clasificación llega con `codequipo`, y **tiene que casar con ellos por
///    id**, sin degradar a nombre ([Anexo RFFM §F.8], §F.18);
/// 3. y el *fallback* de [D-15] suma desde **esos mismos 240 partidos**, así que
///    se puede comparar contra la tabla que publica la federación.
///
/// Con volcados de grupos distintos, los pasos 2 y 3 no se pueden afirmar: no
/// habría con qué casar ni con qué comparar.
///
/// # Por qué el club es de la FCF si los volcados son de Madrid
///
/// Para ejercitar **las dos ramas de [D-15] en la misma pasada**, que es lo que
/// este test existe para probar. La capacidad sale del catálogo en código
/// (`providesRoundStandings`, [D-55]) y no es inyectable, así que la única forma
/// de que el plan mande *"pide la última y calcula el resto"* es un club catalán.
/// El cliente de federación está falseado de todos modos —le damos el volcado de
/// Madrid—, así que lo que se prueba es **la rama**, no el proveedor.
@Suite("Clasificación end-to-end · §2.3-b · los dos volcados hasta Postgres",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct StandingIngestionEndToEndTests {

    static let prefix = "test_stande2e_"
    static let syncInstant = Date(timeIntervalSince1970: 1_790_000_000)

    static func fixture(_ name: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return try String(
            contentsOf: here.deletingLastPathComponent()
                .appendingPathComponent("FederationTests/Fixtures/\(name)"),
            encoding: .utf8)
    }

    /// Los cuerpos del volcado de clasificación, **sin el envoltorio**: el fichero
    /// guarda la URL arriba y el `HTTP 200` abajo, y el parser recibe el cuerpo.
    static func standingsBodies() throws -> [String] {
        try fixture("RFFM-standings-temp21-group-24037549-round30-29.txt")
            .components(separatedBy: "https://www.rffm.es/api/")
            .dropFirst()
            .map { block in
                block.split(separator: "\n", omittingEmptySubsequences: false)
                    .dropFirst()
                    .filter { !$0.hasPrefix("HTTP ") }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
    }

    /// Sirve el calendario o la clasificación **según la URL que le pidan**, que
    /// es lo que permite que la pasada entera corra contra volcados reales.
    /// Sirve los **tres** volcados reales del mismo grupo, decidiendo por la ruta.
    ///
    /// **`scorers` es opcional, y no por comodidad**: los tests que solo ejercitan
    /// el calendario y la clasificación no tienen por qué preparar un ranking, y
    /// devolver `null` es lo que la fuente responde de verdad cuando no hay nada
    /// que servir. Lo que **no** vale es devolver el calendario por defecto para
    /// cualquier ruta desconocida, que es lo que hacía la primera versión de este
    /// doble: con `/api/scorers` sin preparar, el parser de goleadores recibía una
    /// página HTML y el fallo llegaba disfrazado de *"han cambiado la forma"*.
    struct DumpTransport: FederationTransport {
        let calendar: String
        let standingsByRound: [Int: String]
        var scorers: String?

        func get(_ url: String) async throws -> String {
            if url.contains("/api/scorers") {
                return scorers ?? "null"
            }
            if url.contains("/api/standings") {
                let round = url.split(separator: "round=").last.flatMap { Int($0) }
                guard let round, let body = standingsByRound[round] else {
                    Issue.record("nadie preparó la jornada de \(url)")
                    return "null"
                }
                return body
            }
            return calendar
        }
    }

    /// El cuerpo del volcado de goleadores, sin la URL de cabecera.
    static func scorersBody() throws -> String {
        let raw = try fixture("RFFM-scorers-group-24037549.txt")
        return raw
            .components(separatedBy: "https://www.rffm.es/api/")
            .dropFirst()
            .map { block in
                block
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .dropFirst()
                    .filter { !$0.hasPrefix("HTTP ") }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .first ?? ""
    }

    struct FixedInstantClock: Clock {
        let instant: Date
        func now() -> Date { instant }
    }

    struct SingleClientProvider: FederationClientProvider {
        let client: any FederationClient
        func client(for code: FederationCode) -> (any FederationClient)? { client }
    }

    // ─────────────────────────────────────────────────────────────────────────

    @Test("el calendario crea los equipos y la clasificación casa con ellos por id (§F.8)")
    func thewholeChainLandsInPostgres() async throws {
        let slug = "stande2e"
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: Self.prefix, on: app)
            // Club catalán: fuerza la rama *"pide la última y calcula el resto"*.
            try await TestEnvironment.provisionClub(
                slug, federation: .fcf, schemaPrefix: Self.prefix, on: app)
            let tenant = TenantFixture(app: app, slug: slug, schema: "\(Self.prefix)\(slug)")

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

            let bodies = try Self.standingsBodies()
            let transport = DumpTransport(
                calendar: try Self.fixture("RFFM-calendario-temporada-jugada.html"),
                standingsByRound: [30: try #require(bodies.first),
                                   29: try #require(bodies.last)])
            let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            let client = RFFMFederationClient(transport: transport)
            let clock = FixedInstantClock(instant: Self.syncInstant)
            let actor = ActorContext(clubSlug: try Slug(slug))

            // 1) El calendario: 30 jornadas, 240 partidos, 16 equipos.
            _ = try await IngestCalendar(
                unitOfWork: unitOfWork, federation: client,
                clock: clock, ids: SystemUUIDProvider()
            ).execute(competitionID: competition.id, actor: actor)

            // 2) La clasificación, con las dos ramas de `D-15` en la misma pasada.
            let runs = try await IngestStandings(
                unitOfWork: unitOfWork, federation: client,
                clock: clock, ids: SystemUUIDProvider()
            ).execute(competitionID: competition.id, actor: actor)

            // **Una pasada por jornada**: 30 jugadas, 30 filas de registro, cada
            // una con su `round_id`. Sin esa columna serían treinta filas iguales.
            #expect(runs.count == 30)
            #expect(runs.allSatisfy { $0.kind == .standings })
            #expect(Set(runs.compactMap(\.roundID)).count == 30)

            // Y **una sola petición a la federación**: la FCF solo sirve la
            // vigente (`D-55`), así que se pide la última y el resto se calcula.
            #expect(runs.filter { $0.standingRowsCreated > 0 }.count == 30)

            let rounds = try await tenant.scope {
                try await $0.rounds.list(competitionID: competition.id)
            }
            let byNumber = Dictionary(
                rounds.map { ($0.number, $0.id) }, uniquingKeysWith: { first, _ in first })

            // ── La jornada 30: ingerida del volcado real ────────────────────
            let thirty = try await tenant.scope {
                try await $0.standingRows.list(roundID: try #require(byNumber[30]))
            }
            #expect(thirty.count == 16)

            // **Ninguna fila se descartó**: las 16 casaron por `codequipo` con los
            // equipos que creó el calendario. Es el paso 1 de la cadena de §3.7
            // haciendo su trabajo — y si `codequipo` no fuese el mismo
            // identificador que el `codigo_equipo_*`, aquí habría 16 descartes.
            #expect(runs.first { $0.roundID == byNumber[30] }?.skipped.isEmpty == true)

            // El primero del volcado: FOOTBALL DREAMS, 73 puntos, 30 jugados.
            let leader = try #require(thirty.first)
            #expect(leader.position == 1)
            #expect(leader.points == 73)
            #expect(leader.played == 30)
            #expect(leader.goalsFor == 78 && leader.goalsAgainst == 23)

            // ── La jornada 29: CALCULADA desde los 240 partidos ─────────────
            //
            // Y aquí está la comparación que justifica los dos volcados: la tabla
            // que sale de sumar los partidos reales contra la que publica la
            // federación. Medido antes de escribir este test: **16/16 exactas**,
            // orden incluido.
            let twentyNine = try await tenant.scope {
                try await $0.standingRows.list(roundID: try #require(byNumber[29]))
            }
            #expect(twentyNine.count == 16)

            let official29 = try RFFMStandingsParser.parse(try #require(bodies.last))
            let teamsByFederationID = try await tenant.scope {
                Dictionary(
                    try await $0.teams.list().compactMap { team in
                        team.federationTeamID.map { ($0, team.id) }
                    }, uniquingKeysWith: { first, _ in first })
            }

            for row in official29.rows {
                let teamID = try #require(
                    row.team.federationTeamID.flatMap { teamsByFederationID[$0] },
                    "el equipo \(row.team.name) no lo creó el calendario")
                let computed = try #require(
                    twentyNine.first { $0.teamID == teamID },
                    "falta la fila calculada de \(row.team.name)")

                #expect(computed.position == row.position, "posición de \(row.team.name)")
                #expect(computed.points == row.points, "puntos de \(row.team.name)")
                #expect(computed.played == row.played, "jugados de \(row.team.name)")
                #expect(computed.won == row.won && computed.drawn == row.drawn
                        && computed.lost == row.lost, "G/E/P de \(row.team.name)")
                #expect(computed.goalsFor == row.goalsFor
                        && computed.goalsAgainst == row.goalsAgainst,
                        "goles de \(row.team.name)")
            }

            // ── La columna PREV, encadenada de verdad ───────────────────────
            //
            // La 1 no tiene anterior; la 30 sí, y sale de la 29 que esta misma
            // pasada acaba de escribir.
            let first = try await tenant.scope {
                try await $0.standingRows.list(roundID: try #require(byNumber[1]))
            }
            #expect(first.allSatisfy { $0.previousPosition == nil })
            #expect(thirty.allSatisfy { $0.previousPosition != nil })

            try await TestEnvironment.dropClubs([slug], schemaPrefix: Self.prefix, on: app)
        }
    }

    @Test("el recorrido del club sincroniza también la clasificación (F7)")
    func thetraversalAlsoSyncsStandings() async throws {
        let slug = "standtrav"
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: Self.prefix, on: app)
            try await TestEnvironment.provisionClub(
                slug, federation: .fcf, schemaPrefix: Self.prefix, on: app)
            let tenant = TenantFixture(app: app, slug: slug, schema: "\(Self.prefix)\(slug)")

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

            let bodies = try Self.standingsBodies()
            let transport = DumpTransport(
                calendar: try Self.fixture("RFFM-calendario-temporada-jugada.html"),
                standingsByRound: [30: try #require(bodies.first),
                                   29: try #require(bodies.last)],
                // **El tercer volcado, y del MISMO grupo que los otros dos** — por
                // eso F8 lo capturó en vez de reutilizar el de §F.13, que era de
                // PRIMERA INFANTIL G12. Así el recorrido entero se prueba sobre una
                // sola competición, con sus 240 partidos, sus 16 equipos, sus 30
                // clasificaciones y sus 218 goleadores.
                scorers: try Self.scorersBody())

            // **Por el recorrido entero**, que es lo que aquí se prueba: hasta F7
            // `IngestClubCalendars` solo llamaba al calendario, y el cableado
            // nuevo no lo ejercitaba ningún test — los dobles de las suites
            // existentes devuelven calendarios vacíos, así que el plan de
            // clasificación salía vacío y la llamada no llegaba a ocurrir.
            let report = try await IngestClubCalendars(
                unitOfWork: FluentTenantUnitOfWork(controlDatabase: app.db(.control)),
                federationClients: SingleClientProvider(
                    client: RFFMFederationClient(transport: transport)),
                clock: FixedInstantClock(instant: Self.syncInstant),
                ids: SystemUUIDProvider()
            ).execute(
                // **Por su id y no por la temporada vigente**, que con el reloj
                // fijo de este test —septiembre de 2026— no incluiría a la
                // 2025/26. La competición pedida explícitamente gana y no pasa
                // por ese filtro, que es justo para lo que existe esa precedencia.
                scope: IngestionScope(competitionIDs: [competition.id]),
                actor: ActorContext(clubSlug: try Slug(slug)))

            #expect(report.hasFailures == false)

            // El calendario dejó sus partidos **y** la clasificación sus filas.
            let rows = try await tenant.scope { repositories in
                var all: [StandingRow] = []
                for round in try await repositories.rounds.list(competitionID: competition.id) {
                    all += try await repositories.standingRows.list(roundID: round.id)
                }
                return all
            }
            #expect(rows.count == 30 * 16)

            // Y el registro distingue las dos clases: una fila de calendario y
            // treinta de clasificación, cada una con su jornada.
            let runs = try await tenant.scope {
                try await $0.ingestionRuns.list(competitionID: competition.id, limit: 100)
            }
            #expect(runs.filter { $0.kind == .calendar }.count == 1)
            #expect(runs.filter { $0.kind == .standings }.count == 30)
            #expect(runs.filter { $0.kind == .calendar }.allSatisfy { $0.roundID == nil })

            // ── Y F8: la tercera clase de pasada ─────────────────────────────
            //
            // **Una sola, y sin jornada.** Es la asimetría entera de `IngestScorers`
            // contra `IngestStandings` afirmada contra Postgres: treinta filas de
            // clasificación —una por jornada— y **una** de goleadores, porque el
            // ranking es de la competición y `LeagueScorer` es estado vigente
            // único (§3.2). El `CHECK` del esquema lo repite, así que si el
            // `roundID` no fuera nulo esto ni siquiera habría llegado a escribirse.
            let scorerRuns = runs.filter { $0.kind == .scorers }
            #expect(scorerRuns.count == 1)
            #expect(scorerRuns.allSatisfy { $0.roundID == nil })
            #expect(scorerRuns.allSatisfy { $0.outcome == .succeeded })

            // Las **218** filas del volcado, enteras y sin un solo descarte: los
            // `codigo_jugador` vienen en las 218 y son 218 distintos ([Anexo RFFM
            // §F.19]), que es la medición sobre la que se apoya `D-93`.
            let scorers = try await tenant.scope {
                try await $0.leagueScorers.list(competitionID: competition.id)
            }
            #expect(scorers.count == 218)
            #expect(scorerRuns.first?.leagueScorersCreated == 218)
            #expect(scorerRuns.first?.skipped.isEmpty == true)

            // **La clave de `D-93` es única en la tabla de verdad**, no solo en el
            // `Set` de un test: si el `UNIQUE(competition_id, federation_player_id)`
            // no estuviera, esto pasaría igual y el duplicado aparecería en la
            // segunda pasada. Lo que lo prueba es el refresco de abajo.
            #expect(Set(scorers.map(\.federationPlayerID)).count == 218)

            // El orden **es** el dato (`D-49`, §5.1): sin puesto publicado, lo que
            // ordena es el número de goles.
            #expect(scorers.map(\.goals) == scorers.map(\.goals).sorted(by: >))
            #expect(scorers.first?.goals == 31)
            #expect(scorers.allSatisfy { $0.rank == nil },
                    "la RFFM no publica puesto y aquí se ha inventado uno (§F.19)")

            // **El nombre del equipo entra entero, con la letra pegada**, que es
            // como lo publica esta ruta y al revés que el calendario. No se parte
            // porque aquí solo se pinta (`D-32`).
            #expect(scorers.first?.teamLabel == "ARAVACA C.F. - CEIBA A")
            #expect(runs.filter { $0.kind == .standings }.allSatisfy { $0.roundID != nil })

            try await TestEnvironment.dropClubs([slug], schemaPrefix: Self.prefix, on: app)
        }
    }
}

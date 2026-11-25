import APIContract
import Application
import Domain
import Fluent
import Foundation
import SQLKit
import Testing
import Vapor
import VaporTesting
@testable import App
import TestSupport
@testable import Persistence
@testable import Tenancy

/// Nivel 4 (§8.1): la cabecera del acta y las cinco operaciones de la convocatoria
/// (R7.6). Los casos de uso están probados en el nivel 2; aquí, **el borde**: cada
/// ruta, cada campo de la respuesta y cada error con su estado y su código.
@Suite("Appearances · §5.1 · la cabecera del acta y la convocatoria, por HTTP",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct AppearanceEndpointTests {

    static let prefix = "e2e_"
    static let slug = "actaclub"
    static var schema: String { "\(prefix)\(slug)" }
    /// El 4 de octubre de 2025 a las 19:00 de Madrid: el partido de las 18:00 ya ha
    /// empezado; el del día 11, no.
    static let now = try! Date("2025-10-04T17:00:00Z", strategy: .iso8601)

    struct Seeded: Sendable {
        let cadeteA: TeamID
        let cadeteB: TeamID
        let rival: TeamID
        let played: MatchID
        let future: MatchID
        let rivals: MatchID
        let archived: MatchID
        let juan: PlayerID
        let pedro: PlayerID
        let deOtraTemporada: PlayerID
        let enArchivada: PlayerID
    }

    static func withSeededClub(
        slug: String = slug, _ body: @escaping @Sendable (Application, Seeded) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp(clock: FixedClock(instant: now)) { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(slug, federation: .rffm, schemaPrefix: prefix, on: app)
            let at = now
            func season(_ label: String, archived: Bool = false) throws -> Season {
                try Season(id: SeasonID(raw: UUID()), label: try SeasonLabel(label), federationSeasonID: nil,
                           archivedAt: archived ? at : nil, createdAt: at, updatedAt: at)
            }
            let (vigente, pasada, archivada) = (try season("2025/26"), try season("2024/25"),
                                                try season("2023/24", archived: true))
            func competition(_ season: Season, group: String) throws -> Competition {
                try Competition(id: CompetitionID(raw: UUID()), seasonID: season.id, modality: .futbol11,
                                gender: .masculino, federationCompetitionID: "1", federationGroupID: group,
                                ageCategory: .cadete, divisionLabel: "PRIMERA", groupLabel: "Grupo 1",
                                createdAt: at, updatedAt: at)
            }
            let (liga, ligaArchivada) = (try competition(vigente, group: "2"), try competition(archivada, group: "3"))
            func day(_ text: String) -> Date { try! Date("\(text)T00:00:00Z", strategy: .iso8601) }
            func round(_ competition: Competition, _ number: Int, _ date: String) throws -> Round {
                try Round(id: RoundID(raw: UUID()), competitionID: competition.id, number: number,
                          startDate: day(date), endDate: day(date), createdAt: at, updatedAt: at)
            }
            let (r1, r2, rArchivada) = (try round(liga, 1, "2025-10-04"), try round(liga, 2, "2025-10-11"),
                                         try round(ligaArchivada, 1, "2023-10-04"))
            let rivalClub = try OpponentClub(id: OpponentClubID(raw: UUID()), name: "C.D. RIVAL", shortName: "Rival",
                                             slug: try Slug("cd-rival"), createdAt: at, updatedAt: at)
            func own(_ letter: String) throws -> Team {
                try Team(id: TeamID(raw: UUID()), category: .cadete, letter: letter, gender: .masculino,
                         modality: .futbol11, createdAt: at, updatedAt: at)
            }
            func rival(_ letter: String) throws -> Team {
                try Team(id: TeamID(raw: UUID()), opponentClubID: rivalClub.id, seasonID: vigente.id,
                         category: .cadete, letter: letter, gender: .masculino, modality: .futbol11,
                         createdAt: at, updatedAt: at)
            }
            let (a, b, r, r2Team) = (try own("A"), try own("B"), try rival("A"), try rival("B"))
            func match(_ round: Round, _ date: String, _ home: Team, _ away: Team) throws -> Match {
                try Match(id: MatchID(raw: UUID()), competitionID: round.competitionID, roundID: round.id,
                          kickoff: Kickoff(date: day(date), time: WallClockTime(hour: 18, minute: 0)),
                          homeTeamID: home.id, awayTeamID: away.id, status: .programado, createdAt: at,
                          updatedAt: at)
            }
            let played = try match(r1, "2025-10-04", a, r)
            let rivals = try match(r1, "2025-10-04", r2Team, r)
            let future = try match(r2, "2025-10-11", r, a)
            let archived = try match(rArchivada, "2023-10-04", a, r)
            let players: [(PlayerProfile, Player)] = try [
                ("Juan García", vigente), ("Pedro López", vigente), ("Luis Pasado", pasada), ("Raúl Viejo", archivada),
            ].map { name, season in
                let profile = PlayerProfile(id: PlayerProfileID(raw: UUID()), fullName: try PlayerName(name),
                                            birthYear: nil, createdAt: at, updatedAt: at)
                return (profile, Player(id: PlayerID(raw: UUID()), profileID: profile.id, teamID: a.id,
                                        seasonID: season.id, createdAt: at, updatedAt: at))
            }
            try await FluentTenantUnitOfWork(controlDatabase: app.db(.control))
                .withRepositories(actor: ActorContext(clubSlug: try Slug(slug))) { repo in
                    for s in [vigente, pasada, archivada] { try await repo.seasons.save(s) }
                    try await repo.competitions.save(liga)
                    try await repo.competitions.save(ligaArchivada)
                    for x in [r1, r2, rArchivada] { try await repo.rounds.save(x) }
                    try await repo.opponentClubs.save(rivalClub)
                    for t in [a, b, r, r2Team] { try await repo.teams.save(t) }
                    for m in [played, rivals, future, archived] { try await repo.matches.save(m) }
                    for (profile, player) in players {
                        try await repo.playerProfiles.save(profile)
                        try await repo.players.save(player)
                    }
                }
            try await body(app, Seeded(
                cadeteA: a.id, cadeteB: b.id, rival: r.id, played: played.id, future: future.id,
                rivals: rivals.id, archived: archived.id, juan: players[0].1.id, pedro: players[1].1.id,
                deOtraTemporada: players[2].1.id, enArchivada: players[3].1.id))
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    // ── Peticiones ──────────────────────────────────────────────────────────

    static func send(
        _ app: Application, _ method: HTTPMethod, _ path: String, json: String? = nil, slug: String = slug,
        _ check: @escaping @Sendable (TestingHTTPResponse) async throws -> Void
    ) async throws {
        try await app.testing().test(
            method, path,
            beforeRequest: { request in
                request.headers.add(name: "X-Club", value: slug)
                if let json {
                    request.headers.contentType = .json
                    request.body = ByteBuffer(string: json)
                }
            }, afterResponse: check)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ response: TestingHTTPResponse) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(response.body.readableBytesView))
    }

    static func code(_ response: TestingHTTPResponse) throws -> String? {
        try decode(Components.Schemas.Problem.self, response).code?.rawValue
    }

    static func appearanceJSON(player: PlayerID, match: MatchID, team: TeamID, status: String,
                               minutes: Int? = nil, shirt: Int? = nil) -> String {
        var fields = [#""playerId": "\#(player)""#, #""matchId": "\#(match)""#, #""teamId": "\#(team)""#,
                      #""status": "\#(status)""#]
        if let minutes { fields.append(#""minutes": \#(minutes)"#) }
        if let shirt { fields.append(#""shirtNumber": \#(shirt)"#) }
        return "{" + fields.joined(separator: ", ") + "}"
    }

    /// Una convocatoria por la API, para lo que viene después. Devuelve su id.
    static func create(_ app: Application, _ json: String) async throws -> String {
        let box = Box()
        try await send(app, .POST, "/v1/appearances", json: json) { (response: TestingHTTPResponse) async throws in
            #expect(response.status == .created)
            box.id = try decode(Components.Schemas.AppearanceResponse.self, response).id
        }
        return box.id
    }

    final class Box: @unchecked Sendable { var id = "" }

    struct FixedClock: Clock {
        let instant: Date
        func now() -> Date { instant }
    }

    // ── La cabecera del acta ────────────────────────────────────────────────

    @Test("getMatch devuelve el partido, sin fecha de carga ni quitados si no hay acta")
    func getMatchWithoutReport() async throws {
        try await Self.withSeededClub { app, s in
            try await Self.send(app, .GET, "/v1/matches/\(s.played)") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .ok)
                let detail = try Self.decode(Components.Schemas.MatchDetailResponse.self, response)
                #expect(detail.value1.id == "\(s.played)")
                #expect(detail.value1.roundNumber == 1)
                #expect(detail.value1.home.value1.value1.teamId == "\(s.cadeteA)")
                #expect(detail.value1.reportLoadedAt == nil)
                #expect(detail.value2.removedFromReport.isEmpty)
            }
        }
    }

    @Test("con el acta cargada, getMatch dice cuándo y a quién ha quitado el club (D-134)")
    func getMatchWithReport() async throws {
        try await Self.withSeededClub { app, s in
            _ = try await Self.create(app, Self.appearanceJSON(
                player: s.juan, match: s.played, team: s.cadeteA, status: "jugado"))
            let lineup = #"{"players":[{"playerId":"\#(s.juan)","teamId":"\#(s.cadeteA)","status":"jugado"},"#
                + #"{"playerId":"\#(s.pedro)","teamId":"\#(s.cadeteA)","status":"convocado_sin_minutos"}]}"#
            try await (app.db(.control) as! any SQLDatabase).raw("""
                UPDATE \(ident: Self.schema).matches
                SET report_loaded_at = '2025-10-04T22:00:00Z', report_lineup = \(bind: lineup)::jsonb
                WHERE id = \(bind: s.played.raw)
                """).run()
            try await Self.send(app, .GET, "/v1/matches/\(s.played)") { (response: TestingHTTPResponse) async throws in
                let detail = try Self.decode(Components.Schemas.MatchDetailResponse.self, response)
                #expect(detail.value1.reportLoadedAt == (try Date("2025-10-04T22:00:00Z", strategy: .iso8601)))
                #expect(detail.value2.removedFromReport == [.init(
                    playerId: "\(s.pedro)", teamId: "\(s.cadeteA)", status: .convocado_sin_minutos)])
            }
            try await Self.send(app, .GET, "/v1/appearances?matchId=\(s.played)") { (response: TestingHTTPResponse) async throws in
                let rows = try Self.decode([Components.Schemas.AppearanceResponse].self, response)
                #expect(rows.map(\.changedFromReport) == [false])
            }
        }
    }

    @Test("un partido entre dos rivales, o un id que no es UUID, es 404 MATCH_NOT_FOUND (D-130)")
    func getMatchNotFound() async throws {
        try await Self.withSeededClub { app, s in
            for path in ["/v1/matches/\(s.rivals)", "/v1/matches/nada"] {
                try await Self.send(app, .GET, path) { (response: TestingHTTPResponse) async throws in
                    #expect(response.status == .notFound)
                    #expect(try Self.code(response) == "MATCH_NOT_FOUND")
                }
            }
        }
    }

    // ── Apuntar ─────────────────────────────────────────────────────────────

    @Test("createAppearance responde 201 con cada campo de la convocatoria")
    func createReturnsEveryField() async throws {
        try await Self.withSeededClub { app, s in
            try await Self.send(app, .POST, "/v1/appearances", json: Self.appearanceJSON(
                player: s.juan, match: s.played, team: s.cadeteA, status: "jugado", minutes: 70, shirt: 7)
            ) { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .created)
                let row = try Self.decode(Components.Schemas.AppearanceResponse.self, response)
                #expect(row.playerId == "\(s.juan)")
                #expect(row.matchId == "\(s.played)")
                #expect(row.teamId == "\(s.cadeteA)")
                #expect(row.status == .jugado)
                #expect(row.minutes == 70)
                #expect(row.shirtNumber == 7)
                #expect(row.changedFromReport == false)
            }
        }
    }

    @Test("un jugador ya convocado en el partido es 409 PLAYER_ALREADY_CONVOKED")
    func createDuplicateIsConflict() async throws {
        try await Self.withSeededClub { app, s in
            let json = Self.appearanceJSON(player: s.juan, match: s.played, team: s.cadeteA, status: "jugado")
            _ = try await Self.create(app, json)
            try await Self.send(app, .POST, "/v1/appearances", json: json) { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .conflict)
                #expect(try Self.code(response) == "PLAYER_ALREADY_CONVOKED")
            }
        }
    }

    @Test("lo que el cuerpo no cumple es 422, con su código", arguments: [
        ("otro equipo", "TEAM_NOT_IN_MATCH"),
        ("otra temporada", "PLAYER_NOT_IN_SEASON"),
        ("antes de la hora", "MATCH_NOT_STARTED"),
        ("entre rivales", "REFERENCE_NOT_FOUND"),
        ("minutos sin jugar", "INVALID_VALUE"),
        ("archivada", "SEASON_ARCHIVED"),
    ])
    func createRejections(_ case: String, _ code: String) async throws {
        try await Self.withSeededClub { app, s in
            let json: String = switch `case` {
            case "otro equipo": Self.appearanceJSON(player: s.juan, match: s.played, team: s.cadeteB, status: "jugado")
            case "otra temporada":
                Self.appearanceJSON(player: s.deOtraTemporada, match: s.played, team: s.cadeteA, status: "jugado")
            case "antes de la hora": Self.appearanceJSON(player: s.juan, match: s.future, team: s.cadeteA, status: "jugado")
            case "entre rivales": Self.appearanceJSON(player: s.juan, match: s.rivals, team: s.cadeteA, status: "jugado")
            case "minutos sin jugar":
                Self.appearanceJSON(player: s.juan, match: s.played, team: s.cadeteA,
                                    status: "convocado_sin_minutos", minutes: 10)
            default: Self.appearanceJSON(player: s.enArchivada, match: s.archived, team: s.cadeteA, status: "jugado")
            }
            try await Self.send(app, .POST, "/v1/appearances", json: json) { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .unprocessableEntity)
                #expect(try Self.code(response) == code)
            }
        }
    }

    @Test("antes de la hora, «Convocado» sí se apunta (D-133)")
    func createConvokedBeforeKickoff() async throws {
        try await Self.withSeededClub { app, s in
            _ = try await Self.create(app, Self.appearanceJSON(
                player: s.juan, match: s.future, team: s.cadeteA, status: "convocado_sin_minutos"))
        }
    }

    @Test("un id del cuerpo que no es UUID es 400 INVALID_UUID")
    func createWithBadUUID() async throws {
        try await Self.withSeededClub { app, s in
            try await Self.send(app, .POST, "/v1/appearances", json: #"{"playerId": "x", "matchId": "\#(s.played)", "teamId": "\#(s.cadeteA)", "status": "jugado"}"#) { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .badRequest)
                #expect(try Self.code(response) == "INVALID_UUID")
            }
        }
    }

    // ── Leer ────────────────────────────────────────────────────────────────

    @Test("listAppearances trae la convocatoria del partido por dorsal")
    func listByMatch() async throws {
        try await Self.withSeededClub { app, s in
            _ = try await Self.create(app, Self.appearanceJSON(
                player: s.juan, match: s.played, team: s.cadeteA, status: "jugado"))
            _ = try await Self.create(app, Self.appearanceJSON(
                player: s.pedro, match: s.played, team: s.cadeteA, status: "baja_medica", shirt: 4))
            try await Self.send(app, .GET, "/v1/appearances?matchId=\(s.played)") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .ok)
                let rows = try Self.decode([Components.Schemas.AppearanceResponse].self, response)
                #expect(rows.map(\.playerId) == ["\(s.pedro)", "\(s.juan)"])
            }
            try await Self.send(app, .GET, "/v1/appearances?playerId=\(s.juan)") { (response: TestingHTTPResponse) async throws in
                let rows = try Self.decode([Components.Schemas.AppearanceResponse].self, response)
                #expect(rows.map(\.matchId) == ["\(s.played)"])
            }
        }
    }

    @Test("sin ámbito, o con los dos, es 400 MISSING_SCOPE; el partido que no existe, 404")
    func listScope() async throws {
        try await Self.withSeededClub { app, s in
            for path in ["/v1/appearances", "/v1/appearances?matchId=\(s.played)&playerId=\(s.juan)",
                         "/v1/appearances?playerId=\(s.juan)&teamId=\(s.cadeteA)"] {
                try await Self.send(app, .GET, path) { (response: TestingHTTPResponse) async throws in
                    #expect(response.status == .badRequest)
                    #expect(try Self.code(response) == "MISSING_SCOPE")
                }
            }
            try await Self.send(app, .GET, "/v1/appearances?matchId=\(UUID())") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .notFound)
                #expect(try Self.code(response) == "MATCH_NOT_FOUND")
            }
        }
    }

    @Test("getAppearance devuelve la convocatoria; la que no existe es 404 APPEARANCE_NOT_FOUND")
    func getOne() async throws {
        try await Self.withSeededClub { app, s in
            let id = try await Self.create(app, Self.appearanceJSON(
                player: s.juan, match: s.played, team: s.cadeteA, status: "sancionado"))
            try await Self.send(app, .GET, "/v1/appearances/\(id)") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .ok)
                #expect(try Self.decode(Components.Schemas.AppearanceResponse.self, response).status == .sancionado)
            }
            for path in ["/v1/appearances/\(UUID())", "/v1/appearances/nada"] {
                try await Self.send(app, .GET, path) { (response: TestingHTTPResponse) async throws in
                    #expect(response.status == .notFound)
                    #expect(try Self.code(response) == "APPEARANCE_NOT_FOUND")
                }
            }
        }
    }

    // ── Corregir y borrar ───────────────────────────────────────────────────

    @Test("dejar «Jugado» borra los minutos (R7.3, P4)")
    func updateClearsMinutes() async throws {
        try await Self.withSeededClub { app, s in
            let id = try await Self.create(app, Self.appearanceJSON(
                player: s.juan, match: s.played, team: s.cadeteA, status: "jugado", minutes: 60))
            try await Self.send(app, .PATCH, "/v1/appearances/\(id)",
                                json: #"{"status": "convocado_sin_minutos"}"#) { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .ok)
                let row = try Self.decode(Components.Schemas.AppearanceResponse.self, response)
                #expect(row.status == .convocado_sin_minutos)
                #expect(row.minutes == nil)
            }
        }
    }

    @Test("de baja médica a sancionado es 422 STATUS_CHANGE_NOT_ALLOWED; un PATCH vacío, 400 EMPTY_PATCH")
    func updateRejections() async throws {
        try await Self.withSeededClub { app, s in
            let id = try await Self.create(app, Self.appearanceJSON(
                player: s.juan, match: s.played, team: s.cadeteA, status: "baja_medica"))
            try await Self.send(app, .PATCH, "/v1/appearances/\(id)", json: #"{"status": "sancionado"}"#) { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .unprocessableEntity)
                #expect(try Self.code(response) == "STATUS_CHANGE_NOT_ALLOWED")
            }
            try await Self.send(app, .PATCH, "/v1/appearances/\(id)", json: "{}") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .badRequest)
                #expect(try Self.code(response) == "EMPTY_PATCH")
            }
        }
    }

    @Test("deleteAppearance responde 204, y luego la convocatoria es 404")
    func deleteThenNotFound() async throws {
        try await Self.withSeededClub { app, s in
            let id = try await Self.create(app, Self.appearanceJSON(
                player: s.juan, match: s.played, team: s.cadeteA, status: "jugado"))
            try await Self.send(app, .DELETE, "/v1/appearances/\(id)") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .noContent)
            }
            try await Self.send(app, .DELETE, "/v1/appearances/\(id)") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .notFound)
                #expect(try Self.code(response) == "APPEARANCE_NOT_FOUND")
            }
        }
    }
}

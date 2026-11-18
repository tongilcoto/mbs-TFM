import APIContract
import Application
import Domain
import Fluent
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App
import TestSupport
@testable import Persistence
@testable import Tenancy

/// Nivel 4 (§8.1): las cinco operaciones de datos de la plantilla (R6.6). Los casos
/// de uso están probados en el nivel 2; aquí, **el borde**: cada ruta, cada campo
/// de la respuesta y cada error con su estado y su código.
@Suite("Players · §5.1 · el alta, la lista, la ficha, corregir y la baja, por HTTP",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct PlayerEndpointTests {

    static let prefix = "e2e_"
    static let slug = "playersclub"
    static let now = Date(timeIntervalSince1970: 1_760_000_000)

    struct Seeded: Sendable {
        let cadeteA: TeamID
        let cadeteB: TeamID
        let rival: TeamID
        let vigente: SeasonID
        let archivada: SeasonID
        /// Terminada y sin archivar (R6.17), con un jugador que se escribió cuando estaba en curso.
        let terminada: SeasonID
        let deLaTerminada: PlayerID
        /// Un equipo propio sin inscripción en la vigente (R6.17).
        let sinInscribir: TeamID
    }

    static func withSeededClub(
        _ body: @escaping @Sendable (Application, Seeded) async throws -> Void
    ) async throws {
        // Con su reloj: la «vigente» es la 2025/26, y con el de verdad ya habría terminado
        // (una temporada terminada no se cambia, R6.17).
        try await TestEnvironment.withApp(clock: FixedClock(instant: now)) { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(slug, federation: .rffm, schemaPrefix: prefix, on: app)
            let vigente = try Season(id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
                                     federationSeasonID: nil, createdAt: now, updatedAt: now)
            let archivada = try Season(id: SeasonID(raw: UUID()), label: try SeasonLabel("2024/25"),
                                       federationSeasonID: nil, archivedAt: now, createdAt: now,
                                       updatedAt: now)
            func own(_ letter: String) throws -> Team {
                try Team(id: TeamID(raw: UUID()), category: .cadete, letter: letter, gender: .masculino,
                         modality: .futbol11, createdAt: now, updatedAt: now)
            }
            let (a, b, c) = (try own("A"), try own("B"), try own("C"))
            let terminada = try Season(id: SeasonID(raw: UUID()), label: try SeasonLabel("2023/24"),
                                       federationSeasonID: nil, createdAt: now, updatedAt: now)
            let perfil = PlayerProfile(id: PlayerProfileID(raw: UUID()), fullName: try PlayerName("Luis Pasado"),
                                       birthYear: nil, createdAt: now, updatedAt: now)
            let fila = Player(id: PlayerID(raw: UUID()), profileID: perfil.id, teamID: a.id, seasonID: terminada.id,
                              createdAt: now, updatedAt: now)
            let rivalClub = try OpponentClub(
                id: OpponentClubID(raw: UUID()), name: "C.D. Rival", shortName: "Rival",
                slug: try Slug("cd-rival"), federationClubID: "999", createdAt: now, updatedAt: now)
            let rival = try Team(
                id: TeamID(raw: UUID()), opponentClubID: rivalClub.id, seasonID: vigente.id,
                category: .cadete, letter: "A", gender: .masculino, modality: .futbol11,
                federationTeamID: "8888", createdAt: now, updatedAt: now)
            try await FluentTenantUnitOfWork(controlDatabase: app.db(.control))
                .withRepositories(actor: ActorContext(clubSlug: try Slug(slug))) {
                    try await $0.seasons.save(vigente)
                    try await $0.seasons.save(archivada)
                    try await $0.seasons.save(terminada)
                    try await $0.teams.save(a)
                    try await $0.teams.save(b)
                    try await $0.teams.save(c)
                    try await $0.playerProfiles.save(perfil)
                    try await $0.players.save(fila)
                    try await $0.opponentClubs.save(rivalClub)
                    try await $0.teams.save(rival)
                    // Los dos, inscritos en la vigente: el alta lo pide (R6.17).
                    for team in [a, b] {
                        try await $0.teamRegistrations.save(try TeamRegistration(
                            id: TeamRegistrationID(raw: UUID()), team: team, seasonID: vigente.id,
                            createdAt: now, updatedAt: now))
                    }
                }
            try await body(app, Seeded(cadeteA: a.id, cadeteB: b.id, rival: rival.id,
                                       vigente: vigente.id, archivada: archivada.id,
                                       terminada: terminada.id, deLaTerminada: fila.id, sinInscribir: c.id))
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    // ── Peticiones ──────────────────────────────────────────────────────────

    static func send(
        _ app: Application, _ method: HTTPMethod, _ path: String, json: String? = nil,
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

    static func newPlayerJSON(_ s: Seeded, team: TeamID? = nil, season: SeasonID? = nil,
                              name: String = "Juan García", year: Int = 2011,
                              shirt: Int? = nil, position: String? = nil) -> String {
        var fields = [
            #""teamId": "\#(team ?? s.cadeteA)""#, #""seasonId": "\#(season ?? s.vigente)""#,
            #""fullName": "\#(name)""#, #""birthYear": \#(year)"#,
        ]
        if let shirt { fields.append(#""shirtNumber": \#(shirt)"#) }
        if let position { fields.append(#""position": "\#(position)""#) }
        return "{" + fields.joined(separator: ", ") + "}"
    }

    static func player(_ response: TestingHTTPResponse) throws -> Components.Schemas.PlayerResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Components.Schemas.PlayerResponse.self,
                                  from: Data(response.body.readableBytesView))
    }

    static func roster(_ response: TestingHTTPResponse) throws -> [Components.Schemas.PlayerResponse] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Components.Schemas.PlayerResponse].self,
                                  from: Data(response.body.readableBytesView))
    }

    static func decodeProblem(_ response: TestingHTTPResponse) throws -> Components.Schemas.Problem {
        try JSONDecoder().decode(Components.Schemas.Problem.self, from: Data(response.body.readableBytesView))
    }

    /// Da de alta por HTTP y devuelve la respuesta, para los escenarios que la
    /// necesitan de partida.
    static func create(_ app: Application, _ json: String) async throws -> Components.Schemas.PlayerResponse {
        let box = Box()
        try await send(app, .POST, "/v1/players", json: json) { response in
            #expect(response.status == .created)
            box.value = try Self.player(response)
        }
        return try #require(box.value)
    }

    final class Box: @unchecked Sendable { var value: Components.Schemas.PlayerResponse? }

    struct FixedClock: Clock {
        let instant: Date
        func now() -> Date { instant }
    }

    // ── El alta ─────────────────────────────────────────────────────────────

    @Test("el alta de un jugador nuevo es 201, con cada campo de la respuesta (D-119, D-120)")
    func createNewPlayer() async throws {
        try await Self.withSeededClub { app, s in
            try await Self.send(app, .POST, "/v1/players",
                                json: Self.newPlayerJSON(s, name: " juan  garcía ", shirt: 9, position: "delantero")) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .created)
                let p = try Self.player(r)
                #expect(UUID(uuidString: p.id) != nil)
                #expect(UUID(uuidString: p.profileId) != nil)
                #expect(p.teamId == "\(s.cadeteA)")
                #expect(p.seasonId == "\(s.vigente)")
                #expect(p.fullName == "JUAN GARCÍA", "en mayúsculas y limpio (D-120)")
                #expect(p.birthYear == 2011)
                #expect(p.shirtNumber == 9)
                #expect(p.position?.value1 == .delantero)
                // Nulos mientras la plantilla no se ha sincronizado nunca (D-120);
                // sin foto en el alta.
                #expect(p.federated == nil)
                #expect(p.lastListedAt == nil)
                #expect(p.photoUrl == nil)
            }
        }
    }

    @Test("el alta con un perfil que ya existe es 201, con su nombre (D-120)")
    func createWithProfile() async throws {
        try await Self.withSeededClub { app, s in
            let juan = try await Self.create(app, Self.newPlayerJSON(s))
            try await Self.send(app, .DELETE, "/v1/players/\(juan.id)") { #expect($0.status == .noContent) }
            let json = #"{"teamId": "\#(s.cadeteB)", "seasonId": "\#(s.vigente)", "profileId": "\#(juan.profileId)", "shirtNumber": 4}"#
            try await Self.send(app, .POST, "/v1/players", json: json) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .created)
                let p = try Self.player(r)
                #expect(p.profileId == juan.profileId)
                #expect(p.fullName == "JUAN GARCÍA")
                #expect(p.teamId == "\(s.cadeteB)")
                #expect(p.position == nil)
            }
        }
    }

    @Test("las dos formas a la vez, o ninguna, es 400 (oneOf)")
    func bothFormsOrNone() async throws {
        try await Self.withSeededClub { app, s in
            let both = #"{"teamId": "\#(s.cadeteA)", "seasonId": "\#(s.vigente)", "profileId": "\#(UUID())", "fullName": "Juan García", "birthYear": 2011}"#
            try await Self.send(app, .POST, "/v1/players", json: both) { #expect($0.status == .badRequest) }
            let none = #"{"teamId": "\#(s.cadeteA)", "seasonId": "\#(s.vigente)"}"#
            try await Self.send(app, .POST, "/v1/players", json: none) { #expect($0.status == .badRequest) }
        }
    }

    @Test("los 409, cada uno con su código y nada más (D-118, D-121)")
    func conflicts() async throws {
        try await Self.withSeededClub { app, s in
            let juan = try await Self.create(app, Self.newPlayerJSON(s, shirt: 9))
            try await Self.send(app, .POST, "/v1/players",
                                json: Self.newPlayerJSON(s, name: "Pedro López", shirt: 9)) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .conflict)
                #expect(try Self.decodeProblem(r).code == .SHIRT_NUMBER_TAKEN)
            }
            let otherTeam = #"{"teamId": "\#(s.cadeteB)", "seasonId": "\#(s.vigente)", "profileId": "\#(juan.profileId)"}"#
            try await Self.send(app, .POST, "/v1/players", json: otherTeam) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .conflict)
                #expect(try Self.decodeProblem(r).code == .PLAYER_ALREADY_IN_ROSTER)
            }
        }
    }

    @Test("los 422 del alta, cada uno con su código (§5.1, R6.3, D-120)")
    func unprocessable() async throws {
        try await Self.withSeededClub { app, s in
            let cases: [(String, Components.Schemas.ProblemCode)] = [
                (Self.newPlayerJSON(s, team: TeamID(raw: UUID())), .REFERENCE_NOT_FOUND),
                (#"{"teamId": "\#(s.cadeteA)", "seasonId": "\#(s.vigente)", "profileId": "\#(UUID())"}"#,
                 .REFERENCE_NOT_FOUND),
                (Self.newPlayerJSON(s, team: s.rival), .TEAM_NOT_OWN),
                (Self.newPlayerJSON(s, season: s.archivada), .SEASON_ARCHIVED),
                (Self.newPlayerJSON(s, season: s.terminada), .SEASON_ENDED),
                (Self.newPlayerJSON(s, team: s.sinInscribir), .TEAM_NOT_REGISTERED),
                (Self.newPlayerJSON(s, name: "Juan"), .INVALID_VALUE),
                (Self.newPlayerJSON(s, year: 2999), .INVALID_VALUE),
            ]
            for (json, code) in cases {
                try await Self.send(app, .POST, "/v1/players", json: json) { (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .unprocessableEntity, "\(code)")
                    #expect(try Self.decodeProblem(r).code == code)
                }
            }
            // El `detail` del valor dice el campo, para pintarlo junto a él (R6.4).
            try await Self.send(app, .POST, "/v1/players", json: Self.newPlayerJSON(s, name: "Juan")) { (r: TestingHTTPResponse) async throws in
                #expect(try Self.decodeProblem(r).detail?.hasPrefix("fullName: ") == true)
            }
        }
    }

    /// Una temporada terminada se ve, pero no se cambia (R6.17): corregir, la baja y la foto, 422
    /// `SEASON_ENDED`; leer, sí.
    @Test("en una temporada terminada se lee, y corregir, la baja y quitar la foto son 422 SEASON_ENDED (R6.17)")
    func endedSeasonIsReadOnly() async throws {
        try await Self.withSeededClub { app, s in
            let id = s.deLaTerminada
            try await Self.send(app, .GET, "/v1/players/\(id)") { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .ok)
            }
            let writes: [(HTTPMethod, String, String?)] = [
                (.PUT, "/v1/players/\(id)", #"{"fullName": "Luis Pasado"}"#),
                (.DELETE, "/v1/players/\(id)", nil),
                (.DELETE, "/v1/players/\(id)/photo", nil),
            ]
            for (method, path, json) in writes {
                try await Self.send(app, method, path, json: json) { (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .unprocessableEntity, "\(method) \(path)")
                    #expect(try Self.decodeProblem(r).code == .SEASON_ENDED)
                }
            }
        }
    }

    // ── La lista y la ficha ─────────────────────────────────────────────────

    @Test("la plantilla va por dorsal y luego por nombre, y filtra por demarcación (D-118)")
    func listing() async throws {
        try await Self.withSeededClub { app, s in
            _ = try await Self.create(app, Self.newPlayerJSON(s, name: "Zoe Ruiz", position: "portero"))
            _ = try await Self.create(app, Self.newPlayerJSON(s, name: "Luis Pérez", shirt: 10))
            _ = try await Self.create(app, Self.newPlayerJSON(s, name: "Marta Sanz", shirt: 2))
            try await Self.send(app, .GET, "/v1/players?teamId=\(s.cadeteA)&seasonId=\(s.vigente)") { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .ok)
                #expect(try Self.roster(r).map(\.fullName) == ["MARTA SANZ", "LUIS PÉREZ", "ZOE RUIZ"])
            }
            try await Self.send(app, .GET,
                                "/v1/players?teamId=\(s.cadeteA)&seasonId=\(s.vigente)&position=portero") { (r: TestingHTTPResponse) async throws in
                #expect(try Self.roster(r).map(\.fullName) == ["ZOE RUIZ"])
            }
        }
    }

    @Test("la plantilla de un rival es vacía; la de un equipo que no existe, 404 (§5.1)")
    func listingErrors() async throws {
        try await Self.withSeededClub { app, s in
            try await Self.send(app, .GET, "/v1/players?teamId=\(s.rival)&seasonId=\(s.vigente)") { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .ok)
                #expect(try Self.roster(r).isEmpty)
            }
            try await Self.send(app, .GET, "/v1/players?teamId=\(UUID())&seasonId=\(s.vigente)") { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .notFound)
                #expect(try Self.decodeProblem(r).code == .TEAM_NOT_FOUND)
            }
            try await Self.send(app, .GET, "/v1/players?teamId=nope&seasonId=\(s.vigente)") { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .badRequest)
                #expect(try Self.decodeProblem(r).code == .INVALID_UUID)
            }
        }
    }

    @Test("la ficha de un jugador, y 404 si no existe (R6.6)")
    func gettingOne() async throws {
        try await Self.withSeededClub { app, s in
            let juan = try await Self.create(app, Self.newPlayerJSON(s, shirt: 9))
            try await Self.send(app, .GET, "/v1/players/\(juan.id)") { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .ok)
                #expect(try Self.player(r).id == juan.id)
                #expect(try Self.player(r).shirtNumber == 9)
            }
            try await Self.send(app, .GET, "/v1/players/\(UUID())") { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .notFound)
                #expect(try Self.decodeProblem(r).code == .PLAYER_NOT_FOUND)
            }
        }
    }

    // ── Corregir y la baja ──────────────────────────────────────────────────

    @Test("corregir manda la ficha entera, y lo vacío queda vacío (PUT, R6.6)")
    func correcting() async throws {
        try await Self.withSeededClub { app, s in
            let juan = try await Self.create(app, Self.newPlayerJSON(s, shirt: 9, position: "delantero"))
            let json = #"{"fullName": "Juan García Fuente", "birthYear": 2011, "shirtNumber": null, "position": null}"#
            try await Self.send(app, .PUT, "/v1/players/\(juan.id)", json: json) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .ok)
                let p = try Self.player(r)
                #expect(p.fullName == "JUAN GARCÍA FUENTE")
                #expect(p.birthYear == 2011)
                #expect(p.shirtNumber == nil)
                #expect(p.position == nil)
            }
            // Lo que no llega, también cuenta como vacío: con la ficha entera no
            // hay «no lo cambio» (R6.6).
            try await Self.send(app, .PUT, "/v1/players/\(juan.id)",
                                json: #"{"fullName": "Juan García", "birthYear": 2011, "shirtNumber": 5}"#) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .ok)
                #expect(try Self.player(r).shirtNumber == 5)
            }
            // Sin el nombre, 400: es el único que tiene que llegar.
            try await Self.send(app, .PUT, "/v1/players/\(juan.id)", json: #"{"birthYear": 2010}"#) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .badRequest)
            }
            // Quitar o cambiar el año, que el perfil tenía: 422, con el campo (R6.17).
            for year in ["null", "2010"] {
                try await Self.send(app, .PUT, "/v1/players/\(juan.id)",
                                    json: #"{"fullName": "Juan García", "birthYear": \#(year)}"#) { (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .unprocessableEntity)
                    let problem = try Self.decodeProblem(r)
                    #expect(problem.code == .INVALID_VALUE)
                    #expect(problem.detail?.hasPrefix("birthYear: ya está puesto") == true)
                }
            }
        }
    }

    @Test("corregir con el dorsal de otro, 409 (D-118)")
    func correctingConflict() async throws {
        try await Self.withSeededClub { app, s in
            _ = try await Self.create(app, Self.newPlayerJSON(s, name: "Pedro López", shirt: 7))
            let juan = try await Self.create(app, Self.newPlayerJSON(s, shirt: 9))
            try await Self.send(app, .PUT, "/v1/players/\(juan.id)",
                                json: #"{"fullName": "Juan García", "birthYear": 2011, "shirtNumber": 7}"#) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .conflict)
                #expect(try Self.decodeProblem(r).code == .SHIRT_NUMBER_TAKEN)
            }
        }
    }

    @Test("la baja es 204, y después el jugador ya no se encuentra (D-36)")
    func deleting() async throws {
        try await Self.withSeededClub { app, s in
            let juan = try await Self.create(app, Self.newPlayerJSON(s, shirt: 9))
            try await Self.send(app, .DELETE, "/v1/players/\(juan.id)") { #expect($0.status == .noContent) }
            try await Self.send(app, .GET, "/v1/players/\(juan.id)") { #expect($0.status == .notFound) }
            try await Self.send(app, .DELETE, "/v1/players/\(juan.id)") { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .notFound)
                #expect(try Self.decodeProblem(r).code == .PLAYER_NOT_FOUND)
            }
            // Y su dorsal queda libre.
            _ = try await Self.create(app, Self.newPlayerJSON(s, name: "Pedro López", shirt: 9))
        }
    }
}

// ── El buscador del alta (R6.7) ──────────────────────────────────────────────

extension PlayerEndpointTests {
    static func profiles(_ response: TestingHTTPResponse) throws
        -> [Components.Schemas.PlayerProfileSearchResult]
    {
        try JSONDecoder().decode([Components.Schemas.PlayerProfileSearchResult].self,
                                 from: Data(response.body.readableBytesView))
    }

    @Test("el buscador trae el perfil entero, su última plantilla y el otro equipo (D-120, D-121, D-122)")
    func searching() async throws {
        try await Self.withSeededClub { app, s in
            // Juan, en el Cadete B esta temporada: sale marcado para el Cadete A.
            let juan = try await Self.create(
                app, Self.newPlayerJSON(s, team: s.cadeteB, name: "Juan García", shirt: 7, position: "defensa"))
            try await Self.send(app, .GET,
                                "/v1/player-profiles?q=juan%20gar&teamId=\(s.cadeteA)&seasonId=\(s.vigente)") {
                (r: TestingHTTPResponse) async throws in
                #expect(r.status == .ok)
                let found = try Self.profiles(r)
                #expect(found.count == 1)
                let p = try #require(found.first)
                #expect(p.profileId == juan.profileId)
                #expect(p.fullName == "JUAN GARCÍA")
                #expect(p.birthYear == 2011)
                #expect(p.lastShirtNumber == 7)
                #expect(p.lastPosition?.value1 == .defensa)
                #expect(p.lastPhotoUrl == nil, "la foto llega con el almacén (R6.9)")
                let roster = try #require(p.lastRoster?.value1)
                #expect(roster.team.teamId == "\(s.cadeteB)")
                #expect(roster.seasonId == "\(s.vigente)")
                #expect(roster.seasonLabel == "2025/26")
                #expect(p.otherTeamThisSeason?.value1?.teamId == "\(s.cadeteB)")
            }
            // Para su propio equipo no sale: ya está en esa plantilla.
            try await Self.send(app, .GET,
                                "/v1/player-profiles?q=juan&teamId=\(s.cadeteB)&seasonId=\(s.vigente)") {
                (r: TestingHTTPResponse) async throws in
                #expect(r.status == .ok)
                #expect(try Self.profiles(r).isEmpty)
            }
        }
    }

    @Test("con menos de tres letras, 400; con un equipo que no existe, 404 (D-120)")
    func searchingErrors() async throws {
        try await Self.withSeededClub { app, s in
            try await Self.send(app, .GET,
                                "/v1/player-profiles?q=ju&teamId=\(s.cadeteA)&seasonId=\(s.vigente)") {
                (r: TestingHTTPResponse) async throws in
                #expect(r.status == .badRequest)
                #expect(try Self.decodeProblem(r).code == .BAD_REQUEST)
            }
            try await Self.send(app, .GET,
                                "/v1/player-profiles?q=juan&teamId=\(UUID())&seasonId=\(s.vigente)") {
                (r: TestingHTTPResponse) async throws in
                #expect(r.status == .notFound)
                #expect(try Self.decodeProblem(r).code == .TEAM_NOT_FOUND)
            }
        }
    }
}

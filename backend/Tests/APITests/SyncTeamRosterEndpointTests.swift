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

/// Nivel 4 (§8.1): sincronizar la plantilla con la federación, por HTTP ([D-120], R6.14). Los casos de cada jugador
/// están en el nivel 2 (`SyncTeamRosterTests`); aquí, **el borde**: la ruta, el resumen campo a campo, lo que queda
/// escrito en Postgres (la plantilla con «federado» y la inscripción con la fecha) y cada error con su estado y su
/// código.
@Suite("SyncTeamRoster · D-120 · sincronizar la plantilla, por HTTP",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct SyncTeamRosterEndpointTests {

    static let prefix = "e2e_"
    static let slug = "rostersyncclub"
    /// 2026-11-17: dentro de la temporada 2026/27.
    static let now = Date(timeIntervalSince1970: 1_794_900_000)

    /// La federación de mentira: publica lo que se le dé, o falla.
    struct RosterClient: FederationClient {
        var published: [String] = []
        var failure: FederationError?

        func fetchTeamRoster(federationTeamID: String) async throws -> FederationTeamRoster {
            if let failure { throw failure }
            return FederationTeamRoster(players: published.map {
                let halves = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                return FederationRosterPlayer(publishedName: $0,
                                              fullName: halves.count == 2 ? "\(halves[1]) \(halves[0])" : nil)
            })
        }
        func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
            throw Unused(operation: "fetchCalendar")
        }
        func fetchStandings(_ coordinate: FederationCoordinate, round: Int) async throws -> FederationStanding {
            throw Unused(operation: "fetchStandings")
        }
        func fetchScorers(_ coordinate: FederationCoordinate) async throws -> FederationScorerTable {
            throw Unused(operation: "fetchScorers")
        }
        func coordinate(fromCalendarURL url: String) throws -> FederationCoordinate {
            throw Unused(operation: "coordinate")
        }
    }

    struct FixedClock: Clock {
        let instant: Date
        func now() -> Date { instant }
    }

    /// Lo que la sincronización no pide: si se llamara, la prueba fallaría por otro motivo.
    struct Unused: Error { let operation: String }

    struct Provider: FederationClientProvider {
        let client: RosterClient
        func client(for code: FederationCode) -> (any FederationClient)? { code == .rffm ? client : nil }
    }

    struct Seeded: Sendable {
        let cadeteA: TeamID
        let cadeteB: TeamID
        let sinEnganchar: TeamID
        let vigente: SeasonID
        let anterior: SeasonID
        /// Juan García, del club, en el Cadete A con el 7.
        let juan: PlayerID
    }

    static func actor() -> ActorContext { ActorContext(clubSlug: try! Slug(slug)) }

    /// El club con el Cadete A inscrito en la en curso (código «821») y en la anterior; el Cadete B, en la en
    /// curso; y otro equipo inscrito sin enganchar. En el Cadete A, Juan García; en el club, el perfil de
    /// Marcos Díaz, que guarda el 9 y es defensa.
    static func withSeededClub(
        federation: FederationCode = .rffm, client: RosterClient = RosterClient(),
        names: (any NameDictionarySource)? = nil,
        _ body: @escaping @Sendable (Application, Seeded) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp(federationClients: Provider(client: client), clock: FixedClock(instant: now),
                                          names: names) { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(slug, federation: federation, schemaPrefix: prefix, on: app)
            func season(_ label: String) throws -> Season {
                try Season(id: SeasonID(raw: UUID()), label: try SeasonLabel(label), federationSeasonID: nil,
                           createdAt: now, updatedAt: now)
            }
            func own(_ letter: String) throws -> Team {
                try Team(id: TeamID(raw: UUID()), category: .cadete, letter: letter, gender: .masculino,
                         modality: .futbol11, createdAt: now, updatedAt: now)
            }
            let (vigente, anterior) = (try season("2026/27"), try season("2025/26"))
            let (a, b, c) = (try own("A"), try own("B"), try own("C"))
            let competition = try Competition(
                id: CompetitionID(raw: UUID()), seasonID: vigente.id, modality: .futbol11, gender: .masculino,
                federationCompetitionID: "1", federationGroupID: "2", ageCategory: .cadete,
                divisionLabel: "PREFERENTE CADETE", groupLabel: "Grupo 2", createdAt: now, updatedAt: now)
            let previous = try Competition(
                id: CompetitionID(raw: UUID()), seasonID: anterior.id, modality: .futbol11, gender: .masculino,
                federationCompetitionID: "3", federationGroupID: "4", ageCategory: .cadete,
                divisionLabel: "PREFERENTE CADETE", groupLabel: "Grupo 2", createdAt: now, updatedAt: now)
            let juanProfile = PlayerProfile(id: PlayerProfileID(raw: UUID()), fullName: try PlayerName("Juan García"),
                                            birthYear: try BirthYear(2011, notAfter: 2026), createdAt: now, updatedAt: now)
            let marcos = PlayerProfile(id: PlayerProfileID(raw: UUID()), fullName: try PlayerName("Marcos Díaz"),
                                       birthYear: try BirthYear(2011, notAfter: 2026),
                                       lastShirtNumber: try ShirtNumber(9), lastPosition: .defensa,
                                       createdAt: now, updatedAt: now)
            let juan = Player(id: PlayerID(raw: UUID()), profileID: juanProfile.id, teamID: a.id, seasonID: vigente.id,
                              shirtNumber: try ShirtNumber(7), createdAt: now, updatedAt: now)
            try await FluentTenantUnitOfWork(controlDatabase: app.db(.control)).withRepositories(actor: actor()) { r in
                for s in [vigente, anterior] { try await r.seasons.save(s) }
                for t in [a, b, c] { try await r.teams.save(t) }
                try await r.competitions.save(competition)
                try await r.competitions.save(previous)
                for (team, season, comp, code) in [(a, vigente, competition, "821"), (a, anterior, previous, "821"),
                                                    (b, vigente, competition, "822")] {
                    try await r.teamRegistrations.save(try TeamRegistration(
                        id: TeamRegistrationID(raw: UUID()), team: team, seasonID: season.id,
                        competitionID: comp.id, federationTeamID: code, createdAt: now, updatedAt: now))
                }
                try await r.teamRegistrations.save(try TeamRegistration(
                    id: TeamRegistrationID(raw: UUID()), team: c, seasonID: vigente.id, createdAt: now, updatedAt: now))
                try await r.playerProfiles.save(juanProfile)
                try await r.playerProfiles.save(marcos)
                try await r.players.save(juan)
            }
            try await body(app, Seeded(cadeteA: a.id, cadeteB: b.id, sinEnganchar: c.id, vigente: vigente.id,
                                       anterior: anterior.id, juan: juan.id))
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func sync(_ app: Application, team: TeamID, season: SeasonID,
                     _ check: @escaping @Sendable (TestingHTTPResponse) async throws -> Void) async throws {
        try await app.testing().test(
            .POST, "/v1/teams/\(team)/registrations/\(season)/roster-sync",
            beforeRequest: { $0.headers.add(name: "X-Club", value: slug) }, afterResponse: check)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ response: TestingHTTPResponse) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(response.body.readableBytesView))
    }

    @Test("200 con el resumen; la plantilla queda con federado y la inscripción con la fecha")
    func syncs() async throws {
        let client = RosterClient(published: ["DÍAZ, MARCOS", "RUIZ, ANA", "GARCIA, PEPE 1"])
        try await Self.withSeededClub(client: client) { app, s in
            try await Self.sync(app, team: s.cadeteA, season: s.vigente) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .ok)
                let summary = try Self.decode(Components.Schemas.RosterSyncResponse.self, r)
                #expect(summary.syncedAt == Self.now)
                #expect(summary.added == 2)
                #expect(summary.alreadyInRoster == 0)
                #expect(summary.withoutBirthYear == 1, "Ana es nueva; Marcos trae el año de su perfil")
                #expect(summary.deletedInClub == 0)
                #expect(summary.duplicateName.isEmpty)
                #expect(summary.inOtherTeam.isEmpty)
                #expect(summary.invalidName == ["GARCIA, PEPE 1"])
                // El diccionario del repositorio, sin líneas malas (R6.19).
                #expect(summary.namesDictionary.found)
                #expect(summary.namesDictionary.skippedLines.isEmpty)
            }
            try await app.testing().test(
                .GET, "/v1/players?teamId=\(s.cadeteA)&seasonId=\(s.vigente)",
                beforeRequest: { $0.headers.add(name: "X-Club", value: Self.slug) }
            ) { (r: TestingHTTPResponse) async throws in
                let roster = try Self.decode([Components.Schemas.PlayerResponse].self, r)
                let byName = Dictionary(uniqueKeysWithValues: roster.map { ($0.fullName, $0) })
                #expect(byName["JUAN GARCÍA"]?.federated == false, "en la plantilla y no en la federación")
                #expect(byName["JUAN GARCÍA"]?.lastListedAt == nil)
                #expect(byName["MARCOS DÍAZ"]?.federated == true && byName["MARCOS DÍAZ"]?.lastListedAt == Self.now)
                #expect(byName["MARCOS DÍAZ"]?.shirtNumber == 9, "de su perfil (D-122)")
                #expect(byName["MARCOS DÍAZ"]?.position?.value1 == .defensa)
                #expect(byName["ANA RUIZ"]?.birthYear == nil && byName["ANA RUIZ"]?.federated == true)
            }
            try await app.testing().test(
                .GET, "/v1/teams/\(s.cadeteA)/registrations/\(s.vigente)",
                beforeRequest: { $0.headers.add(name: "X-Club", value: Self.slug) }
            ) { (r: TestingHTTPResponse) async throws in
                #expect(try Self.decode(Components.Schemas.TeamRegistrationResponse.self, r).rosterSyncedAt == Self.now)
            }
        }
    }

    /// Una línea mala del diccionario se salta, y el resumen la da con su motivo (decisión 2 de R6.19).
    @Test("el resumen dice las líneas del diccionario que no se han usado, con su motivo")
    func reportsSkippedDictionaryLines() async throws {
        let client = RosterClient(published: ["RUIZ, ANA"])
        let names = FixedNameDictionary(CastilianNames(text: "DÍAZ\nRUIZ\nDÍAZ"))
        try await Self.withSeededClub(client: client, names: names) { app, s in
            try await Self.sync(app, team: s.cadeteA, season: s.vigente) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .ok)
                let report = try Self.decode(Components.Schemas.RosterSyncResponse.self, r).namesDictionary
                #expect(report.found)
                #expect(report.skippedLines.map(\.line) == [2, 3])
                #expect(report.skippedLines.map(\.reason) == [.noMark, .repeated])
                #expect(report.skippedLines.map(\.repeatedLine) == [nil, 1])
            }
        }
    }

    @Test("sin el fichero del diccionario, sincroniza igual y el resumen dice que no se encontró")
    func reportsMissingDictionary() async throws {
        let client = RosterClient(published: ["RUIZ, ANA"])
        try await Self.withSeededClub(client: client, names: FixedNameDictionary(nil)) { app, s in
            try await Self.sync(app, team: s.cadeteA, season: s.vigente) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .ok)
                let summary = try Self.decode(Components.Schemas.RosterSyncResponse.self, r)
                #expect(summary.added == 1)
                #expect(!summary.namesDictionary.found)
                #expect(summary.namesDictionary.skippedLines.isEmpty)
            }
        }
    }

    @Test("el de otro equipo de la temporada sale en el resumen con su equipo, y no se añade")
    func inOtherTeam() async throws {
        let client = RosterClient(published: ["GARCÍA, JUAN"])
        try await Self.withSeededClub(client: client) { app, s in
            try await Self.sync(app, team: s.cadeteB, season: s.vigente) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .ok)
                let summary = try Self.decode(Components.Schemas.RosterSyncResponse.self, r)
                let elsewhere = try #require(summary.inOtherTeam.first)
                #expect(elsewhere.fullName == "JUAN GARCÍA")
                #expect(elsewhere.team.teamId == "\(s.cadeteA)")
                #expect(elsewhere.team.displayName.hasSuffix("Cadete A"))
                #expect(summary.added == 0)
            }
        }
    }

    @Test("el que casa con varios perfiles sale en el resumen con su fila nueva, para revisarlo")
    func duplicateName() async throws {
        let client = RosterClient(published: ["LÓPEZ, PEDRO"])
        try await Self.withSeededClub(client: client) { app, s in
            try await FluentTenantUnitOfWork(controlDatabase: app.db(.control)).withRepositories(actor: Self.actor()) { r in
                for year in [2011, 2012] {
                    try await r.playerProfiles.save(PlayerProfile(
                        id: PlayerProfileID(raw: UUID()), fullName: try PlayerName("Pedro López"),
                        birthYear: try BirthYear(year, notAfter: 2026), createdAt: Self.now, updatedAt: Self.now))
                }
            }
            try await Self.sync(app, team: s.cadeteA, season: s.vigente) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .ok)
                let summary = try Self.decode(Components.Schemas.RosterSyncResponse.self, r)
                let duplicate = try #require(summary.duplicateName.first)
                #expect(duplicate.fullName == "PEDRO LÓPEZ")
                #expect(summary.added == 1 && summary.withoutBirthYear == 1)
                // El que da el resumen es la fila nueva de la plantilla.
                let rows = try await FluentTenantUnitOfWork(controlDatabase: app.db(.control))
                    .withRepositories(actor: Self.actor()) {
                        try await $0.players.list(teamID: s.cadeteA, seasonID: s.vigente)
                    }
                #expect(rows.count == 2 && rows.contains { "\($0.id)" == duplicate.playerId && $0.id != s.juan })
            }
        }
    }

    @Test("los 422, cada uno con su código: temporada que no es la en curso, sin enganchar, y federación sin plantillas")
    func unprocessable() async throws {
        try await Self.withSeededClub { app, s in
            try await Self.sync(app, team: s.cadeteA, season: s.anterior) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .unprocessableEntity)
                #expect(try Self.decode(Components.Schemas.Problem.self, r).code == .SEASON_NOT_CURRENT)
            }
            try await Self.sync(app, team: s.sinEnganchar, season: s.vigente) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .unprocessableEntity)
                #expect(try Self.decode(Components.Schemas.Problem.self, r).code == .TEAM_NOT_LINKED)
            }
        }
        try await Self.withSeededClub(federation: .fcf) { app, s in
            try await Self.sync(app, team: s.cadeteA, season: s.vigente) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .unprocessableEntity)
                #expect(try Self.decode(Components.Schemas.Problem.self, r).code == .FEDERATION_ROSTER_UNAVAILABLE)
            }
        }
    }

    @Test("un equipo que no está inscrito en la temporada, 404 TEAM_NOT_REGISTERED; uno que no existe, TEAM_NOT_FOUND")
    func notFound() async throws {
        try await Self.withSeededClub { app, s in
            try await Self.sync(app, team: s.cadeteB, season: s.anterior) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .notFound)
                #expect(try Self.decode(Components.Schemas.Problem.self, r).code == .TEAM_NOT_REGISTERED)
            }
            try await Self.sync(app, team: TeamID(raw: UUID()), season: s.vigente) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .notFound)
                #expect(try Self.decode(Components.Schemas.Problem.self, r).code == .TEAM_NOT_FOUND)
            }
        }
    }

    @Test("si la federación no responde, el error de la federación, y la plantilla no cambia")
    func federationFails() async throws {
        let client = RosterClient(failure: .transportFailure(url: "https://www.rffm.es/fichaequipo/821", reason: "caída"))
        try await Self.withSeededClub(client: client) { app, s in
            try await Self.sync(app, team: s.cadeteA, season: s.vigente) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .badGateway || r.status == .gatewayTimeout)
                #expect(try Self.decode(Components.Schemas.Problem.self, r).code == .FEDERATION_UNREACHABLE)
            }
            let (rows, registration) = try await FluentTenantUnitOfWork(controlDatabase: app.db(.control))
                .withRepositories(actor: Self.actor()) { r in
                    (try await r.players.list(teamID: s.cadeteA, seasonID: s.vigente),
                     try await r.teamRegistrations.list(teamID: s.cadeteA, seasonID: s.vigente))
                }
            #expect(rows.count == 1 && rows.first?.federated == nil)
            #expect(registration.allSatisfy { $0.rosterSyncedAt == nil })
        }
    }

    @Test("un código mal formado en la dirección es 400")
    func badUUID() async throws {
        try await Self.withSeededClub { app, s in
            try await app.testing().test(
                .POST, "/v1/teams/no-es-un-uuid/registrations/\(s.vigente)/roster-sync",
                beforeRequest: { $0.headers.add(name: "X-Club", value: Self.slug) }
            ) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .badRequest)
            }
        }
    }
}

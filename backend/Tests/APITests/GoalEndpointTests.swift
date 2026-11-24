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
@testable import Tenancy

/// Nivel 4 (§8.1): las cinco operaciones de los goles (R7.7). Los casos de uso están
/// probados en el nivel 2; aquí, **el borde**: cada ruta, cada campo de la respuesta
/// y cada error con su estado y su código. El club es el de `AppearanceEndpointTests`,
/// en su propio *schema*.
@Suite("Goals · §5.1 · apuntar, corregir y borrar un gol, por HTTP",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct GoalEndpointTests {
    typealias A = AppearanceEndpointTests
    static let slug = "golesclub"
    static var schema: String { "\(A.prefix)\(slug)" }

    static func send(
        _ app: Application, _ method: HTTPMethod, _ path: String, json: String? = nil,
        _ check: @escaping @Sendable (TestingHTTPResponse) async throws -> Void
    ) async throws {
        try await A.send(app, method, path, json: json, slug: slug, check)
    }

    static func goalJSON(_ s: A.Seeded, match: MatchID? = nil, team: TeamID? = nil, extra: String = "") -> String {
        let base = #""matchId": "\#(match ?? s.played)", "scoringTeamId": "\#(team ?? s.cadeteA)""#
        return "{" + base + (extra.isEmpty ? "" : ", \(extra)") + "}"
    }

    static func create(_ app: Application, _ json: String) async throws -> String {
        let box = A.Box()
        try await send(app, .POST, "/v1/goals", json: json) { (response: TestingHTTPResponse) async throws in
            #expect(response.status == .created)
            box.id = try A.decode(Components.Schemas.GoalResponse.self, response).id
        }
        return box.id
    }

    /// Lo que hace la carga del acta, por SQL: el acta cargada, o un gol suyo.
    static func loadReport(_ app: Application, _ match: MatchID) async throws {
        try await (app.db(.control) as! any SQLDatabase).raw("""
            UPDATE \(ident: schema).matches SET report_loaded_at = now(), report_lineup = '{"players":[]}'::jsonb
            WHERE id = \(bind: match.raw)
            """).run()
    }

    static func markFromReport(_ app: Application, _ goal: String) async throws {
        try await (app.db(.control) as! any SQLDatabase).raw("""
            UPDATE \(ident: schema).goals SET from_report = true WHERE id = \(bind: UUID(uuidString: goal)!)
            """).run()
    }

    // ── Apuntar ─────────────────────────────────────────────────────────────

    @Test("createGoal responde 201 con cada campo del gol, y el que encaja lo pone el servidor")
    func createReturnsEveryField() async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            let extra = #""scorerPlayerId": "\#(s.juan)", "assistPlayerId": "\#(s.pedro)", "assisted": true, "#
                + #""minute": 33, "zone": "area_chica", "attackSide": "izquierda", "shotSide": "centro", "#
                + #""bodyPart": "pie_izquierdo", "playType": "tras_corner", "comment": "a la escuadra""#
            try await Self.send(app, .POST, "/v1/goals", json: Self.goalJSON(s, extra: extra)) {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .created)
                let goal = try A.decode(Components.Schemas.GoalResponse.self, response)
                #expect(goal.matchId == "\(s.played)")
                #expect(goal.scoringTeamId == "\(s.cadeteA)")
                #expect(goal.concedingTeamId == "\(s.rival)")
                #expect(goal.scorerPlayerId == "\(s.juan)")
                #expect(goal.assistPlayerId == "\(s.pedro)")
                #expect(goal.assisted)
                #expect(goal.minute == 33)
                #expect(goal.zone == .area_chica)
                #expect(goal.attackSide == .izquierda)
                #expect(goal.shotSide == .centro)
                #expect(goal.bodyPart == .pie_izquierdo)
                #expect(goal.playType == .tras_corner)
                #expect(goal.comment == "a la escuadra")
                #expect(goal.fromReport == false)
            }
        }
    }

    @Test("lo que el cuerpo no cumple es 422, con su código", arguments: [
        ("antes de la hora", "MATCH_NOT_STARTED"),
        ("otro equipo", "TEAM_NOT_IN_MATCH"),
        ("penalti fuera", "INVALID_VALUE"),
        ("otra temporada", "PLAYER_NOT_IN_SEASON"),
        ("acta cargada", "MATCH_REPORT_LOADED"),
    ])
    func createRejections(_ case: String, _ code: String) async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            let json: String
            switch `case` {
            case "antes de la hora": json = Self.goalJSON(s, match: s.future)
            case "otro equipo": json = Self.goalJSON(s, team: s.cadeteB)
            case "penalti fuera": json = Self.goalJSON(s, extra: #""playType": "penalti", "zone": "fuera_area""#)
            case "otra temporada": json = Self.goalJSON(s, extra: #""scorerPlayerId": "\#(s.deOtraTemporada)""#)
            default:
                try await Self.loadReport(app, s.played)
                json = Self.goalJSON(s)
            }
            try await Self.send(app, .POST, "/v1/goals", json: json) { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .unprocessableEntity)
                #expect(try A.code(response) == code)
            }
        }
    }

    // ── Leer ────────────────────────────────────────────────────────────────

    @Test("listGoals trae una página de los goles del partido, por minuto")
    func listByMatch() async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            let late = try await Self.create(app, Self.goalJSON(s, extra: #""minute": 80"#))
            let early = try await Self.create(app, Self.goalJSON(s, team: s.rival, extra: #""minute": 5"#))
            try await Self.send(app, .GET, "/v1/goals?matchId=\(s.played)&perPage=10") {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .ok)
                let page = try A.decode(Components.Schemas.Page.self, response)
                #expect(page.page == 1 && page.perPage == 10 && page.total == 2)
                struct Data: Decodable { let data: [Components.Schemas.GoalResponse] }
                #expect(try A.decode(Data.self, response).data.map(\.id) == [early, late])
            }
        }
    }

    @Test("sin ámbito es 400 MISSING_SCOPE; el partido que no existe, 404 MATCH_NOT_FOUND")
    func listScope() async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            try await Self.send(app, .GET, "/v1/goals?seasonId=\(UUID())") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .badRequest)
                #expect(try A.code(response) == "MISSING_SCOPE")
            }
            try await Self.send(app, .GET, "/v1/goals?matchId=\(UUID())") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .notFound)
                #expect(try A.code(response) == "MATCH_NOT_FOUND")
            }
        }
    }

    @Test("getGoal devuelve el gol; el que no existe es 404 GOAL_NOT_FOUND")
    func getOne() async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            let id = try await Self.create(app, Self.goalJSON(s, extra: #""minute": 12"#))
            try await Self.send(app, .GET, "/v1/goals/\(id)") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .ok)
                #expect(try A.decode(Components.Schemas.GoalResponse.self, response).minute == 12)
            }
            for path in ["/v1/goals/\(UUID())", "/v1/goals/nada"] {
                try await Self.send(app, .GET, path) { (response: TestingHTTPResponse) async throws in
                    #expect(response.status == .notFound)
                    #expect(try A.code(response) == "GOAL_NOT_FOUND")
                }
            }
        }
    }

    // ── Corregir y borrar ───────────────────────────────────────────────────

    @Test("updateGoal completa el desglose y deja lo demás como estaba")
    func updateCompletes() async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            let id = try await Self.create(app, Self.goalJSON(s, extra: #""scorerPlayerId": "\#(s.juan)", "minute": 10"#))
            try await Self.send(app, .PATCH, "/v1/goals/\(id)", json: #"{"playType": "falta_directa"}"#) {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .ok)
                let goal = try A.decode(Components.Schemas.GoalResponse.self, response)
                #expect(goal.playType == .falta_directa)
                #expect(goal.minute == 10)
                #expect(goal.scorerPlayerId == "\(s.juan)")
            }
            try await Self.send(app, .PATCH, "/v1/goals/\(id)", json: "{}") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .badRequest)
                #expect(try A.code(response) == "EMPTY_PATCH")
            }
        }
    }

    @Test("en un gol del acta, cambiar el goleador o borrarlo es 422 LOCKED_BY_MATCH_REPORT (D-137)")
    func reportGoalIsLocked() async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            let id = try await Self.create(app, Self.goalJSON(s, extra: #""scorerPlayerId": "\#(s.juan)""#))
            try await Self.markFromReport(app, id)
            try await Self.send(app, .PATCH, "/v1/goals/\(id)", json: #"{"scorerPlayerId": "\#(s.pedro)"}"#) {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .unprocessableEntity)
                #expect(try A.code(response) == "LOCKED_BY_MATCH_REPORT")
            }
            try await Self.send(app, .DELETE, "/v1/goals/\(id)") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .unprocessableEntity)
                #expect(try A.code(response) == "LOCKED_BY_MATCH_REPORT")
            }
        }
    }

    @Test("deleteGoal responde 204 a un gol del club, y luego es 404")
    func deleteThenNotFound() async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            let id = try await Self.create(app, Self.goalJSON(s))
            try await Self.send(app, .DELETE, "/v1/goals/\(id)") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .noContent)
            }
            try await Self.send(app, .DELETE, "/v1/goals/\(id)") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .notFound)
                #expect(try A.code(response) == "GOAL_NOT_FOUND")
            }
        }
    }
}

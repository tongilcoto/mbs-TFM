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

/// Nivel 4 (§8.1): las cinco operaciones de las tarjetas (R7.8). Los casos de uso
/// están probados en el nivel 2; aquí, **el borde**, contra Postgres: cada ruta, cada
/// campo de la respuesta, el orden por minuto y cada error con su estado y su
/// código. El club es el de `AppearanceEndpointTests`, en su propio *schema*.
@Suite("Cards · §5.1 · apuntar, corregir y borrar una tarjeta, por HTTP",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct CardEndpointTests {
    typealias A = AppearanceEndpointTests
    static let slug = "tarjetasclub"
    static var schema: String { "\(A.prefix)\(slug)" }

    static func send(
        _ app: Application, _ method: HTTPMethod, _ path: String, json: String? = nil,
        _ check: @escaping @Sendable (TestingHTTPResponse) async throws -> Void
    ) async throws {
        try await A.send(app, method, path, json: json, slug: slug, check)
    }

    static func cardJSON(_ s: A.Seeded, player: PlayerID? = nil, match: MatchID? = nil, team: TeamID? = nil,
                         type: String = "amarilla", extra: String = "") -> String {
        let base = #""playerId": "\#(player ?? s.juan)", "matchId": "\#(match ?? s.played)", "#
            + #""teamId": "\#(team ?? s.cadeteA)", "type": "\#(type)""#
        return "{" + base + (extra.isEmpty ? "" : ", \(extra)") + "}"
    }

    static func create(_ app: Application, _ json: String) async throws -> String {
        let box = A.Box()
        try await send(app, .POST, "/v1/cards", json: json) { (response: TestingHTTPResponse) async throws in
            #expect(response.status == .created)
            box.id = try A.decode(Components.Schemas.CardResponse.self, response).id
        }
        return box.id
    }

    @Test("createCard responde 201 con cada campo de la tarjeta")
    func createReturnsEveryField() async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            try await Self.send(app, .POST, "/v1/cards", json: Self.cardJSON(
                s, type: "roja", extra: #""isSecondYellow": true, "minute": 70, "comment": "dos amarillas""#)) {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .created)
                let card = try A.decode(Components.Schemas.CardResponse.self, response)
                #expect(card.playerId == "\(s.juan)")
                #expect(card.matchId == "\(s.played)")
                #expect(card.teamId == "\(s.cadeteA)")
                #expect(card._type == .roja)
                #expect(card.isSecondYellow)
                #expect(card.minute == 70)
                #expect(card.comment == "dos amarillas")
                #expect(card.fromReport == false)
            }
        }
    }

    @Test("la misma tarjeta otra vez es 409 CARD_ALREADY_RECORDED")
    func duplicateIsConflict() async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            _ = try await Self.create(app, Self.cardJSON(s))
            try await Self.send(app, .POST, "/v1/cards", json: Self.cardJSON(s)) { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .conflict)
                #expect(try A.code(response) == "CARD_ALREADY_RECORDED")
            }
        }
    }

    @Test("lo que el cuerpo no cumple es 422, con su código", arguments: [
        ("segunda amarilla con suelta", "LOOSE_YELLOW_EXISTS"),
        ("otro equipo", "TEAM_NOT_IN_MATCH"),
        ("antes de la hora", "MATCH_NOT_STARTED"),
        ("segunda amarilla amarilla", "INVALID_VALUE"),
    ])
    func createRejections(_ case: String, _ code: String) async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            let json: String
            switch `case` {
            case "segunda amarilla con suelta":
                _ = try await Self.create(app, Self.cardJSON(s))
                json = Self.cardJSON(s, type: "roja", extra: #""isSecondYellow": true"#)
            case "otro equipo": json = Self.cardJSON(s, team: s.cadeteB)
            case "antes de la hora": json = Self.cardJSON(s, match: s.future)
            default: json = Self.cardJSON(s, extra: #""isSecondYellow": true"#)
            }
            try await Self.send(app, .POST, "/v1/cards", json: json) { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .unprocessableEntity)
                #expect(try A.code(response) == code)
            }
        }
    }

    @Test("listCards trae las del partido por minuto; sin ámbito, 400 MISSING_SCOPE")
    func listByMatch() async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            let late = try await Self.create(app, Self.cardJSON(s, extra: #""minute": 80"#))
            let early = try await Self.create(app, Self.cardJSON(s, player: s.pedro, extra: #""minute": 5"#))
            let noMinute = try await Self.create(app, Self.cardJSON(s, type: "roja"))
            try await Self.send(app, .GET, "/v1/cards?matchId=\(s.played)") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .ok)
                #expect(try A.decode([Components.Schemas.CardResponse].self, response).map(\.id) == [early, late, noMinute])
            }
            try await Self.send(app, .GET, "/v1/cards?matchId=\(s.played)&playerId=\(s.pedro)") {
                (response: TestingHTTPResponse) async throws in
                #expect(try A.decode([Components.Schemas.CardResponse].self, response).map(\.id) == [early])
            }
            try await Self.send(app, .GET, "/v1/cards") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .badRequest)
                #expect(try A.code(response) == "MISSING_SCOPE")
            }
        }
    }

    @Test("getCard devuelve la tarjeta; la que no existe es 404 CARD_NOT_FOUND")
    func getOne() async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            let id = try await Self.create(app, Self.cardJSON(s))
            try await Self.send(app, .GET, "/v1/cards/\(id)") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .ok)
            }
            for path in ["/v1/cards/\(UUID())", "/v1/cards/nada"] {
                try await Self.send(app, .GET, path) { (response: TestingHTTPResponse) async throws in
                    #expect(response.status == .notFound)
                    #expect(try A.code(response) == "CARD_NOT_FOUND")
                }
            }
        }
    }

    @Test("en una tarjeta del acta, el comentario se escribe y el minuto no (D-136); y no se borra")
    func reportCardIsLocked() async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            let id = try await Self.create(app, Self.cardJSON(s, extra: #""minute": 20"#))
            try await (app.db(.control) as! any SQLDatabase).raw("""
                UPDATE \(ident: Self.schema).cards SET from_report = true WHERE id = \(bind: UUID(uuidString: id)!)
                """).run()
            try await Self.send(app, .PATCH, "/v1/cards/\(id)", json: #"{"comment": "protestar"}"#) {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .ok)
                let card = try A.decode(Components.Schemas.CardResponse.self, response)
                #expect(card.comment == "protestar")
                #expect(card.fromReport)
            }
            try await Self.send(app, .PATCH, "/v1/cards/\(id)", json: #"{"minute": 25}"#) {
                (response: TestingHTTPResponse) async throws in
                #expect(response.status == .unprocessableEntity)
                #expect(try A.code(response) == "LOCKED_BY_MATCH_REPORT")
            }
            try await Self.send(app, .DELETE, "/v1/cards/\(id)") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .unprocessableEntity)
            }
        }
    }

    @Test("deleteCard responde 204 a una del club, y luego es 404")
    func deleteThenNotFound() async throws {
        try await A.withSeededClub(slug: Self.slug) { app, s in
            let id = try await Self.create(app, Self.cardJSON(s))
            try await Self.send(app, .DELETE, "/v1/cards/\(id)") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .noContent)
            }
            try await Self.send(app, .DELETE, "/v1/cards/\(id)") { (response: TestingHTTPResponse) async throws in
                #expect(response.status == .notFound)
            }
        }
    }
}

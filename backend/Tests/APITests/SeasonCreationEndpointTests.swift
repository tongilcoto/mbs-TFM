import APIContract
import Application
import Domain
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App
import TestSupport

/// Nivel 4 (§8.1): `POST /v1/seasons` (R2.7, `D-106`). El caso de uso está
/// probado en el nivel 2; aquí, **el borde**: la ruta, cada campo de la respuesta,
/// lo que queda guardado y cada error con su código y su `detail`.
///
/// **Es una extensión de `SeasonEndpointTests`, no una suite aparte**: usa su club
/// sembrado —2024/25 sin código, 2025/26 en curso y 2026/27 **archivada**— y su
/// reloj, el 15 de enero de 2026, y dos suites con el mismo club correrían a la
/// vez y se pisarían el *schema*. Así heredan su `.serialized`.
extension SeasonEndpointTests {

    static func post(
        _ app: Application, _ json: String,
        _ check: @escaping @Sendable (TestingHTTPResponse) async throws -> Void
    ) async throws {
        try await app.testing().test(
            .POST, "/v1/seasons",
            beforeRequest: { request in
                Self.header(&request)
                request.headers.contentType = .json
                request.body = ByteBuffer(string: json)
            }, afterResponse: check)
    }

    static func decodeSeason(_ response: TestingHTTPResponse) throws -> Components.Schemas.SeasonResponse {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            Components.Schemas.SeasonResponse.self, from: Data(response.body.readableBytesView))
    }

    static func decodeProblem(_ response: TestingHTTPResponse) throws -> Components.Schemas.Problem {
        try JSONDecoder().decode(
            Components.Schemas.Problem.self, from: Data(response.body.readableBytesView))
    }

    @Test("solo con la etiqueta: 201, sin código, con sus fechas, y queda guardada (D-106)")
    func createsASeasonWithItsLabelOnly() async throws {
        try await Self.withSeededClub { app, _ in
            try await Self.post(app, #"{"label": "2027/28"}"#) { response async throws in
                #expect(response.status == .created)
                let season = try Self.decodeSeason(response)
                #expect(season.label == "2027/28")
                #expect(season.federationSeasonId == nil)
                #expect(season.startDate == "2027-07-01")
                #expect(season.endDate == "2028-06-30")
                #expect(season.isCurrent == false, "el 15 de enero de 2026 no está en curso")
                #expect(season.archivedAt == nil)
            }
            try await app.testing().test(.GET, "/v1/seasons", beforeRequest: {
                Self.header(&$0)
            }) { response async throws in
                let newest = try #require(try Self.decode(response).first)
                #expect(newest.label == "2027/28", "la nueva no quedó guardada")
                #expect(newest.federationSeasonId == nil)
            }
        }
    }

    @Test("con el código, nace con él")
    func createsASeasonWithItsCode() async throws {
        try await Self.withSeededClub { app, _ in
            try await Self.post(app, #"{"label": "2027/28", "federationSeasonId": "23"}"#) { response async throws in
                #expect(response.status == .created)
                #expect(try Self.decodeSeason(response).federationSeasonId == "23")
            }
        }
    }

    /// La archivada no se ve en el selector, pero su etiqueta sigue ocupada.
    @Test("la etiqueta de una archivada: 409 SEASON_ALREADY_EXISTS, con el campo en el detail")
    func anArchivedLabelIsTaken() async throws {
        try await Self.withSeededClub { app, _ in
            try await Self.post(app, #"{"label": "2026/27"}"#) { response async throws in
                #expect(response.status == .conflict)
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == .SEASON_ALREADY_EXISTS)
                #expect(problem.detail == "label: ya hay una temporada con '2026/27'")
            }
        }
    }

    @Test("un código que ya es de otra: 409 SEASON_ALREADY_EXISTS, por el código")
    func aTakenCodeIsTaken() async throws {
        try await Self.withSeededClub { app, _ in
            try await Self.post(app, #"{"label": "2027/28", "federationSeasonId": "21"}"#) { response async throws in
                #expect(response.status == .conflict)
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == .SEASON_ALREADY_EXISTS)
                #expect(problem.detail == "federationSeasonId: ya hay una temporada con '21'")
            }
        }
    }

    /// Las dos formas de una etiqueta que no vale llegan igual: el generador no
    /// aplica el `pattern` del catálogo (como no aplica `minLength`, `D-65`), así
    /// que las dos las rechaza `SeasonLabel`, con el campo delante.
    @Test("2026/28 y 2026-27: 422 INVALID_VALUE con label en el detail", arguments: ["2026/28", "2026-27"])
    func anInvalidLabelIsRejected(_ label: String) async throws {
        try await Self.withSeededClub { app, _ in
            try await Self.post(app, #"{"label": "\#(label)"}"#) { response async throws in
                #expect(response.status == .unprocessableEntity)
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == .INVALID_VALUE)
                #expect(problem.detail?.hasPrefix("label: ") == true)
            }
        }
    }

    @Test("un código vacío: 422 INVALID_VALUE con federationSeasonId en el detail")
    func anEmptyCodeIsRejected() async throws {
        try await Self.withSeededClub { app, _ in
            try await Self.post(app, #"{"label": "2027/28", "federationSeasonId": " "}"#) { response async throws in
                #expect(response.status == .unprocessableEntity)
                let problem = try Self.decodeProblem(response)
                #expect(problem.code == .INVALID_VALUE)
                #expect(problem.detail?.hasPrefix("federationSeasonId: ") == true)
            }
        }
    }

    @Test("sin etiqueta: 400")
    func aBodyWithoutLabelIsABadRequest() async throws {
        try await Self.withSeededClub { app, _ in
            try await Self.post(app, #"{"federationSeasonId": "23"}"#) { response async throws in
                #expect(response.status == .badRequest)
            }
        }
    }
}

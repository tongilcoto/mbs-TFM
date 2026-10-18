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

/// Nivel 4 (§8.1): `GET /v1/seasons`, el selector de temporada de la portada
/// (Plan R1). La regla de la temporada en curso está probada en el nivel 1 y el
/// caso de uso en el 2; aquí se prueba **el borde**: la ruta, el filtro de la
/// consulta, el orden que trae la base y cada campo del DTO.
@Suite("Seasons · §5.1 · la lista de temporadas",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct SeasonEndpointTests {

    static let prefix = "e2e_"
    static let slug = "seasonsclub"
    static let now = Date(timeIntervalSince1970: 1_760_000_000)
    /// Segundos enteros, para poder compararla tal cual después del viaje.
    static let archivedAt = Date(timeIntervalSince1970: 1_770_000_000)

    /// 15 de enero de 2026: **el reloj se fija** para que la temporada en curso
    /// no dependa del día en que corra la batería.
    static let today = try! Date("2026-01-15T12:00:00Z", strategy: .iso8601)

    struct FixedClock: Clock {
        let instant: Date
        func now() -> Date { instant }
    }

    struct Seeded {
        let older: SeasonID      // 2024/25
        let current: SeasonID    // 2025/26, la que contiene el día de hoy
        let archived: SeasonID   // 2026/27, archivada
    }

    /// Siembra **desordenada a propósito**: el orden de la respuesta tiene que
    /// salir de la consulta, no del orden en que se guardó.
    static func withSeededClub(
        _ body: @escaping @Sendable (Application, Seeded) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp(clock: FixedClock(instant: today)) { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(slug, federation: .rffm, schemaPrefix: prefix, on: app)

            let seeded = Seeded(
                older: SeasonID(raw: UUID()), current: SeasonID(raw: UUID()),
                archived: SeasonID(raw: UUID()))
            let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            try await unitOfWork.withRepositories(actor: ActorContext(clubSlug: try Slug(slug))) {
                for (id, label, federationID, archived) in [
                    (seeded.current, "2025/26", "21", nil as Date?),
                    (seeded.archived, "2026/27", "22", archivedAt),
                    (seeded.older, "2024/25", "20", nil),
                ] {
                    try await $0.seasons.save(try Season(
                        id: id, label: try SeasonLabel(label), federationSeasonID: federationID,
                        archivedAt: archived, createdAt: now, updatedAt: now))
                }
            }

            try await body(app, seeded)
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func decode(_ response: TestingHTTPResponse) throws -> [Components.Schemas.SeasonResponse] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            [Components.Schemas.SeasonResponse].self, from: Data(response.body.readableBytesView))
    }

    static func header(_ request: inout TestingHTTPRequest) {
        request.headers.add(name: "X-Club", value: slug)
    }

    // ─────────────────────────────────────────────────────────────────────────

    @Test("sin filtro: las no archivadas, de la más reciente a la más antigua, con la que está en curso")
    func listsTheVisibleSeasonsNewestFirst() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(.GET, "/v1/seasons", beforeRequest: { Self.header(&$0) }) {
                response async throws in
                #expect(response.status == .ok)
                let seasons = try Self.decode(response)
                #expect(seasons.map(\.label) == ["2025/26", "2024/25"])
                #expect(seasons.map(\.isCurrent) == [true, false])
                #expect(seasons.map(\.id) == ["\(seeded.current)", "\(seeded.older)"])
            }
        }
    }

    /// Cada campo del DTO, con valores distintos entre sí: las dos fechas son
    /// días sin hora (`format: date`), y salen de la etiqueta (§3.2).
    @Test("cada campo de la temporada sale con su valor")
    func mapsEveryField() async throws {
        try await Self.withSeededClub { app, _ in
            try await app.testing().test(.GET, "/v1/seasons", beforeRequest: { Self.header(&$0) }) {
                response async throws in
                let current = try #require(try Self.decode(response).first)
                #expect(current.federationSeasonId == "21")
                #expect(current.startDate == "2025-07-01")
                #expect(current.endDate == "2026-06-30")
                #expect(current.archivedAt == nil)
            }
        }
    }

    @Test("con includeArchived=true salen también las archivadas, con su fecha de archivado (§3.5)")
    func includesTheArchivedOnesWhenAsked() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/seasons?includeArchived=true", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                #expect(response.status == .ok)
                let seasons = try Self.decode(response)
                #expect(seasons.map(\.label) == ["2026/27", "2025/26", "2024/25"])
                #expect(seasons.map(\.isCurrent) == [false, true, false])
                let archived = try #require(seasons.first)
                #expect(archived.id == "\(seeded.archived)")
                #expect(archived.archivedAt == Self.archivedAt)
            }
        }
    }
}

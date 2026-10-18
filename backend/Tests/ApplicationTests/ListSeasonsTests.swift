import Domain
import Foundation
import Synchronization
import Testing
@testable import Application

/// Nivel 2 (§8.1): `ListSeasons` con el repositorio y el reloj falseados.
///
/// Lo que se prueba aquí es lo que decide el caso de uso: **qué le pide al
/// repositorio** (el filtro de las archivadas pasa tal cual) y **cuál marca en
/// curso**, con el reloj que se le dé. El orden y el filtro en SQL son del
/// repositorio, y los prueba el nivel 3.
@Suite("ListSeasons · §5.1 · las temporadas del club, con la que está en curso")
struct ListSeasonsTests {

    /// Devuelve lo que se le dé, **en ese orden**, y apunta con qué se le llamó.
    final class SeasonRepositorySpy: SeasonRepository, Sendable {
        let stored: [Season]
        let requests = Mutex<[Bool]>([])

        init(stored: [Season]) { self.stored = stored }

        func list(includingArchived: Bool) async throws -> [Season] {
            requests.withLock { $0.append(includingArchived) }
            return stored
        }
        func find(_ id: SeasonID) async throws -> Season? { nil }
        func findByFederationID(_ federationSeasonID: String) async throws -> Season? { nil }
        func save(_ season: Season) async throws {}
    }

    static func make(_ label: String, archivedAt: Date? = nil) throws -> Season {
        try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel(label),
            federationSeasonID: "21", archivedAt: archivedAt,
            createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
    }

    /// 15 de enero de 2026: dentro de la 2025/26.
    static let enero2026 = try! Date("2026-01-15T12:00:00Z", strategy: .iso8601)

    @Test("devuelve las temporadas en el orden del repositorio, con la que está en curso")
    func returnsSeasonsWithTheCurrentOne() async throws {
        let seasons = [try Self.make("2026/27"), try Self.make("2025/26"), try Self.make("2024/25")]
        let useCase = ListSeasons(
            seasons: SeasonRepositorySpy(stored: seasons), clock: FixedClock(instant: Self.enero2026))

        let listing = try await useCase.execute(includingArchived: false)

        #expect(listing.seasons.map(\.label.value) == ["2026/27", "2025/26", "2024/25"])
        #expect(listing.currentID == seasons[1].id)
    }

    /// El filtro es del repositorio (§3.5); el caso de uso **no lo decide**, lo
    /// pasa. Con los dos valores, para que un `false` fijo no pase por bueno.
    @Test("pide las archivadas solo cuando se le pide", arguments: [false, true])
    func passesTheArchivedFilterThrough(includingArchived: Bool) async throws {
        let repository = SeasonRepositorySpy(stored: [])
        let useCase = ListSeasons(seasons: repository, clock: FixedClock(instant: Self.enero2026))

        _ = try await useCase.execute(includingArchived: includingArchived)

        #expect(repository.requests.withLock { $0 } == [includingArchived])
    }

    /// Pedidas las archivadas, la que contiene hoy puede estar archivada, y no se
    /// marca: archivar la oculta (§3.5).
    @Test("una temporada archivada no se marca en curso aunque contenga hoy (§3.5)")
    func anArchivedSeasonIsNotMarkedCurrent() async throws {
        let seasons = [try Self.make("2025/26", archivedAt: Date(timeIntervalSince1970: 0))]
        let useCase = ListSeasons(
            seasons: SeasonRepositorySpy(stored: seasons), clock: FixedClock(instant: Self.enero2026))

        let listing = try await useCase.execute(includingArchived: true)

        #expect(listing.seasons.count == 1)
        #expect(listing.currentID == nil)
    }
}

import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): `CreateSeason` con el repositorio falseado.
///
/// Lo que decide el caso de uso: **que la temporada nazca sin código** si no se le
/// da (`D-106`), y **qué es «ya existe»** antes de escribir —la etiqueta o el
/// código, también de una archivada—. Que la etiqueta tenga los años seguidos es
/// del Dominio (`SeasonLabel`), y aquí solo se comprueba que pasa por él.
@Suite("CreateSeason · §5.1 · la temporada nace en la web, sin código (D-106)")
struct CreateSeasonTests {

    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let newID = UUID()

    static func useCase(_ store: IngestionStore) -> CreateSeason {
        CreateSeason(
            seasons: FakeSeasonRepository(store: store),
            clock: FixedClock(instant: now),
            ids: SequentialUUIDProvider([newID]))
    }

    static func existing(
        _ label: String, federationSeasonID: String? = nil, archivedAt: Date? = nil
    ) throws -> Season {
        try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel(label),
            federationSeasonID: federationSeasonID, archivedAt: archivedAt,
            createdAt: now, updatedAt: now)
    }

    @Test("solo con la etiqueta, la temporada nace sin código y se guarda (D-106)")
    func aSeasonIsBornWithItsLabelOnly() async throws {
        let store = IngestionStore()

        let created = try await Self.useCase(store)
            .execute(.init(label: "2026/27", federationSeasonID: nil))

        #expect(created.id == SeasonID(raw: Self.newID))
        #expect(created.label.value == "2026/27")
        #expect(created.federationSeasonID == nil)
        #expect(await store.seasons.map(\.id) == [created.id])
    }

    @Test("con el código, nace con él: semillas, scripts y pruebas (D-106)")
    func aSeasonCanStillBeBornWithItsCode() async throws {
        let store = IngestionStore()

        let created = try await Self.useCase(store)
            .execute(.init(label: "2026/27", federationSeasonID: "22"))

        #expect(created.federationSeasonID == "22")
        #expect(await store.seasons.first?.federationSeasonID == "22")
    }

    @Test("una etiqueta que ya existe, aunque esté archivada, es «ya existe» y no se escribe")
    func aRepeatedLabelAlreadyExists() async throws {
        let store = IngestionStore()
        let archived = try Self.existing("2026/27", archivedAt: Self.now)
        await store.seed(seasons: [archived])

        await #expect(throws: ApplicationError.seasonAlreadyExists(field: "label", value: "2026/27")) {
            try await Self.useCase(store).execute(.init(label: "2026/27", federationSeasonID: nil))
        }
        #expect(await store.seasons.map(\.id) == [archived.id])
    }

    @Test("un código que ya es de otra temporada es «ya existe» y no se escribe")
    func aRepeatedCodeAlreadyExists() async throws {
        let store = IngestionStore()
        let other = try Self.existing("2025/26", federationSeasonID: "22")
        await store.seed(seasons: [other])

        await #expect(throws: ApplicationError.seasonAlreadyExists(field: "federationSeasonId", value: "22")) {
            try await Self.useCase(store).execute(.init(label: "2026/27", federationSeasonID: "22"))
        }
        #expect(await store.seasons.map(\.id) == [other.id])
    }

    /// «2026/28»: la forma vale, los años no siguen. Lo dice el Dominio, con el
    /// campo delante, que es lo que la web enseña junto al suyo.
    @Test("una etiqueta con los años sin seguir la rechaza el Dominio, y no se escribe")
    func aLabelWithNonConsecutiveYearsIsRejected() async throws {
        let store = IngestionStore()

        await #expect {
            try await Self.useCase(store).execute(.init(label: "2026/28", federationSeasonID: nil))
        } throws: { error in
            guard case DomainError.invalidValue(let field, _) = error else { return false }
            return field == "label"
        }
        #expect(await store.seasons.isEmpty)
    }
}

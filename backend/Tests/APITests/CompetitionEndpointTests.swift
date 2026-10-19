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

/// Nivel 4 (§8.1): `GET /v1/competitions` (Plan R1, R1.7). Que los filtros se
/// sumen lo prueba el nivel 3; aquí se prueba **el borde**: que cada filtro de la
/// dirección llega a su sitio, el 400 de una `seasonId` que no es un UUID, y cada
/// campo del DTO. El estado de la ingesta llega en R1.8.
@Suite("Competitions · §5.1 · la lista de competiciones",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct CompetitionEndpointTests {

    static let prefix = "e2e_"
    static let slug = "compsclub"
    static let now = Date(timeIntervalSince1970: 1_760_000_000)
    /// Segundos enteros, para poder compararla tal cual después del viaje.
    static let syncedAt = Date(timeIntervalSince1970: 1_770_000_000)

    /// La `a` y otra por filtro, que se diferencia de ella **solo** en ese campo.
    struct Seeded: Sendable {
        let first: SeasonID, second: SeasonID
        let a: CompetitionID, futbol7: CompetitionID, cadete: CompetitionID
        let femenino: CompetitionID, otherSeason: CompetitionID
    }

    static func withSeededClub(
        _ body: @escaping @Sendable (Application, Seeded) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(slug, federation: .rffm, schemaPrefix: prefix, on: app)

            let seeded = Seeded(
                first: SeasonID(raw: UUID()), second: SeasonID(raw: UUID()),
                a: CompetitionID(raw: UUID()), futbol7: CompetitionID(raw: UUID()),
                cadete: CompetitionID(raw: UUID()), femenino: CompetitionID(raw: UUID()),
                otherSeason: CompetitionID(raw: UUID()))
            let rows: [(CompetitionID, SeasonID, Modality, TeamCategory, Gender, String, Date?)] = [
                (seeded.a, seeded.first, .futbol11, .infantil, .masculino, "Grupo 1", syncedAt),
                (seeded.futbol7, seeded.first, .futbol7, .infantil, .masculino, "Grupo 2", nil),
                (seeded.cadete, seeded.first, .futbol11, .cadete, .masculino, "Grupo 3", nil),
                (seeded.femenino, seeded.first, .futbol11, .infantil, .femenino, "Grupo 4", nil),
                (seeded.otherSeason, seeded.second, .futbol11, .infantil, .masculino, "Grupo 1", nil),
            ]
            let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            try await unitOfWork.withRepositories(actor: ActorContext(clubSlug: try Slug(slug))) {
                for (id, label, federationID) in [
                    (seeded.first, "2025/26", "21"), (seeded.second, "2026/27", "22"),
                ] {
                    try await $0.seasons.save(try Season(
                        id: id, label: try SeasonLabel(label), federationSeasonID: federationID,
                        createdAt: now, updatedAt: now))
                }
                for (index, row) in rows.enumerated() {
                    let (id, seasonID, modality, category, gender, group, synced) = row
                    try await $0.competitions.save(try Competition(
                        id: id, seasonID: seasonID, modality: modality, gender: gender,
                        federationCompetitionID: "2403754\(index)", federationGroupID: "9900\(index)",
                        ageCategory: category, divisionLabel: "Primera División Autonómica",
                        groupLabel: group, lastSyncedAt: synced, createdAt: now, updatedAt: now))
                }
            }

            try await body(app, seeded)
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func decode(_ response: TestingHTTPResponse) throws -> [Components.Schemas.CompetitionResponse] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            [Components.Schemas.CompetitionResponse].self, from: Data(response.body.readableBytesView))
    }

    static func header(_ request: inout TestingHTTPRequest) {
        request.headers.add(name: "X-Club", value: slug)
    }

    // ─────────────────────────────────────────────────────────────────────────

    @Test("sin filtros salen todas las del club, de las dos temporadas")
    func listsThemAll() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(.GET, "/v1/competitions", beforeRequest: { Self.header(&$0) }) {
                response async throws in
                #expect(response.status == .ok)
                let ids = Set(try Self.decode(response).map(\.id))
                #expect(ids == Set([seeded.a, seeded.futbol7, seeded.cadete, seeded.femenino,
                                    seeded.otherSeason].map { "\($0)" }))
            }
        }
    }

    /// Cada filtro de la dirección, solo: si uno no llegara a su sitio, saldrían
    /// las cinco, o la que no es.
    @Test("cada filtro de la dirección deja la que se diferencia en ese campo")
    func eachQueryFilterReachesItsPlace() async throws {
        try await Self.withSeededClub { app, seeded in
            let cases: [(String, CompetitionID)] = [
                ("seasonId=\(seeded.second)", seeded.otherSeason),
                ("modality=futbol_7", seeded.futbol7),
                ("ageCategory=cadete", seeded.cadete),
                ("gender=femenino", seeded.femenino),
            ]
            for (query, expected) in cases {
                try await app.testing().test(
                    .GET, "/v1/competitions?\(query)", beforeRequest: { Self.header(&$0) }
                ) { response async throws in
                    #expect(response.status == .ok, "\(query)")
                    #expect(try Self.decode(response).map(\.id) == ["\(expected)"], "\(query)")
                }
            }
        }
    }

    @Test("una seasonId que no es un UUID es 400 INVALID_UUID")
    func aSeasonIdThatIsNotAUUIDIs400() async throws {
        try await Self.withSeededClub { app, _ in
            try await app.testing().test(
                .GET, "/v1/competitions?seasonId=abc", beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                #expect(response.status == .badRequest)
                let problem = try JSONDecoder().decode(
                    Components.Schemas.Problem.self, from: Data(response.body.readableBytesView))
                #expect(problem.code == .INVALID_UUID)
            }
        }
    }

    /// Cada campo, con valores distintos entre sí: los dos códigos de la
    /// federación no se pueden cruzar sin que se note.
    @Test("cada campo de la competición sale con su valor")
    func mapsEveryField() async throws {
        try await Self.withSeededClub { app, seeded in
            try await app.testing().test(
                .GET, "/v1/competitions?seasonId=\(seeded.first)&gender=masculino&modality=futbol_11&ageCategory=infantil",
                beforeRequest: { Self.header(&$0) }
            ) { response async throws in
                let a = try #require(try Self.decode(response).first)
                #expect(a.id == "\(seeded.a)")
                #expect(a.seasonId == "\(seeded.first)")
                #expect(a.modality == .futbol_11)
                #expect(a.gender == .masculino)
                #expect(a.ageCategory == .infantil)
                #expect(a.divisionLabel == "Primera División Autonómica")
                #expect(a.groupLabel == "Grupo 1")
                #expect(a.federationCompetitionId == "24037540")
                #expect(a.federationGroupId == "99000")
                #expect(a.displayName == "Infantil · Primera División Autonómica · Grupo 1")
                #expect(a.lastSyncedAt == Self.syncedAt)
            }
        }
    }
}

import Application
import Domain
import Fluent
import Foundation
import SQLKit
import Testing
import Vapor
@testable import App
import TestSupport
@testable import Persistence
@testable import Tenancy

/// Nivel 3 (§8.1): el mapeo de `Competition`, su clave única, sus tres `CHECK` y
/// la cascada de su FK.
@Suite("Competition · §4.4 · el mapeo, la clave única de §3.5 y los CHECK de D-02",
        .serialized,
        .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct CompetitionPersistenceTests {

    static func competition(
        seasonID: SeasonID,
        id: UUID = UUID(),
        gender: Gender = .masculino,
        federationGroupID: String = "24037549",
        federationName: String? = nil,
        lastSyncedAt: Date? = nil
    ) throws -> Competition {
        try Competition(
            id: CompetitionID(raw: id),
            seasonID: seasonID,
            modality: .futbol11,
            gender: gender,
            federationCompetitionID: "24037548",
            federationGroupID: federationGroupID,
            ageCategory: .infantil,
            divisionLabel: "Primera",
            groupLabel: "Grupo 1",
            federationName: federationName,
            lastSyncedAt: lastSyncedAt,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Siembra una temporada **por repositorio**, que es lo que el Plan §4.1 pide
    /// de F1: sin HTTP con el que darla de alta, la siembra entra por el puerto.
    static func withSeason(
        _ slug: String,
        _ body: @escaping @Sendable (SeasonID, TenantFixture) async throws -> Void
    ) async throws {
        try await SeasonPersistenceTests.withTenant(slug) { tenant in
            let season = try SeasonPersistenceTests.season("2025/26")
            try await tenant.scope { try await $0.seasons.save(season) }
            try await body(season.id, tenant)
        }
    }

    /// Ida y vuelta con los tres enumerados y los dos campos anulables.
    @Test("guarda y recupera la entidad entera, enumerados incluidos (§4.4)")
    func roundTrip() async throws {
        try await Self.withSeason("comp-rt") { seasonID, tenant in
            let original = try Self.competition(
                seasonID: seasonID, gender: .femenino,
                federationName: "TERCERA FEDERACION DE FÚTBOL FEMENINO",
                lastSyncedAt: Date(timeIntervalSince1970: 1_700_000_000))
            try await tenant.scope { try await $0.competitions.save(original) }

            let stored = try #require(
                try await tenant.scope { try await $0.competitions.find(original.id) })
            #expect(stored.seasonID == seasonID)
            #expect(stored.modality == .futbol11)
            #expect(stored.gender == .femenino)
            #expect(stored.ageCategory == .infantil)
            #expect(stored.federationCompetitionID == "24037548")
            #expect(stored.federationGroupID == "24037549")
            #expect(stored.federationName == "TERCERA FEDERACION DE FÚTBOL FEMENINO")
            #expect(stored.isSynced)
            #expect(stored.displayName == "Infantil · Primera · Grupo 1")
        }
    }

    /// Los dos anulables, nulos. Es el caso del alta por ids —semillas, *scripts*
    /// y tests—, que no pasa por la federación y no tiene nombre que guardar
    /// (`D-72`).
    @Test("federationName y lastSyncedAt son anulables de verdad (D-72)")
    func nullableFieldsStayNull() async throws {
        try await Self.withSeason("comp-null") { seasonID, tenant in
            let original = try Self.competition(seasonID: seasonID)
            try await tenant.scope { try await $0.competitions.save(original) }

            let stored = try #require(
                try await tenant.scope { try await $0.competitions.find(original.id) })
            #expect(stored.federationName == nil)
            #expect(stored.lastSyncedAt == nil)
            #expect(!stored.isSynced, "nunca sincronizada ⇒ coordenadas aún editables (§3.7)")
        }
    }

    /// §3.5: la clave única es (`season_id`, `federation_group_id`), y la consulta
    /// que la usa es la de la cascada de `D-67` — la que decide crear o reutilizar.
    @Test("no caben dos competiciones con el mismo grupo en la misma temporada (§3.5)")
    func groupIsUniqueWithinSeason() async throws {
        try await Self.withSeason("comp-uniq") { seasonID, tenant in
            try await tenant.scope {
                try await $0.competitions.save(try Self.competition(seasonID: seasonID))
            }

            // En su propio ámbito: la violación aborta la transacción (§6.2).
            await #expect(throws: (any Error).self) {
                try await tenant.scope {
                    try await $0.competitions.save(
                        try Self.competition(seasonID: seasonID, federationGroupID: "24037549"))
                }
            }

            let encontrada = try await tenant.scope {
                try await $0.competitions.findByFederationGroup(
                    seasonID: seasonID, federationGroupID: "24037549")
            }
            #expect(encontrada != nil, "es la consulta con la que D-67 decide crear o reutilizar")
        }
    }

    /// La otra mitad de §3.5, y la razón de que `season_id` esté en la clave: el
    /// identificador de grupo envuelve categoría + división + grupo, **pero no la
    /// temporada**. Sin `season_id`, la misma competición no podría existir en dos
    /// temporadas — que es el caso normal.
    @Test("el mismo grupo sí se repite en otra temporada (§3.5)")
    func sameGroupInAnotherSeasonIsAllowed() async throws {
        try await SeasonPersistenceTests.withTenant("comp-2seasons") { tenant in
            let primera = try SeasonPersistenceTests.season("2025/26", federationSeasonID: "21")
            let segunda = try SeasonPersistenceTests.season("2026/27", federationSeasonID: "22")

            try await tenant.scope {
                try await $0.seasons.save(primera)
                try await $0.seasons.save(segunda)
                // Mismo `federation_group_id` en las dos: no colisiona.
                try await $0.competitions.save(try Self.competition(seasonID: primera.id))
                try await $0.competitions.save(try Self.competition(seasonID: segunda.id))
            }

            let deLaPrimera = try await tenant.scope {
                try await $0.competitions.list(seasonID: primera.id)
            }
            let deLaSegunda = try await tenant.scope {
                try await $0.competitions.list(seasonID: segunda.id)
            }
            #expect(deLaPrimera.count == 1)
            #expect(deLaSegunda.count == 1)
        }
    }

    /// §4.6 / `D-02`: el `CHECK` se deriva del `enum` del Dominio. Se ataca por SQL
    /// crudo porque **por el repositorio es inalcanzable**: el tipo de Swift no
    /// deja construir un valor fuera del enumerado. Lo que se prueba es que la
    /// tabla se defiende de los *scripts* y de la ingesta, que es el criterio de
    /// `D-28` para bajar una invariante al esquema.
    @Test("los CHECK rechazan un valor fuera del enumerado (D-02)")
    func checkConstraintsRejectOutOfDomainValues() async throws {
        try await Self.withSeason("comp-check") { seasonID, tenant in
            // Fuera de todo ámbito: la temporada ya está confirmada y el `INSERT`
            // en crudo la ve, así que la FK se cumple.
            func insert(modality: String, gender: String, ageCategory: String) async throws {
                try await tenant.raw.raw("""
                    INSERT INTO \(ident: tenant.schema).competitions
                      (id, season_id, modality, gender, age_category,
                       federation_competition_id, federation_group_id,
                       division_label, group_label, created_at, updated_at)
                    VALUES (gen_random_uuid(), \(bind: seasonID.raw),
                       \(bind: modality), \(bind: gender), \(bind: ageCategory),
                       '1', \(bind: UUID().uuidString), 'Primera', 'Grupo 1', now(), now())
                    """).run()
            }

            // Control positivo: con los tres valores buenos, entra. Sin él, los
            // tres rechazos de abajo pasarían aunque el fallo fuese otro.
            try await insert(modality: "futbol_11", gender: "mixto", ageCategory: "senior")

            await #expect(throws: (any Error).self, "modalidad inventada") {
                try await insert(modality: "futbol_3", gender: "mixto", ageCategory: "senior")
            }
            await #expect(throws: (any Error).self, "género inventado") {
                try await insert(modality: "futbol_11", gender: "otro", ageCategory: "senior")
            }
            await #expect(throws: (any Error).self, "categoría inventada") {
                try await insert(modality: "futbol_11", gender: "mixto", ageCategory: "veterano")
            }
        }
    }

    /// `D-73`: la FK es `ON DELETE CASCADE` porque es el mecanismo con el que §5.4
    /// diseña la **purga** de temporada. Lo que impide que un borrado normal se
    /// lleve el subárbol es la guarda de "cero dependientes → 409" del caso de uso
    /// — que por eso mismo **no puede olvidarse** cuando llegue.
    @Test("borrar la temporada se lleva sus competiciones: la purga de §5.4 (D-73)")
    func deletingSeasonCascades() async throws {
        try await Self.withSeason("comp-cascade") { seasonID, tenant in
            try await tenant.scope {
                try await $0.competitions.save(try Self.competition(seasonID: seasonID))
            }
            let antes = try await tenant.scope {
                try await $0.competitions.list(seasonID: seasonID)
            }
            #expect(antes.count == 1)

            try await tenant.raw.raw("""
                DELETE FROM \(ident: tenant.schema).seasons WHERE id = \(bind: seasonID.raw)
                """).run()

            let despues = try await tenant.scope {
                try await $0.competitions.list(seasonID: seasonID)
            }
            #expect(despues.isEmpty, "la FK no es CASCADE: la purga de §5.4 no funcionaría")
        }
    }
}

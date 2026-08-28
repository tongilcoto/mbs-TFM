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

/// Nivel 3 de la pirámide (§8.1): **Postgres real**, contenedor efímero.
///
/// Lo que se prueba aquí es el **mapeo y el esquema** —`Record` ↔ Entidad,
/// unicidades, `CHECK`, FK—, no las reglas: ésas ya las cubrió el nivel 1
/// (Plan §5). Un test de integración **por adaptador, no por regla**.
///
/// - Note: `docker compose up -d` antes de correrlos.
@Suite("Season · §4.4 · el mapeo y las unicidades de §3.5",
        .serialized,
        .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct SeasonPersistenceTests {

    static let prefix = "test_"

    /// Aprovisiona un club, presta el `TenantFixture` y barre al terminar.
    static func withTenant(
        _ slug: String, _ body: @escaping @Sendable (TenantFixture) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(
                slug, federation: .rffm, schemaPrefix: prefix, on: app)
            try await body(TenantFixture(app: app, slug: slug, schema: "\(prefix)\(slug)"))
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func season(
        _ label: String, id: UUID = UUID(), federationSeasonID: String = "21",
        archivedAt: Date? = nil
    ) throws -> Season {
        try Season(
            id: SeasonID(raw: id), label: try SeasonLabel(label),
            federationSeasonID: federationSeasonID, archivedAt: archivedAt,
            createdAt: Date(), updatedAt: Date()
        )
    }

    /// Ida y vuelta completa: que **nada se pierde ni se inventa** al cruzar la
    /// frontera del ORM.
    @Test("guarda y recupera la entidad entera (§4.4)")
    func roundTrip() async throws {
        try await Self.withTenant("season-rt") { tenant in
            let original = try Self.season("2025/26", federationSeasonID: "21")
            try await tenant.scope { try await $0.seasons.save(original) }

            let stored = try #require(
                try await tenant.scope { try await $0.seasons.find(original.id) })
            #expect(stored.id == original.id)
            #expect(stored.label.value == "2025/26")
            #expect(stored.federationSeasonID == "21")
            #expect(stored.archivedAt == nil)
        }
    }

    /// **El test que vigila la derivación en UTC.** `start_date`/`end_date` son
    /// derivadas de la etiqueta (§3.2); si el `Date` se construyera en hora local
    /// —`Europe/Madrid` es UTC+1/+2—, la medianoche caería el día anterior y el
    /// 1 de julio aterrizaría en la columna `date` como 30 de junio.
    ///
    /// Se leen **en crudo y fuera del ámbito**, sin pasar por el mapeo: lo que se
    /// comprueba es la columna, no el `Record`.
    @Test("las fechas derivadas aterrizan en la columna como 01/07 y 30/06 (§3.2)")
    func derivedDatesLandUnshifted() async throws {
        try await Self.withTenant("season-dates") { tenant in
            try await tenant.scope { try await $0.seasons.save(try Self.season("2025/26")) }

            let row = try #require(try await tenant.raw.raw("""
                SELECT start_date::text AS s, end_date::text AS e
                FROM \(ident: tenant.schema).seasons
                """).first())

            #expect(try row.decode(column: "s", as: String.self) == "2025-07-01")
            #expect(try row.decode(column: "e", as: String.self) == "2026-06-30")
        }
    }

    /// Las dos unicidades de §3.5, **cada una en su propio ámbito**: una
    /// violación aborta la transacción, así que encadenarlas probaría la segunda
    /// contra un "transaction is aborted" y pasaría por el motivo equivocado.
    @Test("label lleva UNIQUE (§3.5)")
    func labelIsUnique() async throws {
        try await Self.withTenant("season-uq-label") { tenant in
            try await tenant.scope {
                try await $0.seasons.save(try Self.season("2025/26", federationSeasonID: "21"))
            }
            await #expect(throws: (any Error).self) {
                try await tenant.scope {
                    try await $0.seasons.save(try Self.season("2025/26", federationSeasonID: "99"))
                }
            }
        }
    }

    @Test("federationSeasonId lleva UNIQUE (§3.5)")
    func federationSeasonIDIsUnique() async throws {
        try await Self.withTenant("season-uq-fed") { tenant in
            try await tenant.scope {
                try await $0.seasons.save(try Self.season("2025/26", federationSeasonID: "21"))
            }
            await #expect(throws: (any Error).self) {
                try await tenant.scope {
                    try await $0.seasons.save(try Self.season("2026/27", federationSeasonID: "21"))
                }
            }
        }
    }

    /// §3.5: *"dos clubes pueden tener a la vez la temporada 2024/25 con el mismo
    /// `federation_season_id` sin colisionar"*. Es el comportamiento que se
    /// quiere y el que un `UNIQUE` global impediría — y sale gratis por vivir
    /// cada tabla en el *schema* de su club.
    @Test("la misma temporada convive en dos clubes: el UNIQUE es por schema (§3.5)")
    func uniquenessIsPerTenant() async throws {
        try await TestEnvironment.withApp { app in
            let slugs = ["season-t1", "season-t2"]
            try await TestEnvironment.dropClubs(slugs, schemaPrefix: Self.prefix, on: app)
            for slug in slugs {
                try await TestEnvironment.provisionClub(
                    slug, federation: .rffm, schemaPrefix: Self.prefix, on: app)
            }

            for slug in slugs {
                let tenant = TenantFixture(
                    app: app, slug: slug, schema: "\(Self.prefix)\(slug)")
                // Misma etiqueta y mismo id de federación en los dos. Que el
                // segundo no reviente **es** el resultado.
                try await tenant.scope {
                    try await $0.seasons.save(
                        try Self.season("2024/25", federationSeasonID: "21"))
                }
                let found = try await tenant.scope {
                    try await $0.seasons.findByFederationID("21")
                }
                #expect(found?.label.value == "2024/25")
            }

            try await TestEnvironment.dropClubs(slugs, schemaPrefix: Self.prefix, on: app)
        }
    }

    /// §3.5: las lecturas aplican por defecto el *scope* `archived_at IS NULL`.
    /// Y `archived_at` es un campo normal, **no** el `deleted_at` de Fluent
    /// (§4.4): la fila sigue ahí y se recupera pidiéndola.
    @Test("las archivadas se excluyen por defecto pero no están borradas (§3.5)")
    func archivedAreScopedOutNotDeleted() async throws {
        try await Self.withTenant("season-arch") { tenant in
            let archivada = try Self.season("2025/26", federationSeasonID: "21")
                .archived(at: Date())
            try await tenant.scope {
                try await $0.seasons.save(try Self.season("2026/27", federationSeasonID: "22"))
                try await $0.seasons.save(archivada)
            }

            let visibles = try await tenant.scope {
                try await $0.seasons.list(includingArchived: false)
            }
            #expect(visibles.map(\.label.value) == ["2026/27"])

            let todas = try await tenant.scope {
                try await $0.seasons.list(includingArchived: true)
            }
            #expect(todas.count == 2)

            let recuperada = try #require(
                try await tenant.scope { try await $0.seasons.find(archivada.id) })
            #expect(recuperada.isArchived, "archivar no es borrar (§3.5)")
        }
    }

    /// `save` es *upsert* (§4.3), a diferencia del de `Club`: aquí el alta es una
    /// operación normal (`D-16`), no provisión.
    @Test("save da de alta y luego actualiza la misma fila (§4.3)")
    func saveUpsertsInsteadOfDuplicating() async throws {
        try await Self.withTenant("season-upsert") { tenant in
            let original = try Self.season("2025/26", federationSeasonID: "21")
            try await tenant.scope { try await $0.seasons.save(original) }
            try await tenant.scope {
                try await $0.seasons.save(try original.applying(federationSeasonID: "22"))
            }

            let todas = try await tenant.scope {
                try await $0.seasons.list(includingArchived: true)
            }
            #expect(todas.count == 1, "el segundo save actualizó, no insertó")
            #expect(todas.first?.federationSeasonID == "22")
        }
    }
}

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

/// Nivel 3 (§8.1): las dos tablas de la plantilla (`D-119`), que la R6.5 estrena.
///
/// Lo que se prueba aquí son **las reglas que solo la base puede sostener**,
/// porque miran varias filas a la vez: el dorsal sin repetir (`D-118`) y un
/// jugador en una sola plantilla por temporada (`D-121`), las dos **entre los no
/// borrados**. Se atacan con SQL crudo, como lo haría un *script*: los
/// repositorios llegan en la R6.6.
@Suite("Player · D-118, D-119, D-121 · las dos tablas y sus índices",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct PlayerSchemaTests {

    static let prefix = "test_player_"

    /// Un club con **dos equipos propios y dos temporadas**: lo justo para separar
    /// «en este equipo» de «en otro equipo» y «esta temporada» de «otra».
    struct Fixture: Sendable {
        let tenant: TenantFixture
        let cadeteA: TeamID
        let cadeteB: TeamID
        let vigente: SeasonID
        let anterior: SeasonID

        var schema: String { tenant.schema }

        /// Un perfil nuevo, por SQL crudo.
        func profile(_ name: String = "JUAN GARCÍA") async throws -> UUID {
            let id = UUID()
            try await tenant.raw.raw("""
                INSERT INTO \(ident: schema).player_profiles (id, full_name, created_at, updated_at)
                VALUES (\(bind: id), \(bind: name), now(), now())
                """).run()
            return id
        }

        /// Una fila de la plantilla. Devuelve su id.
        @discardableResult
        func row(profile: UUID, team: TeamID, season: SeasonID, shirt: Int? = nil,
                 deleted: Bool = false) async throws -> UUID {
            let id = UUID()
            try await tenant.raw.raw("""
                INSERT INTO \(ident: schema).players
                  (id, profile_id, team_id, season_id, shirt_number, deleted_at, created_at, updated_at)
                VALUES (\(bind: id), \(bind: profile), \(bind: team.raw), \(bind: season.raw),
                        \(bind: shirt), \(unsafeRaw: deleted ? "now()" : "NULL"), now(), now())
                """).run()
            return id
        }
    }

    static func withFixture(
        _ slug: String, _ body: @escaping @Sendable (Fixture) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(
                slug, federation: .rffm, schemaPrefix: prefix, on: app)
            let tenant = TenantFixture(app: app, slug: slug, schema: "\(prefix)\(slug)")

            func ownTeam(_ letter: String) throws -> Team {
                try Team(id: TeamID(raw: UUID()), category: .cadete, letter: letter,
                         gender: .masculino, modality: .futbol11,
                         createdAt: Date(), updatedAt: Date())
            }
            let cadeteA = try ownTeam("A")
            let cadeteB = try ownTeam("B")
            let vigente = try Season(
                id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
                federationSeasonID: nil, createdAt: Date(), updatedAt: Date())
            let anterior = try Season(
                id: SeasonID(raw: UUID()), label: try SeasonLabel("2024/25"),
                federationSeasonID: nil, createdAt: Date(), updatedAt: Date())
            try await tenant.scope {
                try await $0.teams.save(cadeteA)
                try await $0.teams.save(cadeteB)
                try await $0.seasons.save(vigente)
                try await $0.seasons.save(anterior)
            }

            try await body(Fixture(tenant: tenant, cadeteA: cadeteA.id, cadeteB: cadeteB.id,
                                   vigente: vigente.id, anterior: anterior.id))
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    /// El `23505` de Postgres, el de un índice único: el que el adaptador
    /// traducirá a 409 en la R6.6.
    static func isUniqueViolation(_ error: any Error, index: String) -> Bool {
        let text = String(reflecting: error)
        return text.contains("23505") && text.contains(index)
    }

    // ── El dorsal (D-118) ───────────────────────────────────────────────────

    @Test("dos jugadores del mismo equipo y temporada no llevan el mismo dorsal (D-118)")
    func shirtIsUniqueInTheRoster() async throws {
        try await Self.withFixture("shirt") { f in
            try await f.row(profile: f.profile(), team: f.cadeteA, season: f.vigente, shirt: 9)
            let otro = try await f.profile("PEDRO LÓPEZ")
            await #expect {
                try await f.row(profile: otro, team: f.cadeteA, season: f.vigente, shirt: 9)
            } throws: { Self.isUniqueViolation($0, index: "uq_players_shirt") }
        }
    }

    /// Es lo que hace que no tener dorsal sea un estado normal (`D-118`): los
    /// nulos no chocan, porque Postgres no los compara.
    @Test("los que no tienen dorsal no chocan entre sí (D-118)")
    func playersWithoutShirtDoNotCollide() async throws {
        try await Self.withFixture("noshirt") { f in
            try await f.row(profile: f.profile(), team: f.cadeteA, season: f.vigente)
            try await f.row(profile: f.profile("PEDRO LÓPEZ"), team: f.cadeteA, season: f.vigente)
        }
    }

    @Test("el dorsal de un jugador dado de baja queda libre (D-36)")
    func deletedPlayerFreesTheShirt() async throws {
        try await Self.withFixture("freeshirt") { f in
            try await f.row(profile: f.profile(), team: f.cadeteA, season: f.vigente, shirt: 9,
                            deleted: true)
            try await f.row(profile: f.profile("PEDRO LÓPEZ"), team: f.cadeteA, season: f.vigente,
                            shirt: 9)
        }
    }

    /// El mismo número en el otro equipo, o en el mismo equipo otra temporada,
    /// no es repetir: el índice es por equipo y temporada.
    @Test("el mismo dorsal en otro equipo, o en otra temporada, sí vale (D-118)")
    func shirtRepeatsAcrossRosters() async throws {
        try await Self.withFixture("shirtacross") { f in
            try await f.row(profile: f.profile(), team: f.cadeteA, season: f.vigente, shirt: 9)
            try await f.row(profile: f.profile("PEDRO LÓPEZ"), team: f.cadeteB, season: f.vigente,
                            shirt: 9)
            try await f.row(profile: f.profile("LUIS RUIZ"), team: f.cadeteA, season: f.anterior,
                            shirt: 9)
        }
    }

    @Test("un dorsal fuera del 1 al 99 no entra ni por SQL (D-118)")
    func shirtCheck() async throws {
        try await Self.withFixture("shirtcheck") { f in
            let juan = try await f.profile()
            await #expect(throws: (any Error).self) {
                try await f.row(profile: juan, team: f.cadeteA, season: f.vigente, shirt: 100)
            }
        }
    }

    // ── Una plantilla por temporada (D-121) ─────────────────────────────────

    @Test("un jugador no está en dos plantillas de la misma temporada (D-121)")
    func onePlayerOneRosterPerSeason() async throws {
        try await Self.withFixture("oneroster") { f in
            let juan = try await f.profile()
            try await f.row(profile: juan, team: f.cadeteA, season: f.vigente)
            await #expect {
                try await f.row(profile: juan, team: f.cadeteB, season: f.vigente)
            } throws: { Self.isUniqueViolation($0, index: "uq_players_profile_season") }
        }
    }

    /// Cambiar de equipo son dos pasos, baja y alta (`D-121`): la fila dada de
    /// baja se queda, con sus goles y tarjetas, y no estorba a la nueva.
    @Test("dado de baja en un equipo, se da de alta en otro de la misma temporada (D-121)")
    func changingTeamIsDeleteThenAdd() async throws {
        try await Self.withFixture("changeteam") { f in
            let juan = try await f.profile()
            try await f.row(profile: juan, team: f.cadeteA, season: f.vigente, deleted: true)
            try await f.row(profile: juan, team: f.cadeteB, season: f.vigente)
        }
    }

    @Test("el mismo jugador sigue en otra temporada (D-119)")
    func samePlayerAcrossSeasons() async throws {
        try await Self.withFixture("seasons") { f in
            let juan = try await f.profile()
            try await f.row(profile: juan, team: f.cadeteA, season: f.anterior)
            try await f.row(profile: juan, team: f.cadeteB, season: f.vigente)
        }
    }

    // ── El perfil y las filas ───────────────────────────────────────────────

    /// El perfil solo se borra cuando ya no tiene filas, en el purgado (R11).
    /// Mientras tenga una, la base no deja borrarlo.
    @Test("un perfil con filas no se puede borrar (D-119)")
    func profileWithRowsCannotBeDeleted() async throws {
        try await Self.withFixture("restrict") { f in
            let juan = try await f.profile()
            try await f.row(profile: juan, team: f.cadeteA, season: f.vigente)
            await #expect(throws: (any Error).self) {
                try await f.tenant.raw.raw("""
                    DELETE FROM \(ident: f.schema).player_profiles WHERE id = \(bind: juan)
                    """).run()
            }
        }
    }

    /// Purgar una temporada (`D-24`) se lleva sus filas, como el resto de su
    /// subárbol, y deja el perfil: lo borra el purgado si se queda sin filas.
    @Test("borrar la temporada se lleva sus filas, y deja el perfil (D-24, D-119)")
    func seasonDeletionCascadesToRows() async throws {
        try await Self.withFixture("cascade") { f in
            let juan = try await f.profile()
            try await f.row(profile: juan, team: f.cadeteA, season: f.anterior)
            try await f.tenant.raw.raw("""
                DELETE FROM \(ident: f.schema).seasons WHERE id = \(bind: f.anterior.raw)
                """).run()

            let rows = try await f.tenant.raw.raw("""
                SELECT count(*) AS n FROM \(ident: f.schema).players
                """).first(decodingColumn: "n", as: Int.self)
            let profiles = try await f.tenant.raw.raw("""
                SELECT count(*) AS n FROM \(ident: f.schema).player_profiles
                """).first(decodingColumn: "n", as: Int.self)
            #expect(rows == 0)
            #expect(profiles == 1)
        }
    }

    @Test("un año fuera de 1900 a 2100 no entra en el perfil ni por SQL (D-119)")
    func birthYearCheck() async throws {
        try await Self.withFixture("yearcheck") { f in
            await #expect(throws: (any Error).self) {
                try await f.tenant.raw.raw("""
                    INSERT INTO \(ident: f.schema).player_profiles
                      (id, full_name, birth_year, created_at, updated_at)
                    VALUES (\(bind: UUID()), 'JUAN GARCÍA', 1899, now(), now())
                    """).run()
            }
        }
    }
}

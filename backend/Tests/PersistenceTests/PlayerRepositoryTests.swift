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

/// Nivel 3 (§8.1): los dos repositorios de la plantilla (R6.6), contra Postgres.
///
/// Lo que se prueba es el **mapeo** de ida y vuelta, con todo lleno y con todo
/// vacío, y que el borrado es **lógico**: la fila deja de verse pero sigue en la
/// tabla (`D-36`).
@Suite("Player · R6.6 · los repositorios de la plantilla y del perfil",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct PlayerRepositoryTests {

    static let prefix = "test_playerrepo_"
    static let now = Date()

    static func withFixture(
        _ slug: String,
        _ body: @escaping @Sendable (TenantFixture, Team, Team, Season, Season) async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(slug, federation: .rffm, schemaPrefix: prefix, on: app)
            let tenant = TenantFixture(app: app, slug: slug, schema: "\(prefix)\(slug)")
            func own(_ letter: String) throws -> Team {
                try Team(id: TeamID(raw: UUID()), category: .cadete, letter: letter, gender: .masculino,
                         modality: .futbol11, createdAt: now, updatedAt: now)
            }
            let (a, b) = (try own("A"), try own("B"))
            let vigente = try Season(id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
                                     federationSeasonID: nil, createdAt: now, updatedAt: now)
            let anterior = try Season(id: SeasonID(raw: UUID()), label: try SeasonLabel("2024/25"),
                                      federationSeasonID: nil, createdAt: now, updatedAt: now)
            try await tenant.scope {
                try await $0.teams.save(a)
                try await $0.teams.save(b)
                try await $0.seasons.save(vigente)
                try await $0.seasons.save(anterior)
            }
            try await body(tenant, a, b, vigente, anterior)
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func profile(_ name: String = "Juan García", full: Bool = true) throws -> PlayerProfile {
        PlayerProfile(
            id: PlayerProfileID(raw: UUID()), fullName: try PlayerName(name),
            birthYear: full ? try BirthYear(2011, notAfter: 2026) : nil,
            lastShirtNumber: full ? try ShirtNumber(9) : nil, lastPosition: full ? .delantero : nil,
            lastPhotoKey: full ? "club/foto.jpg" : nil, createdAt: now, updatedAt: now)
    }

    static func row(_ profile: PlayerProfile, _ team: Team, _ season: Season, full: Bool = true)
        throws -> Player
    {
        Player(id: PlayerID(raw: UUID()), profileID: profile.id, teamID: team.id, seasonID: season.id,
               shirtNumber: full ? try ShirtNumber(9) : nil, position: full ? .delantero : nil,
               photoKey: full ? "club/foto.jpg" : nil, createdAt: now, updatedAt: now)
    }

    @Test("el perfil y la fila van y vuelven enteros, llenos y vacíos (R6.6)")
    func roundTrip() async throws {
        try await Self.withFixture("rt") { tenant, a, _, vigente, _ in
            let lleno = try Self.profile()
            let vacio = try Self.profile("Pedro López", full: false)
            let filaLlena = try Self.row(lleno, a, vigente)
            let filaVacia = try Self.row(vacio, a, vigente, full: false)
            try await tenant.scope {
                try await $0.playerProfiles.save(lleno)
                try await $0.playerProfiles.save(vacio)
                try await $0.players.save(filaLlena)
                try await $0.players.save(filaVacia)
            }

            let (perfiles, filas) = try await tenant.scope { r in
                (try await r.playerProfiles.list(ids: [lleno.id, vacio.id]),
                 [try await r.players.find(filaLlena.id), try await r.players.find(filaVacia.id)])
            }
            let p1 = try #require(perfiles.first { $0.id == lleno.id })
            #expect(p1.fullName.value == "JUAN GARCÍA")
            #expect(p1.birthYear?.value == 2011)
            #expect(p1.lastShirtNumber?.value == 9)
            #expect(p1.lastPosition == .delantero)
            #expect(p1.lastPhotoKey == "club/foto.jpg")
            let p2 = try #require(perfiles.first { $0.id == vacio.id })
            #expect(p2.birthYear == nil && p2.lastShirtNumber == nil && p2.lastPosition == nil
                    && p2.lastPhotoKey == nil)

            let f1 = try #require(filas[0])
            #expect(f1.profileID == lleno.id && f1.teamID == a.id && f1.seasonID == vigente.id)
            #expect(f1.shirtNumber?.value == 9 && f1.position == .delantero && f1.photoKey == "club/foto.jpg")
            let f2 = try #require(filas[1])
            #expect(f2.shirtNumber == nil && f2.position == nil && f2.photoKey == nil)
        }
    }

    @Test("guardar con el mismo id actualiza, no crea otra (R6.6)")
    func saveIsUpsert() async throws {
        try await Self.withFixture("upsert") { tenant, a, _, vigente, _ in
            let juan = try Self.profile()
            let fila = try Self.row(juan, a, vigente)
            try await tenant.scope {
                try await $0.playerProfiles.save(juan)
                try await $0.players.save(fila)
            }
            try await tenant.scope {
                try await $0.players.save(Player(
                    id: fila.id, profileID: juan.id, teamID: a.id, seasonID: vigente.id,
                    shirtNumber: nil, position: .portero, createdAt: Self.now, updatedAt: Self.now))
            }
            let roster = try await tenant.scope { try await $0.players.list(teamID: a.id, seasonID: vigente.id) }
            #expect(roster.count == 1)
            #expect(roster.first?.shirtNumber == nil)
            #expect(roster.first?.position == .portero)
        }
    }

    @Test("las listas son de ese par, y la baja es lógica: no se ve, pero sigue en la tabla (D-36)")
    func listsAndSoftDelete() async throws {
        try await Self.withFixture("lists") { tenant, a, b, vigente, anterior in
            let juan = try Self.profile()
            let pedro = try Self.profile("Pedro López")
            let enA = try Self.row(juan, a, vigente)
            let pasado = try Self.row(juan, a, anterior)
            let enB = try Self.row(pedro, b, vigente)
            try await tenant.scope {
                try await $0.playerProfiles.save(juan)
                try await $0.playerProfiles.save(pedro)
                for fila in [enA, pasado, enB] { try await $0.players.save(fila) }
            }

            let (deA, deJuan) = try await tenant.scope { r in
                (try await r.players.list(teamID: a.id, seasonID: vigente.id),
                 try await r.players.list(profileID: juan.id, seasonID: vigente.id))
            }
            #expect(deA.map(\.id) == [enA.id])
            #expect(deJuan.map(\.id) == [enA.id])

            try await tenant.scope { try await $0.players.delete(enA.id) }
            let (despues, buscado) = try await tenant.scope { r in
                (try await r.players.list(teamID: a.id, seasonID: vigente.id),
                 try await r.players.find(enA.id))
            }
            #expect(despues.isEmpty)
            #expect(buscado == nil)
            let borrado = try await tenant.raw.raw("""
                SELECT count(*) AS n FROM \(ident: tenant.schema).players
                WHERE id = \(bind: enA.id.raw) AND deleted_at IS NOT NULL
                """).first(decodingColumn: "n", as: Int.self)
            #expect(borrado == 1, "la fila sigue, con su deleted_at")
        }
    }
}

// ── El buscador del alta (R6.7) ──────────────────────────────────────────────

extension PlayerRepositoryTests {
    static func search(_ tenant: TenantFixture, _ query: String, team: Team, season: Season,
                       limit: Int = 10) async throws -> [String] {
        let search = try #require(PlayerSearch(query))
        return try await tenant.scope {
            try await $0.playerProfiles.search(search, excludingRosterOf: team.id, seasonID: season.id,
                                               limit: limit)
        }.map(\.fullName.value)
    }

    /// La base pliega con `translate` y la misma tabla que `PlayerSearch`: lo que
    /// prueba este test es que las dos encuentran lo mismo, con tildes, diéresis,
    /// eñe, guion y apóstrofo de por medio.
    @Test("la base encuentra sin tildes, palabra a palabra y con la eñe como «n» (D-120)")
    func searchFolds() async throws {
        try await Self.withFixture("search") { tenant, a, _, vigente, _ in
            try await tenant.scope {
                for name in ["José Muñoz", "Lucía Güell", "Ana Pérez-Gil", "Liam O'Brien",
                             "Juan García Fuente", "João Silva"] {
                    try await $0.playerProfiles.save(try Self.profile(name, full: false))
                }
            }
            #expect(try await Self.search(tenant, "jose munoz", team: a, season: vigente) == ["JOSÉ MUÑOZ"])
            #expect(try await Self.search(tenant, "guell", team: a, season: vigente) == ["LUCÍA GÜELL"])
            #expect(try await Self.search(tenant, "gil", team: a, season: vigente) == ["ANA PÉREZ-GIL"])
            #expect(try await Self.search(tenant, "brien", team: a, season: vigente) == ["LIAM O'BRIEN"])
            #expect(try await Self.search(tenant, "fuen juan", team: a, season: vigente) == ["JUAN GARCÍA FUENTE"])
            #expect(try await Self.search(tenant, "joao", team: a, season: vigente) == ["JOÃO SILVA"])
            #expect(try await Self.search(tenant, "arcia", team: a, season: vigente).isEmpty,
                    "el comienzo de una palabra, no un trozo de en medio")
        }
    }

    @Test("sin los de esa plantilla, con los dados de baja, por nombre y hasta el límite (D-120)")
    func searchScope() async throws {
        try await Self.withFixture("searchscope") { tenant, a, b, vigente, anterior in
            let enA = try Self.profile("Juan Ruiz")
            let deBaja = try Self.profile("Juan Sanz")
            let enB = try Self.profile("Juan Pérez")
            let pasado = try Self.profile("Juan Gil")
            let filaBaja = try Self.row(deBaja, a, vigente, full: false)
            try await tenant.scope {
                for p in [enA, deBaja, enB, pasado] { try await $0.playerProfiles.save(p) }
                try await $0.players.save(try Self.row(enA, a, vigente, full: false))
                try await $0.players.save(filaBaja)
                try await $0.players.save(try Self.row(enB, b, vigente, full: false))
                try await $0.players.save(try Self.row(pasado, a, anterior, full: false))
            }
            try await tenant.scope { try await $0.players.delete(filaBaja.id) }

            #expect(try await Self.search(tenant, "juan", team: a, season: vigente)
                    == ["JUAN GIL", "JUAN PÉREZ", "JUAN SANZ"])
            #expect(try await Self.search(tenant, "juan", team: a, season: vigente, limit: 2)
                    == ["JUAN GIL", "JUAN PÉREZ"])

            let filas = try await tenant.scope { try await $0.players.list(profileIDs: [pasado.id, deBaja.id]) }
            #expect(filas.map(\.seasonID) == [anterior.id], "las no borradas, de cualquier temporada")
        }
    }
}

// ── La foto en uso (R6.9) ────────────────────────────────────────────────────

extension PlayerRepositoryTests {
    @Test("una foto está en uso si la tiene una fila, también dada de baja, o un perfil (D-35, D-122)")
    func photoInUse() async throws {
        try await Self.withFixture("photouse") { tenant, a, _, vigente, _ in
            let juan = try Self.profile(full: false)
            let fila = try Self.row(juan, a, vigente, full: false)
            try await tenant.scope {
                try await $0.playerProfiles.save(juan)
                try await $0.players.save(fila)
            }
            func inUse(_ key: String) async throws -> Bool {
                try await tenant.scope { try await $0.players.isPhotoInUse(key) }
            }
            #expect(try await inUse("club/nadie.jpg") == false)

            try await tenant.scope {
                try await $0.players.save(fila.with(photoKey: "club/fila.jpg", updatedAt: Self.now))
            }
            #expect(try await inUse("club/fila.jpg"))
            try await tenant.scope { try await $0.players.delete(fila.id) }
            #expect(try await inUse("club/fila.jpg"), "la baja no la suelta: se puede deshacer")

            try await tenant.scope {
                try await $0.playerProfiles.save(PlayerProfile(
                    id: juan.id, fullName: juan.fullName, birthYear: nil, lastPhotoKey: "club/perfil.jpg",
                    createdAt: Self.now, updatedAt: Self.now))
            }
            #expect(try await inUse("club/perfil.jpg"))
        }
    }
}

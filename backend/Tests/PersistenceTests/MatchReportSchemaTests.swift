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

/// Nivel 3 (§8.1): las tablas del acta (R7.5) y lo que escribe en el partido y en
/// el perfil.
///
/// Lo que se prueba aquí son **las reglas que la base sostiene**: las que miran
/// varias filas a la vez (una convocatoria por jugador y partido, una tarjeta de
/// cada tipo, un código de la federación por club) y los `CHECK` entre columnas,
/// que protegen la tabla de la ingesta y de los *scripts* ([D-28]). Se atacan con
/// SQL crudo, como lo haría un *script*: los repositorios llegan en la R7.6.
@Suite("MatchReport · D-126 a D-137 · las tablas del acta y sus reglas",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct MatchReportSchemaTests {

    static let prefix = "test_report_"

    /// Un club con **un partido entre su equipo y un rival**, y un jugador en la
    /// plantilla del equipo.
    struct Fixture: Sendable {
        let tenant: TenantFixture
        let match: UUID
        let own: UUID
        let rival: UUID
        let player: UUID
        let otherPlayer: UUID

        var schema: String { tenant.schema }
        var sql: any SQLDatabase { tenant.raw }

        func appearance(player: UUID? = nil, status: String = "convocado_sin_minutos",
                        minutes: Int? = nil, deleted: Bool = false) async throws {
            try await sql.raw("""
                INSERT INTO \(ident: schema).appearances
                  (id, player_id, match_id, team_id, status, minutes, deleted_at)
                VALUES (\(bind: UUID()), \(bind: player ?? self.player), \(bind: match), \(bind: own),
                        \(bind: status), \(bind: minutes), \(unsafeRaw: deleted ? "now()" : "NULL"))
                """).run()
        }

        func card(type: String = "amarilla", secondYellow: Bool = false, deleted: Bool = false) async throws {
            try await sql.raw("""
                INSERT INTO \(ident: schema).cards
                  (id, player_id, match_id, team_id, type, is_second_yellow, deleted_at)
                VALUES (\(bind: UUID()), \(bind: player), \(bind: match), \(bind: own), \(bind: type),
                        \(bind: secondYellow), \(unsafeRaw: deleted ? "now()" : "NULL"))
                """).run()
        }

        /// Un gol del equipo propio, con lo que se le pase en SQL.
        func goal(_ columns: String = "", _ values: String = "") async throws {
            let extraColumns = columns.isEmpty ? "" : ", \(columns)"
            let extraValues = values.isEmpty ? "" : ", \(values)"
            try await sql.raw("""
                INSERT INTO \(ident: schema).goals
                  (id, match_id, scoring_team_id, conceding_team_id, scorer_player_id\(unsafeRaw: extraColumns))
                VALUES (\(bind: UUID()), \(bind: match), \(bind: own), \(bind: rival),
                        \(bind: player)\(unsafeRaw: extraValues))
                """).run()
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
            let sql = tenant.raw
            let schema = tenant.schema

            let (season, competition, round, club) = (UUID(), UUID(), UUID(), UUID())
            let (own, rival, match) = (UUID(), UUID(), UUID())
            try await sql.raw("""
                INSERT INTO \(ident: schema).seasons (id, label, start_date, end_date)
                VALUES (\(bind: season), '2025/26', '2025-07-01', '2026-06-30')
                """).run()
            try await sql.raw("""
                INSERT INTO \(ident: schema).competitions (id, season_id, modality, gender, age_category,
                    federation_competition_id, federation_group_id, division_label, group_label)
                VALUES (\(bind: competition), \(bind: season), 'futbol_11', 'masculino', 'cadete',
                    '1', '2', 'Primera', 'Grupo 1')
                """).run()
            try await sql.raw("""
                INSERT INTO \(ident: schema).rounds (id, competition_id, number, start_date, end_date)
                VALUES (\(bind: round), \(bind: competition), 1, '2025-09-13', '2025-09-14')
                """).run()
            try await sql.raw("""
                INSERT INTO \(ident: schema).opponent_clubs (id, name, short_name, slug)
                VALUES (\(bind: club), 'C.D. LOS ALMENDROS', 'Los Almendros', 'cd-los-almendros')
                """).run()
            try await sql.raw("""
                INSERT INTO \(ident: schema).teams (id, opponent_club_id, season_id, category, letter, gender, modality)
                VALUES (\(bind: own), NULL, NULL, 'cadete', 'A', 'masculino', 'futbol_11'),
                       (\(bind: rival), \(bind: club), \(bind: season), 'cadete', 'B', 'masculino', 'futbol_11')
                """).run()
            try await sql.raw("""
                INSERT INTO \(ident: schema).matches (id, competition_id, round_id, match_date, home_team_id, away_team_id, status)
                VALUES (\(bind: match), \(bind: competition), \(bind: round), '2025-09-13', \(bind: own), \(bind: rival), 'finalizado')
                """).run()

            func player(_ name: String) async throws -> UUID {
                let (profile, row) = (UUID(), UUID())
                try await sql.raw("""
                    INSERT INTO \(ident: schema).player_profiles (id, full_name) VALUES (\(bind: profile), \(bind: name))
                    """).run()
                try await sql.raw("""
                    INSERT INTO \(ident: schema).players (id, profile_id, team_id, season_id)
                    VALUES (\(bind: row), \(bind: profile), \(bind: own), \(bind: season))
                    """).run()
                return row
            }
            let fixture = Fixture(tenant: tenant, match: match, own: own, rival: rival,
                                  player: try await player("JUAN GARCÍA"),
                                  otherPlayer: try await player("PEDRO LÓPEZ"))

            try await body(fixture)
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    static func isUniqueViolation(_ error: any Error, index: String) -> Bool {
        let text = String(reflecting: error)
        return text.contains("23505") && text.contains(index)
    }

    static func isCheckViolation(_ error: any Error, check: String) -> Bool {
        let text = String(reflecting: error)
        return text.contains("23514") && text.contains(check)
    }

    // ── La convocatoria ─────────────────────────────────────────────────────

    @Test("un jugador tiene una sola convocatoria en un partido (§3.5)")
    func oneAppearancePerPlayerAndMatch() async throws {
        try await Self.withFixture("app_unique") { f in
            try await f.appearance()
            await #expect {
                try await f.appearance(status: "baja_medica")
            } throws: { Self.isUniqueViolation($0, index: "uq_appearances") }
        }
    }

    @Test("borrada la convocatoria, se puede volver a apuntar (D-134: anular es borrar)")
    func deletedAppearanceFreesThePlayer() async throws {
        try await Self.withFixture("app_again") { f in
            try await f.appearance(deleted: true)
            try await f.appearance(status: "sancionado")
        }
    }

    @Test("«No convocado» no es un estado (D-134)")
    func noConvocadoIsNotAStatus() async throws {
        try await Self.withFixture("app_status") { f in
            await #expect {
                try await f.appearance(status: "no_convocado")
            } throws: { Self.isCheckViolation($0, check: "chk_appearances_status") }
        }
    }

    @Test("los minutos, solo con «Jugado» (D-42)")
    func minutesOnlyWhenPlayed() async throws {
        try await Self.withFixture("app_minutes") { f in
            try await f.appearance(status: "jugado", minutes: 70)
            await #expect {
                try await f.appearance(player: f.otherPlayer, status: "convocado_sin_minutos", minutes: 10)
            } throws: { Self.isCheckViolation($0, check: "chk_appearances_minutes_when_played") }
        }
    }

    @Test("los minutos van de 1 a 120 (D-134)")
    func minutesFromOne() async throws {
        try await Self.withFixture("app_zero") { f in
            await #expect {
                try await f.appearance(status: "jugado", minutes: 0)
            } throws: { Self.isCheckViolation($0, check: "chk_appearances_minutes") }
        }
    }

    // ── Las tarjetas ────────────────────────────────────────────────────────

    @Test("una tarjeta de cada tipo por jugador y partido; amarilla y roja conviven (D-45)")
    func oneCardOfEachType() async throws {
        try await Self.withFixture("card_unique") { f in
            try await f.card(type: "amarilla")
            try await f.card(type: "roja")
            await #expect {
                try await f.card(type: "amarilla")
            } throws: { Self.isUniqueViolation($0, index: "uq_cards") }
        }
    }

    @Test("la segunda amarilla es una roja (D-45)")
    func secondYellowIsRed() async throws {
        try await Self.withFixture("card_second") { f in
            await #expect {
                try await f.card(type: "amarilla", secondYellow: true)
            } throws: { Self.isCheckViolation($0, check: "chk_cards_second_yellow") }
        }
    }

    @Test("una tarjeta nueva no es del acta, sin decirlo (D-137)")
    func cardsAreNotFromTheReportByDefault() async throws {
        try await Self.withFixture("card_report") { f in
            try await f.card()
            let row = try await f.sql.raw(
                "SELECT from_report FROM \(ident: f.schema).cards").first(decoding: [String: Bool].self)
            #expect(row?["from_report"] == false)
        }
    }

    // ── Los goles ───────────────────────────────────────────────────────────

    @Test("un gol con solo el equipo que marca vale (D-135)")
    func bareGoal() async throws {
        try await Self.withFixture("goal_bare") { f in
            try await f.goal()
        }
    }

    @Test("un penalti no se tira fuera del área ni tiene lado del remate (D-135)")
    func penaltyShape() async throws {
        try await Self.withFixture("goal_penalty") { f in
            try await f.goal("play_type, zone", "'penalti', 'area_penalti'")
            await #expect {
                try await f.goal("play_type, zone", "'penalti', 'fuera_area'")
            } throws: { Self.isCheckViolation($0, check: "chk_goals_penalty") }
            await #expect {
                try await f.goal("play_type, shot_side", "'penalti', 'izquierda'")
            } throws: { Self.isCheckViolation($0, check: "chk_goals_penalty") }
        }
    }

    @Test("un gol en propia puerta no tiene asistencia (D-52)")
    func ownGoalWithoutAssist() async throws {
        try await Self.withFixture("goal_own") { f in
            await #expect {
                try await f.goal("play_type, assisted", "'en_propia_puerta', true")
            } throws: { Self.isCheckViolation($0, check: "chk_goals_own_goal_no_assist") }
        }
    }

    @Test("con asistente, hubo asistencia (D-52)")
    func assistNeedsAssisted() async throws {
        try await Self.withFixture("goal_assist") { f in
            await #expect {
                try await f.goal("assist_player_id, assisted", "'\(f.otherPlayer.uuidString)', false")
            } throws: { Self.isCheckViolation($0, check: "chk_goals_assist_when_assisted") }
        }
    }

    @Test("el pie, izquierdo o derecho; y el tipo «falta» ya no existe (D-135)")
    func newGoalEnumerations() async throws {
        try await Self.withFixture("goal_enums") { f in
            try await f.goal("body_part, play_type, attack_side, shot_side",
                             "'pie_izquierdo', 'tras_corner', 'izquierda', 'centro'")
            await #expect {
                try await f.goal("play_type", "'falta'")
            } throws: { Self.isCheckViolation($0, check: "chk_goals_play_type") }
        }
    }

    @Test("un comentario vacío no se guarda: es nulo (D-135)")
    func emptyCommentIsNull() async throws {
        try await Self.withFixture("goal_comment") { f in
            await #expect {
                try await f.goal("comment", "''")
            } throws: { Self.isCheckViolation($0, check: "chk_goals_comment") }
        }
    }

    // ── El partido y el perfil ──────────────────────────────────────────────

    @Test("la copia del acta va con la fecha de la carga (D-133, D-134)")
    func lineupNeedsLoadedAt() async throws {
        try await Self.withFixture("match_lineup") { f in
            await #expect {
                try await f.sql.raw("""
                    UPDATE \(ident: f.schema).matches SET report_lineup = '{"players":[]}'::jsonb
                    """).run()
            } throws: { Self.isCheckViolation($0, check: "chk_matches_report_lineup_when_loaded") }
            try await f.sql.raw("""
                UPDATE \(ident: f.schema).matches
                SET report_lineup = '{"players":[]}'::jsonb, report_loaded_at = now()
                """).run()
        }
    }

    @Test("un código de la federación es de un solo perfil del club; sin código, no chocan (D-126)")
    func federationCodeIsUniqueInTheClub() async throws {
        try await Self.withFixture("profile_code") { f in
            func profile(_ name: String, code: String?) async throws {
                try await f.sql.raw("""
                    INSERT INTO \(ident: f.schema).player_profiles (id, full_name, federation_player_id)
                    VALUES (\(bind: UUID()), \(bind: name), \(bind: code))
                    """).run()
            }
            try await profile("ANA PÉREZ", code: "123")
            try await profile("EVA RUIZ", code: nil)
            try await profile("LUIS SANZ", code: nil)
            await #expect {
                try await profile("RAÚL GIL", code: "123")
            } throws: { Self.isUniqueViolation($0, index: "uq_player_profiles_federation_player") }
        }
    }

    @Test("purgar el partido se lleva su acta (D-24)")
    func deletingTheMatchCascades() async throws {
        try await Self.withFixture("reportcascade") { f in
            try await f.appearance()
            try await f.card()
            try await f.goal()
            try await f.sql.raw("DELETE FROM \(ident: f.schema).matches").run()
            for table in ["appearances", "cards", "goals"] {
                let row = try await f.sql.raw(
                    "SELECT count(*)::int AS n FROM \(ident: f.schema).\(ident: table)"
                ).first(decoding: [String: Int].self)
                #expect(row?["n"] == 0, "quedan filas en \(table)")
            }
        }
    }
}

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

/// Nivel 3 (§8.1): las cuatro tablas de la **salida** de la ingesta.
///
/// **Un test por adaptador, no por regla** (Plan §5): lo que se prueba aquí es el
/// **mapeo** y las **restricciones**, no la política de §3.7 — ésa ya la cubrió
/// el nivel 1 en milisegundos, y volver a probarla contra Postgres sería pagarla
/// dos veces.
@Suite("Ingesta · §4.4 · el mapeo de las cuatro entidades y las claves de §3.5",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct IngestionPersistenceTests {

    static let prefix = "test_ingest_"

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

    /// Siembra temporada y competición por repositorio, que es de donde cuelgan
    /// `Round` y `Match`.
    static func withCompetition(
        _ slug: String,
        _ body: @escaping @Sendable (CompetitionID, TenantFixture) async throws -> Void
    ) async throws {
        try await withTenant(slug) { tenant in
            let season = try Season(
                id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
                federationSeasonID: "21", createdAt: Date(), updatedAt: Date())
            let competition = try Competition(
                id: CompetitionID(raw: UUID()), seasonID: season.id,
                modality: .futbol11, gender: .masculino,
                federationCompetitionID: "24037548", federationGroupID: "24037549",
                ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
                groupLabel: "Grupo 1", createdAt: Date(), updatedAt: Date())
            try await tenant.scope {
                try await $0.seasons.save(season)
                try await $0.competitions.save(competition)
            }
            try await body(competition.id, tenant)
        }
    }

    static func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "dd-MM-yyyy"
        return f.date(from: iso)!
    }

    // ── La trampa de los NULL en la clave de Team (§3.5) ────────────────────

    /// §3.5 lo dice con todas las letras: *"en Postgres los `NULL` **no comparan
    /// iguales**, así que un `UNIQUE` normal **no protegería a los equipos
    /// propios** — se podrían crear dos «Infantil A» propios"*.
    ///
    /// Este es el test que separa el `UNIQUE` que parece correcto del que lo es,
    /// y **no se puede escribir en el nivel 1**: la regla no vive en el tipo,
    /// vive en el índice. Es exactamente lo que Plan §5 llama probar el adaptador.
    @Test("dos equipos propios iguales no caben: el UNIQUE es NULLS NOT DISTINCT (§3.5)")
    func ownTeamsCollideDespiteTheNullClubID() async throws {
        try await Self.withTenant("team-nulls") { tenant in
            try await tenant.scope {
                try await $0.teams.save(try Team(
                    id: TeamID(raw: UUID()), opponentClubID: nil,
                    category: .cadete, letter: "A", gender: .masculino,
                    modality: .futbol11, createdAt: Date(), updatedAt: Date()))
            }

            // Ámbito propio: una violación de restricción aborta la transacción
            // entera (`25P02`), así que el intento que debe fallar va solo.
            await #expect(throws: (any Error).self) {
                try await tenant.scope {
                    try await $0.teams.save(try Team(
                        id: TeamID(raw: UUID()), opponentClubID: nil,
                        category: .cadete, letter: "A", gender: .masculino,
                        modality: .futbol11, createdAt: Date(), updatedAt: Date()))
                }
            }
        }
    }

    /// El reverso, y hace falta: la letra **también** es anulable, y es la otra
    /// columna de la clave que un `UNIQUE` normal dejaría duplicar. Un club sin
    /// filial tiene un solo equipo por categoría, y ese `nil` **es un valor**.
    @Test("dos equipos propios sin letra tampoco caben (§3.5)")
    func ownTeamsWithoutLetterAlsoCollide() async throws {
        try await Self.withTenant("team-noletter") { tenant in
            try await tenant.scope {
                try await $0.teams.save(try Team(
                    id: TeamID(raw: UUID()), opponentClubID: nil,
                    category: .juvenil, letter: nil, gender: .femenino,
                    modality: .futbolSala, createdAt: Date(), updatedAt: Date()))
            }

            await #expect(throws: (any Error).self) {
                try await tenant.scope {
                    try await $0.teams.save(try Team(
                        id: TeamID(raw: UUID()), opponentClubID: nil,
                        category: .juvenil, letter: nil, gender: .femenino,
                        modality: .futbolSala, createdAt: Date(), updatedAt: Date()))
                }
            }
        }
    }

    /// Y el criterio **opuesto** en la misma tabla (§3.5): en
    /// `federation_team_id` el comportamiento por defecto es el que se quiere —
    /// muchos equipos sin enganchar, y ningún `codigo_equipo` repetido. Si aquí
    /// se hubiera aplicado `NULLS NOT DISTINCT` por simetría, **un solo equipo
    /// sin enganchar** sería el máximo que el club podría tener.
    @Test("muchos equipos sin codigo_equipo sí caben (§3.5, criterio opuesto)")
    func manyTeamsWithoutFederationKeyFit() async throws {
        try await Self.withTenant("team-nokey") { tenant in
            let stored = try await tenant.scope { repositories -> [Team] in
                try await repositories.teams.save(try Team(
                    id: TeamID(raw: UUID()), opponentClubID: nil,
                    category: .cadete, letter: "A", gender: .masculino,
                    modality: .futbol11, federationTeamID: nil,
                    createdAt: Date(), updatedAt: Date()))
                try await repositories.teams.save(try Team(
                    id: TeamID(raw: UUID()), opponentClubID: nil,
                    category: .cadete, letter: "B", gender: .masculino,
                    modality: .futbol11, federationTeamID: nil,
                    createdAt: Date(), updatedAt: Date()))
                return try await repositories.teams.list()
            }

            #expect(stored.count == 2)
            #expect(stored.allSatisfy { $0.federationTeamID == nil })
        }
    }

    // ── Ida y vuelta de las cuatro entidades (§4.4) ─────────────────────────

    @Test("OpponentClub: guarda y recupera la entidad entera, anulables incluidos (§4.4)")
    func opponentClubRoundTrip() async throws {
        try await Self.withTenant("club-rt") { tenant in
            let original = try OpponentClub(
                id: OpponentClubID(raw: UUID()),
                name: "CELTIC CASTILLA C.F.",
                shortName: "Celtic Castilla",
                slug: try Slug(derivedFrom: "CELTIC CASTILLA C.F."),
                federationClubID: "0010940034",
                crestKey: "clubs/celtic-castilla-c-f/crest.png",
                createdAt: Date(), updatedAt: Date())

            let stored = try await tenant.scope { repositories -> [OpponentClub] in
                try await repositories.opponentClubs.save(original)
                return try await repositories.opponentClubs.list()
            }

            #expect(stored.count == 1)
            #expect(stored[0].id == original.id)
            #expect(stored[0].name == "CELTIC CASTILLA C.F.")
            #expect(stored[0].shortName == "Celtic Castilla")
            #expect(stored[0].slug.value == "celtic-castilla-c-f")
            #expect(stored[0].federationClubID == "0010940034")
            #expect(stored[0].crestKey == "clubs/celtic-castilla-c-f/crest.png")
        }
    }

    @Test("Team: guarda y recupera, con sus tres enumerados y su club (§4.4)")
    func teamRoundTrip() async throws {
        try await Self.withTenant("team-rt") { tenant in
            let club = try OpponentClub(
                id: OpponentClubID(raw: UUID()), name: "C.D. GALAPAGAR",
                shortName: "Galapagar", slug: try Slug(derivedFrom: "C.D. GALAPAGAR"),
                createdAt: Date(), updatedAt: Date())
            let team = try Team(
                id: TeamID(raw: UUID()), opponentClubID: club.id,
                category: .cadete, letter: "B", gender: .masculino,
                modality: .futbol11, federationTeamID: "304468",
                createdAt: Date(), updatedAt: Date())

            let stored = try await tenant.scope { repositories -> [Team] in
                try await repositories.opponentClubs.save(club)
                try await repositories.teams.save(team)
                return try await repositories.teams.list()
            }

            #expect(stored.count == 1)
            #expect(stored[0].opponentClubID == club.id)
            #expect(stored[0].category == .cadete)
            #expect(stored[0].letter == "B")
            #expect(stored[0].gender == .masculino)
            #expect(stored[0].modality == .futbol11)
            #expect(stored[0].federationTeamID == "304468")
            #expect(!stored[0].isOwn)
        }
    }

    /// Ida y vuelta **y el día exacto**. Las dos columnas son `date` en Postgres,
    /// así que el huso no forma parte del dato: si la fecha se construyera en
    /// `Europe/Madrid` —UTC+1/+2—, la medianoche local caería el día **anterior**
    /// en UTC y la jornada 1 se guardaría empezando el 26. Es la misma trampa que
    /// `SeasonLabel` documenta, y aquí la fuente de fechas es la federación.
    @Test("Round: guarda y recupera, y no se deja un día por el camino (§4.4)")
    func roundRoundTrip() async throws {
        try await Self.withCompetition("round-rt") { competitionID, tenant in
            let round = try Round(
                id: RoundID(raw: UUID()), competitionID: competitionID, number: 1,
                startDate: Self.date("27-09-2025"), endDate: Self.date("28-09-2025"),
                createdAt: Date(), updatedAt: Date())

            let stored = try await tenant.scope { repositories -> [Round] in
                try await repositories.rounds.save(round)
                return try await repositories.rounds.list(competitionID: competitionID)
            }

            #expect(stored.count == 1)
            #expect(stored[0].number == 1)
            #expect(stored[0].startDate == Self.date("27-09-2025"))
            #expect(stored[0].endDate == Self.date("28-09-2025"))
        }
    }

    /// El partido entero, con las tres piezas que el esquema **no** sabe
    /// expresar y reconstruye el mapeo: el par del marcador, la hora de reloj
    /// como texto `HH:mm` y el `Kickoff` con sus dos mitades.
    @Test("Match: guarda y recupera el marcador, la hora y el estado (§4.4)")
    func matchRoundTrip() async throws {
        try await Self.withCompetition("match-rt") { competitionID, tenant in
            let stored = try await tenant.scope { repositories -> [Match] in
                let (round, home, away) = try await Self.seed(
                    competitionID: competitionID, into: repositories)
                try await repositories.matches.save(try Match(
                    id: MatchID(raw: UUID()), competitionID: competitionID,
                    roundID: round, kickoff: Kickoff(
                        date: Self.date("27-09-2025"),
                        time: WallClockTime(hour: 10, minute: 45)),
                    homeTeamID: home, awayTeamID: away,
                    result: try MatchResult(homeScore: 3, awayScore: 3),
                    status: .finalizado, venue: "CANAL ISABEL II",
                    federationMatchID: "5374968",
                    createdAt: Date(), updatedAt: Date()))
                return try await repositories.matches.list(competitionID: competitionID)
            }

            #expect(stored.count == 1)
            #expect(stored[0].kickoff.date == Self.date("27-09-2025"))
            #expect(stored[0].kickoff.time == WallClockTime(hour: 10, minute: 45))
            #expect(stored[0].isKickoffConfirmed)
            #expect(stored[0].result == (try MatchResult(homeScore: 3, awayScore: 3)))
            #expect(stored[0].status == .finalizado)
            #expect(stored[0].venue == "CANAL ISABEL II")
            #expect(stored[0].federationMatchID == "5374968")
        }
    }

    /// Siembra una jornada y dos equipos propios, que es lo mínimo con lo que se
    /// puede insertar un partido.
    static func seed(
        competitionID: CompetitionID, into repositories: any Repositories
    ) async throws -> (RoundID, TeamID, TeamID) {
        let round = try Round(
            id: RoundID(raw: UUID()), competitionID: competitionID, number: 1,
            startDate: Self.date("27-09-2025"), endDate: Self.date("28-09-2025"),
            createdAt: Date(), updatedAt: Date())
        let home = try Team(
            id: TeamID(raw: UUID()), category: .cadete, letter: "A",
            gender: .masculino, modality: .futbol11,
            createdAt: Date(), updatedAt: Date())
        let away = try Team(
            id: TeamID(raw: UUID()), category: .cadete, letter: "B",
            gender: .masculino, modality: .futbol11,
            createdAt: Date(), updatedAt: Date())
        try await repositories.rounds.save(round)
        try await repositories.teams.save(home)
        try await repositories.teams.save(away)
        return (round.id, home.id, away.id)
    }

    // ── Las claves de §3.5 que sostienen la cadena de §3.7 ──────────────────

    /// §3.5: *"sin el índice único no sería una clave, solo una consulta"*. Es
    /// literalmente el **paso 2 de la cadena de emparejamiento** de §3.7, el que
    /// permite reconocer un partido cuando el proveedor no publica `codacta`.
    ///
    /// La asunción que lo sostiene está en `D-12`: no hay repeticiones dentro de
    /// la misma jornada — una eliminatoria a doble vuelta son **dos**.
    @Test("el mismo enfrentamiento no cabe dos veces en una jornada (§3.5, D-12)")
    func matchCoordinatesAreUnique() async throws {
        try await Self.withCompetition("match-uq") { competitionID, tenant in
            let seeded = try await tenant.scope { repositories -> (RoundID, TeamID, TeamID) in
                let seed = try await Self.seed(
                    competitionID: competitionID, into: repositories)
                try await repositories.matches.save(try Match(
                    id: MatchID(raw: UUID()), competitionID: competitionID,
                    roundID: seed.0, kickoff: Kickoff(date: Self.date("27-09-2025")),
                    homeTeamID: seed.1, awayTeamID: seed.2,
                    status: .programado, createdAt: Date(), updatedAt: Date()))
                return seed
            }

            // Otro `id`, otra fecha, otro `codacta`: solo coinciden las tres
            // columnas de la clave. Si el índice no estuviera, esto sería el
            // partido duplicado que `D-31` existe para evitar.
            await #expect(throws: (any Error).self) {
                try await tenant.scope {
                    try await $0.matches.save(try Match(
                        id: MatchID(raw: UUID()), competitionID: competitionID,
                        roundID: seeded.0, kickoff: Kickoff(date: Self.date("28-09-2025")),
                        homeTeamID: seeded.1, awayTeamID: seeded.2,
                        status: .programado, federationMatchID: "9999999",
                        createdAt: Date(), updatedAt: Date()))
                }
            }
        }
    }

    /// La otra unicidad de `Match` (§3.5): el `codacta` es el **paso 1** de la
    /// cadena, el exacto. `MatchingChain.byFederationKey` devuelve *el primero*
    /// sin comprobar si hay más precisamente porque este índice existe.
    @Test("dos partidos no pueden compartir codacta (§3.5, paso 1 de §3.7)")
    func federationMatchIDIsUnique() async throws {
        try await Self.withCompetition("match-acta") { competitionID, tenant in
            let seeded = try await tenant.scope { repositories -> (RoundID, TeamID, TeamID) in
                let seed = try await Self.seed(
                    competitionID: competitionID, into: repositories)
                try await repositories.matches.save(try Match(
                    id: MatchID(raw: UUID()), competitionID: competitionID,
                    roundID: seed.0, kickoff: Kickoff(date: Self.date("27-09-2025")),
                    homeTeamID: seed.1, awayTeamID: seed.2, status: .programado,
                    federationMatchID: "5374968", createdAt: Date(), updatedAt: Date()))
                return seed
            }

            // Equipos cruzados: la clave de coordenadas es distinta, así que lo
            // único que puede rechazarlo es el `UNIQUE` del codacta.
            await #expect(throws: (any Error).self) {
                try await tenant.scope {
                    try await $0.matches.save(try Match(
                        id: MatchID(raw: UUID()), competitionID: competitionID,
                        roundID: seeded.0, kickoff: Kickoff(date: Self.date("27-09-2025")),
                        homeTeamID: seeded.2, awayTeamID: seeded.1, status: .programado,
                        federationMatchID: "5374968",
                        createdAt: Date(), updatedAt: Date()))
                }
            }
        }
    }

    /// §3.5: Único(competición, número). Es lo que permite que la pasada
    /// empareje jornadas por su `codjornada` sin cadena ninguna.
    @Test("una competición no tiene dos jornadas con el mismo número (§3.5)")
    func roundNumberIsUniquePerCompetition() async throws {
        try await Self.withCompetition("round-uq") { competitionID, tenant in
            try await tenant.scope {
                try await $0.rounds.save(try Round(
                    id: RoundID(raw: UUID()), competitionID: competitionID, number: 1,
                    startDate: Self.date("27-09-2025"), endDate: Self.date("28-09-2025"),
                    createdAt: Date(), updatedAt: Date()))
            }

            await #expect(throws: (any Error).self) {
                try await tenant.scope {
                    try await $0.rounds.save(try Round(
                        id: RoundID(raw: UUID()), competitionID: competitionID, number: 1,
                        startDate: Self.date("04-10-2025"), endDate: Self.date("05-10-2025"),
                        createdAt: Date(), updatedAt: Date()))
                }
            }
        }
    }

    // ── La cascada de D-73, ahora con dos escalones más ─────────────────────

    /// `D-73` diseñó la purga de §5.4 como `ON DELETE CASCADE` bajo `Season`, y
    /// F1 lo comprobó con un solo escalón (`Season → Competition`). F5 le añade
    /// dos, así que hay que volver a verlo: borrar la competición tiene que
    /// llevarse **jornadas y partidos**.
    ///
    /// Y lo que **no** debe llevarse: los equipos. Cuelgan de `OpponentClub`, no
    /// de la competición, y por eso su FK se dejó sin cascada — si la tuviera,
    /// purgar una temporada borraría equipos que juegan en otras.
    @Test("borrar la competición se lleva jornadas y partidos, no equipos (D-73)")
    func deletingTheCompetitionCascades() async throws {
        try await Self.withCompetition("cascade") { competitionID, tenant in
            try await tenant.scope { repositories in
                let seed = try await Self.seed(
                    competitionID: competitionID, into: repositories)
                try await repositories.matches.save(try Match(
                    id: MatchID(raw: UUID()), competitionID: competitionID,
                    roundID: seed.0, kickoff: Kickoff(date: Self.date("27-09-2025")),
                    homeTeamID: seed.1, awayTeamID: seed.2,
                    status: .programado, createdAt: Date(), updatedAt: Date()))
            }

            try await tenant.raw.raw(
                "DELETE FROM \(ident: tenant.schema).\(ident: "competitions")").run()

            let after = try await tenant.scope { repositories in
                (rounds: try await repositories.rounds.list(competitionID: competitionID),
                 matches: try await repositories.matches.list(competitionID: competitionID),
                 teams: try await repositories.teams.list())
            }

            #expect(after.rounds.isEmpty)
            #expect(after.matches.isEmpty)
            #expect(after.teams.count == 2)
        }
    }

    // ── Lo que el esquema no sabe expresar (§4.4) ───────────────────────────

    /// `MatchResult` es **"los dos goles o ninguno"**, y el esquema son dos
    /// columnas anulables independientes: media fila es representable en SQL y no
    /// en el Dominio. El mapeo es el sitio donde esa invariante vuelve a existir,
    /// y lo trata como lo que es —corrupción— y no como un caso de negocio.
    ///
    /// Se escribe con SQL crudo porque **no hay forma de producirlo por el
    /// repositorio**: es exactamente lo que se quiere demostrar.
    @Test("media fila de marcador es corrupción, no un partido a medias (§4.4)")
    func halfAScoreIsCorruption() async throws {
        try await Self.withCompetition("half-score") { competitionID, tenant in
            let seeded = try await tenant.scope { repositories in
                try await Self.seed(competitionID: competitionID, into: repositories)
            }

            try await tenant.raw.raw("""
                INSERT INTO \(ident: tenant.schema).\(ident: "matches")
                (id, competition_id, round_id, match_date, home_team_id, away_team_id,
                 home_score, status, created_at, updated_at)
                VALUES (\(bind: UUID()), \(bind: competitionID.raw), \(bind: seeded.0.raw),
                        \(bind: Self.date("27-09-2025")), \(bind: seeded.1.raw),
                        \(bind: seeded.2.raw), 3, 'finalizado', now(), now())
                """).run()

            await #expect(throws: PersistenceError.self) {
                try await tenant.scope {
                    try await $0.matches.list(competitionID: competitionID)
                }
            }
        }
    }
}

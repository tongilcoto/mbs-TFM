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

/// Nivel 3 (§8.1): la tabla de [D-68], que F10 estrena.
///
/// Lo que se prueba aquí es el **mapeo** y las **restricciones** —la clave de
/// tres columnas con `NULLS NOT DISTINCT` y la FK compuesta—, no la política de
/// la cascada del enganche: ésa la cubrió el Bloque C en el nivel 2 y volver a
/// pagarla contra Postgres no diría nada nuevo.
@Suite("TeamRegistration · §4.4 · el mapeo, la clave de tres columnas y la FK compuesta",
       .serialized,
       .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct TeamRegistrationPersistenceTests {

    static let prefix = "test_treg_"

    /// Siembra un club con **un equipo propio, dos temporadas y una competición
    /// en la primera**. Las dos temporadas no son adorno: son lo que separa
    /// *"las de este par"* de *"todas las del equipo"*.
    static func withFixture(
        _ slug: String,
        _ body: @escaping @Sendable (Team, SeasonID, SeasonID, CompetitionID, TenantFixture)
            async throws -> Void
    ) async throws {
        try await TestEnvironment.withApp { app in
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
            try await TestEnvironment.provisionClub(
                slug, federation: .rffm, schemaPrefix: prefix, on: app)
            let tenant = TenantFixture(app: app, slug: slug, schema: "\(prefix)\(slug)")

            let team = try Team(
                id: TeamID(raw: UUID()), opponentClubID: nil,
                category: .cadete, letter: "A", gender: .masculino,
                modality: .futbol11, createdAt: Date(), updatedAt: Date())
            let vigente = try Season(
                id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
                federationSeasonID: "21", createdAt: Date(), updatedAt: Date())
            let anterior = try Season(
                id: SeasonID(raw: UUID()), label: try SeasonLabel("2024/25"),
                federationSeasonID: "20", createdAt: Date(), updatedAt: Date())
            let competicion = try Competition(
                id: CompetitionID(raw: UUID()), seasonID: vigente.id,
                modality: .futbol11, gender: .masculino,
                federationCompetitionID: "24037548", federationGroupID: "24037549",
                ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
                groupLabel: "Grupo 1", createdAt: Date(), updatedAt: Date())
            try await tenant.scope {
                try await $0.teams.save(team)
                try await $0.seasons.save(vigente)
                try await $0.seasons.save(anterior)
                try await $0.competitions.save(competicion)
            }

            try await body(team, vigente.id, anterior.id, competicion.id, tenant)
            try await TestEnvironment.dropClubs([slug], schemaPrefix: prefix, on: app)
        }
    }

    // ── C-D.2 · el mapeo ────────────────────────────────────────────────────

    /// Ida y vuelta, **con la competición nula**: es la fila de junio, el estado
    /// en el que la tabla nace y el que justifica que exista ([D-68]) — el club
    /// forma el equipo antes de que la federación publique calendario.
    ///
    /// **Y la consulta es por el par, no por el equipo.** Se siembra una
    /// inscripción en **otra temporada** a propósito: sin ese segundo renglón,
    /// un `list` que ignorara el filtro pasaría el test entero y la cascada del
    /// enganche vería inscripciones del año pasado como si fueran de éste.
    @Test("la inscripción va y vuelve entera, y list trae solo las de ese par (C-D.2, D-68)")
    func roundTrip() async throws {
        try await Self.withFixture("treg-rt") { team, vigente, anterior, _, tenant in
            // **El otro equipo del club, y lo pidió la mutación.** Con un solo
            // equipo sembrado, un `list` que ignorara el filtro de equipo daba
            // exactamente el mismo resultado y el test pasaba igual: `M4`
            // sobrevivía. Ahora el par tiene dos vecinos, uno por cada eje.
            let juvenilB = try Team(
                id: TeamID(raw: UUID()), opponentClubID: nil,
                category: .juvenil, letter: "B", gender: .masculino,
                modality: .futbol11, createdAt: Date(), updatedAt: Date())
            let deJunio = try TeamRegistration(
                id: TeamRegistrationID(raw: UUID()), team: team, seasonID: vigente,
                competitionID: nil, createdAt: Date(), updatedAt: Date())
            let delAnhoPasado = try TeamRegistration(
                id: TeamRegistrationID(raw: UUID()), team: team, seasonID: anterior,
                competitionID: nil, createdAt: Date(), updatedAt: Date())
            try await tenant.scope {
                try await $0.teams.save(juvenilB)
                try await $0.teamRegistrations.save(deJunio)
                try await $0.teamRegistrations.save(delAnhoPasado)
                try await $0.teamRegistrations.save(try TeamRegistration(
                    id: TeamRegistrationID(raw: UUID()), team: juvenilB,
                    seasonID: vigente, competitionID: nil,
                    createdAt: Date(), updatedAt: Date()))
            }

            let suyas = try await tenant.scope {
                try await $0.teamRegistrations.list(teamID: team.id, seasonID: vigente)
            }
            #expect(suyas.count == 1,
                    "las de ESE par: ni las del equipo en otra temporada, ni las del vecino")
            let stored = try #require(suyas.first)
            #expect(stored.id == deJunio.id)
            #expect(stored.teamID == team.id)
            #expect(stored.seasonID == vigente)
            #expect(stored.competitionID == nil, "la fila de junio: inscrito, sin competición")
        }
    }

    /// La otra mitad del mapeo: **la tercera columna con valor**, que es lo que
    /// la cascada del enganche escribe ([D-67]). Y completar la fila de junio es
    /// un `save` con el **mismo id** — no una fila nueva, que dejaría al equipo
    /// dos veces en la portada de §9.12.
    @Test("completar la fila de junio con su competición no crea una segunda (C-D.2, D-68)")
    func completingTheJuneRowKeepsOneRow() async throws {
        try await Self.withFixture("treg-complete") { team, vigente, _, competicion, tenant in
            let deJunio = try TeamRegistration(
                id: TeamRegistrationID(raw: UUID()), team: team, seasonID: vigente,
                competitionID: nil, createdAt: Date(), updatedAt: Date())
            try await tenant.scope { try await $0.teamRegistrations.save(deJunio) }

            let completada = try TeamRegistration(
                id: deJunio.id, team: team, seasonID: vigente,
                competitionID: competicion, createdAt: Date(), updatedAt: Date())
            try await tenant.scope { try await $0.teamRegistrations.save(completada) }

            let suyas = try await tenant.scope {
                try await $0.teamRegistrations.list(teamID: team.id, seasonID: vigente)
            }
            #expect(suyas.count == 1, "se completa, no se añade")
            #expect(suyas.first?.competitionID == competicion)
        }
    }
    // ── C-D.3 · las dos invariantes que bajan al esquema ────────────────────

    /// **La trampa de los `NULL`, por segunda vez en este modelo** (§3.5). La
    /// clave es `(team_id, season_id, competition_id)` y la tercera columna es
    /// anulable, así que con un `UNIQUE` normal dos filas `(equipo, temporada,
    /// NULL)` **no colisionan** —en Postgres los nulos no comparan iguales— y el
    /// mismo equipo sale dos veces en la portada de §9.12.
    ///
    /// Es literalmente lo que la clave de `Team` ya se comió en F5, y por eso
    /// [D-68] lo deja escrito: se paga una vez. **No se puede afirmar en el nivel
    /// 1**: la regla no vive en el tipo, vive en el índice.
    @Test("dos inscripciones sin competición no caben: NULLS NOT DISTINCT (C-D.3, D-68)")
    func twoOpenRegistrationsCollide() async throws {
        try await Self.withFixture("treg-nulls") { team, vigente, _, _, tenant in
            try await tenant.scope {
                try await $0.teamRegistrations.save(try TeamRegistration(
                    id: TeamRegistrationID(raw: UUID()), team: team, seasonID: vigente,
                    competitionID: nil, createdAt: Date(), updatedAt: Date()))
            }

            // Ámbito propio: una violación aborta la transacción entera (§6.2).
            await #expect(throws: (any Error).self) {
                try await tenant.scope {
                    try await $0.teamRegistrations.save(try TeamRegistration(
                        id: TeamRegistrationID(raw: UUID()), team: team, seasonID: vigente,
                        competitionID: nil, createdAt: Date(), updatedAt: Date()))
                }
            }
        }
    }

    /// El reverso, y hace falta por lo mismo que en el Bloque B: **toda guarda
    /// tiene dos mitades**, y la que no se afirma es por la que se cuela un
    /// índice demasiado estrecho. Un equipo sí juega dos competiciones en la
    /// misma temporada —liga y copa ([D-12])—, así que la clave tiene que dejar
    /// entrar la **segunda fila con competición**.
    @Test("liga y copa sí caben: son dos filas con competición distinta (C-D.3, D-12)")
    func twoCompetitionsInTheSameSeasonFit() async throws {
        try await Self.withFixture("treg-cup") { team, vigente, _, liga, tenant in
            let copa = try Competition(
                id: CompetitionID(raw: UUID()), seasonID: vigente,
                modality: .futbol11, gender: .masculino,
                federationCompetitionID: "24037600", federationGroupID: "24037601",
                ageCategory: .cadete, divisionLabel: "Copa", groupLabel: "Grupo 1",
                createdAt: Date(), updatedAt: Date())
            let stored = try await tenant.scope { repositories -> [TeamRegistration] in
                try await repositories.competitions.save(copa)
                try await repositories.teamRegistrations.save(try TeamRegistration(
                    id: TeamRegistrationID(raw: UUID()), team: team, seasonID: vigente,
                    competitionID: liga, createdAt: Date(), updatedAt: Date()))
                try await repositories.teamRegistrations.save(try TeamRegistration(
                    id: TeamRegistrationID(raw: UUID()), team: team, seasonID: vigente,
                    competitionID: copa.id, createdAt: Date(), updatedAt: Date()))
                return try await repositories.teamRegistrations.list(
                    teamID: team.id, seasonID: vigente)
            }

            #expect(stored.count == 2)
            #expect(Set(stored.compactMap(\.competitionID)) == [liga, copa.id])
        }
    }

    /// **La coherencia entre competición y temporada es una FK compuesta, no una
    /// guarda** (§4.6, [D-61]): `(competition_id, season_id) → competitions(id,
    /// season_id)`. Sin ella nada impide inscribir un equipo en una competición
    /// de **otra** temporada, y el desenlace es el de [D-58] —*"no degrada,
    /// colisiona"*—: la portada de §9.12 enseñaría al Cadete A en una competición
    /// del año pasado y la purga de la temporada no se la llevaría.
    ///
    /// Que no sea una guarda del caso de uso es la decisión, no el detalle: el
    /// backoffice tiene su propia puerta a esta tabla (`POST /v1/teams`, sin
    /// fase) y tendría que acordarse de escribirla otra vez. **Bajada al
    /// esquema, no es representable.**
    @Test("no cabe una inscripción en una competición de otra temporada (C-D.3, D-61)")
    func theCompetitionMustBelongToTheSeason() async throws {
        try await Self.withFixture("treg-fk") { team, _, anterior, deVigente, tenant in
            await #expect(throws: (any Error).self) {
                try await tenant.scope {
                    try await $0.teamRegistrations.save(try TeamRegistration(
                        id: TeamRegistrationID(raw: UUID()), team: team,
                        seasonID: anterior, competitionID: deVigente,
                        createdAt: Date(), updatedAt: Date()))
                }
            }
        }
    }

    // ── D-101 · el código del equipo, en la inscripción ─────────────────────

    /// **El código va y vuelve, y `list(competitionID:)` trae las de esa
    /// competición**, de todos los equipos propios: es lo que la pasada lee para
    /// reconocerlos (`D-101`). La de otra competición no sale.
    @Test("el código va y vuelve, y list por competición trae solo las suyas (D-101)")
    func theCodeRoundTripsAndListsByCompetition() async throws {
        try await Self.withFixture("treg-code") { team, vigente, anterior, liga, tenant in
            let previa = try Competition(
                id: CompetitionID(raw: UUID()), seasonID: anterior,
                modality: .futbol11, gender: .masculino,
                federationCompetitionID: "20000000", federationGroupID: "20000001",
                ageCategory: .cadete, divisionLabel: "Preferente", groupLabel: "Grupo 2",
                createdAt: Date(), updatedAt: Date())
            let aqui = try TeamRegistration(
                id: TeamRegistrationID(raw: UUID()), team: team, seasonID: vigente,
                competitionID: liga, federationTeamID: "33712",
                createdAt: Date(), updatedAt: Date())
            let elAnho = try TeamRegistration(
                id: TeamRegistrationID(raw: UUID()), team: team, seasonID: anterior,
                competitionID: previa.id, federationTeamID: "33710",
                createdAt: Date(), updatedAt: Date())

            let stored = try await tenant.scope { repositories -> [TeamRegistration] in
                try await repositories.competitions.save(previa)
                try await repositories.teamRegistrations.save(aqui)
                try await repositories.teamRegistrations.save(elAnho)
                return try await repositories.teamRegistrations.list(competitionID: liga)
            }

            #expect(stored.map(\.id) == [aqui.id])
            #expect(stored.first?.federationTeamID == "33712")
        }
    }

    /// **`UNIQUE (competition_id, federation_team_id)`**: en una competición, un
    /// código es de un solo equipo propio. El caso de uso lo pregunta antes
    /// (`C-E.10`); esto es lo que lo hace imposible.
    @Test("dos equipos propios con el mismo código en una competición no caben (D-101)")
    func twoOwnTeamsCannotShareACodeInACompetition() async throws {
        try await Self.withFixture("treg-uq") { team, vigente, _, liga, tenant in
            let otro = try Team(
                id: TeamID(raw: UUID()), opponentClubID: nil,
                category: .cadete, letter: "B", gender: .masculino,
                modality: .futbol11, createdAt: Date(), updatedAt: Date())
            try await tenant.scope {
                try await $0.teams.save(otro)
                try await $0.teamRegistrations.save(try TeamRegistration(
                    id: TeamRegistrationID(raw: UUID()), team: team, seasonID: vigente,
                    competitionID: liga, federationTeamID: "33712",
                    createdAt: Date(), updatedAt: Date()))
            }

            await #expect(throws: (any Error).self) {
                try await tenant.scope {
                    try await $0.teamRegistrations.save(try TeamRegistration(
                        id: TeamRegistrationID(raw: UUID()), team: otro, seasonID: vigente,
                        competitionID: liga, federationTeamID: "33712",
                        createdAt: Date(), updatedAt: Date()))
                }
            }
        }
    }

    /// **Los dos `CHECK` de `D-101`, contra el esquema y no contra el
    /// Dominio**: el Dominio ya los rechaza, así que se escriben con SQL crudo,
    /// que es por donde entrarían un *script* o una migración descuidada.
    @Test("ni un propio con código ni una fila de junio con código caben en la tabla (D-101)")
    func theSchemaRejectsCodesWhereTheyDoNotBelong() async throws {
        try await Self.withFixture("treg-chk") { team, vigente, _, _, tenant in
            let schema = tenant.schema
            await #expect(throws: (any Error).self) {
                try await tenant.raw.raw("""
                    UPDATE \(ident: schema).teams SET federation_team_id = '33712'
                    WHERE id = \(bind: team.id.raw)
                    """).run()
            }
            await #expect(throws: (any Error).self) {
                try await tenant.raw.raw("""
                    INSERT INTO \(ident: schema).team_registrations
                        (id, team_id, season_id, competition_id, federation_team_id)
                    VALUES (\(bind: UUID()), \(bind: team.id.raw), \(bind: vigente.raw), NULL, '33712')
                    """).run()
            }
        }
    }
}

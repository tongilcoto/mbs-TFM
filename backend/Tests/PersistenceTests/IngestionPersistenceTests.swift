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

    // ── F10 · C-D.1 · el equipo por su id ───────────────────────────────────

    /// **`TeamRepository.find(_:)`**, que hasta F10 no existía y no era un olvido:
    /// la ingesta carga la lista entera para emparejar (§3.7), así que nadie
    /// llegaba a un equipo **por su id**. El enganche sí — la ruta es
    /// `/v1/teams/{id}/federation-link` ([D-67]) y el equipo llega designado desde
    /// fuera.
    ///
    /// **Las dos mitades, y las dos hacen falta.** Que traiga **ése y no otro** es
    /// lo que separa esta consulta de `list().first`; que devuelva `nil` cuando no
    /// está es lo único sobre lo que `C-E.6` puede levantar su **404**, y sin esa
    /// mitad la ruta contestaría *"no existe"* y *"existe pero no lo encuentro"*
    /// con la misma cara.
    ///
    /// Se siembran **dos** equipos a propósito: con uno solo, una implementación
    /// que devolviera *"el primero que haya"* pasaría el test entero.
    @Test("find trae ese equipo y no otro, y nil si no está (C-D.1, D-67)")
    func findBringsTheDesignatedTeam() async throws {
        try await Self.withTenant("team-find") { tenant in
            let cadeteA = try Team(
                id: TeamID(raw: UUID()), opponentClubID: nil,
                category: .cadete, letter: "A", gender: .masculino,
                modality: .futbol11, createdAt: Date(), updatedAt: Date())
            let cadeteB = try Team(
                id: TeamID(raw: UUID()), opponentClubID: nil,
                category: .cadete, letter: "B", gender: .masculino,
                modality: .futbol11, createdAt: Date(), updatedAt: Date())
            try await tenant.scope {
                try await $0.teams.save(cadeteA)
                try await $0.teams.save(cadeteB)
            }

            let encontrado = try #require(
                try await tenant.scope { try await $0.teams.find(cadeteB.id) })
            #expect(encontrado.id == cadeteB.id)
            #expect(encontrado.letter == "B", "el designado, no el primero de la tabla")

            let ninguno = try await tenant.scope {
                try await $0.teams.find(TeamID(raw: UUID()))
            }
            #expect(ninguno == nil, "sobre esto levanta C-E.6 su 404")
        }
    }

    /// **`TeamRepository.lock(_:)`** (A-12·H-73): lo mismo que `find`, contra el
    /// `SELECT … FOR UPDATE` de verdad, que el doble del nivel 2 no tiene.
    ///
    /// **Lo que este test no puede afirmar, dicho**: que el bloqueo *espere*. Con
    /// el *pool* de tenant de una conexión (A-12·H-77) una segunda transacción no
    /// llega a abrirse mientras la primera vive, así que no hay con quién
    /// competir. Quitar el `FOR UPDATE` deja este test en verde, y lo seguirá
    /// dejando hasta que el *pool* crezca.
    @Test("lock trae ese equipo y no otro, y nil si no está (A-12·H-73)")
    func lockBringsTheDesignatedTeam() async throws {
        try await Self.withTenant("team-lock") { tenant in
            let cadeteA = try Team(
                id: TeamID(raw: UUID()), opponentClubID: nil,
                category: .cadete, letter: "A", gender: .masculino,
                modality: .futbol11, createdAt: Date(), updatedAt: Date())
            let cadeteB = try Team(
                id: TeamID(raw: UUID()), opponentClubID: nil,
                category: .cadete, letter: "B", gender: .masculino,
                modality: .futbol11, federationTeamID: "3349087",
                createdAt: Date(), updatedAt: Date())
            try await tenant.scope {
                try await $0.teams.save(cadeteA)
                try await $0.teams.save(cadeteB)
            }

            let bloqueado = try #require(
                try await tenant.scope { try await $0.teams.lock(cadeteB.id) })
            #expect(bloqueado.id == cadeteB.id)
            #expect(bloqueado.federationTeamID == "3349087")

            let ninguno = try await tenant.scope {
                try await $0.teams.lock(TeamID(raw: UUID()))
            }
            #expect(ninguno == nil)
        }
    }

    // ── Ida y vuelta de las cuatro entidades (§4.4) ─────────────────────────

    // ── F10-bis · B-1 · la fila aceptada cabe en la tabla ───────────────────

    /// **La migración de [D-96]**, y es lo primero de la mini-fase porque sin
    /// ella no hay nada que mirar: hoy `finished_at` es `NOT NULL` y el `CHECK`
    /// de `outcome` se derivó cuando el enumerado tenía dos casos, así que
    /// **ninguna fila `accepted` cabe en Postgres**.
    ///
    /// Que el Dominio ya la admita (`C-A.5`) no basta y es justo el reparto que
    /// §4.6 y [D-02] describen: la invariante vive en los dos sitios, y aquí se
    /// comprueba el de abajo.
    ///
    /// **Las dos mitades**, como toda guarda: que la fila aceptada entre y se
    /// lea, y que el par siga atado —una fila que diga *"aceptada"* **con** fecha
    /// de final no cabe—. Lo segundo se intenta por SQL crudo porque el Dominio
    /// no deja construirla: es el mismo motivo por el que `theKindCheckAdmits…`
    /// baja a `pg_constraint`.
    @Test("la pasada aceptada cabe en la tabla, y sin final (D-96, F10-bis)")
    func anAcceptedRunFitsInTheTable() async throws {
        try await Self.withCompetition("accepted-row") { competitionID, tenant in
            let run = try IngestionRun(
                id: IngestionRunID(raw: UUID()), competitionID: competitionID,
                kind: .calendar, startedAt: Self.date("13-09-2025"),
                finishedAt: nil, outcome: .accepted)

            _ = try await tenant.scope { try await $0.ingestionRuns.record(run) }

            let stored = try await tenant.scope {
                try await $0.ingestionRuns.list(competitionID: competitionID, limit: 10)
            }
            #expect(stored.count == 1)
            #expect(stored.first?.outcome == .accepted)
            #expect(stored.first?.finishedAt == nil)

            // La otra mitad: el par sigue atado en el esquema. Se ataca la tabla
            // como lo haría un *script*, que es contra quien el `CHECK` protege.
            await #expect(throws: (any Error).self) {
                try await tenant.raw.raw(
                    """
                    UPDATE \(ident: tenant.schema).\(ident: "ingestion_runs")
                    SET \(ident: "finished_at") = now()
                    WHERE \(ident: "id") = \(bind: run.id.raw)
                    """
                ).run()
            }
        }
    }

    // ── F10-bis · B-2 · `record` cierra lo que ya estaba abierto ────────────

    /// **`record` deja de ser solo-inserta, y es una enmienda a su propia
    /// documentación.**
    ///
    /// El puerto decía *"solo inserta: una pasada ocurrió o no ocurrió, y
    /// reescribir la historia de una sincronización no significa nada"*, y el
    /// argumento era bueno **mientras toda fila naciera acabada**. [D-96] crea la
    /// excepción y la crea entera: una fila `accepted` dice *"todavía no ha
    /// ocurrido"*, así que cerrarla no reescribe ninguna historia — **la
    /// termina**. Escribirla como fila nueva es lo que dejaría dos versiones de la
    /// misma pasada, que es lo que la cabecera de `closed(as:at:)` llama el peor
    /// desenlace posible.
    ///
    /// Lo que se afirma es por el `id`, que es la identidad de la pasada: dos
    /// escrituras del mismo `id` son **una** fila, con lo último que se dijo.
    @Test("escribir dos veces la misma pasada la cierra, no la duplica (D-96, F10-bis)")
    func recordingTwiceClosesTheSameRow() async throws {
        try await Self.withCompetition("run-upsert") { competitionID, tenant in
            let accepted = try IngestionRun(
                id: IngestionRunID(raw: UUID()), competitionID: competitionID,
                kind: .calendar, startedAt: Self.date("13-09-2025"),
                finishedAt: nil, outcome: .accepted)
            _ = try await tenant.scope { try await $0.ingestionRuns.record(accepted) }

            var pass = try accepted.closed(as: .succeeded, at: Self.date("14-09-2025"))
            pass.matchesCreated = 240
            let closed = pass
            _ = try await tenant.scope { try await $0.ingestionRuns.record(closed) }

            let stored = try await tenant.scope {
                try await $0.ingestionRuns.list(competitionID: competitionID, limit: 10)
            }

            #expect(stored.count == 1, "la pasada quedó duplicada: \(stored.count) filas")
            #expect(stored.first?.id == accepted.id)
            #expect(stored.first?.outcome == .succeeded)
            #expect(stored.first?.finishedAt == Self.date("14-09-2025"))
            // **Y `started_at` no se toca**, que es lo que `C-A.6` decidió: es
            // cuándo se PIDIÓ, que es lo que el `202` dejó para consultar.
            #expect(stored.first?.startedAt == Self.date("13-09-2025"))
            // Los contadores son los de la pasada, no los ceros de la aceptada.
            #expect(stored.first?.matchesCreated == 240)
        }
    }

    /// **Lo que otra pasada ya cerró no se pisa** (A-11·H-55).
    ///
    /// Dos pasadas que adoptan la misma fila la leen **abierta** las dos, y
    /// `closed(as:)` no puede saber que la otra se le adelantó. Con el *upsert*
    /// ciego, la segunda escribía encima: medido, una fila `succeeded` con su
    /// partido escrito pasaba a `failed` con los contadores a cero. La segunda
    /// escritura del mismo `id` sobre una fila **ya cerrada** no toca nada y lo
    /// dice, para que quien llegó tarde escriba la suya.
    @Test("lo que otra pasada ya cerró no se pisa, y se dice (A-11·H-55)")
    func aClosedRowIsNotOverwritten() async throws {
        try await Self.withCompetition("run-closed") { competitionID, tenant in
            let accepted = try IngestionRun(
                id: IngestionRunID(raw: UUID()), competitionID: competitionID,
                kind: .calendar, startedAt: Self.date("13-09-2025"),
                finishedAt: nil, outcome: .accepted)
            _ = try await tenant.scope { try await $0.ingestionRuns.record(accepted) }

            // Las dos pasadas cierran **su copia** de la misma aceptada.
            var winner = try accepted.closed(as: .succeeded, at: Self.date("14-09-2025"))
            winner.matchesCreated = 240
            let first = winner
            let late = try accepted.closed(
                as: .failed, at: Self.date("15-09-2025"), error: "la federación no contestó")

            let firstWrite = try await tenant.scope { try await $0.ingestionRuns.record(first) }
            let lateWrite = try await tenant.scope { try await $0.ingestionRuns.record(late) }

            let stored = try await tenant.scope {
                try await $0.ingestionRuns.list(competitionID: competitionID, limit: 10)
            }
            #expect(firstWrite == .recorded)
            #expect(lateWrite == .alreadyClosed)
            #expect(stored.count == 1)
            #expect(stored.first?.outcome == .succeeded, "la que llegó tarde pisó la cerrada")
            #expect(stored.first?.matchesCreated == 240)
            #expect(stored.first?.error == nil)
        }
    }

    /// **Y la pregunta se hace con la fila bloqueada**, o la carrera solo cambia de
    /// sitio (A-11·H-55).
    ///
    /// La primera en cerrar retiene su transacción abierta un momento; la segunda
    /// intenta cerrar la misma fila mientras tanto. Sin `FOR UPDATE`, la segunda
    /// **lee `accepted`** —lo de la primera aún no está confirmado—, su `UPDATE`
    /// espera a la primera y después **escribe encima**. Con el bloqueo, la lectura
    /// misma espera, y cuando llega ve la fila cerrada.
    @Test("dos cierres a la vez: el segundo espera y ve la fila cerrada (A-11·H-55)")
    func concurrentClosesAreSerialized() async throws {
        try await Self.withCompetition("run-lock") { competitionID, tenant in
            let accepted = try IngestionRun(
                id: IngestionRunID(raw: UUID()), competitionID: competitionID,
                kind: .calendar, startedAt: Self.date("13-09-2025"),
                finishedAt: nil, outcome: .accepted)
            _ = try await tenant.scope { try await $0.ingestionRuns.record(accepted) }
            let first = try accepted.closed(as: .succeeded, at: Self.date("14-09-2025"))
            let late = try accepted.closed(
                as: .failed, at: Self.date("15-09-2025"), error: "llegó tarde")

            let lateWrite = try await tenant.scope { repositories in
                _ = try await repositories.ingestionRuns.record(first)
                // **Con la primera todavía sin confirmar**, arranca la segunda en
                // su propio ámbito y se le da tiempo a lanzar su consulta.
                let contender = Task { try await tenant.scope { try await $0.ingestionRuns.record(late) } }
                try await Task.sleep(for: .milliseconds(300))
                return contender
            }.value

            let stored = try await tenant.scope {
                try await $0.ingestionRuns.list(competitionID: competitionID, limit: 10)
            }
            #expect(lateWrite == .alreadyClosed)
            #expect(stored.first?.outcome == .succeeded, "el segundo cierre pisó al primero")
        }
    }

    /// **`C-D.6`: el registro se ordena por `started_at`, no por `finished_at`.**
    ///
    /// Es la otra mitad de [D-96], y no es cosmética. La consulta contesta *"¿qué
    /// pasó la última vez?"*, y desde que existe la fila `accepted` hay filas
    /// **sin final**: ordenando por `finished_at DESC`, Postgres pone los `NULL`
    /// **primero**, así que una pasada aceptada hace tres semanas se colaría por
    /// delante de la que acabó hoy. El `202` dejó constancia de **cuándo se
    /// pidió**, y ése es el eje que siempre tiene valor.
    ///
    /// Las tres filas están puestas para que los dos criterios den órdenes
    /// **distintos**: con `started_at` la aceptada queda en medio; con
    /// `finished_at` se iría a la cabeza. Con dos filas el test no distinguiría
    /// un criterio del otro.
    @Test("el registro se ordena por started_at, y la aceptada no se cuela (C-D.6, D-96)")
    func theLogIsOrderedByStartedAt() async throws {
        try await Self.withCompetition("run-order") { competitionID, tenant in
            let vieja = try IngestionRun(
                id: IngestionRunID(raw: UUID()), competitionID: competitionID,
                kind: .calendar, startedAt: Self.date("01-09-2025"),
                finishedAt: Self.date("01-09-2025"), outcome: .succeeded)
            let aceptada = try IngestionRun(
                id: IngestionRunID(raw: UUID()), competitionID: competitionID,
                kind: .calendar, startedAt: Self.date("05-09-2025"),
                finishedAt: nil, outcome: .accepted)
            let reciente = try IngestionRun(
                id: IngestionRunID(raw: UUID()), competitionID: competitionID,
                kind: .calendar, startedAt: Self.date("10-09-2025"),
                finishedAt: Self.date("10-09-2025"), outcome: .succeeded)

            let stored = try await tenant.scope { repositories -> [IngestionRun] in
                for run in [vieja, aceptada, reciente] {
                    try await repositories.ingestionRuns.record(run)
                }
                return try await repositories.ingestionRuns.list(
                    competitionID: competitionID, limit: 10)
            }

            #expect(stored.map(\.id) == [reciente.id, aceptada.id, vieja.id],
                    "ordenado por finished_at, el NULL de la aceptada se va a la cabeza")
        }
    }

    /// **Lo que `findAccepted` busca es lo que está ABIERTO**, y esto lo pidió
    /// la comprobación de mutación: quitar el filtro de `outcome` al adaptador
    /// **sobrevivía** a toda la batería, porque el test de nivel 2 de al lado
    /// interroga al doble y no a esta consulta.
    ///
    /// Lo que rompe no es un caso raro, es **el caso normal de la segunda
    /// semana**: sin el filtro, la pasada del cron encontraría la fila
    /// `succeeded` de la semana pasada e intentaría cerrarla otra vez. El
    /// Dominio se niega con razón —*"solo se cierra una pasada aceptada"*
    /// (`C-A.6`)—, así que la ingesta se caería en la segunda pasada de cada
    /// competición.
    ///
    /// Se afirman las dos mitades: la cerrada no se devuelve, y la abierta sí.
    @Test("`findAccepted` ignora la pasada ya cerrada y encuentra la abierta (F10-bis)")
    func findAcceptedOnlyReturnsTheOpenRun() async throws {
        try await Self.withCompetition("find-accepted") { competitionID, tenant in
            let lastWeek = try IngestionRun(
                id: IngestionRunID(raw: UUID()), competitionID: competitionID,
                kind: .calendar, startedAt: Self.date("06-09-2025"),
                finishedAt: Self.date("06-09-2025"), outcome: .succeeded)
            _ = try await tenant.scope { try await $0.ingestionRuns.record(lastWeek) }

            let onlyClosed = try await tenant.scope {
                try await $0.ingestionRuns.findAccepted(
                    competitionID: competitionID, kind: .calendar)
            }
            #expect(onlyClosed == nil, "adoptaría la pasada de la semana pasada")

            let open = try IngestionRun(
                id: IngestionRunID(raw: UUID()), competitionID: competitionID,
                kind: .calendar, startedAt: Self.date("13-09-2025"),
                finishedAt: nil, outcome: .accepted)
            _ = try await tenant.scope { try await $0.ingestionRuns.record(open) }

            let found = try await tenant.scope {
                try await $0.ingestionRuns.findAccepted(
                    competitionID: competitionID, kind: .calendar)
            }
            #expect(found?.id == open.id)
            // Y la clase importa: lo que el `202` promete es el calendario, así
            // que una aceptada de otra clase no es la suya.
            let otherKind = try await tenant.scope {
                try await $0.ingestionRuns.findAccepted(
                    competitionID: competitionID, kind: .scorers)
            }
            #expect(otherKind == nil)
        }
    }

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

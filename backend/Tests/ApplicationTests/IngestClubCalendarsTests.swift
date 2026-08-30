import Domain
import Foundation
import Testing

@testable import Application

/// Nivel 2 (§8.1): **el recorrido de un club**, con los puertos falseados y cero
/// I/O.
///
/// Lo que se prueba aquí es lo que F6 añade sobre F5: **qué competiciones entran
/// en la pasada, en qué orden y qué pasa cuando una falla**. La pasada en sí
/// —qué se escribe de cada partido— es de `IngestCalendar` y ya está cubierta;
/// aquí el `FederationClient` falseado devuelve siempre lo mismo a propósito,
/// porque lo que se afirma es **a quién se llama**, no qué se guarda.
@Suite("IngestClubCalendars · §2.3-b · el recorrido de un club")
struct IngestClubCalendarsTests {

    // ── Instantes ────────────────────────────────────────────────────────────
    // Dentro de la temporada 2025/26 (§3.2: termina el 30 de junio de 2026), que
    // es lo que hace que `current(on:)` tenga una respuesta y no dos.
    static let now = instant("2026-03-02")

    static func instant(_ yyyyMMdd: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: yyyyMMdd)!
    }

    // ── Fixtures ─────────────────────────────────────────────────────────────

    static func club(federation: FederationCode = .rffm) throws -> Club {
        try Club(
            id: ClubID(raw: UUID()), name: "C.D. Ejemplo", shortName: "Ejemplo",
            slug: try Slug("ejemplo"), federation: federation,
            createdAt: now, updatedAt: now)
    }

    static func season(_ label: String, federationSeasonID: String) throws -> Season {
        try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel(label),
            federationSeasonID: federationSeasonID, createdAt: now, updatedAt: now)
    }

    static func competition(
        seasonID: SeasonID,
        federationCompetitionID: String = "24037548",
        federationGroupID: String = "24037549",
        lastSyncedAt: Date? = nil
    ) throws -> Competition {
        try Competition(
            id: CompetitionID(raw: UUID()), seasonID: seasonID,
            modality: .futbol11, gender: .masculino,
            federationCompetitionID: federationCompetitionID,
            federationGroupID: federationGroupID,
            ageCategory: .cadete, divisionLabel: "Primera División Autonómica",
            groupLabel: "Grupo 1", federationName: nil,
            lastSyncedAt: lastSyncedAt, createdAt: now, updatedAt: now)
    }

    /// Un calendario vacío: **no hay nada que escribir y es deliberado**. Lo que
    /// estos tests afirman es el recorrido, no el contenido de la pasada.
    static let calendar = FederationCalendar(
        seasonLabel: try! SeasonLabel("2025/26"),
        competitionName: nil, groupLabel: "Grupo 1",
        currentRound: 1, rounds: [])

    /// Arma el caso de uso sobre un almacén ya sembrado.
    static func useCase(
        store: IngestionStore,
        federation: any FederationClient,
        code: FederationCode = .rffm
    ) -> IngestClubCalendars {
        IngestClubCalendars(
            unitOfWork: FakeUnitOfWork(store: store),
            federationClients: FakeFederationClientProvider([code: federation]),
            clock: FixedClock(instant: now),
            ids: SequentialUUIDProvider())
    }

    static let actor = ActorContext(clubSlug: try! Slug("ejemplo"), isSystem: true)

    // ─────────────────────────────────────────────────────────────────────────

    @Test("solo se recorre la temporada vigente (§3.2)")
    func onlyTheCurrentSeason() async throws {
        let store = IngestionStore()
        await store.seed(club: try Self.club())

        let past = try Self.season("2024/25", federationSeasonID: "20")
        let current = try Self.season("2025/26", federationSeasonID: "21")
        await store.seed(
            seasons: [past, current],
            competitions: [
                try Self.competition(seasonID: past.id, federationGroupID: "111"),
                try Self.competition(seasonID: current.id, federationGroupID: "222"),
            ])

        let federation = SpyFederationClient(returning: Self.calendar)
        _ = try await Self.useCase(store: store, federation: federation)
            .execute(scope: IngestionScope(), actor: Self.actor)

        // La temporada pasada no se vuelve a pedir: su calendario ya no cambia, y
        // pedirlo gasta una petición por competición archivable.
        #expect(federation.received.map(\.federationSeasonID) == ["21"])
    }

    @Test("con `competitionId` se recorre solo ésa (§5.6)")
    func onlyTheRequestedCompetition() async throws {
        let store = IngestionStore()
        await store.seed(club: try Self.club())

        let current = try Self.season("2025/26", federationSeasonID: "21")
        let wanted = try Self.competition(seasonID: current.id, federationGroupID: "222")
        let other = try Self.competition(seasonID: current.id, federationGroupID: "333")
        await store.seed(seasons: [current], competitions: [wanted, other])

        let federation = SpyFederationClient(returning: Self.calendar)
        _ = try await Self.useCase(store: store, federation: federation)
            .execute(scope: IngestionScope(competitionIDs: [wanted.id]), actor: Self.actor)

        // Es el filtro del botón "resincroniza ésta" del backoffice: una sola
        // petición a la federación, no las de toda la temporada.
        #expect(federation.received.map(\.federationGroupID) == ["222"])
    }

    @Test("con varias competiciones se recorren todas, en el orden pedido (D-88)")
    func severalCompetitionsAreAllVisited() async throws {
        let store = IngestionStore()
        await store.seed(club: try Self.club())

        let current = try Self.season("2025/26", federationSeasonID: "21")
        let cadete = try Self.competition(seasonID: current.id, federationGroupID: "222")
        let infantil = try Self.competition(seasonID: current.id, federationGroupID: "333")
        let senior = try Self.competition(seasonID: current.id, federationGroupID: "444")
        await store.seed(seasons: [current], competitions: [cadete, infantil, senior])

        let federation = SpyFederationClient(returning: Self.calendar)
        _ = try await Self.useCase(store: store, federation: federation)
            .execute(
                scope: IngestionScope(competitionIDs: [senior.id, cadete.id]),
                actor: Self.actor)

        // La pantalla es una lista de equipos con una casilla al lado, así que
        // marcar tres es **una** acción del usuario: el ámbito lleva lista, no un
        // id suelto. Y el orden es el pedido, no el del almacén.
        #expect(federation.received.map(\.federationGroupID) == ["444", "222"])
    }

    @Test("si una de las competiciones pedidas no existe, no se sincroniza ninguna (D-84)")
    func anUnknownCompetitionInTheListStopsTheWholeRequest() async throws {
        let store = IngestionStore()
        await store.seed(club: try Self.club())

        let current = try Self.season("2025/26", federationSeasonID: "21")
        let cadete = try Self.competition(seasonID: current.id, federationGroupID: "222")
        await store.seed(seasons: [current], competitions: [cadete])

        let federation = SpyFederationClient(returning: Self.calendar)
        let useCase = Self.useCase(store: store, federation: federation)

        // **Se falla antes de empezar, no a mitad.** El plan se resuelve entero
        // en un solo ámbito (`D-83`), así que un id equivocado en la lista se ve
        // antes de tocar la red — y quien marcó tres casillas se entera de que
        // una estaba mal en vez de recibir dos pasadas y un silencio.
        await #expect(throws: ApplicationError.self) {
            try await useCase.execute(
                scope: IngestionScope(competitionIDs: [cadete.id, CompetitionID(raw: UUID())]),
                actor: Self.actor)
        }
        #expect(federation.received.isEmpty)
    }

    @Test("con `seasonId` se recorre esa temporada aunque no sea la vigente (§5.6)")
    func anExplicitSeasonBeatsTheCurrentOne() async throws {
        let store = IngestionStore()
        await store.seed(club: try Self.club())

        let past = try Self.season("2024/25", federationSeasonID: "20")
        let current = try Self.season("2025/26", federationSeasonID: "21")
        await store.seed(
            seasons: [past, current],
            competitions: [
                try Self.competition(seasonID: past.id, federationGroupID: "111"),
                try Self.competition(seasonID: current.id, federationGroupID: "222"),
            ])

        let federation = SpyFederationClient(returning: Self.calendar)
        _ = try await Self.useCase(store: store, federation: federation)
            .execute(scope: IngestionScope(seasonID: past.id), actor: Self.actor)

        // "Solo la vigente" es el **valor por defecto** del recorrido automático,
        // no una prohibición: pedir una temporada por su id es lo que permite
        // recomponer una que se quedó a medias sin esperar a que vuelva a serlo.
        #expect(federation.received.map(\.federationSeasonID) == ["20"])
    }

    @Test("una `seasonId` que no existe no cae a la vigente: falla (D-84)")
    func anUnknownSeasonDoesNotFallBack() async throws {
        let store = IngestionStore()
        await store.seed(club: try Self.club())

        let current = try Self.season("2025/26", federationSeasonID: "21")
        await store.seed(
            seasons: [current],
            competitions: [try Self.competition(seasonID: current.id)])

        let federation = SpyFederationClient(returning: Self.calendar)
        let useCase = Self.useCase(store: store, federation: federation)

        // La lección de `D-84` aplicada a nuestro propio código: **sincronizar
        // otra cosa no es un fallo visible**. Si un id desconocido cayera a la
        // temporada vigente, quien pidió recomponer la 2024/25 vería una pasada
        // con éxito y los datos de otra.
        await #expect(throws: ApplicationError.self) {
            try await useCase.execute(
                scope: IngestionScope(seasonID: SeasonID(raw: UUID())), actor: Self.actor)
        }
        #expect(federation.received.isEmpty)
    }

    /// El antirrebote de §5.6. **No es el tope semanal**: aquél es un máximo
    /// entre pasadas y lo hace cumplir la cadencia del disparador; esto es un
    /// mínimo que evita repetir trabajo cuando dos disparos se solapan.
    @Test("la sincronizada hace menos del intervalo mínimo no se vuelve a pedir (§5.6)")
    func aFreshCompetitionIsNotAskedAgain() async throws {
        let store = IngestionStore()
        await store.seed(club: try Self.club())

        let current = try Self.season("2025/26", federationSeasonID: "21")
        await store.seed(
            seasons: [current],
            competitions: [
                try Self.competition(
                    seasonID: current.id, lastSyncedAt: Self.now.addingTimeInterval(-3600))
            ])

        let federation = SpyFederationClient(returning: Self.calendar)
        _ = try await Self.useCase(store: store, federation: federation)
            .execute(scope: IngestionScope(minInterval: 6 * 3600), actor: Self.actor)

        #expect(federation.received.isEmpty)
    }

    @Test("la que nunca se sincronizó entra aunque haya intervalo mínimo (§3.2)")
    func aNeverSyncedCompetitionAlwaysEnters() async throws {
        let store = IngestionStore()
        await store.seed(club: try Self.club())

        let current = try Self.season("2025/26", federationSeasonID: "21")
        await store.seed(
            seasons: [current],
            // `lastSyncedAt` nulo: nunca sincronizada con éxito (§3.2).
            competitions: [try Self.competition(seasonID: current.id)])

        let federation = SpyFederationClient(returning: Self.calendar)
        _ = try await Self.useCase(store: store, federation: federation)
            .execute(scope: IngestionScope(minInterval: 6 * 3600), actor: Self.actor)

        // Sin esto, una competición recién dada de alta —el enganche de `D-67`,
        // que es F10— se quedaría esperando **para siempre**: nunca se
        // sincronizó, así que nunca sería "vieja", así que el cron nunca la
        // tocaría. Lo encontró la comprobación de mutación, no un rojo.
        #expect(federation.received.count == 1)
    }

    @Test("el antirrebote alcanza también a la competición pedida por id (§5.6)")
    func theGuardAlsoCoversAnExplicitCompetition() async throws {
        let store = IngestionStore()
        await store.seed(club: try Self.club())

        let current = try Self.season("2025/26", federationSeasonID: "21")
        let wanted = try Self.competition(
            seasonID: current.id, lastSyncedAt: Self.now.addingTimeInterval(-3600))
        await store.seed(seasons: [current], competitions: [wanted])

        let federation = SpyFederationClient(returning: Self.calendar)
        _ = try await Self.useCase(store: store, federation: federation)
            .execute(
                scope: IngestionScope(competitionIDs: [wanted.id], minInterval: 6 * 3600),
                actor: Self.actor)

        // **Las tres puertas se miran con la misma regla.** El botón del
        // backoffice no manda intervalo (`minInterval: nil`), así que a él no le
        // afecta; pero un cron lanzado con `--competition` sí, y que la guarda
        // dependiera de por qué puerta se entró sería una asimetría que nadie
        // podría recordar.
        #expect(federation.received.isEmpty)
    }

    @Test("la sincronizada hace más del intervalo mínimo vuelve a entrar (§5.6)")
    func aStaleCompetitionIsAskedAgain() async throws {
        let store = IngestionStore()
        await store.seed(club: try Self.club())

        let current = try Self.season("2025/26", federationSeasonID: "21")
        await store.seed(
            seasons: [current],
            competitions: [
                try Self.competition(
                    seasonID: current.id, lastSyncedAt: Self.now.addingTimeInterval(-48 * 3600))
            ])

        let federation = SpyFederationClient(returning: Self.calendar)
        _ = try await Self.useCase(store: store, federation: federation)
            .execute(scope: IngestionScope(minInterval: 6 * 3600), actor: Self.actor)

        // Es la mitad que importa del par: sin ella, "no repitas lo reciente" se
        // implementa igual de bien con "no repitas nunca", y la ingesta dejaría
        // de sincronizar en cuanto lo hiciera una vez.
        #expect(federation.received.count == 1)
    }

    @Test("sin intervalo mínimo se pide aunque acabe de sincronizarse (§5.6)")
    func withoutAGuardEverythingIsAskedAgain() async throws {
        let store = IngestionStore()
        await store.seed(club: try Self.club())

        let current = try Self.season("2025/26", federationSeasonID: "21")
        await store.seed(
            seasons: [current],
            competitions: [
                try Self.competition(
                    seasonID: current.id, lastSyncedAt: Self.now.addingTimeInterval(-60))
            ])

        let federation = SpyFederationClient(returning: Self.calendar)
        _ = try await Self.useCase(store: store, federation: federation)
            .execute(scope: IngestionScope(), actor: Self.actor)

        // Es el caso del botón del backoffice: quien lo pulsa lo pulsa porque
        // quiere **ahora**, y un antirrebote silencioso le diría que ya está
        // sincronizado sin haber ido a mirar.
        #expect(federation.received.count == 1)
    }

    // ── El recorrido no se detiene (D-86) ────────────────────────────────────

    /// Siembra dos competiciones de la temporada vigente, la primera de las
    /// cuales revienta al llamar a la federación.
    static func storeWithABrokenFirstCompetition() async throws
        -> (store: IngestionStore, broken: Competition, healthy: Competition)
    {
        let store = IngestionStore()
        await store.seed(club: try Self.club())
        let current = try Self.season("2025/26", federationSeasonID: "21")
        let broken = try Self.competition(seasonID: current.id, federationGroupID: "222")
        let healthy = try Self.competition(seasonID: current.id, federationGroupID: "333")
        await store.seed(seasons: [current], competitions: [broken, healthy])
        return (store, broken, healthy)
    }

    @Test("una competición que falla no detiene el recorrido (D-86)")
    func aFailureDoesNotStopTheTraversal() async throws {
        let (store, _, _) = try await Self.storeWithABrokenFirstCompetition()
        let federation = FlakyFederationClient(
            returning: Self.calendar, failingGroups: ["222"])

        _ = try? await Self.useCase(store: store, federation: federation)
            .execute(scope: IngestionScope(), actor: Self.actor)

        // La unidad de aislamiento es la **competición**, no el club: `D-83` ya
        // la hace atómica y `D-85` ya deja escrito el fallo, así que parar aquí
        // solo conseguiría que una coordenada caducada —de las que `D-84` dice
        // que las hay, y en silencio— dejara sin sincronizar a todo lo demás.
        #expect(federation.received.map(\.federationGroupID) == ["222", "333"])
    }

    @Test("el recorrido dice cuál falló y por qué (D-86)")
    func theReportNamesTheFailure() async throws {
        let (store, broken, healthy) = try await Self.storeWithABrokenFirstCompetition()
        let federation = FlakyFederationClient(
            returning: Self.calendar, failingGroups: ["222"])

        let report = try await Self.useCase(store: store, federation: federation)
            .execute(scope: IngestionScope(), actor: Self.actor)

        // Continuar y callárselo es peor que parar: quien lanza el job no está
        // delante (§2.3-b), así que un recorrido que se traga los fallos parece
        // uno que fue bien.
        #expect(report.entries.map(\.competitionID) == [broken.id, healthy.id])
        #expect(report.hasFailures)
        guard case .failed(let reason) = report.entries.first?.outcome else {
            Issue.record("la primera entrada debería ser un fallo, y es \(String(describing: report.entries.first?.outcome))")
            return
        }
        #expect(reason.contains("222"))
    }

    @Test("cada competición deja su fila, falle o no (D-85, D-86)")
    func everyCompetitionLeavesItsRow() async throws {
        let (store, _, _) = try await Self.storeWithABrokenFirstCompetition()
        let federation = FlakyFederationClient(
            returning: Self.calendar, failingGroups: ["222"])

        _ = try await Self.useCase(store: store, federation: federation)
            .execute(scope: IngestionScope(), actor: Self.actor)

        // `D-85` escribe el registro **fuera** de la transacción de la pasada
        // precisamente para esto: la que falla es la que hay que poder leer
        // después, y el recorrido no puede ser lo que la borre.
        let outcomes = await store.ingestionRuns.map(\.outcome)
        #expect(outcomes == [.failed, .succeeded])
    }

    // ── El catálogo decide el adaptador (D-17) ───────────────────────────────
    //
    // Los dos tests de aquí abajo **llegaron en verde**, y no se disimula (Plan
    // §5.1). Los sostiene la estructura —el adaptador sale de un dato del club y
    // el `nil` del catálogo corta antes del bucle—, no una línea que se pueda
    // invertir, así que se verifican con mutación y no con un rojo fingido.

    @Test("el adaptador sale de `Club.federation`, no del cableado (D-17)")
    func theAdapterComesFromTheClub() async throws {
        let store = IngestionStore()
        await store.seed(club: try Self.club(federation: .fcf))
        let current = try Self.season("2025/26", federationSeasonID: "21")
        await store.seed(
            seasons: [current], competitions: [try Self.competition(seasonID: current.id)])

        let rffm = SpyFederationClient(returning: Self.calendar)
        let fcf = SpyFederationClient(returning: Self.calendar)
        let useCase = IngestClubCalendars(
            unitOfWork: FakeUnitOfWork(store: store),
            federationClients: FakeFederationClientProvider([.rffm: rffm, .fcf: fcf]),
            clock: FixedClock(instant: Self.now),
            ids: SequentialUUIDProvider())

        _ = try await useCase.execute(scope: IngestionScope(), actor: Self.actor)

        // Equivocarse aquí no da un error: da el calendario de otra federación
        // escrito con cara de éxito, que es la misma familia de fallo que `D-84`.
        #expect(fcf.received.count == 1)
        #expect(rffm.received.isEmpty)
    }

    @Test("un club cuya federación no tiene adaptador no deja pasadas fallidas (D-17)")
    func aFederationWithoutAnAdapterLeavesNoRows() async throws {
        let store = IngestionStore()
        await store.seed(club: try Self.club(federation: .fcf))
        let current = try Self.season("2025/26", federationSeasonID: "21")
        await store.seed(
            seasons: [current], competitions: [try Self.competition(seasonID: current.id)])

        // Solo la RFFM tiene adaptador; la FCF es F9.
        let useCase = Self.useCase(
            store: store, federation: SpyFederationClient(returning: Self.calendar), code: .rffm)

        await #expect(throws: ApplicationError.federationAdapterMissing(federation: "fcf")) {
            try await useCase.execute(scope: IngestionScope(), actor: Self.actor)
        }

        // **No es una pasada que falla, es un club que todavía no se puede
        // sincronizar.** Registrarlo dejaría una fila por competición y semana
        // que nadie puede resolver hasta F9, y `ingestion_runs` existe para
        // leerse (`D-85`).
        let runs = await store.ingestionRuns
        #expect(runs.isEmpty)
    }
}

public import Domain
public import struct Foundation.Date
public import struct Foundation.TimeInterval

/// Caso de uso: **el recorrido de un club** (§2.3-b, §5.6).
///
/// `IngestCalendar` sincroniza **una** competición. Esto decide **cuáles**, en
/// qué orden y qué se hace cuando una falla — que es todo lo que F6 añade sobre
/// F5 por el lado de la Aplicación.
///
/// # Por qué el recorrido no vive en el `AsyncCommand`
///
/// Es la lección literal de `D-83`: *"si la frontera transaccional la pusiera el
/// `AsyncCommand`, sería un detalle que se puede hacer mal desde fuera"*. Aquí
/// pasa lo mismo con dos reglas más caras de equivocar que de escribir —qué
/// temporada entra y qué pasa tras un fallo—, y con una razón añadida que F6
/// trae y F5 no tenía: **hay dos llamantes**. El job (§2.3-b) y el disparador
/// manual del backoffice (§2.3-a) son dos adaptadores primarios del **mismo**
/// caso de uso, así que una regla escrita en cualquiera de los dos sería una
/// regla que el otro no cumple.
public struct IngestClubCalendars: Sendable {
    private let unitOfWork: any TenantUnitOfWork
    private let federationClients: any FederationClientProvider
    private let clock: any Clock
    private let ids: any UUIDProvider

    public init(
        unitOfWork: any TenantUnitOfWork,
        federationClients: any FederationClientProvider,
        clock: any Clock,
        ids: any UUIDProvider
    ) {
        self.unitOfWork = unitOfWork
        self.federationClients = federationClients
        self.clock = clock
        self.ids = ids
    }

    public func execute(
        scope: IngestionScope = IngestionScope(), actor: ActorContext
    ) async throws -> ClubIngestionReport {
        let plan = try await plan(scope: scope, actor: actor)

        guard let client = federationClients.client(for: plan.federation) else {
            throw ApplicationError.federationAdapterMissing(
                federation: plan.federation.rawValue)
        }

        let ingest = IngestCalendar(
            unitOfWork: unitOfWork, federation: client, clock: clock, ids: ids)

        var report = ClubIngestionReport(
            clubSlug: actor.clubSlug, federation: plan.federation)
        for competition in plan.competitions {
            // **Se continúa, y se apunta** (`D-86`). Las dos mitades son
            // igual de necesarias: continuar sin apuntar convierte un recorrido
            // con fallos en uno que parece haber ido bien, y quien lanza el job
            // no está delante para notar la diferencia (§2.3-b).
            //
            // Lo que aquí se guarda es una **copia** para el llamante: la
            // constancia que sobrevive al proceso ya la escribió `IngestCalendar`
            // en `ingestion_runs`, fuera de la transacción que se deshizo
            // (`D-85`).
            do {
                let run = try await ingest.execute(competitionID: competition.id, actor: actor)
                report.entries.append(
                    ClubIngestionReport.Entry(
                        competitionID: competition.id, outcome: .synced(run)))
            } catch {
                report.entries.append(
                    ClubIngestionReport.Entry(
                        competitionID: competition.id,
                        outcome: .failed(diagnosticText(for: error))))
            }
        }
        return report
    }

    /// Qué competiciones entrarían en este recorrido, **sin ejecutarlo**.
    ///
    /// Existe por el `202` de `POST /ingestion-runs` (`D-87`): la respuesta tiene
    /// que decir *qué* se ha aceptado antes de que el trabajo ocurra. Y de paso
    /// resuelve algo que importa más — una `seasonId` inexistente da **404 antes
    /// del 202**, en vez de un `202` seguido de un fallo que nadie ve.
    ///
    /// El precio es leer la coordenada dos veces. Es el mismo intercambio que
    /// `D-83` ya aceptó por otro motivo, y por menos.
    public func plannedCompetitions(
        scope: IngestionScope = IngestionScope(), actor: ActorContext
    ) async throws -> [CompetitionID] {
        try await plan(scope: scope, actor: actor).competitions.map(\.id)
    }

    /// Qué se va a sincronizar, resuelto en **un solo ámbito** y antes de tocar
    /// la red — igual que el ámbito 1 de `D-83`, y por el mismo motivo.
    private func plan(
        scope: IngestionScope, actor: ActorContext
    ) async throws -> (federation: FederationCode, competitions: [Competition]) {
        try await unitOfWork.withRepositories(actor: actor) { repositories in
            guard let club = try await repositories.clubs.current() else {
                throw ApplicationError.tenantNotProvisioned(slug: actor.clubSlug.value)
            }
            // **La competición concreta gana**, y a propósito no pasa por el
            // filtro de temporada vigente: quien pide una por su id ya sabe cuál
            // quiere —el botón de la ficha en el backoffice— y hacérselo pasar
            // por "¿es de la temporada en curso?" convertiría una petición
            // explícita en un silencio.
            if let requested = scope.competitionIDs, !requested.isEmpty {
                var competitions: [Competition] = []
                // **Se resuelven todas antes de tocar la red.** El plan entero
                // cabe en el ámbito 1 de `D-83`, así que un id equivocado en la
                // lista se ve **antes** de empezar: quien marcó tres casillas se
                // entera de que una estaba mal, en vez de recibir dos pasadas y
                // un silencio.
                for competitionID in requested {
                    guard let competition = try await repositories.competitions.find(competitionID)
                    else {
                        throw ApplicationError.competitionNotFound(id: "\(competitionID.raw)")
                    }
                    competitions.append(competition)
                }
                return (club.federation, due(competitions, scope: scope))
            }

            // **La vigente es el valor por defecto, no una prohibición** (§3.2).
            // El calendario de una temporada terminada ya no cambia, así que
            // recorrerla automáticamente gasta una petición por competición y no
            // trae nada — con un club de diez años a cuestas, eso es la
            // diferencia entre una pasada y decenas. Pero pedirla por su id es
            // otra cosa: es lo que permite recomponer la que se quedó a medias.
            //
            // `current(on:)` vive en el Dominio y ya excluye las archivadas,
            // aunque el repositorio también lo haga: son dos guardas de la misma
            // regla puestas en las dos capas a propósito (§3.5).
            let seasons = try await repositories.seasons.list(includingArchived: false)
            let season: Season?
            if let requested = scope.seasonID {
                // **Si no está, se falla; no se cae a la vigente.** Un `??` aquí
                // sería el `D-84` de nuestra propia casa: quien pidió recomponer
                // la 2024/25 vería una pasada con éxito y los datos de otra.
                guard let found = seasons.first(where: { $0.id == requested }) else {
                    throw ApplicationError.unknownSeason(id: "\(requested.raw)")
                }
                season = found
            } else {
                season = seasons.current(on: clock.now())
            }
            guard let season else { return (club.federation, []) }
            let competitions = try await repositories.competitions.list(seasonID: season.id)
            return (club.federation, due(competitions, scope: scope))
        }
    }

    /// El antirrebote de §5.6, aplicado **igual a las tres puertas** —una
    /// competición, una temporada, la vigente—.
    ///
    /// Vive aquí y no en `Competition` porque no es una invariante de la entidad
    /// sino una **política de cadencia**: la misma fila es o no es "reciente"
    /// según con qué intervalo se la mire, y quien elige ese intervalo es el
    /// llamante (el cron con el suyo, el botón sin ninguno).
    ///
    /// **La que nunca se sincronizó entra siempre**, tenga el intervalo el valor
    /// que tenga: `lastSyncedAt` nulo significa *"nunca, con éxito"* (§3.2), y
    /// una guarda que la excluyera dejaría a la competición recién dada de alta
    /// esperando para siempre.
    private func due(_ competitions: [Competition], scope: IngestionScope) -> [Competition] {
        guard let minInterval = scope.minInterval else { return competitions }
        let now = clock.now()
        return competitions.filter { competition in
            guard let lastSyncedAt = competition.lastSyncedAt else { return true }
            return now.timeIntervalSince(lastSyncedAt) >= minInterval
        }
    }
}

/// Qué parte del club entra en esta pasada.
///
/// Los dos filtros son **las dos filas de la coordenada de la federación**, no
/// dos campos sueltos: la URL que teclea el administrador
/// (`temporada=21&competicion=24037548&grupo=24037549`) se reparte entre
/// `Season` —`temporada`— y `Competition` —`competicion` **y** `grupo` juntos,
/// que forman una sola fila (§3.5)—. Por eso no hay filtro de grupo: ya está
/// dentro del de competición.
public struct IngestionScope: Sendable, Equatable {
    /// Solo esta temporada. `nil` ⇒ la **vigente** (§3.2).
    public let seasonID: SeasonID?

    /// Solo éstas. Gana sobre `seasonID`, porque es más específica.
    ///
    /// **Es una lista y no un id suelto** por la pantalla que la usa: el
    /// backoffice enseña los equipos del club con una casilla al lado, y
    /// resincronizar tres es **una** acción del usuario. Partirla en tres
    /// peticiones le traslada al cliente el manejo de tres respuestas, tres
    /// errores parciales y tres estados de carga — y al servidor, tres
    /// recorridos que ya sabía hacer de una vez.
    public let competitionIDs: [CompetitionID]?

    /// **Antirrebote, no el tope semanal.** Una competición sincronizada con
    /// éxito hace menos de esto no se vuelve a pedir.
    ///
    /// No confundirlo con el requisito de §5.6: aquel es un **máximo** de una
    /// semana entre pasadas y lo hace cumplir la **cadencia** del disparador;
    /// esto es un **mínimo** que evita que dos disparos solapados —un reintento
    /// del cron, un doble clic en el backoffice— repitan el trabajo. `nil` ⇒ sin
    /// guarda, que es lo que quiere quien pulsa el botón a mano.
    public let minInterval: TimeInterval?

    public init(
        seasonID: SeasonID? = nil,
        competitionIDs: [CompetitionID]? = nil,
        minInterval: TimeInterval? = nil
    ) {
        self.seasonID = seasonID
        self.competitionIDs = competitionIDs
        self.minInterval = minInterval
    }
}

/// Lo que el recorrido deja dicho de sí mismo.
///
/// **No es `IngestionRun`, y no lo sustituye**: aquél es la fila que `D-85`
/// escribe por competición y sobrevive al proceso; esto es lo que el recorrido
/// devuelve a su llamante —la consola del job o la respuesta del disparador—
/// para que sepa qué acaba de pasar sin volver a consultar.
public struct ClubIngestionReport: Sendable, Equatable {
    public let clubSlug: Slug
    public let federation: FederationCode
    public var entries: [Entry] = []

    public init(clubSlug: Slug, federation: FederationCode, entries: [Entry] = []) {
        self.clubSlug = clubSlug
        self.federation = federation
        self.entries = entries
    }

    public struct Entry: Sendable, Equatable {
        public let competitionID: CompetitionID
        public let outcome: Outcome

        public init(competitionID: CompetitionID, outcome: Outcome) {
            self.competitionID = competitionID
            self.outcome = outcome
        }
    }

    public enum Outcome: Sendable, Equatable {
        /// La pasada se hizo y quedó escrita.
        case synced(IngestionRun)
        /// La pasada falló. El motivo ya está en su fila de `ingestion_runs`
        /// (`D-85`); esto es la copia que ve el llamante.
        case failed(String)
    }

    /// `true` si alguna competición falló. Es lo que decide el **código de
    /// salida** del job: un recorrido que continúa tras un fallo (`D-86`) no
    /// puede además callárselo.
    public var hasFailures: Bool {
        entries.contains { if case .failed = $0.outcome { true } else { false } }
    }
}

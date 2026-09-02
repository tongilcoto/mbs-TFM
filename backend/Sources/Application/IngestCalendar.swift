public import Domain

/// Caso de uso: **la pasada de ingesta del calendario** (§2.3-b, §5.6).
///
/// Es donde F3 y F4 se juntan por primera vez: **la cadena decide qué fila es**
/// (`MatchingChain`) y **`UpsertPolicy` decide qué se le escribe**. Aquí no hay
/// ninguna regla nueva de las dos; lo que hay es el orden, la carga de
/// candidatos y qué se hace con cada desenlace.
///
/// # Por qué éste recibe el `TenantUnitOfWork` y `GetClub` no
///
/// Los casos de uso de F0 reciben repositorios y es el **adaptador primario**
/// quien abre el ámbito (§6.2). Aquí no puede ser: entre leer la coordenada y
/// escribir el resultado hay **una llamada de red** a un tercero, y dejar una
/// transacción abierta mientras se espera a la federación es lo que convierte
/// una caída suya en conexiones bloqueadas del *pool* (§6.4).
///
/// Así que la pasada abre **tres** ámbitos y la red queda fuera de los tres. Y
/// esa decisión no puede vivir en el adaptador —sería un detalle que se puede
/// hacer mal desde fuera, como el orden de los marcadores de `D-56`—, así que
/// vive aquí (`D-83`).
///
/// # Los tres, y por qué son tres
///
/// 1. **Leer la coordenada**, y cerrarlo antes de llamar a la federación.
/// 2. **Escribir**, y ahí va **todo**. Una violación de restricción aborta la
///    transacción entera (`25P02`, F1), y aquí eso es **la propiedad que se
///    quiere**: o la competición queda sincronizada entera o no queda tocada,
///    coherente con que `last_synced_at` signifique *"última sincronización
///    **con éxito**"* (§3.2). Lo que un fallo **nunca** hace es destruir lo que
///    había: no se borra nada, se deshace lo de esta pasada.
/// 3. **Registrar la pasada** (`D-85`), y **fuera** del anterior: dentro, el
///    `rollback` se llevaría por delante el registro de la pasada que falla, que
///    es justo la que hay que poder leer porque no hay nadie mirando.
public struct IngestCalendar: Sendable {
    private let unitOfWork: any TenantUnitOfWork
    private let federation: any FederationClient
    private let clock: any Clock
    private let ids: any UUIDProvider

    public init(
        unitOfWork: any TenantUnitOfWork,
        federation: any FederationClient,
        clock: any Clock,
        ids: any UUIDProvider
    ) {
        self.unitOfWork = unitOfWork
        self.federation = federation
        self.clock = clock
        self.ids = ids
    }

    public func execute(
        competitionID: CompetitionID, actor: ActorContext
    ) async throws -> IngestionRun {
        let startedAt = clock.now()
        do {
            // **Las marcas de tiempo las pone quien conoce los dos extremos.**
            // `CalendarPass` construye su informe al empezar, así que si se
            // quedara con las suyas toda pasada con éxito registraría duración
            // cero — que es lo que hacía, y solo se vio ejecutándola contra la
            // base de trabajo. La fallida sí se medía: la asimetría era el
            // síntoma.
            let run = try await sync(competitionID: competitionID, actor: actor)
                .timed(from: startedAt, to: clock.now())
            try await record(run, actor: actor)
            return run
        } catch {
            // `D-85`: **la pasada que falla es la que nadie ve**, porque no hay
            // usuario esperando una respuesta (§2.3-b). Es la que más falta hace
            // registrar, y la que un registro escrito dentro de la transacción de
            // `D-83` se llevaría por delante con el `rollback`.
            //
            // Los contadores quedan a cero, y es lo honesto: la transacción se
            // deshizo, así que no se escribió nada aunque la pasada hubiera
            // llegado a la última jornada.
            let failed = try IngestionRun(
                id: IngestionRunID(raw: ids.next()),
                competitionID: competitionID,
                startedAt: startedAt, finishedAt: clock.now(),
                outcome: .failed, error: diagnosticText(for: error))

            // Si el registro tampoco se puede escribir, **manda el error
            // original**: es el que explica lo que pasó, y taparlo con "no pude
            // apuntarlo" dejaría al que depura mirando al sitio equivocado.
            do { try await record(failed, actor: actor) } catch {}

            throw error
        }
    }

    /// El registro va en **su propio ámbito**, fuera de la transacción de la
    /// pasada (`D-83`, `D-85`). Es lo que hace que sobreviva al `rollback`.
    private func record(_ run: IngestionRun, actor: ActorContext) async throws {
        try await unitOfWork.withRepositories(actor: actor) { repositories in
            try await repositories.ingestionRuns.record(run)
        }
    }

    private func sync(
        competitionID: CompetitionID, actor: ActorContext
    ) async throws -> IngestionRun {
        // ── Ámbito 1: leer la coordenada ────────────────────────────────
        let coordinate = try await unitOfWork.withRepositories(actor: actor) { repositories in
            guard let competition = try await repositories.competitions.find(competitionID)
            else {
                throw ApplicationError.competitionNotFound(id: "\(competitionID.raw)")
            }
            guard let season = try await repositories.seasons.find(competition.seasonID)
            else {
                throw ApplicationError.seasonNotFound(id: "\(competition.seasonID.raw)")
            }
            return FederationCoordinate(
                federationSeasonID: season.federationSeasonID,
                federationCompetitionID: competition.federationCompetitionID,
                federationGroupID: competition.federationGroupID,
                modality: competition.modality)
        }

        // ── Fuera de todo ámbito: la red ────────────────────────────────
        let calendar = try await federation.fetchCalendar(coordinate)

        // ── Ámbito 2: **todo** lo que se escribe ────────────────────────
        return try await unitOfWork.withRepositories(actor: actor) { repositories in
            guard let competition = try await repositories.competitions.find(competitionID)
            else {
                throw ApplicationError.competitionNotFound(id: "\(competitionID.raw)")
            }

            let pass = try await CalendarPass(
                competition: competition, repositories: repositories,
                ids: ids, now: clock.now())
            try await pass.run(calendar)
            return pass.report
        }
    }
}

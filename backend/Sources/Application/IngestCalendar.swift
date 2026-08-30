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
/// Así que la pasada abre **dos** ámbitos y la red queda fuera de los dos. Y esa
/// decisión no puede vivir en el adaptador —sería un detalle que se puede hacer
/// mal desde fuera, como el orden de los marcadores de `D-56`—, así que vive
/// aquí (`D-83`).
///
/// # Todo lo que se escribe va en un solo ámbito
///
/// El segundo. Una violación de restricción aborta la transacción entera
/// (`25P02`, F1), y aquí eso es **la propiedad que se quiere**: o la competición
/// queda sincronizada entera o no queda tocada, coherente con que
/// `last_synced_at` signifique *"última sincronización **con éxito**"* (§3.2).
/// Lo que un fallo **nunca** hace es destruir lo que había: no se borra nada, se
/// deshace lo de esta pasada.
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
    ) async throws -> IngestionReport {
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

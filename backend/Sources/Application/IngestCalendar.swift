public import Domain
import struct Foundation.Date

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
        // **Qué fila se está cerrando, si es que hay alguna** (F10-bis, [D-96]).
        //
        // Lo pone el ámbito 1 en cuanto lo sabe, y vive aquí fuera porque **el
        // camino de fallo también adopta**: `D-96` dice que la pasada cierra la
        // aceptada a `succeeded` **o a `failed`**, y si sólo adoptara el camino
        // de éxito, una pasada que revienta dejaría la fila abierta para siempre
        // — justo el defecto que esta mini-fase arregla, escondido en la rama que
        // nadie mira.
        //
        // `nil` cuando no hay nada que adoptar **o cuando ni se pudo mirar**: si
        // el ámbito 1 es lo que falla, se escribe una fila nueva, que es lo único
        // honesto que se puede hacer sin haber podido leer.
        var adopted: IngestionRun?
        let run: IngestionRun
        do {
            // **Las marcas de tiempo las pone quien conoce los dos extremos.**
            // `CalendarPass` construye su informe al empezar, así que si se
            // quedara con las suyas toda pasada con éxito registraría duración
            // cero — que es lo que hacía, y solo se vio ejecutándola contra la
            // base de trabajo. La fallida sí se medía: la asimetría era el
            // síntoma.
            //
            // **Desde F10-bis eso lo hace `closed(as:)` y no `timed(from:to:)`**:
            // el informe nace abierto, así que cerrarlo ya es ponerle el final, y
            // el principio es el que tenía — el de la fila adoptada cuando la
            // hay, que es **cuándo se pidió** y no cuándo arrancó el *job*.
            run = try await sync(
                competitionID: competitionID, actor: actor,
                startedAt: startedAt, adopted: &adopted
            ).closed(as: .succeeded, at: clock.now())
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
                id: adopted?.id ?? IngestionRunID(raw: ids.next()),
                competitionID: competitionID, kind: .calendar,
                startedAt: adopted?.startedAt ?? startedAt, finishedAt: clock.now(),
                outcome: .failed, error: diagnosticText(for: error))

            // Si el registro tampoco se puede escribir, **manda el error
            // original**: es el que explica lo que pasó, y taparlo con "no pude
            // apuntarlo" dejaría al que depura mirando al sitio equivocado.
            do { try await record(failed, actor: actor) } catch {}

            throw error
        }

        // **El registro del camino de éxito va fuera del `do` de arriba, y eso lo
        // arregló H-24.** Estando dentro, un fallo **solo al apuntar** caía en el
        // `catch` de la pasada fallida y se registraba como `failed` una pasada
        // cuyo ámbito 2 **ya había comprometido**: los datos escritos,
        // `last_synced_at` puesto, y la fila diciendo lo contrario. Tres testigos
        // de la misma pasada dando tres respuestas, y el motivo guardado hablando
        // del apunte y no de la pasada — justo lo que manda a depurar al sitio
        // equivocado.
        //
        // Lo que se hace en su lugar es decir exactamente lo que ocurrió. Quien lo
        // reciba tiene que saber que **la ingesta sí se hizo**, o la repetirá.
        do {
            try await record(run, actor: actor)
        } catch {
            throw ApplicationError.runNotRecorded(
                competitionID: "\(competitionID.raw)",
                reason: diagnosticText(for: error))
        }
        return run
    }

    /// El registro va en **su propio ámbito**, fuera de la transacción de la
    /// pasada (`D-83`, `D-85`). Es lo que hace que sobreviva al `rollback`.
    private func record(_ run: IngestionRun, actor: ActorContext) async throws {
        try await unitOfWork.withRepositories(actor: actor) { repositories in
            try await repositories.ingestionRuns.record(run)
        }
    }

    private func sync(
        competitionID: CompetitionID, actor: ActorContext,
        startedAt: Date, adopted: inout IngestionRun?
    ) async throws -> IngestionRun {
        // ── Ámbito 1: leer la coordenada ────────────────────────────────
        //
        // **Y de paso, la fila que haya que cerrar.** Va aquí y no en un ámbito
        // propio porque son la misma pregunta —*"¿qué voy a sincronizar y por
        // cuenta de quién?"*— y porque un ámbito más antes de la red es una
        // conexión más retenida mientras se espera a un tercero (§6.4). Los tres
        // de `D-83` siguen siendo tres.
        let plan = try await unitOfWork.withRepositories(actor: actor) { repositories in
            guard let competition = try await repositories.competitions.find(competitionID)
            else {
                throw ApplicationError.competitionNotFound(id: "\(competitionID.raw)")
            }
            guard let season = try await repositories.seasons.find(competition.seasonID)
            else {
                throw ApplicationError.seasonNotFound(id: "\(competition.seasonID.raw)")
            }
            return (
                coordinate: FederationCoordinate(
                    federationSeasonID: season.federationSeasonID,
                    federationCompetitionID: competition.federationCompetitionID,
                    federationGroupID: competition.federationGroupID,
                    modality: competition.modality),
                accepted: try await repositories.ingestionRuns.findAccepted(
                    competitionID: competitionID, kind: .calendar))
        }
        adopted = plan.accepted
        let coordinate = plan.coordinate

        // ── Fuera de todo ámbito: la red ────────────────────────────────
        let calendar = try await federation.fetchCalendar(coordinate)

        // ── Ámbito 2: **todo** lo que se escribe ────────────────────────
        return try await unitOfWork.withRepositories(actor: actor) { repositories in
            guard let competition = try await repositories.competitions.find(competitionID)
            else {
                throw ApplicationError.competitionNotFound(id: "\(competitionID.raw)")
            }
            // La temporada se relee **aquí dentro**, y es el mismo intercambio
            // que `D-83` ya asumió con la competición: un `SELECT` por PK a
            // cambio de no mantener viva una transacción durante la latencia de
            // un tercero. La necesita la guarda de `D-91`, que compara las
            // fechas del calendario con la ventana de la temporada.
            guard let season = try await repositories.seasons.find(competition.seasonID)
            else {
                throw ApplicationError.seasonNotFound(id: "\(competition.seasonID.raw)")
            }

            let pass = try await CalendarPass(
                competition: competition, season: season, repositories: repositories,
                // **Adoptar es esto**: la pasada escribe con el `id` de la fila
                // que el `202` dejó abierta, así que al cerrarla es **esa** fila
                // la que pasa a `succeeded`, con los contadores de esta pasada.
                // Sin fila que adoptar, un `id` nuevo y la pasada abre la suya,
                // que es lo que hace el cron.
                identity: (
                    id: plan.accepted?.id ?? IngestionRunID(raw: ids.next()),
                    startedAt: plan.accepted?.startedAt ?? startedAt),
                ids: ids, now: clock.now())
            try await pass.run(calendar)
            return pass.report
        }
    }
}

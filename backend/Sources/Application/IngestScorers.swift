public import Domain
import struct Foundation.Date

/// Caso de uso: **la pasada de goleadores** (F8, §2.3-b).
///
/// Es el tercer hermano de `IngestCalendar` e `IngestStandings`, y conviene
/// tener delante en qué se parece a cada uno, porque **no se parece al mismo en
/// las dos cosas que importan**.
///
/// | | Calendario | Clasificación | **Goleadores** |
/// |---|---|---|---|
/// | Unidad de la pasada | competición | **jornada** | **competición** |
/// | Filas en `ingestion_runs` | una | una por jornada | **una** |
/// | Si la fuente no lo da | — | se **calcula** (`D-15`) | **no hay nada** (`D-48`) |
/// | Lo que la fuente deja de publicar | se queda (`D-75`) | se queda | **se retira** (`D-94`) |
///
/// # La unidad es la competición, y lo decide el endpoint
///
/// `/api/standings?round=N` sirve **una** jornada, así que allí la pasada es la
/// jornada. `/api/scorers` devuelve el ranking entero de la competición en una
/// petición, y el modelo va detrás: `LeagueScorer` es **estado vigente único**,
/// sin histórico ni columna PREV (§3.2). De ahí que esta pasada caiga del lado
/// **nulo** de `IngestionRun.roundID`.
///
/// # Y la capacidad de `D-48` es una guarda de verdad, no un rótulo
///
/// `providesRoundStandings` dice de dónde **viene** el dato; con `false` la
/// clasificación existe igual, calculada. `providesScorers` dice **si hay** dato:
/// con `false` no se pide, no se escribe y no se retira — la tabla queda vacía y
/// el cliente oculta la pantalla. Calcular el ranking desde `Goal` daría el de
/// nuestra plantilla presentado como el de la liga, que es peor que no tenerlo
/// (`D-09`).
///
/// # Los ámbitos de `D-83`
///
/// 1. **Leer el plan**: la coordenada, la capacidad y lo que ya está escrito.
/// 2. La **red**, fuera de todo ámbito.
/// 3. **Un ámbito que escribe el ranking entero y retira lo que sobra** — las dos
///    cosas juntas, o ninguna. Es lo que hace que una caída a mitad no pueda
///    dejar la tabla vacía, al revés que la variante ingenua de *"borro todo y
///    vuelvo a insertar"*.
/// 4. Y el **registro**, en su propio ámbito, para que sobreviva al `rollback` de
///    la que falla (`D-85`).
public struct IngestScorers: Sendable {
    private let unitOfWork: any TenantUnitOfWork
    private let federation: any FederationClient
    private let clock: any Clock
    private let ids: any UUIDProvider

    /// De dónde salen las capacidades de la federación.
    ///
    /// **Inyectable solo para poder probar la guarda de `D-48`**: hoy las dos
    /// federaciones publican goleadores, así que con el catálogo de verdad esa
    /// rama no se ejercita nunca — y una guarda que ningún test alcanza es una
    /// guarda que nadie sabe si funciona. Por defecto es el catálogo (`D-17`),
    /// que es el único sitio donde las capacidades se declaran.
    private let capabilities: @Sendable (FederationCode) -> FederationCapabilities

    public init(
        unitOfWork: any TenantUnitOfWork,
        federation: any FederationClient,
        clock: any Clock,
        ids: any UUIDProvider,
        capabilities: @escaping @Sendable (FederationCode) -> FederationCapabilities = {
            $0.capabilities
        }
    ) {
        self.unitOfWork = unitOfWork
        self.federation = federation
        self.clock = clock
        self.ids = ids
        self.capabilities = capabilities
    }

    /// Sincroniza el ranking de la competición.
    ///
    /// Devuelve la pasada, o **`nil` si esta federación no publica goleadores**
    /// (`D-48`) — que no es un fallo ni una pasada vacía: es que no hay nada que
    /// sincronizar, y registrar una fila diciéndolo cada semana llenaría
    /// `ingestion_runs` de ruido para siempre.
    public func execute(
        competitionID: CompetitionID, actor: ActorContext
    ) async throws -> IngestionRun? {
        // ── Ámbito 1: el plan ───────────────────────────────────────────────
        let plan = try await self.plan(competitionID: competitionID, actor: actor)

        // **La guarda sale antes de tocar nada, y eso incluye la retirada.** Si
        // cortara más abajo, apagar la capacidad de una federación vaciaría los
        // rankings ya ingeridos: `D-48` dice *"no hay dato"*, no *"borra el que
        // había"*.
        guard plan.providesScorers else { return nil }

        let startedAt = clock.now()
        do {
            // ── Fuera de todo ámbito: la red ────────────────────────────────
            let published = try await federation.fetchScorers(plan.coordinate)

            // **La guarda de `D-84`, y es lo único que este sobre puede ofrecer.**
            // El nombre no es eco —se envían números y vuelve texto— pero sí es
            // ciego a la temporada, porque §F.17 midió que es idéntico entre
            // años. La guarda de temporada de `D-91` **no se puede aplicar aquí**:
            // esta respuesta no trae ni una fecha. La hace el calendario.
            try plan.competition.requireSameSource(as: published.competitionName)

            let (scorers, skipped) = rows(
                from: published, competitionID: competitionID,
                existing: plan.existing, syncedAt: startedAt)

            // ── Ámbito 2: el ranking entero y la retirada, juntos ────────────
            let counters = try await write(
                scorers, competitionID: competitionID, syncedAt: startedAt, actor: actor)

            var run = try IngestionRun(
                id: IngestionRunID(raw: ids.next()),
                competitionID: competitionID, kind: .scorers,
                startedAt: startedAt, finishedAt: clock.now())
            run.leagueScorersCreated = counters.created
            run.leagueScorersUpdated = counters.updated
            run.leagueScorersRetired = counters.retired
            run.skipped = skipped

            // ── Ámbito 3: el registro, aparte (`D-85`) ──────────────────────
            try await record(run, actor: actor)
            return run
        } catch {
            // La constancia de la que falla es la única que nadie ve, porque la
            // ingesta no tiene usuario delante (§2.3-b). Se escribe fuera de la
            // transacción que se acaba de deshacer.
            let failed = try IngestionRun(
                id: IngestionRunID(raw: ids.next()),
                competitionID: competitionID, kind: .scorers,
                startedAt: startedAt, finishedAt: clock.now(),
                outcome: .failed, error: diagnosticText(for: error))
            try await record(failed, actor: actor)
            throw error
        }
    }

    /// Las filas publicadas, convertidas en entidades.
    ///
    /// # Aquí no hay cadena de emparejamiento, y es la decisión (`D-09`)
    ///
    /// `IngestStandings` empareja cada fila con un `Team` por su identificador de
    /// federación. Ésta **no empareja con nada**: el ranking incluye jugadores
    /// rivales, de los que no hay plantilla y no la va a haber, así que `fullName`
    /// y `teamLabel` son texto del proveedor y se guardan tal cual (`D-32`).
    ///
    /// > **Y no es que no se pudiera.** [Anexo RFFM §F.19] midió que el
    /// > `codigo_equipo` del ranking casa **16/16** con el del calendario, así que
    /// > unir cada goleador con su `Team` sería posible, por id y sin degradar a
    /// > nombre. No se hace porque `D-09` no quiere — y por eso el DTO del puerto
    /// > ni siquiera transporta ese código.
    ///
    /// # Lo que no se puede construir se descarta y se apunta
    ///
    /// Una fila sin identificador de jugador (`D-93`), sin goles (`D-56`) o que
    /// el Dominio rechace por cualquier otro motivo **no tira la pasada**: es
    /// `D-86` a escala de fila. Un ranking de 217 de 218 sigue siendo un ranking
    /// utilizable, porque **no hay numeración que agujerear** — que es justo lo
    /// contrario de una clasificación, donde una fila que falte deja un hueco en
    /// una numeración que el *spec* declara imposible.
    ///
    /// **El filtro es el propio `init` del Dominio**, y no una lista de
    /// comprobaciones aquí: así la regla vive en un solo sitio y un descarte no
    /// puede discrepar de la invariante que dice defender.
    func rows(
        from published: FederationScorerTable,
        competitionID: CompetitionID,
        existing: [String: LeagueScorer],
        syncedAt: Date
    ) -> (scorers: [LeagueScorer], skipped: [IngestionSkip]) {
        var scorers: [LeagueScorer] = []
        var skipped: [IngestionSkip] = []

        for row in published.rows {
            // **El id se reutiliza si la fila ya estaba**, que es lo que convierte
            // la escritura en *upsert* sin releer y lo que hace que el
            // `UNIQUE(competition_id, federation_player_id)` no salte al
            // refrescar. La clave es `D-93`.
            let previous = row.federationPlayerID.flatMap { existing[$0] }
            do {
                scorers.append(
                    try LeagueScorer(
                        id: previous?.id ?? LeagueScorerID(raw: ids.next()),
                        competitionID: competitionID,
                        federationPlayerID: row.federationPlayerID ?? "",
                        fullName: row.fullName,
                        teamLabel: row.teamLabel,
                        goals: try requireGoals(row),
                        rank: row.rank,
                        syncedAt: syncedAt,
                        createdAt: previous?.createdAt ?? syncedAt,
                        updatedAt: syncedAt))
            } catch {
                skipped.append(
                    IngestionSkip(
                        reason: .unidentifiedScorer,
                        detail: "\(row.fullName) (\(row.teamLabel), codigo_jugador "
                            + "\(row.federationPlayerID ?? "ausente")): "
                            + diagnosticText(for: error)))
            }
        }
        return (scorers, skipped)
    }

    /// Los goles, o el descarte. **`nil` no es `0`** (`D-56`): escribir un cero
    /// afirmaría *"este jugador no ha marcado"*, que es un dato, y lo que hay es
    /// *"la fuente no lo dijo"*.
    private func requireGoals(_ row: FederationScorerRow) throws -> Int {
        guard let goals = row.goals else {
            throw DomainError.invalidValue(
                field: "goals", reason: "la fuente no publicó los goles")
        }
        return goals
    }

    // ── Lo de dentro ─────────────────────────────────────────────────────────

    private struct Plan: Sendable {
        let coordinate: FederationCoordinate
        let competition: Competition
        let providesScorers: Bool
        /// Lo que ya hay, **indexado por la clave de `D-93`**, para reutilizar los
        /// `id` sin releer dentro del ámbito de escritura.
        let existing: [String: LeagueScorer]
    }

    private func plan(
        competitionID: CompetitionID, actor: ActorContext
    ) async throws -> Plan {
        try await unitOfWork.withRepositories(actor: actor) { repositories in
            guard let competition = try await repositories.competitions.find(competitionID)
            else {
                throw ApplicationError.competitionNotFound(id: "\(competitionID.raw)")
            }
            guard let season = try await repositories.seasons.find(competition.seasonID)
            else {
                throw ApplicationError.seasonNotFound(id: "\(competition.seasonID.raw)")
            }
            guard let club = try await repositories.clubs.current() else {
                throw ApplicationError.tenantNotProvisioned(slug: actor.clubSlug.value)
            }

            return Plan(
                coordinate: FederationCoordinate(
                    federationSeasonID: season.federationSeasonID,
                    federationCompetitionID: competition.federationCompetitionID,
                    federationGroupID: competition.federationGroupID,
                    modality: competition.modality),
                competition: competition,
                providesScorers: capabilities(club.federation).providesScorers,
                existing: Dictionary(
                    try await repositories.leagueScorers.list(competitionID: competitionID)
                        .map { ($0.federationPlayerID, $0) },
                    uniquingKeysWith: { first, _ in first }))
        }
    }

    /// Escribe el ranking **y retira lo que sobra, en el mismo ámbito**.
    ///
    /// Las dos cosas van juntas porque `D-83` hace la pasada atómica, y de ahí sale
    /// la propiedad que justifica hacerlo por marca y no borrando primero: o se
    /// escriben las nuevas **y** se retiran las viejas, o no pasa ninguna de las
    /// dos cosas. Una caída a mitad no puede dejar la tabla vacía.
    ///
    /// La marca es `syncedAt`, **la misma instantánea** que se escribió en cada
    /// fila: lo que lleva esta marca se queda y lo demás cae. **Distinto de**, no
    /// *anterior a* — un `<` haría depender la regla de la resolución del reloj, y
    /// dos pasadas en el mismo instante no retirarían nada.
    private func write(
        _ scorers: [LeagueScorer],
        competitionID: CompetitionID,
        syncedAt: Date,
        actor: ActorContext
    ) async throws -> (created: Int, updated: Int, retired: Int) {
        try await unitOfWork.withRepositories(actor: actor) { repositories in
            let existing = Set(
                try await repositories.leagueScorers.list(competitionID: competitionID)
                    .map(\.id))

            var created = 0
            var updated = 0
            for scorer in scorers {
                try await repositories.leagueScorers.save(scorer)
                if existing.contains(scorer.id) { updated += 1 } else { created += 1 }
            }

            let retired = try await repositories.leagueScorers.retire(
                competitionID: competitionID, keepingMark: syncedAt)
            return (created, updated, retired)
        }
    }

    private func record(_ run: IngestionRun, actor: ActorContext) async throws {
        try await unitOfWork.withRepositories(actor: actor) { repositories in
            try await repositories.ingestionRuns.record(run)
        }
    }
}

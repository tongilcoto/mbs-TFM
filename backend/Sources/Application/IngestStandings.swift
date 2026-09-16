public import Domain

/// Caso de uso: **la pasada de clasificación** (F7, §2.3-b).
///
/// Es el hermano de `IngestCalendar`, y se parece a él en casi todo menos en lo
/// que de verdad importa: **la unidad**.
///
/// # Una pasada es una jornada, y eso lo decide el endpoint
///
/// El calendario es agnóstico de jornada **por construcción**: su endpoint
/// devuelve la competición entera en una petición (§5.6), así que su pasada es la
/// competición. `/api/standings?round=N` sirve **una** jornada, así que aquí la
/// pasada es la jornada — y un alta a mitad de temporada deja **tantas filas en
/// `ingestion_runs` como jornadas recompuso**, cada una con su desenlace propio.
///
/// Esa asimetría es la que destapó que `round_id` faltaba en el registro.
///
/// # Las dos fuentes entran por la misma puerta (`D-15`)
///
/// `StandingsSyncPlan` decide, por jornada, si la tabla se **pide** o se
/// **calcula**. Las dos producen las mismas `StandingTable.Line`, así que la
/// columna PREV, el emparejamiento y la escritura son idénticos a partir de ahí.
/// Es `D-15` —*"agnóstica a la fuente"*— hecho flujo de control y no comentario.
///
/// # Los ámbitos de `D-83`, uno por jornada
///
/// 1. **Leer el plan**: la coordenada, las jornadas, los partidos y lo que ya
///    está escrito. **Una vez**, no una por jornada.
/// 2. Por cada jornada: la **red** fuera de todo ámbito, y luego **un ámbito que
///    escribe esa jornada entera** — o se escribe la tabla completa o no se
///    escribe nada de ella.
/// 3. Y el **registro** de esa jornada, en su propio ámbito, para que sobreviva
///    al `rollback` de la que falla (`D-85`).
public struct IngestStandings: Sendable {
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

    /// Sincroniza las jornadas que le toquen, **una pasada por jornada**.
    ///
    /// Devuelve una `IngestionRun` por jornada tratada, en orden ascendente. La
    /// lista vacía **no es un fallo**: es una competición sin ninguna jornada
    /// jugada todavía.
    public func execute(
        competitionID: CompetitionID, actor: ActorContext
    ) async throws -> [IngestionRun] {
        // ── Ámbito 1: el plan, de una vez ───────────────────────────────────
        //
        // **Una sola lectura para todas las jornadas.** Recomponer diez jornadas
        // releyendo los 240 partidos diez veces no daría un dato distinto: el
        // calendario no cambia mientras dura la pasada, y si cambiara, la foto
        // que se quiere es la del instante en que empezó.
        let plan = try await self.plan(competitionID: competitionID, actor: actor)
        guard !plan.steps.isEmpty else { return [] }

        var runs: [IngestionRun] = []
        // La tabla de la jornada anterior, que es de donde sale la columna PREV
        // (`D-33`). Se arrastra en memoria en vez de releerla: las que esta
        // pasada acaba de escribir todavía no están confirmadas cuando se
        // necesitan, y las de antes ya las trajo el ámbito 1.
        var previous: [StandingTable.Line]? = plan.previousOfFirstStep

        for step in plan.steps {
            let startedAt = clock.now()
            do {
                // ── Fuera de todo ámbito: la red ────────────────────────────
                let lines: [StandingTable.Line]
                var skipped: [IngestionSkip] = []
                switch step.source {
                case .fetch:
                    let published = try await federation.fetchStandings(
                        plan.coordinate, round: step.round.number)
                    (lines, skipped) = Self.lines(from: published, teams: plan.teamsByFederationID)
                case .compute:
                    lines = StandingTable.upTo(
                        round: step.round.number, fixtures: plan.fixtures)
                }

                let resolved = StandingTable.resolvingPreviousPositions(
                    lines, previous: previous)

                // ── Ámbito 2: la jornada entera, o nada ─────────────────────
                let counters = try await write(
                    resolved, step: step, competitionID: competitionID, actor: actor)

                var run = try IngestionRun(
                    id: IngestionRunID(raw: ids.next()),
                    competitionID: competitionID, kind: .standings,
                    roundID: step.round.id,
                    startedAt: startedAt, finishedAt: clock.now())
                run.standingRowsCreated = counters.created
                run.standingRowsUpdated = counters.updated
                run.skipped = skipped

                // ── Ámbito 3: el registro, aparte (`D-85`) ──────────────────
                try await record(run, actor: actor)
                runs.append(run)

                // **Y solo después se avanza la PREV.** Si la jornada falló, la
                // siguiente no debe compararse con una tabla que no se escribió.
                previous = lines
            } catch {
                // La constancia de la que falla es la única que nadie ve, porque
                // la ingesta no tiene usuario delante (§2.3-b). Se escribe fuera
                // de la transacción que se acaba de deshacer.
                let failed = try IngestionRun(
                    id: IngestionRunID(raw: ids.next()),
                    competitionID: competitionID, kind: .standings,
                    roundID: step.round.id,
                    startedAt: startedAt, finishedAt: clock.now(),
                    outcome: .failed, error: diagnosticText(for: error))
                try await record(failed, actor: actor)
                throw error
            }
        }
        return runs
    }

    /// Las filas publicadas, emparejadas con los equipos que ya existen.
    ///
    /// # Se empareja **solo por el identificador de federación**, y es deliberado
    ///
    /// La cadena de §3.7 tiene tres pasos, y aquí solo cabe el primero. Los otros
    /// dos comparan la **clave única entera** —nombre, categoría, letra, género y
    /// modalidad (`D-77`)— y una fila de clasificación no trae ni categoría ni
    /// género ni modalidad: trae nombre y poco más. Construir esa clave exigiría
    /// inventarse tres de sus cinco columnas.
    ///
    /// Y hay una razón mejor para no degradar a nombre: **la clasificación no crea
    /// equipos**. El único que los crea es el calendario (`D-66`), así que una
    /// fila que no case no es un equipo nuevo — es un equipo que el calendario
    /// todavía no ha visto. Emparejarla por parecido de nombre pegaría un
    /// *snapshot* al equipo equivocado, y un *snapshot* no lo corrige nadie
    /// después.
    ///
    /// Lo que sostiene que el paso 1 baste: `codequipo` **es el mismo
    /// identificador** que el `codigo_equipo_*` del calendario, medido en
    /// [Anexo RFFM §F.8] y reconfirmado en §F.18.
    static func lines(
        from published: FederationStanding, teams: [String: TeamID]
    ) -> (lines: [StandingTable.Line], skipped: [IngestionSkip]) {
        var lines: [StandingTable.Line] = []
        var skipped: [IngestionSkip] = []

        for row in published.rows {
            guard let federationTeamID = row.team.federationTeamID,
                  let teamID = teams[federationTeamID]
            else {
                skipped.append(
                    IngestionSkip(
                        reason: .unknownStandingTeam,
                        detail: "\(row.team.name) (codequipo "
                            + "\(row.team.federationTeamID ?? "ausente"))"))
                continue
            }
            lines.append(
                StandingTable.Line(
                    teamID: teamID,
                    position: row.position,
                    played: row.played, won: row.won, drawn: row.drawn, lost: row.lost,
                    goalsFor: row.goalsFor, goalsAgainst: row.goalsAgainst,
                    points: row.points))
        }
        return (lines, skipped)
    }

    // ── Lo de dentro ─────────────────────────────────────────────────────────

    private struct Plan: Sendable {
        let coordinate: FederationCoordinate
        let steps: [StandingsSyncPlan.Step]
        let fixtures: [StandingTable.Fixture]
        let teamsByFederationID: [String: TeamID]
        /// La tabla guardada de la jornada **anterior a la primera** que se va a
        /// tratar, si la hay. Sin ella, la PREV de un refresco saldría nula y la
        /// pantalla perdería las flechas de la jornada en curso.
        let previousOfFirstStep: [StandingTable.Line]?
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

            let rounds = try await repositories.rounds.list(competitionID: competitionID)
            let matches = try await repositories.matches.list(competitionID: competitionID)
            let numbersByRoundID = Dictionary(
                rounds.map { ($0.id, $0.number) }, uniquingKeysWith: { first, _ in first })

            let fixtures = matches.compactMap { match -> StandingTable.Fixture? in
                guard let number = numbersByRoundID[match.roundID] else { return nil }
                return StandingTable.Fixture(
                    roundNumber: number,
                    homeTeamID: match.homeTeamID, awayTeamID: match.awayTeamID,
                    result: match.result)
            }

            // Qué jornadas ya tienen *snapshot*. Se pregunta jornada a jornada
            // porque el puerto lee por jornada, que es la unidad del modelo.
            var stored: Set<RoundID> = []
            var tablesByRound: [RoundID: [StandingTable.Line]] = [:]
            for round in rounds {
                let existing = try await repositories.standingRows.list(roundID: round.id)
                guard !existing.isEmpty else { continue }
                stored.insert(round.id)
                tablesByRound[round.id] = existing.map(\.asLine)
            }

            let steps = StandingsSyncPlan.steps(
                rounds: rounds.map { .init(id: $0.id, number: $0.number) },
                fixtures: fixtures,
                alreadyStored: stored,
                providesRoundStandings: club.federationCapabilities.providesRoundStandings)

            let previous = steps.first.flatMap { first in
                rounds.first { $0.number == first.round.number - 1 }
                    .flatMap { tablesByRound[$0.id] }
            }

            return Plan(
                coordinate: FederationCoordinate(
                    federationSeasonID: season.federationSeasonID,
                    federationCompetitionID: competition.federationCompetitionID,
                    federationGroupID: competition.federationGroupID,
                    modality: competition.modality),
                steps: steps,
                fixtures: fixtures,
                teamsByFederationID: Dictionary(
                    try await repositories.teams.list().compactMap { team in
                        team.federationTeamID.map { ($0, team.id) }
                    }, uniquingKeysWith: { first, _ in first }),
                previousOfFirstStep: previous)
        }
    }

    private func write(
        _ lines: [StandingTable.Line],
        step: StandingsSyncPlan.Step,
        competitionID: CompetitionID,
        actor: ActorContext
    ) async throws -> (created: Int, updated: Int) {
        try await unitOfWork.withRepositories(actor: actor) { repositories in
            let existing = try await repositories.standingRows.list(roundID: step.round.id)
            let byTeam = Dictionary(
                existing.map { ($0.teamID, $0) }, uniquingKeysWith: { first, _ in first })

            var created = 0
            var updated = 0
            let now = clock.now()
            for line in lines {
                // **El id lo pone el caso de uso**, igual que en las cuatro
                // entidades de F5: reutilizar el de la fila que ya está es lo que
                // convierte la escritura en *upsert* sin releer, y lo que hace que
                // el `UNIQUE(round_id, team_id)` no salte al refrescar.
                let previous = byTeam[line.teamID]
                try await repositories.standingRows.save(
                    try StandingRow(
                        id: previous?.id ?? StandingRowID(raw: ids.next()),
                        competitionID: competitionID,
                        roundID: step.round.id,
                        teamID: line.teamID,
                        position: line.position,
                        previousPosition: line.previousPosition,
                        played: line.played, won: line.won,
                        drawn: line.drawn, lost: line.lost,
                        goalsFor: line.goalsFor, goalsAgainst: line.goalsAgainst,
                        points: line.points,
                        createdAt: previous?.createdAt ?? now, updatedAt: now))
                if previous == nil { created += 1 } else { updated += 1 }
            }
            return (created, updated)
        }
    }

    private func record(_ run: IngestionRun, actor: ActorContext) async throws {
        try await unitOfWork.withRepositories(actor: actor) { repositories in
            try await repositories.ingestionRuns.record(run)
        }
    }
}

extension StandingRow {
    /// La fila guardada, vista como lo que la aritmética entiende.
    ///
    /// Existe para la columna PREV: comparar la jornada N con la N−1 necesita la
    /// tabla anterior en el mismo tipo que produce el cálculo, venga de donde
    /// venga (`D-15`).
    var asLine: StandingTable.Line {
        StandingTable.Line(
            teamID: teamID, position: position,
            played: played, won: won, drawn: drawn, lost: lost,
            goalsFor: goalsFor, goalsAgainst: goalsAgainst, points: points,
            previousPosition: previousPosition)
    }
}

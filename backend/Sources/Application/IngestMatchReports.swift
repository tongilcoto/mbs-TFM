public import Domain
import struct Foundation.Date

/// Caso de uso: **la pasada de actas** (R7.12, D-138), la cuarta de cada competición, detrás de los goleadores.
///
/// Carga **una vez** el acta de cada partido del club cuando la federación la cierra (`D-125`, `D-133`): la
/// convocatoria, los goles y las tarjetas, casados con los jugadores del club por el conector (`D-126`).
///
/// # Cómo va
///
/// 1. **El plan**, en un ámbito: la competición, su temporada (la archivada no tiene pasada, `D-138` punto 2), los
///    códigos de equipo de cada lado y **los partidos que tocan**: los del club, con código de acta, que ya han
///    empezado y no tienen el acta cargada (`D-133`, punto 1).
/// 2. **La federación, fuera de todo ámbito**, un acta detrás de otra. La sin cerrar se cuenta y se deja; la que no
///    se puede leer, o cuyos equipos no son los del partido, se cuenta como fallida con su código (`D-138`, puntos
///    1 y 7). Ninguna de las dos hace fallida la pasada: se vuelven a pedir en la siguiente.
/// 3. Cada acta cerrada, **en su propia transacción** (`D-138`, punto 1).
/// 4. El registro, aparte (`D-85`).
public struct IngestMatchReports: Sendable {
    private let unitOfWork: any TenantUnitOfWork
    private let federation: any FederationClient
    private let clock: any Clock
    private let ids: any UUIDProvider
    /// El diccionario de nombres (`D-123`), leído en cada pasada: los nombres nuevos se guardan con sus tildes.
    private let names: any NameDictionarySource

    public init(
        unitOfWork: any TenantUnitOfWork, federation: any FederationClient, clock: any Clock, ids: any UUIDProvider,
        names: any NameDictionarySource
    ) {
        self.unitOfWork = unitOfWork
        self.federation = federation
        self.clock = clock
        self.ids = ids
        self.names = names
    }

    /// Carga las actas que tocan de la competición y deja la fila de la pasada (`D-138`).
    ///
    /// Devuelve la pasada, o **`nil` si no hay pasada de actas**: la competición es de una temporada archivada
    /// (`D-138`, punto 2). Un acta que falla no la hace fallida: se cuenta y se vuelve a pedir en la siguiente.
    public func execute(competitionID: CompetitionID, actor: ActorContext) async throws -> IngestionRun? {
        guard let plan = try await plan(competitionID: competitionID, actor: actor) else { return nil }
        let startedAt = clock.now()
        let run: IngestionRun
        do {
            let classified = await classify(plan)
            var counters = Counters(notClosed: classified.notClosed, failed: classified.failed.count,
                                    skipped: classified.failed)
            let dictionary = names.read() ?? .empty
            var synced = Set<TeamID>()
            for due in classified.toLoad {
                // **La ficha, fuera de la transacción**, como en la sincronización (`D-100`): la de los equipos del
                // club en el partido que nadie ha sincronizado, una vez por pasada. Si no llega, el acta se carga
                // igual y la plantilla se intenta con la siguiente.
                var rosters: [TeamID: FederationTeamRoster] = [:]
                for team in [due.match.homeTeamID, due.match.awayTeamID]
                where plan.unsynced.contains(team) && !synced.contains(team) {
                    guard let code = plan.codes[team] else { continue }
                    if let roster = try? await federation.fetchTeamRoster(federationTeamID: code) {
                        rosters[team] = roster
                    }
                }
                let fetched = rosters
                do {
                    let loaded = try await unitOfWork.withRepositories(actor: actor) { r in
                        try await self.load(due, plan: plan, rosters: fetched, names: dictionary, in: r)
                    }
                    synced.formUnion(rosters.keys)
                    counters.loaded += 1
                    counters.playersAdded += loaded.playersAdded
                    counters.skipped += loaded.skipped
                } catch {
                    // **En su transacción** (`D-138`, punto 1): la que falla no deja nada, y las demás siguen.
                    counters.failed += 1
                    counters.skipped.append(IngestionSkip(
                        reason: .unreadableMatchReport,
                        detail: "\(due.match.federationMatchID ?? "?"): \(diagnosticText(for: error))"))
                }
            }
            var done = try IngestionRun(
                id: IngestionRunID(raw: ids.next()), competitionID: competitionID, kind: .matchReports,
                startedAt: startedAt, finishedAt: clock.now())
            done.matchReportsLoaded = counters.loaded
            done.matchReportsNotClosed = counters.notClosed
            done.matchReportsFailed = counters.failed
            done.matchReportPlayersAdded = counters.playersAdded
            done.skipped = counters.skipped
            run = done
        } catch {
            let failed = try IngestionRun(
                id: IngestionRunID(raw: ids.next()), competitionID: competitionID, kind: .matchReports,
                startedAt: startedAt, finishedAt: clock.now(), outcome: .failed, error: diagnosticText(for: error))
            do { try await record(failed, actor: actor) } catch {}
            throw error
        }
        // El registro, aparte (`D-85`): si solo falla al apuntar, las actas ya están cargadas, y se dice así.
        do {
            try await record(run, actor: actor)
        } catch {
            throw ApplicationError.runNotRecorded(competitionID: "\(competitionID)", reason: diagnosticText(for: error))
        }
        return run
    }

    private struct Counters {
        var loaded = 0
        var notClosed: Int
        var failed: Int
        var playersAdded = 0
        var skipped: [IngestionSkip]
    }

    private func record(_ run: IngestionRun, actor: ActorContext) async throws {
        _ = try await unitOfWork.withRepositories(actor: actor) { r in
            try await r.ingestionRuns.record(run)
        }
    }

    // ── 1 · El plan ────────────────────────────────────────────────────────────

    struct Plan: Sendable {
        let competition: Competition
        let season: Season
        /// Los partidos cuya acta se pide, en el orden en que se piden: por fecha y hora.
        let due: [Match]
        /// El código de la federación de cada equipo de la competición: el de la inscripción en los del club
        /// (`D-101`), el suyo en los rivales. Con él se comprueba que el acta sea de ese partido.
        let codes: [TeamID: String]
        /// Los equipos del club que juegan en la competición.
        let ownTeams: Set<TeamID>
        /// Los del club cuya plantilla nadie ha sincronizado, **solo en la temporada en curso**: la ficha es la de
        /// hoy (decisión 1 de R6.14). La carga la sincroniza antes de su primera acta (`D-127`, punto 1).
        let unsynced: Set<TeamID>
    }

    /// `nil` si la competición no tiene pasada de actas: la de una temporada archivada (`D-138`, punto 2), como los
    /// goleadores cuando la federación no los publica.
    func plan(competitionID: CompetitionID, actor: ActorContext) async throws -> Plan? {
        let now = clock.now()
        return try await unitOfWork.withRepositories(actor: actor) { r in
            guard let competition = try await r.competitions.find(competitionID) else {
                throw ApplicationError.competitionNotFound(id: "\(competitionID)")
            }
            guard let season = try await r.seasons.find(competition.seasonID) else {
                throw ApplicationError.seasonNotFound(id: "\(competition.seasonID)")
            }
            guard season.archivedAt == nil else { return nil }

            let matches = try await r.matches.list(competitionID: competitionID)
            let teams = try await r.teams.list(ids: Array(Set(matches.flatMap { [$0.homeTeamID, $0.awayTeamID] })))
            let ownTeams = Set(teams.filter { $0.opponentClubID == nil }.map(\.id))
            let isCurrent = try await r.seasons.list(includingArchived: false).current(on: now)?.id == season.id
            var codes: [TeamID: String] = [:]
            var unsynced = Set<TeamID>()
            for team in teams {
                if ownTeams.contains(team.id) {
                    let rows = try await r.teamRegistrations.list(teamID: team.id, seasonID: season.id)
                    codes[team.id] = rows.first { $0.competitionID == competitionID }?.federationTeamID
                    if isCurrent, rows.allSatisfy({ $0.rosterSyncedAt == nil }) { unsynced.insert(team.id) }
                } else {
                    codes[team.id] = team.federationTeamID
                }
            }

            let candidates = matches.filter { match in
                !match.isRestDay && match.federationMatchID != nil
                    && (ownTeams.contains(match.homeTeamID) || ownTeams.contains(match.awayTeamID))
                    && match.kickoff.hasStarted(on: now)
            }
            let loaded = try await r.matches.reportCopies(of: candidates.map(\.id))
            func order(_ match: Match) -> (Date, Int) {
                (match.kickoff.date, match.kickoff.time.map { $0.hour * 60 + $0.minute } ?? 0)
            }
            let due = candidates.filter { loaded[$0.id] == nil }.sorted { order($0) < order($1) }
            return Plan(competition: competition, season: season, due: due, codes: codes, ownTeams: ownTeams,
                        unsynced: unsynced)
        }
    }

    // ── 2 · La federación, acta por acta ──────────────────────────────────────

    /// Un acta cerrada y de ese partido, lista para cargar.
    struct Due: Sendable {
        let match: Match
        let report: FederationMatchReport
    }

    /// Lo que la federación dijo de cada partido del plan.
    struct Classified: Sendable {
        var toLoad: [Due] = []
        /// Las que la federación todavía no ha cerrado (`D-133`, punto 2).
        var notClosed = 0
        /// Las que no se cargan: no se pudieron leer o no son de ese partido, con su código (`D-138`).
        var failed: [IngestionSkip] = []
    }

    /// **Fuera de todo ámbito**: la federación puede tardar segundos por acta, y el acceso a los datos es de una
    /// conexión (`D-100`). Un acta que falla no corta las demás.
    func classify(_ plan: Plan) async -> Classified {
        var result = Classified()
        for match in plan.due {
            guard let code = match.federationMatchID else { continue }
            let report: FederationMatchReport
            do {
                report = try await federation.fetchMatchReport(federationMatchID: code)
            } catch {
                result.failed.append(IngestionSkip(
                    reason: .unreadableMatchReport, detail: "\(code): \(diagnosticText(for: error))"))
                continue
            }
            guard report.isClosed else {
                result.notClosed += 1
                continue
            }
            // **El acta tiene que ser de ese partido** (`D-138`, punto 7): sus dos equipos, los nuestros.
            let expected = (plan.codes[match.homeTeamID], plan.codes[match.awayTeamID])
            guard expected.0 == report.homeTeamFederationID, expected.1 == report.awayTeamFederationID else {
                result.failed.append(IngestionSkip(
                    reason: .unreadableMatchReport,
                    detail: "\(code): el acta es de los equipos \(report.homeTeamFederationID) y "
                        + "\(report.awayTeamFederationID), no de los del partido "
                        + "(\(expected.0 ?? "sin código")) y (\(expected.1 ?? "sin código"))"))
                continue
            }
            result.toLoad.append(Due(match: match, report: report))
        }
        return result
    }

    // ── 3 · Un acta, en su transacción ─────────────────────────────────────────

    /// Lo que dejó la carga de un acta.
    struct Loaded: Sendable {
        var playersAdded = 0
        var skipped: [IngestionSkip] = []
        /// La convocatoria tal como la trajo el acta (`D-134`).
        var lineup: [ReportLineupEntry] = []
        /// Con quién de los nuestros es cada jugador del club en el acta: su fila de la temporada y el equipo con el
        /// que jugó. Por lado y código, porque entre dos equipos del club los dos lados son nuestros.
        var rows: [Key: (player: PlayerID, team: TeamID)] = [:]

        struct Key: Hashable, Sendable {
            let side: FederationReportSide
            let code: String
        }
    }

    func load(
        _ due: Due, plan: Plan, rosters: [TeamID: FederationTeamRoster], names: CastilianNames,
        in r: any Repositories
    ) async throws -> Loaded {
        let now = clock.now()
        let season = plan.season
        let code = due.match.federationMatchID ?? "?"
        var loaded = Loaded()

        // **La plantilla que nadie sincronizó, primero** (`D-127`, punto 1): la misma sincronización, que solo añade.
        if !rosters.isEmpty, let club = try await r.clubs.current() {
            for (teamID, roster) in rosters {
                guard let team = try await r.teams.find(teamID), let federationCode = plan.codes[teamID],
                      let registration = try await r.teamRegistrations.list(teamID: teamID, seasonID: season.id)
                          .first(where: { $0.competitionID == plan.competition.id })
                else { continue }
                let syncPlan = SyncTeamRoster.Plan(
                    club: club, federation: club.federation, team: team, season: season,
                    registration: registration, code: federationCode)
                let summary = try await SyncTeamRoster.apply(
                    roster, plan: syncPlan, now: now, ids: ids, names: names, client: federation, in: r)
                loaded.playersAdded += summary.added
            }
        }

        // **Los jugadores del club**, lado por lado: del rival, nada (`D-138`, punto 5).
        var profiles = try await r.playerProfiles.all()
        let sides: [(FederationReportSide, TeamID)] = [
            (.home, due.match.homeTeamID), (.away, due.match.awayTeamID),
        ].filter { plan.ownTeams.contains($0.1) }
        for (side, teamID) in sides {
            for published in due.report.players where published.side == side {
                let name = published.fullName
                    .flatMap { try? PlayerName($0) }?
                    .spelledInCastilian(with: names)
                let match = federation.matchPlayers(
                    [FederationMatchQuery(federationPlayerID: published.federationPlayerID, name: name)],
                    against: profiles.map(FederationMatchCandidate.init))[0]
                let matched: PlayerProfile?
                switch match {
                case .byCode(let id), .byName(let id): matched = profiles.first { $0.id == id }
                case .ambiguousName, .none: matched = nil
                }

                // El perfil: el casado, con su código si no lo tenía (`D-126`), o uno nuevo, sin año.
                let profile: PlayerProfile
                if var found = matched {
                    if found.federationPlayerID == nil {
                        found = found.withFederationPlayerID(published.federationPlayerID)
                        try await r.playerProfiles.save(found)
                        profiles = profiles.map { $0.id == found.id ? found : $0 }
                    }
                    profile = found
                } else {
                    // **Sin un nombre que se lea no hay perfil** (`D-138`, punto 4): ni alta ni convocatoria.
                    guard let name else {
                        loaded.skipped.append(IngestionSkip(
                            reason: .unreadableReportPlayerName, detail: "\(code): \(published.publishedName)"))
                        continue
                    }
                    profile = PlayerProfile(
                        id: PlayerProfileID(raw: ids.next()), fullName: name, birthYear: nil,
                        federationPlayerID: published.federationPlayerID, createdAt: now, updatedAt: now)
                    try await r.playerProfiles.save(profile)
                    profiles.append(profile)
                }

                // Su fila de la temporada: la de este equipo; la de otro, de refuerzo (`D-127` punto 4, `D-128`); o
                // un alta aquí, también si el club lo había dado de baja (`D-127`, puntos 2 y 3).
                let seasonRows = try await r.players.list(profileID: profile.id, seasonID: season.id)
                let row: Player
                if let here = seasonRows.first(where: { $0.teamID == teamID }) {
                    row = here
                } else if let elsewhere = seasonRows.first {
                    row = elsewhere
                } else {
                    let roster = try await r.players.list(teamID: teamID, seasonID: season.id)
                    let shirt = profile.lastShirtNumber.flatMap { number in
                        roster.contains { $0.shirtNumber == number } ? nil : number
                    }
                    row = Player(
                        id: PlayerID(raw: ids.next()), profileID: profile.id, teamID: teamID, seasonID: season.id,
                        shirtNumber: shirt, position: profile.lastPosition, photoKey: profile.lastPhotoKey,
                        createdAt: now, updatedAt: now)
                    try await r.players.save(row)
                    loaded.playersAdded += 1
                }
                loaded.rows[Loaded.Key(side: side, code: published.federationPlayerID)] = (row.id, teamID)

                // **La convocatoria: manda el acta** (`D-133`, punto 5). Jugó el titular y el que entra en un cambio;
                // los demás suplentes, «Convocado sin minutos» (`D-132`). Su dorsal; los minutos del club, si jugó.
                let status: AppearanceStatus = published.isStarter || published.cameOn ? .jugado : .convocadoSinMinutos
                let shirt = published.shirtNumber.flatMap { try? ShirtNumber($0) }
                let existing = try await r.appearances.find(playerID: row.id, matchID: due.match.id)
                if let existing, existing.teamID != teamID {
                    // El equipo es identidad (`D-37`): con otro equipo, la fila se rehace.
                    try await r.appearances.delete(existing.id)
                }
                let kept = existing.flatMap { $0.teamID == teamID ? $0 : nil }
                try await r.appearances.save(Appearance(
                    id: kept?.id ?? AppearanceID(raw: ids.next()), playerID: row.id, matchID: due.match.id,
                    teamID: teamID, status: status, shirtNumber: shirt,
                    minutes: status == .jugado ? kept?.minutes : nil,
                    createdAt: kept?.createdAt ?? now, updatedAt: now))
                loaded.lineup.append(ReportLineupEntry(playerID: row.id, teamID: teamID, status: status))
            }
        }
        return loaded
    }
}

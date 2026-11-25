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

    public init(
        unitOfWork: any TenantUnitOfWork, federation: any FederationClient, clock: any Clock, ids: any UUIDProvider
    ) {
        self.unitOfWork = unitOfWork
        self.federation = federation
        self.clock = clock
        self.ids = ids
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
            var codes: [TeamID: String] = [:]
            for team in teams {
                if ownTeams.contains(team.id) {
                    let rows = try await r.teamRegistrations.list(teamID: team.id, seasonID: season.id)
                    codes[team.id] = rows.first { $0.competitionID == competitionID }?.federationTeamID
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
            return Plan(competition: competition, season: season, due: due, codes: codes, ownTeams: ownTeams)
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
}

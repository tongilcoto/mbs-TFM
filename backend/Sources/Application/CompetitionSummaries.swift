public import Domain

/// **El resumen de cada competición de una inscripción** (`D-113`): lo que la
/// portada enseña de cada equipo. Lo usan la lista de equipos de la temporada y
/// la lectura de un equipo, que tienen la misma forma (`D-102`).
///
/// Por competición, dos lecturas: sus jornadas y su última tabla; por equipo, sus
/// partidos. Y de una vez para toda la lista, los nombres de los equipos del
/// último y el próximo partido y la fila de cada lado en su jornada. La regla de qué es lo
/// último y lo próximo es del dominio (`TeamSummary`).
public struct CompetitionSummaries: Sendable {
    private let rounds: any RoundRepository
    private let matches: any MatchRepository
    private let standingRows: any StandingRowRepository
    private let teams: any TeamRepository
    private let opponentClubs: any OpponentClubRepository

    public init(
        rounds: any RoundRepository, matches: any MatchRepository, standingRows: any StandingRowRepository,
        teams: any TeamRepository, opponentClubs: any OpponentClubRepository
    ) {
        self.rounds = rounds
        self.matches = matches
        self.standingRows = standingRows
        self.teams = teams
        self.opponentClubs = opponentClubs
    }

    /// Las mismas inscripciones, con el resumen en cada competición.
    public func adding(to registrations: [SeasonRegistration], club: Club) async throws -> [SeasonRegistration] {
        // Lo que se lee, una vez por competición o por equipo: los números de las
        // jornadas, la última tabla y los partidos del equipo. **No** todos los
        // partidos de la competición ni las tablas de todas las jornadas: medido
        // en R5.5, convertir esas filas era casi todo el tiempo de la respuesta.
        var numbers: [CompetitionID: [RoundID: Int]] = [:]
        var tables: [CompetitionID: [StandingRow]] = [:]
        var teamMatches: [TeamID: [Match]] = [:]
        var summaries: [TeamCompetition: TeamSummary] = [:]
        for registration in registrations {
            let team = registration.team.id
            for competition in registration.competitions {
                let id = competition.competitionID
                if numbers[id] == nil {
                    numbers[id] = Dictionary(
                        uniqueKeysWithValues: try await rounds.list(competitionID: id).map { ($0.id, $0.number) })
                    tables[id] = try await standingRows.latest(competitionID: id)
                }
                if teamMatches[team] == nil { teamMatches[team] = try await matches.list(teamID: team) }
                // Los partidos del equipo en otra competición no hace falta quitarlos:
                // sus jornadas no tienen número en ésta, y el dominio los deja fuera
                // (lo vio la mutación, R5.5).
                summaries[TeamCompetition(team: team, competition: id)] = TeamSummary.of(
                    team, matches: teamMatches[team] ?? [], rows: tables[id] ?? [], roundNumbers: numbers[id] ?? [:])
            }
        }

        // Lo que llevan el último y el próximo partido: los nombres de sus equipos
        // y la fila de cada lado en su jornada (`D-112`), de una vez para toda la
        // lista. La de la última tabla ya está leída.
        let shown = summaries.values.flatMap { [$0.lastMatch, $0.nextMatch].compactMap { $0 } }
        let labels = try await TeamLabels.resolve(
            shown.flatMap { [$0.homeTeamID, $0.awayTeamID] }, club: club, teams: teams, opponentClubs: opponentClubs)
        let read = Set(tables.values.flatMap { $0.map(\.roundID) })
        let others = try await standingRows.list(roundIDs: Array(Set(shown.map(\.roundID)).subtracting(read)))
        let rows = tables.values.flatMap { $0 } + others

        return registrations.map { registration in
            SeasonRegistration(
                team: registration.team, seasonID: registration.seasonID,
                competitions: registration.competitions.map { competition in
                    let id = competition.competitionID
                    guard let summary = summaries[TeamCompetition(team: registration.team.id, competition: id)]
                    else { return competition }
                    // Cada lado, con su fila de la jornada del partido (`D-112`).
                    func line(_ match: Match?) -> ListMatches.Line? {
                        guard let match, let home = labels[match.homeTeamID], let away = labels[match.awayTeamID]
                        else { return nil }
                        func standing(_ team: TeamID) -> StandingRow? {
                            rows.first { $0.roundID == match.roundID && $0.teamID == team }
                        }
                        return ListMatches.Line(
                            match: match, roundNumber: numbers[id]?[match.roundID] ?? 0,
                            home: .init(team: home, standing: standing(match.homeTeamID)),
                            away: .init(team: away, standing: standing(match.awayTeamID)))
                    }
                    return RegisteredCompetition(
                        competitionID: id, federationTeamID: competition.federationTeamID,
                        summary: CompetitionSummary(
                            position: summary.position, form: summary.form,
                            lastMatch: line(summary.lastMatch), nextMatch: line(summary.nextMatch),
                            nextOpponentPosition: summary.nextOpponentPosition))
                })
        }
    }

    private struct TeamCompetition: Hashable {
        let team: TeamID
        let competition: CompetitionID
    }
}

/// El resumen de un equipo en una competición, listo para la respuesta: el del
/// dominio, con el último y el próximo partido como líneas de `ListMatches`
/// (cada lado con su club y su fila de esa jornada), que es la forma de
/// `MatchResponse`.
public struct CompetitionSummary: Equatable, Sendable {
    public let position: Int?
    public let form: [FormEntry]
    public let lastMatch: ListMatches.Line?
    public let nextMatch: ListMatches.Line?
    public let nextOpponentPosition: Int?

    public init(
        position: Int?, form: [FormEntry], lastMatch: ListMatches.Line?, nextMatch: ListMatches.Line?,
        nextOpponentPosition: Int?
    ) {
        self.position = position
        self.form = form
        self.lastMatch = lastMatch
        self.nextMatch = nextMatch
        self.nextOpponentPosition = nextOpponentPosition
    }

    public static let empty = CompetitionSummary(
        position: nil, form: [], lastMatch: nil, nextMatch: nil, nextOpponentPosition: nil)
}

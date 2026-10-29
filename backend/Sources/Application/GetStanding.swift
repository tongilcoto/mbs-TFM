public import Domain

/// `GET /v1/standings?roundId=` (§5.1, `D-34`, R4.7): **la clasificación de una
/// jornada**, por puesto, cada fila con su equipo y su racha.
///
/// La fila es la guardada (`D-15`); **la racha no se guarda**: se deriva de los
/// partidos de la competición hasta esa jornada (`Form.of`, `D-34`). Una jornada
/// sin tabla todavía da la lista vacía, no un error.
public struct GetStanding: Sendable {
    private let clubs: any ClubRepository
    private let rounds: any RoundRepository
    private let standingRows: any StandingRowRepository
    private let matches: any MatchRepository
    private let teams: any TeamRepository
    private let opponentClubs: any OpponentClubRepository

    public init(
        clubs: any ClubRepository, rounds: any RoundRepository, standingRows: any StandingRowRepository,
        matches: any MatchRepository, teams: any TeamRepository, opponentClubs: any OpponentClubRepository
    ) {
        self.clubs = clubs
        self.rounds = rounds
        self.standingRows = standingRows
        self.matches = matches
        self.teams = teams
        self.opponentClubs = opponentClubs
    }

    /// Una fila de la tabla, con su equipo nombrado y su racha.
    public struct Line: Equatable, Sendable {
        public let row: StandingRow
        public let team: LabeledTeam
        public let form: [FormEntry]
    }

    public func execute(actor: ActorContext, roundID: RoundID) async throws -> [Line] {
        guard let club = try await clubs.current() else {
            throw ApplicationError.tenantNotProvisioned(slug: actor.clubSlug.value)
        }
        guard let round = try await rounds.find(roundID) else {
            throw ApplicationError.roundNotFound(id: "\(roundID)")
        }
        // Ya por puesto (el repositorio lo promete, §5.1).
        let rows = try await standingRows.list(roundID: roundID)
        guard !rows.isEmpty else { return [] }

        let labels = try await TeamLabels.resolve(
            rows.map(\.teamID), club: club, teams: teams, opponentClubs: opponentClubs)
        let numbers = Dictionary(
            uniqueKeysWithValues: try await rounds.list(competitionID: round.competitionID).map { ($0.id, $0.number) })
        let played = try await matches.list(competitionID: round.competitionID)
        return rows.map { row in
            Line(
                row: row, team: labels[row.teamID]!,
                form: Form.of(row.teamID, upTo: round.number, matches: played, roundNumbers: numbers))
        }
    }
}

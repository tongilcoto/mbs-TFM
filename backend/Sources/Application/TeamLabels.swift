public import Domain

/// **Un equipo con los dos nombres de su club**, el propio o el rival: lo que
/// el adaptador HTTP necesita para componer un `TeamRef` (`D-32`, `D-109`,
/// `D-111`). Lo usan las filas de la clasificación y de los partidos (R4.7, R4.8).
public struct LabeledTeam: Equatable, Sendable {
    public let team: Team
    public let clubName: String
    public let clubShortName: String

    public init(team: Team, clubName: String, clubShortName: String) {
        self.team = team
        self.clubName = clubName
        self.clubShortName = clubShortName
    }
}

/// Resuelve de una vez los equipos de una tabla o de un calendario, con su club:
/// el propio para los del club, el rival para los demás. Dos lecturas y no una
/// por equipo: los equipos por sus ids, y los clubes rivales, que son pocos.
public enum TeamLabels {
    public static func resolve(
        _ ids: [TeamID], club: Club, teams: any TeamRepository, opponentClubs: any OpponentClubRepository
    ) async throws -> [TeamID: LabeledTeam] {
        let found = try await teams.list(ids: Array(Set(ids)))
        let rivals = found.contains { !$0.isOwn } ? try await opponentClubs.list() : []
        var labels: [TeamID: LabeledTeam] = [:]
        for team in found {
            guard let rivalClubID = team.opponentClubID else {
                labels[team.id] = LabeledTeam(team: team, clubName: club.name, clubShortName: club.shortName)
                continue
            }
            // La FK de `teams.opponent_club_id` lo impide: si pasa, la base está
            // rota, y es un 500.
            guard let rival = rivals.first(where: { $0.id == rivalClubID }) else {
                throw MissingLabel(team: "\(team.id)")
            }
            labels[team.id] = LabeledTeam(team: team, clubName: rival.name, clubShortName: rival.shortName)
        }
        // Lo mismo con un equipo que la tabla o el partido nombran y no está.
        if let missing = ids.first(where: { labels[$0] == nil }) { throw MissingLabel(team: "\(missing)") }
        return labels
    }

    struct MissingLabel: Error {
        let team: String
    }
}

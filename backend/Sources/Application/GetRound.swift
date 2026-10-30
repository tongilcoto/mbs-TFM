public import Domain

/// `GET /v1/rounds/{roundId}` (§5.1, R4.6): **una jornada**, y si está en curso.
/// Para saberlo hacen falta las demás de su competición: «en curso» es la
/// próxima que no ha pasado (`[Round].current(on:)`).
public struct GetRound: Sendable {
    private let rounds: any RoundRepository
    private let clock: any Clock

    public init(rounds: any RoundRepository, clock: any Clock) {
        self.rounds = rounds
        self.clock = clock
    }

    public struct Result: Equatable, Sendable {
        public let round: Round
        public let isCurrent: Bool
    }

    public func execute(roundID: RoundID) async throws -> Result {
        guard let round = try await rounds.find(roundID) else {
            throw ApplicationError.roundNotFound(id: "\(roundID)")
        }
        let siblings = try await rounds.list(competitionID: round.competitionID)
        return Result(round: round, isCurrent: siblings.current(on: clock.now())?.id == round.id)
    }
}

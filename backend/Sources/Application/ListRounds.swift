public import Domain

/// `GET /v1/rounds?competitionId=` (§5.1, R4.6): **las jornadas de una
/// competición**, por número, y cuál está en curso.
///
/// **`isCurrent` se deriva en lectura**, como el de las temporadas: la regla vive
/// en el Dominio (`[Round].current(on:)`), y aquí solo se le da el reloj.
public struct ListRounds: Sendable {
    private let competitions: any CompetitionRepository
    private let rounds: any RoundRepository
    private let clock: any Clock

    public init(competitions: any CompetitionRepository, rounds: any RoundRepository, clock: any Clock) {
        self.competitions = competitions
        self.rounds = rounds
        self.clock = clock
    }

    /// Las jornadas, por número, y cuál está en curso; viajan juntas porque
    /// `isCurrent` no es de una jornada sola, sino de su competición.
    public struct Listing: Equatable, Sendable {
        public let rounds: [Round]
        public let currentID: RoundID?
    }

    public func execute(competitionID: CompetitionID) async throws -> Listing {
        // El id lo puso quien llama: si no existe, **404** (`COMPETITION_NOT_FOUND`).
        guard try await competitions.find(competitionID) != nil else {
            throw ApplicationError.competitionNotFound(id: "\(competitionID)")
        }
        // Por número aquí, sin fiarse del orden del repositorio: es lo que promete
        // el contrato (§5.3).
        let list = try await rounds.list(competitionID: competitionID).sorted { $0.number < $1.number }
        return Listing(rounds: list, currentID: list.current(on: clock.now())?.id)
    }
}

import Application
import Domain
import Foundation

/// Los dobles del nivel 2 (§8.1, Plan §5): *"orquestación con los puertos
/// falseados: `FederationClient` en memoria, `Clock` y `UUIDProvider` fijos.
/// Sin I/O"*.
///
/// **No son un mini-ORM.** Guardan por `id` y devuelven listas, que es todo lo
/// que los puertos de F5 prometen. Lo que aquí **no** hay —y es deliberado— son
/// las restricciones de §3.5: si el caso de uso escribiera dos filas que el
/// `UNIQUE` rechazaría, estos dobles lo aceptarían tan contentos. Cazar eso es
/// del nivel 3, y por eso F5 tiene los dos.

/// El almacén compartido. Es un `actor` porque los repositorios son `Sendable` y
/// mutan; no porque haya concurrencia que probar.
actor IngestionStore {
    var seasons: [Season] = []
    var competitions: [Competition] = []
    var rounds: [Round] = []
    var opponentClubs: [OpponentClub] = []
    var teams: [Team] = []
    var matches: [Match] = []

    /// Cuántas veces se abrió un ámbito de tenant. Lo mira el test de
    /// atomicidad: la pasada escribe en **uno**.
    var scopesOpened = 0

    func seed(seasons: [Season] = [], competitions: [Competition] = [],
              rounds: [Round] = [], opponentClubs: [OpponentClub] = [],
              teams: [Team] = [], matches: [Match] = []) {
        self.seasons += seasons
        self.competitions += competitions
        self.rounds += rounds
        self.opponentClubs += opponentClubs
        self.teams += teams
        self.matches += matches
    }

    func openScope() { scopesOpened += 1 }

    func save(_ value: Season) { upsert(&seasons, value) { $0.id == value.id } }
    func save(_ value: Competition) { upsert(&competitions, value) { $0.id == value.id } }
    func save(_ value: Round) { upsert(&rounds, value) { $0.id == value.id } }
    func save(_ value: OpponentClub) { upsert(&opponentClubs, value) { $0.id == value.id } }
    func save(_ value: Team) { upsert(&teams, value) { $0.id == value.id } }
    func save(_ value: Match) { upsert(&matches, value) { $0.id == value.id } }

    private func upsert<T>(_ list: inout [T], _ value: T, where match: (T) -> Bool) {
        if let index = list.firstIndex(where: match) { list[index] = value } else {
            list.append(value)
        }
    }
}

struct FakeSeasonRepository: SeasonRepository {
    let store: IngestionStore
    func find(_ id: SeasonID) async throws -> Season? {
        await store.seasons.first { $0.id == id }
    }
    func findByFederationID(_ federationSeasonID: String) async throws -> Season? {
        await store.seasons.first { $0.federationSeasonID == federationSeasonID }
    }
    func list(includingArchived: Bool) async throws -> [Season] { await store.seasons }
    func save(_ season: Season) async throws { await store.save(season) }
}

struct FakeCompetitionRepository: CompetitionRepository {
    let store: IngestionStore
    func find(_ id: CompetitionID) async throws -> Competition? {
        await store.competitions.first { $0.id == id }
    }
    func findByFederationGroup(
        seasonID: SeasonID, federationGroupID: String
    ) async throws -> Competition? {
        await store.competitions.first {
            $0.seasonID == seasonID && $0.federationGroupID == federationGroupID
        }
    }
    func list(seasonID: SeasonID) async throws -> [Competition] {
        await store.competitions.filter { $0.seasonID == seasonID }
    }
    func save(_ competition: Competition) async throws { await store.save(competition) }
}

struct FakeRoundRepository: RoundRepository {
    let store: IngestionStore
    func list(competitionID: CompetitionID) async throws -> [Round] {
        await store.rounds.filter { $0.competitionID == competitionID }
    }
    func save(_ round: Round) async throws { await store.save(round) }
}

struct FakeOpponentClubRepository: OpponentClubRepository {
    let store: IngestionStore
    func list() async throws -> [OpponentClub] { await store.opponentClubs }
    func save(_ club: OpponentClub) async throws { await store.save(club) }
}

struct FakeTeamRepository: TeamRepository {
    let store: IngestionStore
    func list() async throws -> [Team] { await store.teams }
    func save(_ team: Team) async throws { await store.save(team) }
}

struct FakeMatchRepository: MatchRepository {
    let store: IngestionStore
    func list(competitionID: CompetitionID) async throws -> [Match] {
        await store.matches.filter { $0.competitionID == competitionID }
    }
    func save(_ match: Match) async throws { await store.save(match) }
}

/// `clubs` está en el protocolo desde F0 y esta fase no lo usa. Se falsea
/// **vacío** en vez de dejarlo fuera: quien lo llame por descuido se encuentra
/// un `nil` y no un `fatalError` disfrazado de repositorio.
struct FakeClubRepository: ClubRepository {
    func current() async throws -> Club? { nil }
    func save(_ club: Club) async throws {}
}

struct FakeRepositories: Repositories {
    let store: IngestionStore
    var clubs: any ClubRepository { FakeClubRepository() }
    var seasons: any SeasonRepository { FakeSeasonRepository(store: store) }
    var competitions: any CompetitionRepository { FakeCompetitionRepository(store: store) }
    var rounds: any RoundRepository { FakeRoundRepository(store: store) }
    var opponentClubs: any OpponentClubRepository {
        FakeOpponentClubRepository(store: store)
    }
    var teams: any TeamRepository { FakeTeamRepository(store: store) }
    var matches: any MatchRepository { FakeMatchRepository(store: store) }
}

/// El ámbito de tenant, sin transacción y sin `search_path`.
///
/// Lo único que reproduce es **contar cuántas veces se abre**, que es lo que el
/// caso de uso decide y el nivel 3 no puede afirmar cómodamente.
struct FakeUnitOfWork: TenantUnitOfWork {
    let store: IngestionStore

    func withRepositories<T: Sendable>(
        actor: ActorContext,
        _ work: @escaping @Sendable (any Repositories) async throws -> T
    ) async throws -> T {
        await store.openScope()
        return try await work(FakeRepositories(store: store))
    }
}

/// El `FederationClient` en memoria: devuelve el calendario que se le dé y
/// **apunta con qué coordenada se le llamó**, que es lo que prueba el primer
/// ciclo.
final class SpyFederationClient: FederationClient, @unchecked Sendable {
    private let calendar: FederationCalendar
    private let error: (any Error)?
    private(set) var received: [FederationCoordinate] = []

    init(returning calendar: FederationCalendar) {
        self.calendar = calendar
        self.error = nil
    }

    init(failingWith error: any Error, calendar: FederationCalendar) {
        self.calendar = calendar
        self.error = error
    }

    func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
        received.append(coordinate)
        if let error { throw error }
        return calendar
    }
}

struct FixedClock: Clock {
    let instant: Date
    func now() -> Date { instant }
}

/// Devuelve UUIDs **de una lista, en orden**, para que un test pueda afirmar
/// *qué* fila se creó y no solo cuántas. Si se agota, sigue con UUIDs nuevos:
/// quedarse sin ids no es lo que ningún test de esta fase quiere demostrar.
final class SequentialUUIDProvider: UUIDProvider, @unchecked Sendable {
    private var queue: [UUID]
    init(_ queue: [UUID] = []) { self.queue = queue }
    func next() -> UUID { queue.isEmpty ? UUID() : queue.removeFirst() }
}

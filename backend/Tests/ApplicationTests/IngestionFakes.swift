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
    /// El club del tenant. F6 lo necesita porque de `Club.federation` sale **qué
    /// adaptador** se usa (`D-17`), y eso es una decisión del recorrido, no del
    /// cableado.
    var club: Club?
    var seasons: [Season] = []
    var competitions: [Competition] = []
    var rounds: [Round] = []
    var opponentClubs: [OpponentClub] = []
    var teams: [Team] = []
    var matches: [Match] = []
    var ingestionRuns: [IngestionRun] = []

    /// Cuántas veces se abrió un ámbito de tenant. Lo mira el test de
    /// atomicidad: la pasada escribe en **uno**.
    var scopesOpened = 0

    func seed(club: Club) { self.club = club }

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
    func record(_ value: IngestionRun) { ingestionRuns.append(value) }

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

/// `clubs` entró en el protocolo en F0 y hasta F5 no lo usaba nadie: devolvía
/// `nil` a secas. **F6 sí lo usa** —de `Club.federation` sale el adaptador
/// (`D-17`)—, así que ahora devuelve lo que se haya sembrado, y `nil` cuando no
/// hay nada: que es exactamente lo que significa un *schema* sin aprovisionar.
struct FakeClubRepository: ClubRepository {
    let store: IngestionStore
    func current() async throws -> Club? { await store.club }
    func save(_ club: Club) async throws { await store.seed(club: club) }
}

struct FakeIngestionRunRepository: IngestionRunRepository {
    let store: IngestionStore
    func record(_ run: IngestionRun) async throws { await store.record(run) }
    func list(competitionID: CompetitionID, limit: Int) async throws -> [IngestionRun] {
        await store.ingestionRuns
            .filter { $0.competitionID == competitionID }
            .sorted { $0.finishedAt > $1.finishedAt }
            .prefix(limit)
            .map { $0 }
    }
}

struct FakeRepositories: Repositories {
    let store: IngestionStore
    var clubs: any ClubRepository { FakeClubRepository(store: store) }
    var seasons: any SeasonRepository { FakeSeasonRepository(store: store) }
    var competitions: any CompetitionRepository { FakeCompetitionRepository(store: store) }
    var rounds: any RoundRepository { FakeRoundRepository(store: store) }
    var opponentClubs: any OpponentClubRepository {
        FakeOpponentClubRepository(store: store)
    }
    var teams: any TeamRepository { FakeTeamRepository(store: store) }
    var matches: any MatchRepository { FakeMatchRepository(store: store) }
    var ingestionRuns: any IngestionRunRepository {
        FakeIngestionRunRepository(store: store)
    }
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

/// El catálogo de adaptadores, falseado (`D-17`).
///
/// **Devuelve `nil` para la federación que no se le haya dado**, que es la
/// situación real hasta F9: la FCF tiene entrada en el catálogo del Dominio y no
/// tiene adaptador.
struct FakeFederationClientProvider: FederationClientProvider {
    let clients: [FederationCode: any FederationClient]

    init(_ clients: [FederationCode: any FederationClient]) { self.clients = clients }

    func client(for code: FederationCode) -> (any FederationClient)? { clients[code] }
}

/// Un `FederationClient` que **falla solo para ciertos grupos**.
///
/// F5 no lo necesitó: su pasada era una, así que "falla" y "no falla" bastaban.
/// El recorrido de F6 tiene que poder demostrar que una competición rota **no se
/// lleva por delante a las de al lado** (`D-86`), y eso exige un doble que
/// distinga a quién le toca fallar.
final class FlakyFederationClient: FederationClient, @unchecked Sendable {
    struct Failure: Error, Equatable { let group: String }

    private let calendar: FederationCalendar
    private let failingGroups: Set<String>
    private(set) var received: [FederationCoordinate] = []

    init(returning calendar: FederationCalendar, failingGroups: Set<String>) {
        self.calendar = calendar
        self.failingGroups = failingGroups
    }

    func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
        received.append(coordinate)
        if failingGroups.contains(coordinate.federationGroupID) {
            throw Failure(group: coordinate.federationGroupID)
        }
        return calendar
    }
}

/// Un reloj que **avanza** un segundo en cada consulta.
///
/// `FixedClock` no sirve para afirmar una duración: con él, empezar y terminar
/// son el mismo instante y un cronómetro roto pasa el test. Lo encontraron las
/// pruebas manuales de F6 —toda pasada con éxito registraba 0,00 s— y por eso
/// este doble existe.
final class TickingClock: Clock, @unchecked Sendable {
    private let start: Date
    private var ticks = 0
    init(from start: Date) { self.start = start }
    func now() -> Date {
        defer { ticks += 1 }
        return start.addingTimeInterval(Double(ticks))
    }
}

/// Un error que **esconde su descripción**, como `PSQLError`.
///
/// No es un caso rebuscado: es el error más probable de la ingesta —una
/// violación de restricción— y su `description` dice literalmente *"Generic
/// description to prevent accidental leakage of sensitive data"*. Todo lo útil
/// está en su `debugDescription`, que es lo que `String(reflecting:)` devuelve.
struct OpaqueError: Error, CustomStringConvertible, CustomDebugStringConvertible {
    let detail: String
    var description: String {
        "Generic description to prevent accidental leakage of sensitive data"
    }
    var debugDescription: String { "OpaqueError(detail: \(detail))" }
}

/// Falla **siempre**, con un error opaco.
struct OpaqueFailingClient: FederationClient {
    let detail: String
    func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
        throw OpaqueError(detail: detail)
    }
}

import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): las cinco operaciones de las tarjetas (R7.8), con los repositorios
/// falseados. Reutiliza el club de `AppearanceUseCaseTests`.
///
/// Lo que deciden los casos de uso: **con qué equipo** (`D-128`), **cuándo** se apunta
/// (`D-133`, `D-137`), **una de cada tipo** (§3.5), **la segunda amarilla** (`D-45`) y
/// **lo que el acta deja fijo** (`D-136`, punto 4; `D-137`).
@Suite("Cards · R7.8 · apuntar, corregir y borrar una tarjeta")
struct CardUseCaseTests {
    typealias A = AppearanceUseCaseTests

    static func repositories(_ store: IngestionStore) -> CardRepositories {
        CardRepositories(
            matches: FakeMatchRepository(store: store), competitions: FakeCompetitionRepository(store: store),
            seasons: FakeSeasonRepository(store: store), teams: FakeTeamRepository(store: store),
            players: FakePlayerRepository(store: store), cards: FakeCardRepository(store: store))
    }

    static func create(_ s: A.Seeded, at instant: Date = A.after) -> CreateCard {
        CreateCard(repositories: repositories(s.store), clock: FixedClock(instant: instant),
                   ids: SequentialUUIDProvider())
    }

    static func update(_ s: A.Seeded) -> UpdateCard {
        UpdateCard(repositories: repositories(s.store), clock: FixedClock(instant: A.after))
    }

    static func command(_ s: A.Seeded, _ type: CardType, player: Player? = nil, team: Team? = nil,
                        secondYellow: Bool = false, minute: Int? = nil, comment: String? = nil) -> CreateCard.Command {
        .init(playerID: (player ?? s.juan).id, matchID: s.match.id, teamID: (team ?? s.cadeteA).id, type: type,
              isSecondYellow: secondYellow, minute: minute, comment: comment)
    }

    @Test("una tarjeta con solo el jugador y el tipo vale, y con todo lo guarda entero (D-136)")
    func createsCards() async throws {
        let s = try await A.seed()
        let bare = try await Self.create(s).execute(Self.command(s, .amarilla))
        #expect(bare.minute == nil && bare.comment == nil && !bare.fromReport)
        let full = try await Self.create(s).execute(Self.command(s, .roja, player: s.pedro, minute: 70,
                                                                  comment: "  protestar  "))
        #expect(full.minute?.value == 70)
        #expect(full.comment?.value == "protestar")
        #expect(full.teamID == s.cadeteA.id)
    }

    @Test("un refuerzo se amonesta con el equipo del partido (D-128); otro equipo, no")
    func teamOfTheMatch() async throws {
        let s = try await A.seed()
        _ = try await Self.create(s).execute(Self.command(s, .amarilla, player: s.refuerzo))
        await #expect(throws: DomainError.teamNotInMatch(team: s.cadeteB.id.description)) {
            try await Self.create(s).execute(Self.command(s, .amarilla, team: s.cadeteB))
        }
    }

    @Test("antes de la hora, o con el acta cargada, no se apunta (D-133, D-137)")
    func notBeforeKickoffNorWithReport() async throws {
        let s = try await A.seed()
        await #expect(throws: DomainError.matchNotStarted) {
            try await Self.create(s, at: A.before).execute(Self.command(s, .amarilla))
        }
        await s.store.seed(reportCopy: MatchReportCopy(loadedAt: A.after, lineup: []), for: s.match.id)
        await #expect(throws: DomainError.matchReportLoaded) {
            try await Self.create(s).execute(Self.command(s, .amarilla))
        }
    }

    @Test("una de cada tipo: la amarilla repetida es un 409, y la roja convive con ella")
    func oneOfEachType() async throws {
        let s = try await A.seed()
        _ = try await Self.create(s).execute(Self.command(s, .amarilla))
        _ = try await Self.create(s).execute(Self.command(s, .roja))
        await #expect(throws: ApplicationError.cardAlreadyRecorded(player: "\(s.juan.id)", type: "amarilla")) {
            try await Self.create(s).execute(Self.command(s, .amarilla))
        }
    }

    @Test("la segunda amarilla es una roja, y sin una amarilla suelta (D-45)")
    func secondYellow() async throws {
        let s = try await A.seed()
        _ = try await Self.create(s).execute(Self.command(s, .roja, player: s.pedro, secondYellow: true))
        _ = try await Self.create(s).execute(Self.command(s, .amarilla))
        await #expect(throws: DomainError.looseYellowExists) {
            try await Self.create(s).execute(Self.command(s, .roja, secondYellow: true))
        }
        await #expect(throws: DomainError.invalidValue(field: "isSecondYellow", reason: "solo con una roja")) {
            try await Self.create(s).execute(Self.command(s, .amarilla, player: s.refuerzo, secondYellow: true))
        }
    }

    @Test("corregir cambia solo lo que llega")
    func updateOnlyWhatArrives() async throws {
        let s = try await A.seed()
        let card = try await Self.create(s).execute(Self.command(s, .amarilla, minute: 30))
        let updated = try await Self.update(s).execute(card.id, .init(comment: "falta táctica"))
        #expect(updated.minute?.value == 30)
        #expect(updated.type == .amarilla)
        #expect(updated.comment?.value == "falta táctica")
    }

    @Test("en una tarjeta del acta, solo el comentario cambia, y no se borra (D-136, D-137)")
    func reportCardLocks() async throws {
        let s = try await A.seed()
        let card = Card(id: CardID(raw: UUID()), playerID: s.juan.id, matchID: s.match.id, teamID: s.cadeteA.id,
                        type: .amarilla, minute: try MatchMinute(20), fromReport: true,
                        createdAt: A.epoch, updatedAt: A.epoch)
        await s.store.save(card)
        let updated = try await Self.update(s).execute(card.id, .init(comment: "lo dijo el árbitro"))
        #expect(updated.comment?.value == "lo dijo el árbitro")
        await #expect(throws: DomainError.lockedByMatchReport(field: "minute")) {
            try await Self.update(s).execute(card.id, .init(minute: 25))
        }
        await #expect(throws: DomainError.lockedByMatchReport(field: "id")) {
            try await DeleteCard(repositories: Self.repositories(s.store)).execute(card.id)
        }
    }

    @Test("borrar una tarjeta del club la quita, y luego no existe")
    func deleteClubCard() async throws {
        let s = try await A.seed()
        let card = try await Self.create(s).execute(Self.command(s, .amarilla))
        try await DeleteCard(repositories: Self.repositories(s.store)).execute(card.id)
        #expect(await s.store.cards.isEmpty)
        await #expect(throws: ApplicationError.cardNotFound(id: "\(card.id)")) {
            try await DeleteCard(repositories: Self.repositories(s.store)).execute(card.id)
        }
    }

    @Test("la lista de un partido va por minuto; el ámbito que no existe, su 404")
    func listByMatch() async throws {
        let s = try await A.seed()
        let late = try await Self.create(s).execute(Self.command(s, .amarilla, minute: 80))
        let early = try await Self.create(s).execute(Self.command(s, .amarilla, player: s.pedro, minute: 5))
        let list = ListCards(matches: FakeMatchRepository(store: s.store), teams: FakeTeamRepository(store: s.store),
                             players: FakePlayerRepository(store: s.store), cards: FakeCardRepository(store: s.store))
        #expect(try await list.execute(matchID: s.match.id, playerID: nil, teamID: nil, type: nil).map(\.id)
            == [early.id, late.id])
        #expect(try await list.execute(matchID: s.match.id, playerID: s.pedro.id, teamID: nil, type: nil).map(\.id)
            == [early.id])
        let nada = MatchID(raw: UUID())
        await #expect(throws: ApplicationError.matchNotFound(id: "\(nada)")) {
            try await list.execute(matchID: nada, playerID: nil, teamID: nil, type: nil)
        }
    }
}

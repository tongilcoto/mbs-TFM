import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): `GetTeam` con los repositorios falseados.
///
/// Lo que decide el caso de uso: **de qué club sale el nombre** —el propio o el
/// rival— y que un equipo que no está es `TEAM_NOT_FOUND`.
@Suite("GetTeam · §5.1 · un equipo, propio o rival, con su club (R3.7)")
struct GetTeamTests {

    static let now = Date(timeIntervalSince1970: 1_790_000_000)
    static let actor = ActorContext(clubSlug: try! Slug("ejemplo"), isSystem: false)

    static func club() throws -> Club {
        try Club(
            id: ClubID(raw: UUID()), name: "C.D. Ejemplo", shortName: "Ejemplo",
            slug: try Slug("ejemplo"), federation: .rffm, createdAt: now, updatedAt: now)
    }

    static func useCase(_ store: IngestionStore) -> GetTeam {
        GetTeam(
            clubs: FakeClubRepository(store: store),
            teams: FakeTeamRepository(store: store),
            opponentClubs: FakeOpponentClubRepository(store: store))
    }

    @Test("un equipo propio sale con el club propio")
    func anOwnTeamComesWithTheClub() async throws {
        let club = try Self.club()
        let team = try Team(
            id: TeamID(raw: UUID()), category: .alevin, letter: "A",
            gender: .masculino, modality: .futbol7, createdAt: Self.now, updatedAt: Self.now)
        let store = IngestionStore()
        await store.seed(club: club)
        await store.seed(teams: [team])

        let result = try await Self.useCase(store).execute(team.id, actor: Self.actor)

        #expect(result == .own(team, club: club))
    }

    /// **El rival, con su club y no con el propio**, y entre varios clubes
    /// rivales el suyo: es de donde sale su nombre.
    @Test("un rival sale con su club rival, no con el propio")
    func anOpponentComesWithItsOwnClub() async throws {
        let season = SeasonID(raw: UUID())
        func rivalClub(_ name: String) throws -> OpponentClub {
            try OpponentClub(
                id: OpponentClubID(raw: UUID()), name: name, shortName: name,
                slug: try Slug(name.lowercased()), createdAt: Self.now, updatedAt: Self.now)
        }
        let galapagar = try rivalClub("Galapagar")
        let alcala = try rivalClub("Alcala")
        let rival = try Team(
            id: TeamID(raw: UUID()), opponentClubID: alcala.id, seasonID: season,
            category: .alevin, letter: "B", gender: .masculino, modality: .futbol7,
            federationTeamID: "3349087", createdAt: Self.now, updatedAt: Self.now)
        let store = IngestionStore()
        await store.seed(club: try Self.club())
        await store.seed(opponentClubs: [galapagar, alcala], teams: [rival])

        let result = try await Self.useCase(store).execute(rival.id, actor: Self.actor)

        #expect(result == .opponent(rival, club: alcala))
    }

    @Test("un equipo que no está es TEAM_NOT_FOUND")
    func aMissingTeamIsNotFound() async throws {
        let store = IngestionStore()
        await store.seed(club: try Self.club())
        let missing = TeamID(raw: UUID())

        await #expect(throws: ApplicationError.teamNotFound(id: "\(missing)")) {
            try await Self.useCase(store).execute(missing, actor: Self.actor)
        }
    }
}

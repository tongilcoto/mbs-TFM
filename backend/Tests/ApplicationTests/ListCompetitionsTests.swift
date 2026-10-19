import Domain
import Foundation
import Synchronization
import Testing
@testable import Application

/// Nivel 2 (§8.1): `ListCompetitions` con el repositorio falseado.
///
/// El caso de uso **no decide nada de los filtros**: los pasa al repositorio tal
/// cual, y los aplica el nivel 3. Lo que se prueba aquí es eso, que pasan enteros,
/// y que lo que vuelve sale sin tocar.
@Suite("ListCompetitions · §5.1 · las competiciones del club, con sus filtros")
struct ListCompetitionsTests {

    final class CompetitionRepositorySpy: CompetitionRepository, Sendable {
        let stored: [Competition]
        let requests = Mutex<[CompetitionFilter]>([])

        init(stored: [Competition]) { self.stored = stored }

        func list(_ filter: CompetitionFilter) async throws -> [Competition] {
            requests.withLock { $0.append(filter) }
            return stored
        }
        func find(_ id: CompetitionID) async throws -> Competition? { nil }
        func lock(_ id: CompetitionID) async throws -> Competition? { nil }
        func findByFederationGroup(
            seasonID: SeasonID, federationGroupID: String
        ) async throws -> Competition? { nil }
        func save(_ competition: Competition) async throws {}
    }

    @Test("pasa los cuatro filtros al repositorio y devuelve lo que trae")
    func passesTheFilterThroughAndReturnsTheResult() async throws {
        let seasonID = SeasonID(raw: UUID())
        let stored = try Competition(
            id: CompetitionID(raw: UUID()), seasonID: seasonID, modality: .futbol7,
            gender: .femenino, federationCompetitionID: "1", federationGroupID: "2",
            ageCategory: .cadete, divisionLabel: "Primera", groupLabel: "Grupo 1",
            createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0))
        let repository = CompetitionRepositorySpy(stored: [stored])
        let filter = CompetitionFilter(
            seasonID: seasonID, modality: .futbol7, ageCategory: .cadete, gender: .femenino)

        let result = try await ListCompetitions(competitions: repository).execute(filter)

        #expect(repository.requests.withLock { $0 } == [filter])
        #expect(result == [stored])
    }
}

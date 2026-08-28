import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): la orquestación de la escritura, **sin I/O**.
///
/// Lo que se prueba aquí es que el caso de uso *coordina* bien. Que un nombre
/// vacío sea inválido **no** se prueba aquí: eso es del Dominio y ya tiene sus
/// tests. Cada regla en el nivel más barato donde vive (Plan §5).
@Suite("UpdateClub · §5.1 · campo ausente = no se modifica")
struct UpdateClubTests {
    typealias Stub = GetClubTests.ClubRepositoryStub

    @Test("solo cambia lo que viene; lo ausente se conserva (§5.5)")
    func partialUpdate() async throws {
        let original = try GetClubTests.makeClub()
        let repository = Stub(stored: original)

        let result = try await UpdateClub(clubs: repository).execute(
            actor: try GetClubTests.makeActor(),
            command: .init(name: "Nombre Nuevo", shortName: nil))

        #expect(result.name == "Nombre Nuevo")
        #expect(result.shortName == original.shortName, "shortName no venía: no se toca")
        #expect(repository.saved?.name == "Nombre Nuevo", "y se persiste")
    }

    /// El `slug` es inmutable (§3.2) y la federación se fija al aprovisionar.
    /// **No hay forma de escribirlos**: no están en el comando. Este test existe
    /// para que quitar esa garantía se note.
    @Test("ni el slug ni la federación son alcanzables desde este camino (§3.2)")
    func immutableFieldsSurvive() async throws {
        let original = try GetClubTests.makeClub(federation: .fcf)
        let repository = Stub(stored: original)

        let result = try await UpdateClub(clubs: repository).execute(
            actor: try GetClubTests.makeActor(),
            command: .init(name: "Otro", shortName: "Otro"))

        #expect(result.slug == original.slug)
        #expect(result.federation == .fcf)
    }

    /// Un valor inválido **no llega a persistirse**: el Dominio lanza al aplicar
    /// el cambio, antes del `save`. El orden importa — validar después de guardar
    /// dejaría la fila rota.
    @Test("un valor inválido aborta antes de tocar el repositorio")
    func invalidValueDoesNotPersist() async throws {
        let repository = Stub(stored: try GetClubTests.makeClub())

        await #expect(throws: DomainError.self) {
            try await UpdateClub(clubs: repository).execute(
                actor: try GetClubTests.makeActor(),
                command: .init(name: "  ", shortName: nil))
        }
        #expect(repository.saved == nil, "no debe haberse guardado nada")
    }

    /// `minProperties: 1` lo comprueba el adaptador (D-65), pero el comando sabe
    /// decir si está vacío — así la regla se enuncia una vez y el adaptador solo
    /// la consulta.
    @Test("el comando sabe cuándo no pide nada (minProperties, D-65)")
    func emptyCommandIsDetectable() {
        #expect(UpdateClub.Command(name: nil, shortName: nil).isEmpty)
        #expect(!UpdateClub.Command(name: "algo", shortName: nil).isEmpty)
    }
}

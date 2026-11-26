import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): **quién es quién** entre los jugadores de la federación y los del club (`D-126`, R7.12). Las
/// reglas, escritas una vez: primero por el código de la federación y, si no casa, por «el mismo nombre» de la
/// plantilla (`PlayerName.sameNameKey`, `D-120`). Sin base: entran las dos listas, salen las parejas.
@Suite("FederationPlayerMatching · D-126 · casar a los jugadores de la federación")
struct FederationPlayerMatchingTests {

    static func ours(_ name: String, code: String? = nil) throws -> FederationMatchCandidate {
        FederationMatchCandidate(
            profileID: PlayerProfileID(raw: UUID()), fullName: try PlayerName(name), federationPlayerID: code)
    }

    static func theirs(_ name: String?, code: String? = nil) throws -> FederationMatchQuery {
        FederationMatchQuery(federationPlayerID: code, name: try name.map(PlayerName.init))
    }

    static func match(_ query: FederationMatchQuery, _ ours: [FederationMatchCandidate]) -> FederationPlayerMatch {
        FederationPlayerMatching.byCodeThenName([query], against: ours)[0]
    }

    @Test("por el código, aunque el nombre no se parezca: el club lo corrigió")
    func byCode() throws {
        let juan = try Self.ours("Juan García", code: "111")
        let otro = try Self.ours("Juanito García López", code: "222")

        #expect(Self.match(try Self.theirs("JUAN GARCIA LOPEZ", code: "111"), [otro, juan]) == .byCode(juan.profileID))
    }

    @Test("sin código que case, por el mismo nombre sin contar tildes")
    func byName() throws {
        let juan = try Self.ours("Juan García López")

        #expect(Self.match(try Self.theirs("JUAN GARCIA LOPEZ", code: "111"), [juan]) == .byName(juan.profileID))
        #expect(Self.match(try Self.theirs("JUAN GARCIA LOPEZ"), [juan]) == .byName(juan.profileID))
    }

    /// Un perfil que ya tiene **otro** código es otro jugador de la federación, aunque se llame igual: dos chavales
    /// con el mismo nombre no se juntan.
    @Test("el mismo nombre con otro código no casa: son dos personas")
    func sameNameOtherCode() throws {
        let juan = try Self.ours("Juan García", code: "222")

        #expect(Self.match(try Self.theirs("JUAN GARCIA", code: "111"), [juan]) == .none)
        #expect(Self.match(try Self.theirs("JUAN GARCIA"), [juan]) == .byName(juan.profileID),
                "sin código publicado, el nombre basta")
    }

    @Test("varios con el mismo nombre: ambiguo, con todos")
    func ambiguous() throws {
        let uno = try Self.ours("Juan García")
        let otro = try Self.ours("Juan Garcia")

        #expect(Self.match(try Self.theirs("JUAN GARCÍA"), [uno, otro]) == .ambiguousName([uno.profileID, otro.profileID]))
    }

    @Test("nadie con ese código ni ese nombre, o sin nombre que leer y sin código: ninguno")
    func none() throws {
        let juan = try Self.ours("Juan García", code: "111")

        #expect(Self.match(try Self.theirs("PEDRO PÉREZ", code: "333"), [juan]) == .none)
        #expect(Self.match(try Self.theirs(nil), [juan]) == .none)
        #expect(Self.match(try Self.theirs(nil, code: "111"), [juan]) == .byCode(juan.profileID),
                "sin nombre, el código basta (D-138, punto 4)")
    }

    /// Una federación sin código casa solo por el nombre: aunque nuestro perfil guarde uno, el suyo no viene.
    @Test("solo por el nombre: el código no cuenta")
    func byNameOnly() throws {
        let juan = try Self.ours("Juan García", code: "111")

        #expect(FederationPlayerMatching.byNameOnly([try Self.theirs("JUAN GARCIA", code: "999")], against: [juan])
                == [.byName(juan.profileID)])
    }

    @Test("una respuesta por jugador publicado, en el mismo orden")
    func keepsTheOrder() throws {
        let juan = try Self.ours("Juan García")
        let pedro = try Self.ours("Pedro Pérez", code: "7")

        let matches = FederationPlayerMatching.byCodeThenName(
            [try Self.theirs("ANA RUIZ"), try Self.theirs("X Y", code: "7"), try Self.theirs("JUAN GARCIA")],
            against: [juan, pedro])
        #expect(matches == [.none, .byCode(pedro.profileID), .byName(juan.profileID)])
    }
}

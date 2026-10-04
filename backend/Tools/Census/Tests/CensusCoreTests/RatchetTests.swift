import Testing
@testable import CensusCore

@Suite("El trinquete: los huecos de hoy contra los sabidos (A-15·H-72)")
struct RatchetTests {

    @Test("si los huecos son exactamente los sabidos, el trinquete aguanta")
    func holds() {
        let result = ratchet(gaps: ["NOT_FOUND"], known: ["NOT_FOUND": "no se alcanza (H-68)"])
        #expect(result.holds)
    }

    @Test("un hueco que no está en la lista es un aviso: código o campo nuevo sin test")
    func unexpectedGap() {
        let result = ratchet(gaps: ["NOT_FOUND", "TEAM_GONE"], known: ["NOT_FOUND": "…"])
        #expect(result.unexpected == ["TEAM_GONE"])
        #expect(!result.holds)
    }

    @Test("una entrada de la lista que ya no es hueco también: la lista ha caducado")
    func staleEntry() {
        let result = ratchet(gaps: [], known: ["NOT_FOUND": "…"])
        #expect(result.stale == ["NOT_FOUND"])
        #expect(!result.holds)
    }

    @Test("las dos listas salen ordenadas, para que el informe se pueda comparar")
    func sorted() {
        let result = ratchet(gaps: ["B", "A"], known: ["Z": "…", "Y": "…"])
        #expect(result.unexpected == ["A", "B"])
        #expect(result.stale == ["Y", "Z"])
    }
}

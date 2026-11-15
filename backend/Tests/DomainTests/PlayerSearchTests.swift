import Testing
@testable import Domain

/// Nivel 1 (§8.1): cómo busca el buscador del alta (`D-120`), **cero I/O**.
///
/// No compara nombres, ayuda a encontrar: sin tildes, diéresis ni mayúsculas, la
/// eñe como una «n», y cada palabra escrita es el comienzo de una palabra del
/// nombre.
@Suite("PlayerSearch · D-120 · sin tildes, palabra a palabra, desde 3 letras")
struct PlayerSearchTests {

    static func finds(_ query: String, _ name: String) throws -> Bool {
        try #require(PlayerSearch(query)).matches(try PlayerName(name))
    }

    @Test("con menos de tres letras no busca", arguments: ["", "ju", "  j u ", "12345", "j-"])
    func needsThreeLetters(_ query: String) {
        #expect(PlayerSearch(query) == nil)
    }

    @Test("tres letras sueltas en dos palabras sí cuentan")
    func threeLettersAcrossWords() {
        #expect(PlayerSearch("ju g") != nil)
    }

    @Test("encuentra sin tildes, diéresis ni mayúsculas", arguments: [
        ("jose", "José Pérez"), ("JOSÉ", "Jose Perez"), ("guell", "Lucía Güell"),
        ("lucia", "Lucía Güell"),
    ])
    func ignoresAccentsAndCase(_ query: String, _ name: String) throws {
        #expect(try Self.finds(query, name))
    }

    /// Para buscar, la eñe es una «n» (lo eligió el desarrollador en la R6.3):
    /// quien no la teclea también encuentra a «Muñoz».
    @Test("la eñe es una «n» al buscar, en los dos sentidos")
    func enyeIsN() throws {
        #expect(try Self.finds("munoz", "Juan Muñoz"))
        #expect(try Self.finds("muñoz", "Juan Munoz"))
    }

    @Test("palabra a palabra: cada una, el comienzo de una palabra del nombre", arguments: [
        ("juan fuen", true), ("fuen juan", true), ("gar", true), ("arcia", false),
        ("juan lopez", false),
    ])
    func wordByWord(_ query: String, _ expected: Bool) throws {
        #expect(try Self.finds(query, "Juan García Fuente") == expected)
    }

    @Test("tras un guion o un apóstrofo empieza otra palabra")
    func hyphenAndApostropheSplit() throws {
        #expect(try Self.finds("gil", "Ana Pérez-Gil"))
        #expect(try Self.finds("brien", "Liam O'Brien"))
    }

    /// Lo que no es letra en lo escrito no cuenta: así ningún comodín de la base
    /// llega a la consulta.
    @Test("lo que no es letra en lo escrito no cuenta")
    func nonLettersAreDropped() throws {
        let search = try #require(PlayerSearch("ju%an_ ga!rcía"))
        #expect(search.words == ["JUAN", "GARCIA"])
    }

    /// La base busca con la misma tabla de letras (`translate`), así que las dos
    /// tienen que cubrir lo mismo: cada letra de la tabla, una sola letra.
    @Test("la tabla de letras va letra por letra, sin repetir")
    func foldTableIsConsistent() {
        #expect(PlayerSearch.foldFrom.count == PlayerSearch.foldTo.count)
        #expect(Set(PlayerSearch.foldFrom).count == PlayerSearch.foldFrom.count)
    }
}

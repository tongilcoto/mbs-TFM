import Testing
@testable import Domain

/// Nivel 1 (§8.1): el diccionario de nombres y apellidos en castellano (`D-123`), **cero I/O**: cómo se lee el texto
/// del fichero (R6.19) y cómo se aplica a un nombre. Que la lista de verdad no tiene ninguna línea mala lo mira
/// `NameDictionaryFileTests`, que lee el fichero.
@Suite("CastilianNames · D-123 · las tildes y eñes que quita la federación")
struct CastilianNamesTests {

    /// Un diccionario pequeño, escrito aquí, con las formas que importan.
    static let names = CastilianNames(text: """
        # Nombres
        JESÚS
        ROMÁN
        MARTÍN

        # Apellidos
        FERNÁNDEZ
        PÉREZ
        MUÑOZ
        IBÁÑEZ
        ARGÜELLES
        GARCÍA
        LÓPEZ
        """)

    // ── Leer el texto ──

    @Test("una palabra por línea; las vacías y los comentarios no cuentan")
    func readsOneWordPerLine() {
        #expect(Self.names.words == ["JESÚS", "ROMÁN", "MARTÍN", "FERNÁNDEZ", "PÉREZ", "MUÑOZ", "IBÁÑEZ",
                                     "ARGÜELLES", "GARCÍA", "LÓPEZ"])
        #expect(Self.names.problems.isEmpty)
    }

    @Test("los espacios de los lados y los saltos de Windows no cuentan")
    func trimsAndAcceptsWindowsLines() {
        let names = CastilianNames(text: "  JESÚS  \r\nROMÁN\r\n")
        #expect(names.words == ["JESÚS", "ROMÁN"])
        #expect(names.problems.isEmpty)
    }

    /// Solo hacen falta las palabras con tilde, eñe o diéresis: las demás ya llegan bien.
    @Test("una palabra sin tilde, eñe ni diéresis no se usa, y se dice por qué")
    func wordWithoutMarkIsSkipped() {
        let names = CastilianNames(text: "JESÚS\nGARCIA\nROMÁN")
        #expect(names.words == ["JESÚS", "ROMÁN"])
        #expect(names.problems == [.init(line: 2, text: "GARCIA", reason: .noMark)])
    }

    /// En mayúsculas y sola: se busca palabra a palabra.
    @Test("una línea que no es una palabra en mayúsculas no se usa", arguments: [
        "garcía", "García", "GARCÍA PÉREZ", "GARCÍA-PÉREZ", "PÉREZ2", "PÉREZ.",
    ])
    func notOneUppercaseWordIsSkipped(_ line: String) {
        let names = CastilianNames(text: "JESÚS\n\(line)")
        #expect(names.words == ["JESÚS"])
        #expect(names.problems == [.init(line: 2, text: line, reason: .notOneUppercaseWord)])
    }

    /// Una sola forma por palabra: dos que se buscan igual dirían cosas distintas. Vale la primera.
    @Test("una palabra dos veces, o con otras tildes, vale la primera")
    func repeatedWordKeepsTheFirst() throws {
        let names = CastilianNames(text: "DÍEZ\nJESÚS\nDÍEZ\nDIÉZ")
        #expect(names.words == ["DÍEZ", "JESÚS"])
        #expect(names.problems == [.init(line: 3, text: "DÍEZ", reason: .repeated(line: 1)),
                                   .init(line: 4, text: "DIÉZ", reason: .repeated(line: 1))])
        #expect(try PlayerName("JORGE DIEZ").spelledInCastilian(with: names).value == "JORGE DÍEZ")
    }

    @Test("sin texto, ninguna palabra: los nombres se quedan como llegan")
    func emptyChangesNothing() throws {
        #expect(CastilianNames.empty.words.isEmpty)
        #expect(try PlayerName("JORGE FERNANDEZ").spelledInCastilian(with: .empty).value == "JORGE FERNANDEZ")
    }

    // ── Aplicarla a un nombre ──

    @Test("pone las tildes, las eñes y las diéresis que faltan", arguments: [
        ("JORGE FERNANDEZ PEREZ", "JORGE FERNÁNDEZ PÉREZ"),
        ("JESUS MUNOZ IBANEZ", "JESÚS MUÑOZ IBÁÑEZ"),
        ("ROMAN MARTIN ARGUELLES", "ROMÁN MARTÍN ARGÜELLES"),
    ])
    func addsMarks(_ raw: String, _ spelled: String) throws {
        #expect(try PlayerName(raw).spelledInCastilian(with: Self.names).value == spelled)
    }

    @Test("lo que no está en la lista, y lo que ya llega bien, se queda como está")
    func leavesTheRest() throws {
        #expect(try PlayerName("JORGE RUIZ SANZ").spelledInCastilian(with: Self.names).value == "JORGE RUIZ SANZ")
        #expect(try PlayerName("JORGE GARCÍA").spelledInCastilian(with: Self.names).value == "JORGE GARCÍA")
        #expect(try PlayerName("KEVIN SMITH").spelledInCastilian(with: Self.names).value == "KEVIN SMITH")
    }

    /// Solo palabras enteras: «PEREZOSO» no es «PÉREZ», y «MARTINEZ» no se toca por «MARTÍN».
    @Test("solo palabras enteras, también tras un guion")
    func wholeWordsOnly() throws {
        #expect(try PlayerName("JORGE GARCIA-PEREZ").spelledInCastilian(with: Self.names).value == "JORGE GARCÍA-PÉREZ")
        #expect(try PlayerName("JORGE PEREZOSO").spelledInCastilian(with: Self.names).value == "JORGE PEREZOSO")
        #expect(try PlayerName("JORGE O'MARTIN").spelledInCastilian(with: Self.names).value == "JORGE O'MARTIN")
    }

    /// Escrito con otras tildes, se corrige a la de la lista: «LOPÉZ» es «LÓPEZ».
    @Test("una tilde mal puesta se cambia por la de la lista")
    func wrongMarkIsReplaced() throws {
        #expect(try PlayerName("JORGE LOPÉZ").spelledInCastilian(with: Self.names).value == "JORGE LÓPEZ")
    }
}

import Testing
import Domain
@testable import Federation

/// Nivel 1 (§8.1): parseo puro, **cero I/O**.
///
/// Esta suite es la que el Plan §4.2 señala como el motivo de volver a TDD en F2:
///
/// > *"el reformateo de `"2025-2026"` a `"2025/26"` es exactamente el sitio donde
/// > un test escrito después se limitaría a bendecir el error."*
///
/// Y es también la mitad que le faltaba a `D-71`. Allí se demostró que
/// `SeasonLabel` **rechaza** `"2025/20"`; aquí se demuestra que el adaptador
/// **no lo produce**. Las dos piezas juntas son la garantía; ninguna sola basta.
@Suite("RFFM · etiqueta de temporada · Anexo RFFM §F.11 · D-71")
struct RFFMSeasonLabelTests {

    /// La fuente publica `"2026-2027"` ([Anexo RFFM §F.11], y confirmado en el
    /// sobre del calendario, §F.15: `calendar.temporada`). El modelo quiere
    /// `"2026/27"` (§3.2).
    @Test("reformatea AAAA-BBBB al AAAA/BB del modelo", arguments: [
        ("2026-2027", "2026/27"),
        ("2025-2026", "2025/26"),
        ("2011-2012", "2011/12"),
    ])
    func reformats(_ raw: String, _ expected: String) throws {
        #expect(try RFFMSeasonLabel.parse(raw).value == expected)
    }

    /// **El test que justifica que esto exista.** `"2025/20"` cumple el `pattern`
    /// del *spec*, así que el contrato no lo pararía — y esta ruta no pasa por el
    /// contrato de todas formas. Es lo que sale de coger los dos caracteres
    /// equivocados: los **primeros** dos del segundo año en vez de los últimos.
    @Test("no produce el 2025/20 de D-71: coge los dos últimos dígitos, no los dos primeros")
    func doesNotTakeTheWrongTwoCharacters() throws {
        #expect(try RFFMSeasonLabel.parse("2025-2026").value != "2025/20")
        #expect(try RFFMSeasonLabel.parse("2025-2026").value == "2025/26")
    }

    /// El cambio de siglo, que es donde el `% 100` de `SeasonLabel` gana su sitio.
    @Test("cruza el cambio de siglo", arguments: [
        ("1999-2000", "1999/00"),
        ("2099-2100", "2099/00"),
    ])
    func crossesCentury(_ raw: String, _ expected: String) throws {
        #expect(try RFFMSeasonLabel.parse(raw).value == expected)
    }

    /// Un campo ausente o vacío **no es un valor** (`D-56`): que falle aquí, no
    /// que se invente una temporada.
    @Test("rechaza lo que no tiene la forma de la fuente", arguments: [
        "",
        "2026",
        "2026/2027",     // ya en formato del modelo, pero con el año largo
        "2026-27",       // segunda mitad corta
        "20262027",      // sin separador
        "abcd-efgh",
        "2026 - 2027",   // con espacios
    ])
    func rejectsMalformed(_ raw: String) {
        #expect(throws: (any Error).self) { try RFFMSeasonLabel.parse(raw) }
    }

    /// Los dos años **tienen que ser consecutivos**. Si la fuente publicase
    /// `"2026-2028"`, lo que hay es un problema en origen — y lo que **no** puede
    /// pasar es que se guarde una temporada con una etiqueta inventada. La guarda
    /// vive en `SeasonLabel` (`D-71`) y aquí se comprueba que el adaptador la
    /// deja actuar en vez de esquivarla componiendo la cadena a mano.
    @Test("rechaza años no consecutivos, delegando en la invariante del dominio", arguments: [
        "2026-2028",
        "2026-2026",
        "2026-2025",
    ])
    func rejectsNonConsecutiveYears(_ raw: String) {
        #expect(throws: DomainError.self) { try RFFMSeasonLabel.parse(raw) }
    }
}

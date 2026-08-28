import Testing
@testable import Domain

/// Nivel 1 de la pirámide (§8.1): invariantes de *Value Objects*, **cero I/O**.
///
/// Estas reglas se prueban **aquí y solo aquí**: el `pattern` del spec no lo
/// aplica el código generado (D-65), así que este tipo es el único sitio donde
/// existen — y volver a probarlas por HTTP sería duplicarlas (Plan §5).
@Suite("Slug · §4.1 · el pattern del spec lo hace cumplir el Dominio (D-65)")
struct SlugTests {

    @Test("acepta minúsculas, dígitos y guiones simples", arguments: [
        "cd-ejemplo", "atleti", "club123", "a", "1", "un-club-con-nombre-largo",
    ])
    func acceptsValid(_ value: String) throws {
        #expect(try Slug(value).value == value)
    }

    /// El `pattern` `^[a-z0-9]+(-[a-z0-9]+)*$` rechaza cada uno de estos, y son
    /// justo los que un `UNIQUE` no salvaría después: el slug entra en el
    /// enrutado por subdominio (§6.1) y en las claves de Storage (D-19).
    @Test("rechaza lo que el pattern del spec no admite", arguments: [
        "",             // vacío
        "-atleti",      // guion inicial
        "atleti-",      // guion final
        "cd--ejemplo",  // guion doble
        "CD-Ejemplo",   // mayúsculas
        "cd_ejemplo",   // guion bajo
        "cd ejemplo",   // espacio
        "cd.ejemplo",   // punto
        "clüb",         // no ASCII
    ])
    func rejectsInvalid(_ value: String) {
        #expect(throws: DomainError.self) { try Slug(value) }
    }
}

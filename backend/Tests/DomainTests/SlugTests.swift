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

    // ── Derivación desde el nombre (D-82) ────────────────────────────────────

    /// El *spec* dice que el `slug` de `OpponentClub` lo **genera el servidor a
    /// partir del nombre al crear la fila**, y quien crea esas filas es la
    /// ingesta (§3.7). El nombre llega como lo publica la RFFM: mayúsculas,
    /// puntuación irregular y a veces acentos ([Anexo RFFM §F.5]).
    ///
    /// **La derivación es mecánica** (`D-82`): plegar, minúsculas, y todo lo que
    /// no sea letra o dígito se convierte en **una** frontera. Nada de listas de
    /// formas jurídicas —"C.F.", "S.A.D.", "E.F.M.O."— que serían una segunda
    /// fuente de verdad que nadie mantiene.
    @Test("deriva el slug del nombre que publica la federación (D-82)", arguments: [
        ("CELTIC CASTILLA C.F.", "celtic-castilla-c-f"),
        ("C.D. GALAPAGAR", "c-d-galapagar"),
        ("ARAVACA C.F. - CEIBA", "aravaca-c-f-ceiba"),
        ("A.D. UNIÓN ADARVE", "a-d-union-adarve"),
        ("E.F.M.O. BOADILLA", "e-f-m-o-boadilla"),
        ("PEÑA MADRIDISTA 2000", "pena-madridista-2000"),
    ])
    func derivesFromName(_ input: String, _ expected: String) throws {
        #expect(try Slug(derivedFrom: input).value == expected)
    }

    /// Un nombre del que no queda nada sluguificable **no da un slug feo: no da
    /// slug**. Es la misma frontera que `NormalizedName` NO tiene —allí no hay
    /// nombre inválido— y que aquí sí, porque el slug entra en claves de Storage
    /// (`D-19`) y en un `UNIQUE` (§3.5). Lo reporta la ingesta.
    @Test("un nombre sin una sola letra ni dígito no produce slug (D-82)")
    func rejectsUnsluggableName() {
        #expect(throws: DomainError.self) { try Slug(derivedFrom: "··· --- ···") }
    }
}

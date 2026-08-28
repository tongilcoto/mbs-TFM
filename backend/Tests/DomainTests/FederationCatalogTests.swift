import Testing
@testable import Domain

/// El catálogo de federaciones es **código, no dato** (§3.6, D-17), así que sus
/// capacidades son testables sin infraestructura. Cada aserción cita la evidencia
/// del anexo correspondiente: no se deduce de memoria (AGENTS.md).
@Suite("Catálogo de federaciones · §3.6 · D-17")
struct FederationCatalogTests {

    /// D-55: la RFFM deja recuperar cualquier jornada (Anexo RFFM §F.8); la FCF
    /// solo la vigente, así que las anteriores al alta se calculan (D-15).
    @Test("solo la RFFM sirve clasificación de jornadas pasadas (D-55)")
    func roundStandings() {
        #expect(FederationCode.rffm.capabilities.providesRoundStandings)
        #expect(!FederationCode.fcf.capabilities.providesRoundStandings)
    }

    /// D-48: aquí no hay *fallback* posible —calcular el ranking exigiría la
    /// plantilla de los rivales (D-09)—, así que `false` significa que la
    /// pantalla se oculta, no que se pinte vacía. Por eso el valor se cambia
    /// **solo con un volcado delante**, que es lo que pasó el 2026-08-28.
    @Test("las dos federaciones publican goleadores (Anexo RFFM §F.13, Anexo FCF §C.10, D-48)")
    func scorers() {
        #expect(FederationCode.rffm.capabilities.providesScorers)
        // Era `false` citando el §C.9 del sitio antiguo. La web nueva de la FCF
        // publica `/api/competition/goleadores` — evidencia en
        // `docs/Federation APIs examples/FCF-goleadores.txt`.
        #expect(FederationCode.fcf.capabilities.providesScorers)
    }

    /// Si alguien añade una federación al enum, este test la obliga a declarar
    /// sus capacidades en el mismo commit — el `switch` es exhaustivo, pero un
    /// caso nuevo copiado del vecino compilaría con datos mentira.
    @Test("toda federación del catálogo declara sus capacidades")
    func everyCaseIsCatalogued() {
        #expect(FederationCode.allCases.count == 2, "¿federación nueva? revisa su anexo antes de tocar esto")
    }
}

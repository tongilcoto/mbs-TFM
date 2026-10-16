import Testing

@testable import App
@testable import Federation

/// Nivel 1, sin Docker: **con qué dirección monta la raíz de composición el
/// adaptador de la RFFM** (`R0.8` del plan del backoffice).
///
/// Que `RFFMEndpoints` sepa leer `RFFM_BASE_URL` no sirve de nada si quien monta
/// el adaptador de producción no se la pasa: los escenarios del backoffice
/// seguirían yendo a la RFFM de verdad. Lo que queda sin cubrir aquí es la
/// línea que le da a este montaje el entorno del proceso; ésa se comprueba a
/// mano, con una `ingest` contra la federación falsa.
@Suite("FederationCatalog · la RFFM con la dirección del entorno (R0.8)")
struct FederationCatalogTests {

    @Test("con RFFM_BASE_URL, el adaptador de la RFFM pide ahí")
    func theAdapterUsesTheVariable() {
        let client = CatalogFederationClientProvider.rffm(
            environment: ["RFFM_BASE_URL": "http://localhost:8090"])
        #expect((client as? RFFMFederationClient)?.endpoints
            == RFFMEndpoints(baseURL: "http://localhost:8090"))
    }

    @Test("sin RFFM_BASE_URL, a la RFFM de verdad: lo de siempre")
    func withoutTheVariableItIsTheRealRFFM() {
        let client = CatalogFederationClientProvider.rffm(environment: [:])
        #expect((client as? RFFMFederationClient)?.endpoints == RFFMEndpoints())
    }
}

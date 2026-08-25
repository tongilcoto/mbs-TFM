import Testing
import Vapor
@testable import Tenancy

/// §6.1 — la extracción del slug del `Host`.
///
/// Es **lógica pura** pese a vivir en infraestructura, así que va en el nivel
/// barato de la pirámide (§8.1) y no necesita contenedor.
@Suite("HostSlugExtractor · §6.1 · sufijo configurado, no contador de etiquetas")
struct HostSlugExtractorTests {
    let extractor = HostSlugExtractor(domainSuffix: "myapp.com")

    @Test("un subdominio de club se resuelve", arguments: [
        ("atleti.myapp.com", "atleti"),
        ("cd-ejemplo.myapp.com", "cd-ejemplo"),
        ("atleti.myapp.com:8080", "atleti"),   // el Host puede traer puerto
        ("ATLETI.MyApp.com", "atleti"),        // el Host no distingue mayúsculas
    ])
    func extractsSlug(_ input: String, _ expected: String) {
        #expect(extractor.slug(fromHost: input) == expected)
    }

    /// **El caso que motiva toda la regla.** Partir por puntos y quedarse con la
    /// primera etiqueta funciona hasta que alguien pide el ápice: `api.myapp.com`
    /// tiene tantas etiquetas como `atleti.myapp.com` y se resolvería como un
    /// club llamado "api". Por eso se recorta un **sufijo configurado**.
    @Test("el ápice y los nombres reservados no son clubes (§6.1)", arguments: [
        "myapp.com",            // el ápice: ninguna etiqueta delante
        "www.myapp.com",
        "api.myapp.com",
        "admin.myapp.com",
        "app.myapp.com",
        "status.myapp.com",
        "mail.myapp.com",
        "staging.myapp.com",
    ])
    func rejectsApexAndReserved(_ host: String) {
        #expect(extractor.slug(fromHost: host) == nil)
    }

    /// Un `Host` que no cuelga del sufijo configurado **no es una petición de
    /// tenant**. Es distinto de "club desconocido", que es un 404 y lo decide
    /// `TenantResolver` — aquí todavía no se ha tocado la BD.
    @Test("fuera del sufijo configurado no hay tenant", arguments: [
        "atleti.otrodominio.com",
        "myapp.com.attacker.net",   // sufijo como prefijo: no cuela
        "localhost",
        "",
    ])
    func rejectsForeignHosts(_ host: String) {
        #expect(extractor.slug(fromHost: host) == nil)
    }

    /// Exactamente **una** etiqueta delante del sufijo.
    @Test("los subdominios anidados no son clubes", arguments: [
        "a.b.myapp.com",
        "pre.atleti.myapp.com",
    ])
    func rejectsNestedSubdomains(_ host: String) {
        #expect(extractor.slug(fromHost: host) == nil)
    }

    /// El mismo mecanismo sirve en local **sin configurar nada**: `*.localhost`
    /// resuelve a 127.0.0.1 por defecto en macOS y en los navegadores modernos.
    /// Es lo que permite que desarrollo use la **misma** vía que producción y
    /// que la cabecera `X-Club` sea prescindible.
    @Test("con sufijo `localhost`, el desarrollo usa la misma vía que producción")
    func worksForLocalDevelopment() {
        let local = HostSlugExtractor(domainSuffix: "localhost")
        #expect(local.slug(fromHost: "atleti.localhost:8080") == "atleti")
        #expect(local.slug(fromHost: "localhost:8080") == nil)
    }
}

/// La cabecera de desarrollo es un **conmutador de tenant** si se acepta en
/// producción: la controla el cliente por completo (§6.1).
@Suite("La cabecera X-Club está apagada fuera de desarrollo (§6.1)")
struct DevelopmentHeaderGateTests {

    @Test("solo desarrollo y test la aceptan")
    func onlyDevelopmentAndTesting() {
        #expect(TenantResolutionMiddleware.allowsDevelopmentHeader(in: .development))
        #expect(TenantResolutionMiddleware.allowsDevelopmentHeader(in: .testing))
        #expect(!TenantResolutionMiddleware.allowsDevelopmentHeader(in: .production))
    }

    /// Lista **blanca**, no lista negra: un entorno nuevo nace con la cabecera
    /// apagada. Si esto se invirtiera, `staging` la aceptaría sin que nadie lo
    /// decidiera.
    @Test("un entorno desconocido nace con la cabecera apagada")
    func unknownEnvironmentIsClosed() {
        #expect(!TenantResolutionMiddleware.allowsDevelopmentHeader(in: .init(name: "staging")))
    }
}

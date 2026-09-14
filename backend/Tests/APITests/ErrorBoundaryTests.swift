import APIContract
import Application
import Domain
import Fluent
import Foundation
import Logging
import SQLKit
import Testing
import Vapor
import VaporTesting
@testable import App
import TestSupport
@testable import Persistence
@testable import Tenancy

/// Nivel 4 (§8.1): **la frontera de error**, que hasta A-6 no la probaba nada.
///
/// # Qué se prueba aquí y no en otro sitio
///
/// Los cuatro *handlers* traducen a mano los errores que esperan —`updateClub`
/// atrapa `DomainError.invalidValue`, los dos de ingesta enumeran casos de
/// `ApplicationError`— y el `switch` exhaustivo de `ProblemMiddleware` traduce
/// **lo que se les escapa**. Esa segunda mitad es la que no tenía test, y la
/// consecuencia fue un hallazgo: los dos ficheros de *handlers* llegaron a
/// **afirmar lo contrario** —que el transporte generado convierte en 500
/// cualquier cosa que se lance, antes de que ningún middleware la vea— y nadie
/// lo desmintió en tres fases, porque un comentario no tiene batería que lo
/// tumbe (`A-6`/H-40).
///
/// Así que estos tests son, literalmente, el comentario convertido en aserción.
/// El vehículo de los tres primeros es el mismo y es el más barato que hay:
/// **`getClub` no tiene `do/catch`**, así que todo lo que `GetClub` lance sale
/// del *handler* sin tocar. El cuarto cambia de sujeto —la guarda de §6.1— y no
/// va por HTTP, por el motivo que explica en su sitio.
@Suite("La frontera de error · §5.4 · lo que se escapa de un handler",
        .serialized,
        .enabled(if: DatabaseAvailability.isReachable, "\(DatabaseAvailability.skipReason)"))
struct ErrorBoundaryTests {

    static let prefix = "e2e_"

    /// El cuerpo RFC 7807 tal cual, sin el tipo generado: estos dos códigos —500
    /// `TENANT_NOT_PROVISIONED` y 500 `INTERNAL`— **no** están declarados en el
    /// *spec* para `getClub`, y ése es justo el punto (H-40). Decodificar con
    /// `Components.Schemas.Problem` insinuaría que el contrato los cubre.
    static func problem(_ response: TestingHTTPResponse) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(
            with: Data(response.body.readableBytesView))
        return try #require(object as? [String: Any])
    }

    static func sql(_ app: Application) throws -> any SQLDatabase {
        try #require(app.db(.control) as? any SQLDatabase)
    }

    /// **Un `ApplicationError` que se escapa del *handler* sale traducido**, y no
    /// como el 500 genérico que los comentarios de `ClubHandler` prometían.
    ///
    /// El montaje es el de A-6: un club **aprovisionado y con sus tablas**, al
    /// que se le vacía `clubs`. Con eso `GetClub.execute` lanza
    /// `ApplicationError.tenantNotProvisioned` (§6.3), que `getClub` no atrapa.
    ///
    /// Lo que se afirma no es el código —un 500 aquí es correcto y está razonado
    /// en `ProblemMiddleware`— sino que **la traducción ocurrió**: el `code` y el
    /// `detail` con el nombre del club solo puede haberlos puesto el `switch` del
    /// middleware, porque el transporte generado no sabe nada de
    /// `ApplicationError`.
    @Test("un ApplicationError que escapa del handler lo traduce el middleware (A-6/H-40)")
    func applicationErrorEscapingAHandlerIsTranslated() async throws {
        try await TestEnvironment.withApp { app in
            let slug = "a6esc"
            try await TestEnvironment.dropClubs([slug], schemaPrefix: Self.prefix, on: app)
            let schema = try await TestEnvironment.provisionClub(
                slug, federation: .rffm, schemaPrefix: Self.prefix, on: app)

            // El club queda registrado en el plano de control y con sus ocho
            // tablas, pero sin la fila que `provision-tenant` siembra. Es el
            // *schema* "a medio aprovisionar" que `tenantNotProvisioned` describe.
            try await Self.sql(app).raw("DELETE FROM \(ident: schema).clubs").run()

            try await app.testing().test(
                .GET, "/v1/club",
                beforeRequest: { $0.headers.add(name: "X-Club", value: slug) }
            ) { response async throws in
                #expect(response.status == .internalServerError)
                let problem = try Self.problem(response)
                #expect(problem["code"] as? String == "TENANT_NOT_PROVISIONED")
                // El `detail` nombra al club, que es lo que hace accionable un
                // 500: sin él, *"error interno"* no dice a quién le pasa.
                let detail = try #require(problem["detail"] as? String)
                #expect(detail.contains(slug))
                // Y el `Content-Type` del contrato, no `application/json` (§5.4).
                #expect(response.headers.contentType?.subType == "problem+json")
            }

            try await TestEnvironment.dropClubs([slug], schemaPrefix: Self.prefix, on: app)
        }
    }

    /// **Y el error que el `switch` no clasifica dice su motivo verdadero.**
    ///
    /// Es la mitad de diagnóstico que A-5 dejó abierta (H-34) y donde aterrizará
    /// `FederationError` cuando F10 lo haga cruzar la frontera dentro de la
    /// petición (H-15). El vehículo: un *schema* **sin la tabla**, que es el
    /// estado que dejan `--revert` y un fallo a mitad de `migrate-tenants`.
    ///
    /// # Por qué se afirma el `SQLSTATE` y no una frase
    ///
    /// Igual que el test del `23505` de `CalendarIngestionEndToEndTests` y por lo
    /// mismo: el texto de PostgresNIO puede cambiar de redacción, el código de
    /// Postgres no. Aquí es **`42P01`**, `undefined_table`. Lo que la aserción
    /// caza es que el `detail` **no** se quedó en la descripción corta —que es lo
    /// que `PSQLError` devuelve a `String(describing:)` para no filtrar datos— y
    /// que en su lugar viaja lo que `String(reflecting:)` sí revela.
    ///
    /// El `detail` de un 5xx **se calla fuera de desarrollo** (`Problem.response`,
    /// `exposesInternalDetail`), así que esto no abre ninguna filtración en
    /// producción: lo que arregla es el entorno de desarrollo y, sobre todo, el
    /// **log**, que en producción es la única salida que queda.
    @Test("el error que el switch no clasifica dice su motivo, no 'User handler threw an error' (A-6/H-43)")
    func unclassifiedErrorCarriesItsRealReason() async throws {
        try await TestEnvironment.withApp { app in
            let slug = "a6raw"
            try await TestEnvironment.dropClubs([slug], schemaPrefix: Self.prefix, on: app)
            let schema = try await TestEnvironment.provisionClub(
                slug, federation: .rffm, schemaPrefix: Self.prefix, on: app)

            // Registrado, con *schema*, y sin la tabla que la consulta necesita.
            try await Self.sql(app).raw("DROP TABLE \(ident: schema).clubs").run()

            try await app.testing().test(
                .GET, "/v1/club",
                beforeRequest: { $0.headers.add(name: "X-Club", value: slug) }
            ) { response async throws in
                #expect(response.status == .internalServerError)
                let problem = try Self.problem(response)
                #expect(problem["code"] as? String == "INTERNAL")

                let detail = try #require(problem["detail"] as? String)
                #expect(detail.contains("42P01"),
                        "el detalle tiene que llevar el SQLSTATE, no la descripción corta")
                #expect(!detail.contains("Generic description"),
                        "eso es lo que PSQLError devuelve cuando se le pide con String(describing:)")
            }

            try await TestEnvironment.dropClubs([slug], schemaPrefix: Self.prefix, on: app)
        }
    }

    /// **Y la otra salida: el log** (`A-6`/H-43, segunda mitad).
    ///
    /// Es la que de verdad importa en producción, porque allí el `detail` de un
    /// 5xx **se calla** (`Problem.response`). Va en un test aparte y no en una
    /// aserción más del de arriba porque necesita otro montaje: sustituir el
    /// `Logger` de la `Application` **antes** de la petición, del que
    /// `Request.logger` hereda.
    ///
    /// # Por qué existe este test y no una comprobación a mano
    ///
    /// Porque la primera versión del arreglo **pasó el test del cuerpo y dejó el
    /// log igual de enmascarado** —reflejaba el `ServerError` en vez de lo que
    /// lleva dentro—, y la mutación de `rootCause` sobrevivía a la batería. Las
    /// dos salidas son dos caminos distintos y hacían falta dos aserciones.
    @Test("y el log dice el motivo verdadero, no solo el cuerpo (A-6/H-43)")
    func theLogAlsoCarriesTheRealReason() async throws {
        try await TestEnvironment.withApp { app in
            let slug = "a6log"
            try await TestEnvironment.dropClubs([slug], schemaPrefix: Self.prefix, on: app)
            let schema = try await TestEnvironment.provisionClub(
                slug, federation: .rffm, schemaPrefix: Self.prefix, on: app)
            try await Self.sql(app).raw("DROP TABLE \(ident: schema).clubs").run()

            let spy = LogSpy()
            app.logger = Logger(label: "test") { _ in CapturingLogHandler(spy: spy) }

            try await app.testing().test(
                .GET, "/v1/club",
                beforeRequest: { $0.headers.add(name: "X-Club", value: slug) }
            ) { response async in
                #expect(response.status == .internalServerError)
            }

            let errors = spy.messages(at: .error).joined(separator: "\n")
            #expect(errors.contains("42P01"),
                    "sin esto, en producción no queda NINGUNA salida con el motivo")
            #expect(errors.contains("relation \"clubs\" does not exist"))

            try await TestEnvironment.dropClubs([slug], schemaPrefix: Self.prefix, on: app)
        }
    }

    /// **La guarda de §6.1 dispara cuando el actor y el ambiente discrepan**
    /// (`A-6`/H-42).
    ///
    /// Es la regla que §6.1 llama la que *"evita la clase entera de confusiones
    /// «el token dice un club y la URL dice otro»"*, y hasta ahora no la
    /// afirmaba nada: se lanza en un solo sitio
    /// (`FluentTenantUnitOfWork.resolveTenant`), se traduce a **403** en otro, y
    /// en el camino HTTP **no puede ocurrir** porque `currentActor()` construye
    /// el actor *desde* el ambiente — la comparación es una tautología.
    ///
    /// # Por eso el test no va por HTTP
    ///
    /// Va contra el `UnitOfWork` con el actor **construido a mano**, que es lo
    /// que lo hace escribible **hoy** en vez de cuando llegue JWKS. Cuando el
    /// *claim* pase a ser la fuente del actor (§7.2), esta llamada será la que
    /// ocurra de verdad y este test dejará de ser hipotético sin tocar una línea.
    @Test("si el actor y el tenant ambiental discrepan, se rechaza (§6.1, A-6/H-42)")
    func actorAndAmbientTenantMustAgree() async throws {
        try await TestEnvironment.withApp { app in
            let slugs = ["a6uno", "a6dos"]
            try await TestEnvironment.dropClubs(slugs, schemaPrefix: Self.prefix, on: app)
            for slug in slugs {
                try await TestEnvironment.provisionClub(
                    slug, federation: .rffm, schemaPrefix: Self.prefix, on: app)
            }

            let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
            let ambient = try await TenantResolver(database: app.db(.control))
                .resolve(slug: "a6uno")

            // El ambiente dice "a6uno" y el actor dice "a6dos": no se elige uno,
            // se rechaza (§6.1). Sin ámbito abierto no se toca ningún *schema*.
            await #expect(throws: TenancyError.self) {
                try await TenantContext.$current.withValue(ambient) {
                    try await unitOfWork.withRepositories(
                        actor: ActorContext(clubSlug: try Slug("a6dos"))
                    ) { _ in }
                }
            }

            // Y el caso bueno pasa, para que el test no pudiera aprobar por
            // rechazarlo todo — que es la mutación obvia de esta guarda.
            let club = try await TenantContext.$current.withValue(ambient) {
                try await unitOfWork.withRepositories(
                    actor: ActorContext(clubSlug: try Slug("a6uno"))
                ) { repositories in
                    try await repositories.clubs.current()
                }
            }
            #expect(club?.slug.value == "a6uno")

            try await TestEnvironment.dropClubs(slugs, schemaPrefix: Self.prefix, on: app)
        }
    }
}

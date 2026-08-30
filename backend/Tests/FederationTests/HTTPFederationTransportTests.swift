import Application
import Testing

@testable import Federation

/// Nivel 1 (§8.1): **la lectura de la respuesta**, sin red.
///
/// Lo que aquí se prueba es lo que la app heredada no hacía ([Anexo RFFM §F.7]):
/// mirar el código antes que el cuerpo. La petición en sí —abrir el socket,
/// seguir la redirección, cerrar— es de `AsyncHTTPClient` y la ejercita el
/// canario, que es la única prueba que puede.
@Suite("HTTPFederationTransport · §F.7 · el 2xx se valida antes de mirar el cuerpo")
struct HTTPFederationTransportTests {

    static let url = "https://www.rffm.es/competicion/calendario?temporada=21"

    /// [Anexo RFFM §F.7] sobre la app heredada: *"imprime el código HTTP pero no
    /// lo valida"*. La consecuencia es que un 500 —con su página de error HTML—
    /// **acaba en el parser**, y lo que se ve es un fallo sobre el
    /// `__NEXT_DATA__` que no está. Se depura el parser durante media hora y el
    /// problema era que el servidor estaba caído.
    @Test("un 500 no llega al parser: se llama fallo del servidor (§F.7)")
    func serverErrorNeverReachesTheParser() async throws {
        let transport = HTTPFederationTransport { _ in
            (status: 500, body: "<html><body>Error interno</body></html>")
        }

        await #expect(throws: FederationError.unexpectedStatus(status: 500, url: Self.url)) {
            try await transport.get(Self.url)
        }
    }

    /// Plan §4.4: *"un 404 tiene que decir una cosa y un parseo fallido otra"*.
    ///
    /// **La RFFM no da 404 con una coordenada mala** —medido en F5: responde
    /// `200` con `calendar: null`—, así que esta rama la cumple el parser para
    /// ese proveedor. Se prueba aquí igual porque el transporte lo comparten los
    /// dos adaptadores y el 404 es la respuesta genérica a "eso no existe".
    /// `temporada` cambia cada año y `competicion`/`grupo` con ella ([Anexo RFFM
    /// §F.1]), así que un 404 es **revisa la coordenada** y no *"han rehecho la
    /// web"*. Sin separarlos, el canario grita lo mismo para las dos cosas y a
    /// las tres semanas nadie lo mira.
    @Test("un 404 dice 'coordenada caducada', no 'cambió la fuente' (Plan §4.4)")
    func notFoundIsItsOwnSignal() async throws {
        let transport = HTTPFederationTransport { _ in (status: 404, body: "") }

        await #expect(throws: FederationError.coordinateNotFound(detail: Self.url)) {
            try await transport.get(Self.url)
        }
    }

    /// Y el camino bueno: con `2xx`, el cuerpo pasa **tal cual**. El transporte
    /// no interpreta nada — eso es del parser, y separarlos es lo que hace que
    /// todo F2 sea nivel 1 (Plan §7.3).
    @Test("con 2xx devuelve el cuerpo sin tocarlo")
    func successReturnsTheBodyVerbatim() async throws {
        let body = #"<script id="__NEXT_DATA__">{"props":{}}</script>"#
        let transport = HTTPFederationTransport { _ in (status: 200, body: body) }

        #expect(try await transport.get(Self.url) == body)
    }

    /// El `204` es `2xx` y **no trae cuerpo**. Aceptarlo dejaría que un cuerpo
    /// vacío llegue al parser, que fallaría hablando del `__NEXT_DATA__` — otra
    /// vez el error engañoso de §F.7, por la puerta de al lado.
    @Test("un 2xx sin cuerpo tampoco llega al parser (§F.7)")
    func emptyBodyIsRejected() async throws {
        let transport = HTTPFederationTransport { _ in (status: 204, body: "") }

        await #expect(throws: FederationError.self) { try await transport.get(Self.url) }
    }
}

import enum Application.FederationError

import AsyncHTTPClient
import NIOCore
// `NIOHTTP1` no llega de gratis desde `AsyncHTTPClient`: `MemberImportVisibility`
// (SE-0444) exige declarar el módulo que define `.GET` y `status.code`, aunque
// el tipo que los lleva venga de otro. Es la cuarta fase seguida en que esta
// bandera cobra pieza, y siempre por lo mismo.
import NIOHTTP1

/// El transporte de verdad: trae bytes por HTTP. **La implementación que F2
/// dejó sin escribir** a propósito, porque no tenía integración que la
/// ejercitara (Plan §4.3).
///
/// # Qué es lo que aquí se decide
///
/// Nada de lo que dice la respuesta —eso es del parser—. Lo que se decide es
/// **cómo se lee el sobre**, y es donde la app heredada se equivocaba: [Anexo
/// RFFM §F.7] documenta que *"imprime el código HTTP pero no lo valida"*, así que
/// un 500 acaba en el parser de JSON y el error que se ve habla del cuerpo. Aquí
/// el código se mira **antes** que el cuerpo, siempre.
///
/// # Tres señales, no dos
///
/// Plan §4.4 pedía distinguir *"cambió la fuente"* de *"caducó la coordenada"*.
/// Son tres: un **404** dice que la coordenada ya no está, un **fallo de
/// transporte** dice que no hemos llegado a hablar, y un **parseo fallido**
/// —que ya no es de aquí— dice que han cambiado ellos. Solo la tercera es la que
/// el canario existe para detectar; las otras dos son ruido si se confunden con
/// ella.
///
/// # La RFFM no pide cabeceras
///
/// [Anexo RFFM §F.7]: *"**GET** siempre, parámetros en query string, **sin
/// cabeceras** (ni `Accept`, ni User-Agent), **sin autenticación**, respuesta
/// **UTF-8**"*. No se manda ninguna, y menos un `User-Agent` de navegador
/// inventado: fingir un navegador contra una API que no lo pide es la clase de
/// cosa que deja de funcionar sin avisar. La FCF **sí** los exige ([Anexo FCF]),
/// y ése será su adaptador, no éste (F9).
public struct HTTPFederationTransport: FederationTransport {
    /// Lo que hace la petición de verdad.
    ///
    /// Se inyecta para que **la lectura del sobre se pueda probar sin red**: las
    /// reglas de arriba son cuatro `if` y merecen tests de nivel 1, mientras que
    /// abrir el socket no se puede probar sin uno. Lo que queda sin cubrir por la
    /// batería es la línea que llama al cliente HTTP, y ésa la ejercita el
    /// canario — que es la única prueba que puede.
    typealias Perform = @Sendable (String) async throws -> (status: Int, body: String)

    private let perform: Perform

    init(perform: @escaping Perform) {
        self.perform = perform
    }

    /// El transporte de producción.
    ///
    /// # Lo que hay que saber de estas quince líneas
    ///
    /// **Es lo único de F5 que la batería no cubre**, y es deliberado: no se
    /// puede abrir un socket sin uno. Quien las ejercita es el canario, con
    /// `FEDERATION_LIVE=1`. Todo lo que se podía sacar de aquí —la lectura del
    /// código, el cuerpo vacío, los tres tipos de fallo— está fuera, en `get`, y
    /// probado sin red.
    ///
    /// **`HTTPClient.shared`** y no uno propio: un cliente por adaptador tendría
    /// que apagarse, y el ciclo de vida de la ingesta es el del proceso. El
    /// compartido lo gestiona la biblioteca.
    ///
    /// **Un *timeout* corto y explícito.** §2.3-c lo exige para el `/preview`,
    /// que llama a la federación **dentro** de una petición HTTP; y el job de F6
    /// lo necesita igual, porque una pasada colgada bloquea la del resto de
    /// clubes. Sin él, `AsyncHTTPClient` espera lo que haga falta.
    ///
    /// **El cuerpo se lee con tope.** El calendario más grande que hemos visto
    /// son 392 KB; 8 MB deja margen de sobra y evita que una respuesta
    /// inesperada se coma la memoria del proceso.
    ///
    /// - Parameter timeout: por defecto 20 s, que es holgado para una petición
    ///   que en las medidas de F5 tardó menos de dos.
    public init(client: HTTPClient = .shared, timeout: TimeAmount = .seconds(20)) {
        self.perform = { url in
            var request = HTTPClientRequest(url: url)
            request.method = .GET
            // Sin cabeceras: la RFFM no pide ninguna ([Anexo RFFM §F.7]).

            do {
                let response = try await client.execute(request, timeout: timeout)
                let body = try await response.body.collect(upTo: 8 * 1024 * 1024)
                return (status: Int(response.status.code), body: String(buffer: body))
            } catch {
                // La tercera señal (Plan §4.4): no hemos llegado a hablar. No es
                // ni "cambió la fuente" ni "caducó la coordenada", y confundirla
                // con cualquiera de las dos haría que el canario gritase cada vez
                // que alguien trabaja sin conexión.
                throw FederationError.transportFailure(
                    url: url, reason: "\(type(of: error)): \(error)")
            }
        }
    }

    public func get(_ url: String) async throws -> String {
        let response = try await perform(url)

        // **El código, antes que el cuerpo.** Siempre, y con el 404 aparte.
        // El 404 se mapea porque es la respuesta **genérica** a "eso no existe" y
        // este transporte lo comparten los dos adaptadores. Conviene saber que
        // **la RFFM no lo usa**: con una coordenada inexistente responde `200`
        // (medido en F5), así que ahí quien levanta esto es el parser. Que aquí
        // no se dispare con la RFFM no lo convierte en código muerto — lo
        // convierte en la mitad genérica de una regla que la otra mitad cumple.
        if response.status == 404 {
            throw FederationError.coordinateNotFound(detail: url)
        }
        guard (200..<300).contains(response.status) else {
            throw FederationError.unexpectedStatus(status: response.status, url: url)
        }

        // Un `2xx` vacío es `2xx`, y aun así no hay nada que parsear. Dejarlo
        // pasar reproduce el error engañoso de §F.7 por la puerta de al lado: el
        // parser se quejaría del `__NEXT_DATA__` que falta, no del cuerpo que no
        // llegó.
        guard !response.body.isEmpty else {
            throw FederationError.malformedResponse(
                field: "body", reason: "la respuesta llegó \(response.status) y vacía")
        }

        return response.body
    }
}

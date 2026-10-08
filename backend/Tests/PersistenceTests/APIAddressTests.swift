import Testing

@testable import App

/// Nivel 1, sin Docker: **de dónde sale el puerto de la API** que `serve` usa por
/// defecto y que los comandos imprimen en sus `curl` de ejemplo.
///
/// # Por qué existe esta suite
///
/// `seed-team`, `seed-competition` y `provision-tenant` imprimían `:8080` fijo.
/// Con `serve --port 8765` el `curl` que dejaban "listo para pegar" daba
/// `connection refused`, y nada en la salida decía por qué. Un comando no puede
/// preguntarle a `serve` en qué puerto está —es otro proceso—, así que los dos
/// leen la misma variable, `API_PORT`.
@Suite("APIAddress · el puerto de la API, compartido por serve y los comandos")
struct APIAddressTests {

    @Test("sin API_PORT, 8080: lo de siempre")
    func defaultsTo8080() {
        #expect(APIAddress(environment: [:]).port == 8080)
    }

    @Test("API_PORT fija el puerto")
    func readsAPIPort() {
        #expect(APIAddress(environment: ["API_PORT": "8765"]).port == 8765)
    }

    @Test("un API_PORT que no es un puerto cae a 8080, como DB_PORT")
    func invalidFallsBackToDefault() {
        #expect(APIAddress(environment: ["API_PORT": "abc"]).port == 8080)
        #expect(APIAddress(environment: ["API_PORT": "0"]).port == 8080)
        #expect(APIAddress(environment: ["API_PORT": "65536"]).port == 8080)
        #expect(APIAddress(environment: ["API_PORT": "65535"]).port == 65535)
        #expect(APIAddress(environment: ["API_PORT": "1"]).port == 1)
    }

    @Test("la URL del club lleva el slug en el subdominio y el puerto leído")
    func clubURL() {
        #expect(APIAddress(environment: ["API_PORT": "8765"]).clubURL(slug: "celtic-castilla")
            == "http://celtic-castilla.localhost:8765")
        #expect(APIAddress(environment: [:]).clubURL(slug: "atleti")
            == "http://atleti.localhost:8080")
    }
}

import Testing
import Application
import Domain
@testable import Federation

/// Nivel 1 (§8.1): **sin red**. El transporte entra por un protocolo y aquí se
/// falsea, que es lo que permite que F2 entera sea *unit puro* (Plan §4.1).
@Suite("RFFM · cliente y coordenada · Anexo RFFM §F.1, §F.9 · D-74")
struct RFFMFederationClientTests {

    /// Transporte de mentira: apunta lo que le piden y devuelve lo que le digan.
    /// **No hay HTTP en esta suite**, y es deliberado — validar el cliente real
    /// contra la federación es integración, y va en F5.
    final class SpyTransport: FederationTransport, @unchecked Sendable {
        var requested: [String] = []
        var response: Result<String, any Error>

        init(returning response: Result<String, any Error>) { self.response = response }

        func get(_ url: String) async throws -> String {
            requested.append(url)
            return try response.get()
        }
    }

    static let coordinate = FederationCoordinate(
        federationSeasonID: "22",
        federationCompetitionID: "26737701",
        federationGroupID: "26737702",
        modality: .futbol11
    )

    // ── La URL ───────────────────────────────────────────────────────────────

    /// §F.1: *"la consulta del calendario de un grupo —el punto de entrada de toda
    /// la ingesta— es exactamente esta"*. Literal, y con los nombres de parámetro
    /// en minúscula que el anexo insiste en que no se supongan (`grupo`, no
    /// `codgrupo`).
    @Test("construye la URL del calendario tal y como la documenta §F.1")
    func buildsCalendarURL() {
        #expect(RFFMEndpoints.calendar(for: Self.coordinate) ==
            "https://www.rffm.es/competicion/calendario"
            + "?temporada=22&tipojuego=1&competicion=26737701&grupo=26737702")
    }

    /// §F.9. **`3` es fútbol sala y `4` es fútbol-5**, no al revés: es exactamente
    /// donde un mapeo escrito por el orden del enumerado se equivocaría, y el
    /// error sería mudo — devolvería el calendario de otra modalidad, no un 404.
    @Test("traduce la modalidad al tipojuego del catálogo, sin fiarse del orden (§F.9)", arguments: [
        (Modality.futbol11, "1"),
        (Modality.futbol7, "2"),
        (Modality.futbolSala, "3"),
        (Modality.futbol5, "4"),
        (Modality.futbolPlaya, "5"),
    ])
    func mapsModalityToGameType(_ modality: Modality, _ expected: String) {
        #expect(RFFMGameType.code(for: modality) == expected)
    }

    /// §F.9 avisa de que el catálogo es tipográficamente inconsistente
    /// (`Futbol-11` sin acento, `Fútbol Sala` con acento y espacio): **usar el
    /// código, nunca el nombre**. Este test es la guardia de que el enumerado no
    /// crezca sin decidir su código.
    @Test("toda modalidad del dominio tiene código de la RFFM (§F.9)")
    func everyModalityIsMapped() {
        #expect(Modality.allCases.allSatisfy { !RFFMGameType.code(for: $0).isEmpty })
    }

    // ── El cliente ───────────────────────────────────────────────────────────

    /// La coordenada de `D-74`: tres códigos, uno por columna del modelo. El
    /// cliente **no compone rutas ni recuerda nada entre llamadas** (Plan §7.2).
    @Test("pide la URL de la coordenada y devuelve el calendario parseado")
    func fetchesAndParses() async throws {
        let transport = SpyTransport(returning: .success(RFFMCalendarParserTests.fixture))
        let client = RFFMFederationClient(transport: transport)

        let calendar = try await client.fetchCalendar(Self.coordinate)

        #expect(transport.requested == [RFFMEndpoints.calendar(for: Self.coordinate)])
        #expect(calendar.rounds.count == 34)
        #expect(calendar.seasonLabel.value == "2026/27")
    }

    /// **El puerto es sin estado** (Plan §7.2, punto 2): el `FCFContext` de la app
    /// heredada recordaba temporada y categoría entre llamadas, y en un backend
    /// multi-tenant eso es una fuga entre peticiones. Dos llamadas con coordenadas
    /// distintas sobre el **mismo** cliente tienen que pedir URLs distintas.
    @Test("dos coordenadas seguidas no se contaminan: el cliente no recuerda nada (Plan §7.2)")
    func isStateless() async throws {
        let transport = SpyTransport(returning: .success(RFFMCalendarParserTests.fixture))
        let client = RFFMFederationClient(transport: transport)
        let other = FederationCoordinate(
            federationSeasonID: "21", federationCompetitionID: "24037548",
            federationGroupID: "24037549", modality: .futbol7
        )

        _ = try await client.fetchCalendar(Self.coordinate)
        _ = try await client.fetchCalendar(other)

        #expect(transport.requested.count == 2)
        #expect(transport.requested[0].contains("temporada=22&tipojuego=1"))
        #expect(transport.requested[1].contains("temporada=21&tipojuego=2"))
    }

    /// §F.7: la app heredada *"imprime el código HTTP pero no lo valida"*, así que
    /// un 500 acababa en el parser de JSON con un error engañoso. Lo que llega del
    /// transporte sube tal cual, sin disfrazarse de error de parseo.
    @Test("un fallo de transporte no se disfraza de respuesta malformada (§F.7)")
    func propagatesTransportFailure() async {
        struct Boom: Error {}
        let client = RFFMFederationClient(transport: SpyTransport(returning: .failure(Boom())))
        await #expect(throws: Boom.self) { try await client.fetchCalendar(Self.coordinate) }
    }
}

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
        #expect(RFFMEndpoints().calendar(for: Self.coordinate) ==
            "https://www.rffm.es/competicion/calendario"
            + "?temporada=22&tipojuego=1&competicion=26737701&grupo=26737702")
    }

    /// §F.8 y §F.18. **Ni el mismo nombre de parámetro ni los mismos parámetros**
    /// que el calendario, y las dos cosas se equivocan escribiéndolas "por
    /// simetría": `idGroup` es **el único en *camelCase*** de toda la API, y esta
    /// ruta **no lleva `temporada` ni `tipojuego`**.
    ///
    /// Que la coordenada traiga los dos y aquí no se usen está medido y no es
    /// pereza: el grupo ya determina la competición, y la fuente lo demuestra
    /// devolviendo un `codigo_competicion` que nadie le envió (§F.18).
    @Test("construye la URL de la clasificación tal y como la documenta §F.8")
    func buildsStandingsURL() {
        #expect(RFFMEndpoints().standings(for: Self.coordinate, round: 30) ==
            "https://www.rffm.es/api/standings?idGroup=26737702&round=30")
    }

    /// §F.19. **Tercera ruta y tercer juego de nombres**, que es el argumento
    /// entero de que estas URLs vivan en un solo sitio: `idGroup` **y**
    /// `idCompetition`, los dos en *camelCase*, y sin `temporada` ni `tipojuego`.
    ///
    /// **Y aquí `idCompetition` SÍ hace falta**, al revés que en la clasificación,
    /// que se apaña con el grupo. No es simetría: está medido —sin ese parámetro,
    /// o con uno que no case con el grupo, la respuesta es `null` (§F.19)—. Quien
    /// lo quite "porque en `standings` no está" convierte la ruta en un silencio.
    @Test("construye la URL de goleadores tal y como la documenta §F.19")
    func buildsScorersURL() {
        #expect(RFFMEndpoints().scorers(for: Self.coordinate) ==
            "https://www.rffm.es/api/scorers?idGroup=26737702&idCompetition=26737701")
    }

    /// El reverso del test de arriba, y el que de verdad caza el cruce: los dos
    /// códigos son números largos y parecidos, así que intercambiarlos **no da un
    /// error** — da `null`, que se lee como *"esta competición no tiene
    /// goleadores"*. Afirmar el orden con dos valores distintos es lo único que lo
    /// distingue.
    @Test("y no cruza grupo con competición, que no daría error sino silencio (§F.19)")
    func theScorersURLDoesNotSwapTheTwoCodes() {
        let url = RFFMEndpoints().scorers(for: Self.coordinate)
        #expect(url.contains("idGroup=\(Self.coordinate.federationGroupID)"))
        #expect(url.contains("idCompetition=\(Self.coordinate.federationCompetitionID)"))
        #expect(Self.coordinate.federationGroupID != Self.coordinate.federationCompetitionID)
    }

    /// `R0.8` del plan del backoffice: los escenarios ponen una federación falsa
    /// en el sitio de la RFFM. **Cambia dónde, y solo dónde**: las tres rutas,
    /// con sus tres juegos de nombres, siguen siendo las de arriba.
    @Test("con otra dirección, las tres rutas cuelgan de ella y no de la RFFM (R0.8)")
    func routesHangFromTheConfiguredBaseURL() {
        let endpoints = RFFMEndpoints(baseURL: "http://localhost:8090")

        #expect(endpoints.calendar(for: Self.coordinate) ==
            "http://localhost:8090/competicion/calendario"
            + "?temporada=22&tipojuego=1&competicion=26737701&grupo=26737702")
        #expect(endpoints.standings(for: Self.coordinate, round: 30) ==
            "http://localhost:8090/api/standings?idGroup=26737702&round=30")
        #expect(endpoints.scorers(for: Self.coordinate) ==
            "http://localhost:8090/api/scorers?idGroup=26737702&idCompetition=26737701")
    }

    /// De dónde sale la dirección: `RFFM_BASE_URL`. **Sin ella, todo sigue como
    /// antes**, que es lo que de verdad hay que proteger: la ingesta de `launchd`
    /// no la tiene puesta y tiene que seguir yendo a la RFFM real.
    @Test("sin RFFM_BASE_URL, o vacía, la RFFM de verdad (R0.8)")
    func withoutTheVariableItIsTheRealRFFM() {
        #expect(RFFMEndpoints(environment: [:]).baseURL == "https://www.rffm.es")
        #expect(RFFMEndpoints(environment: ["RFFM_BASE_URL": ""]).baseURL == "https://www.rffm.es")
    }

    @Test("RFFM_BASE_URL fija la dirección (R0.8)")
    func theVariableSetsTheBaseURL() {
        #expect(RFFMEndpoints(environment: ["RFFM_BASE_URL": "http://localhost:8090"]).baseURL
            == "http://localhost:8090")
    }

    /// Con la barra final, la ruta saldría `…:8090//competicion/calendario`, y un
    /// servidor que busca `/competicion/calendario` no la reconoce: el escenario
    /// fallaría sin que nada en el error hablara de la barra.
    @Test("la barra final de RFFM_BASE_URL se quita, o las rutas saldrían con dos (R0.8)")
    func aTrailingSlashIsDropped() {
        let endpoints = RFFMEndpoints(environment: ["RFFM_BASE_URL": "http://localhost:8090/"])
        #expect(endpoints.scorers(for: Self.coordinate) ==
            "http://localhost:8090/api/scorers?idGroup=26737702&idCompetition=26737701")
    }

    /// Y el adaptador **pide** ahí: no basta con que las rutas sepan colgar de otra
    /// dirección si el cliente sigue construyendo las suyas con la de la RFFM.
    @Test("el cliente pide sus tres rutas a la dirección que le dan (R0.8)")
    func theClientAsksTheConfiguredBaseURL() async throws {
        let transport = SpyTransport(returning: .success("null"))
        let client = RFFMFederationClient(
            transport: transport, endpoints: RFFMEndpoints(baseURL: "http://localhost:8090"))

        _ = try? await client.fetchCalendar(Self.coordinate)
        _ = try? await client.fetchStandings(Self.coordinate, round: 30)
        _ = try? await client.fetchScorers(Self.coordinate)

        #expect(transport.requested.count == 3)
        #expect(transport.requested.allSatisfy { $0.hasPrefix("http://localhost:8090/") })
    }

    /// Los goleadores **no llevan jornada**, y el puerto lo dice en la firma: son
    /// estado vigente único, no *snapshot* (§3.2). Es la asimetría con el test de
    /// abajo, y por eso van juntos.
    @Test("la misma coordenada pide siempre la misma URL de goleadores (F8)")
    func scorersHaveNoRound() async throws {
        let transport = SpyTransport(returning: .success("null"))
        let client = RFFMFederationClient(transport: transport)

        _ = try? await client.fetchScorers(Self.coordinate)
        _ = try? await client.fetchScorers(Self.coordinate)

        #expect(transport.requested == [
            "https://www.rffm.es/api/scorers?idGroup=26737702&idCompetition=26737701",
            "https://www.rffm.es/api/scorers?idGroup=26737702&idCompetition=26737701",
        ])
    }

    /// Lo mismo que su hermana de la clasificación, y hace falta por separado: un
    /// adaptador que se "protegiera" devolviendo una tabla vacía convertiría una
    /// coordenada mala en *"esta liga no tiene goleadores"* — que aquí es un dato
    /// **perfectamente creíble**, porque `D-48` dice que hay federaciones que no
    /// los publican. Es el peor sitio del puerto para tragarse ese error.
    @Test("una coordenada mala de goleadores sube como tal, no como ranking vacío (D-84, D-48)")
    func theClientDoesNotSwallowTheScorersCoordinateError() async throws {
        let client = RFFMFederationClient(transport: SpyTransport(returning: .success("null")))

        await #expect(throws: FederationError.self) {
            try await client.fetchScorers(Self.coordinate)
        }
    }

    /// La jornada es **de la operación, no de la competición** (H-14): con la
    /// misma coordenada se piden dos fotos distintas, y eso es lo que hace que
    /// `StandingRow` sea un *snapshot* (`D-33`).
    @Test("la misma coordenada con dos jornadas pide dos URLs distintas (H-14)")
    func theRoundTravelsInTheURL() async throws {
        let transport = SpyTransport(returning: .success("null"))
        let client = RFFMFederationClient(transport: transport)

        // `null` hace que las dos lancen `coordinateNotFound`; lo que se afirma
        // aquí es **a dónde fue a preguntar**, no qué trajo.
        _ = try? await client.fetchStandings(Self.coordinate, round: 29)
        _ = try? await client.fetchStandings(Self.coordinate, round: 30)

        #expect(transport.requested == [
            "https://www.rffm.es/api/standings?idGroup=26737702&round=29",
            "https://www.rffm.es/api/standings?idGroup=26737702&round=30",
        ])
    }

    /// El cliente **no interpreta**: pasa el cuerpo al parser y deja subir lo que
    /// éste levante. Sin esto, un adaptador que se "protegiera" devolviendo una
    /// tabla vacía convertiría una coordenada mala en una clasificación de cero
    /// equipos, que es un dato perfectamente creíble y perfectamente falso.
    @Test("una coordenada que no designa nada sube como tal, no como tabla vacía (D-84)")
    func theClientDoesNotSwallowTheCoordinateError() async throws {
        let client = RFFMFederationClient(transport: SpyTransport(returning: .success("null")))

        await #expect(throws: FederationError.self) {
            try await client.fetchStandings(Self.coordinate, round: 1)
        }
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

        #expect(transport.requested == [RFFMEndpoints().calendar(for: Self.coordinate)])
        #expect(calendar.rounds.count == 34)
        #expect(calendar.seasonLabel?.value == "2026/27")
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

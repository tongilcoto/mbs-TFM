import Application
import Foundation
import Domain
import Testing

@testable import Federation

/// Nivel 1: **la inversa de `RFFMEndpoints.calendar(for:)`**, sin red.
///
/// Existe por `D-22`: la mitigación contra el dígito mal tecleado es **pegar la
/// URL entera**, porque copiar de la barra de direcciones no admite errata. Si
/// la herramienta que siembra competiciones pidiera los cuatro números sueltos,
/// esa mitigación se pierde justo donde más duele — un dígito cambiado **no da
/// error**, sincroniza otro calendario (`D-84`).
@Suite("RFFMCalendarURL · D-22 · la coordenada sale de la URL pegada")
struct RFFMCalendarURLTests {

    static let url = "https://www.rffm.es/competicion/calendario"
        + "?temporada=21&tipojuego=1&competicion=24037548&grupo=24037549"

    @Test("los cuatro parámetros caen en su sitio (Anexo RFFM §F.1)")
    func theFourParametersLandWhereTheyBelong() throws {
        let coordinate = try RFFMEndpoints.coordinate(fromCalendarURL: Self.url)

        // `competicion` y `grupo` **no son intercambiables** (§3.7) y cruzarlos
        // no daría un 404: devolvería otra cosa, en silencio.
        #expect(coordinate.federationSeasonID == "21")
        #expect(coordinate.federationCompetitionID == "24037548")
        #expect(coordinate.federationGroupID == "24037549")
        #expect(coordinate.modality == .futbol11)
    }

    @Test("la ida y la vuelta se cierran")
    func theRoundTripCloses() throws {
        let coordinate = try RFFMEndpoints.coordinate(fromCalendarURL: Self.url)
        #expect(RFFMEndpoints.calendar(for: coordinate) == Self.url)
    }

    @Test("`tipojuego` 3 es fútbol sala y 4 es fútbol-5, no al revés (Anexo RFFM §F.9)")
    func theGameTypeTrapIsRespected() throws {
        // La trampa que `RFFMGameType` ya documenta en la ida: escribirlo "por
        // orden" no da un 404, da el calendario de otra modalidad.
        let sala = try RFFMEndpoints.coordinate(
            fromCalendarURL: Self.url.replacingOccurrences(of: "tipojuego=1", with: "tipojuego=3"))
        let cinco = try RFFMEndpoints.coordinate(
            fromCalendarURL: Self.url.replacingOccurrences(of: "tipojuego=1", with: "tipojuego=4"))

        #expect(sala.modality == .futbolSala)
        #expect(cinco.modality == .futbol5)
    }

    @Test("una URL a la que le falta un parámetro se rechaza, no se completa")
    func aMissingParameterIsRejected() {
        // Inventar un valor por defecto aquí sería sincronizar otra competición
        // sin decirlo, que es exactamente lo que `D-84` enseñó a temer.
        for missing in ["temporada=21&", "competicion=24037548&", "grupo=24037549"] {
            let mutilada = Self.url.replacingOccurrences(of: missing, with: "")
            #expect(throws: (any Error).self, "sin '\(missing)'") {
                try RFFMEndpoints.coordinate(fromCalendarURL: mutilada)
            }
        }
    }

    @Test("un `tipojuego` que no está en el catálogo se rechaza")
    func anUnknownGameTypeIsRejected() {
        #expect(throws: (any Error).self) {
            try RFFMEndpoints.coordinate(
                fromCalendarURL: Self.url.replacingOccurrences(
                    of: "tipojuego=1", with: "tipojuego=9"))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// `C-B.1` · La misma inversa, pero **por el puerto**
// ─────────────────────────────────────────────────────────────────────────────

/// Nivel 1: **la inversa vista desde donde la va a usar el enganche**, sin red.
///
/// Los tests de arriba llaman a `RFFMEndpoints` por su nombre, y eso solo lo
/// puede hacer quien ya sabe que su federación es la RFFM — hoy, un único
/// llamante: el `AsyncCommand` de `seed-competition`. **El caso de uso del
/// `/preview` no lo sabe ni puede saberlo** ([D-67], [D-97]): llega al adaptador
/// por club → `Club.federation` → `FederationClientProvider`, así que lo que
/// tiene delante es `any FederationClient` y nada más.
///
/// De ahí que ésta sea una suite aparte y no un `@Test` más: lo que afirma no es
/// el parseo —ya afirmado arriba— sino **que la lectura de la URL está en el
/// puerto**. El principio es más ancho que el método: el adaptador es dueño del
/// universo de datos de su federación de punta a punta —su URL, su JSON, dónde
/// pega la letra del equipo— y eso está fuera del universo que el Dominio modela.
@Suite("FederationClient · D-97 · el adaptador lee su propia URL")
struct FederationClientCoordinateTests {

    /// Transporte que **no se puede usar**: leer una URL es parseo, no red.
    ///
    /// No es ceremonia. Si la implementación se fuera alguna vez a preguntarle a
    /// la federación qué significa su propia URL, este doble lo convierte en un
    /// fallo ruidoso en vez de en una suite que tarda medio segundo más.
    struct MuteTransport: FederationTransport {
        func get(_ url: String) async throws -> String {
            Issue.record("leer la URL no habla con la red: \(url)")
            return ""
        }
    }

    @Test("la coordenada se lee por el puerto, no por el nombre del adaptador (D-97)")
    func thePortReadsItsOwnURL() throws {
        // Por el existencial **a propósito**: lo que se afirma es que el puerto
        // lo declara, no que este `struct` tenga un método que se llama así.
        let client: any FederationClient = RFFMFederationClient(transport: MuteTransport())

        let coordinate = try client.coordinate(fromCalendarURL: RFFMCalendarURLTests.url)

        // Los mismos cuatro de §F.1, y por el mismo motivo: `competicion` y
        // `grupo` cruzados no dan un 404, dan otro calendario en silencio (`D-84`).
        #expect(coordinate.federationSeasonID == "21")
        #expect(coordinate.federationCompetitionID == "24037548")
        #expect(coordinate.federationGroupID == "24037549")
        #expect(coordinate.modality == .futbol11)
    }
}

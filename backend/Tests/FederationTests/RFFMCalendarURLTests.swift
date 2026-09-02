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

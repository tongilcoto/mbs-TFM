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

    /// `C-B.2` · Lo que no es una URL de calendario **de esta** federación se
    /// rechaza entera, y se rechaza **con un error de dominio**.
    ///
    /// # Dos mitades, y la segunda es la que no se ve
    ///
    /// La primera es la guarda del *host*, que el *spec* pide con todas las
    /// letras —*"comprueba que el host corresponde a la federación del club"*—
    /// y que hasta ahora no existía: una URL de la FCF pegada por un
    /// administrador de Madrid no decía *"esta URL no es de tu federación"*,
    /// decía que le faltaba `tipojuego`. **Un parseo a medias contando un
    /// problema que no es el que hay.**
    ///
    /// La segunda es **de qué tipo es el error**. Los dos motivos de rechazo son
    /// del universo de datos de la RFFM —su *host*, sus nombres de parámetro— y
    /// ese universo no sale del adaptador ([D-97]). Lo que sale es la única cosa
    /// que el caso de uso puede entender sin saber de qué federación hablamos:
    /// *"lo que me has pegado no se puede leer"*. Sin esta traducción, un
    /// `RFFMURLError` cruza la frontera HTTP sin que nadie lo conozca y
    /// `ProblemMiddleware` lo sirve como **500** — un fallo nuestro, cuando lo
    /// que pasa es que el administrador se equivocó de pestaña.
    @Test("la URL ajena o ilegible da un error de dominio, y DICE POR QUÉ (D-97, D-22)")
    func aForeignOrUnreadableURLIsRejected() {
        let client: any FederationClient = RFFMFederationClient(transport: MuteTransport())

        // **Cada una con lo que el motivo tiene que decir**, y ahí está el
        // ciclo: afirmar solo el tipo del error dejaba pasar el defecto entero.
        // La URL de la FCF también daba `DomainError` **sin guarda ninguna** —por
        // el camino de "le falta `tipojuego`"—, que es exactamente el parseo a
        // medias contando un problema que no es el que hay. Lo cazó la mutación
        // M3, no un rojo.
        let rechazadas = [
            // De otra federación. Que la FCF no tenga adaptador ([D-95]) es otra
            // puerta y otro código: aquí hay un administrador de la RFFM pegando
            // lo que no es suyo.
            ("https://www.fcf.cat/resultats/2526/futbol-11/tercera-catalana/grup-8",
             "no es de la RFFM"),
            // Ni siquiera es una URL: sin *host* no hay federación que reconocer.
            ("el calendario del cadete, el de los sábados", "no es de la RFFM"),
            // De la RFFM, del calendario, y **sin `grupo`**: lo que se rechaza no
            // es solo lo ajeno. Inventarlo sería elegir por el administrador qué
            // liga se ingiere ([D-22]).
            ("https://www.rffm.es/competicion/calendario"
                + "?temporada=21&tipojuego=1&competicion=24037548", "grupo"),
        ]

        for (url, loQueTieneQueDecir) in rechazadas {
            do {
                let leida = try client.coordinate(fromCalendarURL: url)
                Issue.record("se aceptó '\(url)' y salió \(leida)")
            } catch let error as DomainError {
                // **`DomainError` y no cualquier error**: lo que cruza la
                // frontera tiene que ser algo que el llamante conozca — un
                // `RFFMURLError` lo serviría `ProblemMiddleware` como 500.
                guard case .unreadableFederationURL(let devuelta, let motivo) = error else {
                    Issue.record("el caso de `DomainError` no es el suyo: \(error)")
                    continue
                }
                #expect(motivo.contains(loQueTieneQueDecir), "motivo de '\(url)': \(motivo)")
                // La URL vuelve **entera**: el administrador tiene doce equipos y
                // acaba de pegar una de doce pestañas.
                #expect(devuelta == url)
            } catch {
                Issue.record("error de otro tipo para '\(url)': \(error)")
            }
        }
    }

    /// Y la otra mitad de la guarda, que es la que se olvida: **no puede
    /// rechazar lo que sí es suyo**.
    ///
    /// El *host* llega como lo escriba quien pega —el DNS no distingue
    /// mayúsculas— así que una URL a gritos sigue siendo de la RFFM. Este test
    /// lo pidió la mutación M6, no un rojo: sin él, quitar el `lowercased()` no
    /// rompía nada y el enganche habría empezado a decir *"esa URL no es de la
    /// RFFM"* sobre una que sí lo es.
    @Test("la guarda no rechaza la suya por venir en mayúsculas (C-B.2)")
    func theGuardDoesNotRejectItsOwnURLShouted() throws {
        let client: any FederationClient = RFFMFederationClient(transport: MuteTransport())

        let aGritos = "HTTPS://WWW.RFFM.ES/competicion/calendario"
            + "?temporada=21&tipojuego=1&competicion=24037548&grupo=24037549"

        let coordinate = try client.coordinate(fromCalendarURL: aGritos)

        #expect(coordinate.federationGroupID == "24037549")
    }
}

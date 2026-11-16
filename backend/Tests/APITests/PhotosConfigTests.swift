import Foundation
import Testing

@testable import App

/// La carpeta de las fotos por entorno (`D-115`, punto 2; R6.8). Sin servidor ni base: solo cómo se lee.
@Suite("App · R6.8 · la carpeta de las fotos")
struct PhotosConfigTests {

    @Test("sin PHOTOS_DIR, fotos/ dentro de la carpeta desde la que se lanza")
    func defaultsToFotos() {
        #expect(PhotosConfig.fromEnvironment(nil, workingDirectory: "/tmp/backend").folder.path == "/tmp/backend/fotos")
        #expect(PhotosConfig.fromEnvironment("", workingDirectory: "/tmp/backend").folder.path == "/tmp/backend/fotos")
    }

    @Test("PHOTOS_DIR manda: absoluta tal cual, relativa desde la carpeta de lanzar")
    func environmentWins() {
        #expect(PhotosConfig.fromEnvironment("/srv/escenarios/fotos", workingDirectory: "/tmp/backend").folder.path
                == "/srv/escenarios/fotos")
        #expect(PhotosConfig.fromEnvironment("../otra", workingDirectory: "/tmp/backend").folder.path
                == "/tmp/otra")
    }
}

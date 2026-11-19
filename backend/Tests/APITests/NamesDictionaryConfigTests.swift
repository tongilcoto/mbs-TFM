import Foundation
import Storage
import Testing

@testable import App

/// Dónde busca el servidor el diccionario de nombres (`D-123`; decisión 1 de R6.19), como las fotos (`PhotosConfig`).
@Suite("App · R6.19 · dónde está el diccionario de nombres")
struct NamesDictionaryConfigTests {

    @Test("sin NAMES_DICTIONARY_FILE, diccionario-nombres.txt en la carpeta desde la que se lanza")
    func defaultFile() {
        #expect(NamesDictionaryConfig.fromEnvironment(nil, workingDirectory: "/tmp/backend").file.path
                    == "/tmp/backend/diccionario-nombres.txt")
        #expect(NamesDictionaryConfig.fromEnvironment("", workingDirectory: "/tmp/backend").file.path
                    == "/tmp/backend/diccionario-nombres.txt")
    }

    @Test("NAMES_DICTIONARY_FILE manda: absoluta tal cual, relativa desde la carpeta de lanzar")
    func fromEnvironment() {
        #expect(NamesDictionaryConfig.fromEnvironment("/srv/tfm/nombres.txt", workingDirectory: "/tmp/backend").file.path
                    == "/srv/tfm/nombres.txt")
        #expect(NamesDictionaryConfig.fromEnvironment("../otro/nombres.txt", workingDirectory: "/tmp/backend").file.path
                    == "/tmp/otro/nombres.txt")
    }
}

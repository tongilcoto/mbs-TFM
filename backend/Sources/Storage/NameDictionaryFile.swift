public import Application
public import Domain
public import struct Foundation.URL
import Foundation

/// El diccionario de nombres (`D-123`) en un fichero de texto, **leído cada vez que se pide** (enmienda a `D-123`,
/// R6.19): corregir una palabra es editar el fichero, y la siguiente sincronización ya la usa, sin relanzar el
/// servidor. Unas 300 líneas, y se sincroniza a mano, equipo a equipo: leerlo cada vez no cuesta.
///
/// Si el fichero no está, o no se puede leer como texto, da `nil`, y quien lo pide sigue sin diccionario (decisión 2
/// de R6.19).
public struct NameDictionaryFile: NameDictionarySource {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    public func read() -> CastilianNames? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return CastilianNames(text: text)
    }
}

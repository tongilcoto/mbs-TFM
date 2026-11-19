public import Domain

/// De dónde sale el diccionario de nombres y apellidos (`D-123`), como **puerto** (§4.3): hoy, un fichero de texto
/// que se cambia en caliente (enmienda a `D-123`, R6.19); la pieza `Storage` lo lee.
///
/// Lo que cada adaptador promete:
/// 1. **Se lee cada vez que se pide**: lo cambiado vale desde la siguiente sincronización, sin relanzar el servidor.
/// 2. **Si no está, o no se puede leer, da `nil`**, y quien lo pide sigue sin diccionario: nunca se para por él
///    (decisión 2 de R6.19). Las líneas malas, en el propio diccionario (`CastilianNames.problems`).
public protocol NameDictionarySource: Sendable {
    func read() -> CastilianNames?
}

/// Un diccionario fijo, el que se le dé: para las pruebas, y para quien no tiene fichero.
public struct FixedNameDictionary: NameDictionarySource {
    private let names: CastilianNames?

    public init(_ names: CastilianNames?) {
        self.names = names
    }

    public func read() -> CastilianNames? { names }
}

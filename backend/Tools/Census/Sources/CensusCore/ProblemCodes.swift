import Foundation

/// Un fichero leído del árbol: su ruta relativa y su texto.
public struct SourceFile: Sendable, Equatable {
    public var path: String
    public var text: String

    public init(path: String, text: String) {
        self.path = path
        self.text = text
    }
}

/// Dónde emite el código un código `Problem`.
public struct CodeEmission: Sendable, Equatable {
    public var code: String
    public var file: String
    public var line: Int

    public init(code: String, file: String, line: Int) {
        self.code = code
        self.file = file
        self.line = line
    }
}

/// Los códigos `Problem` que el código puede emitir: cada `code: "X"` de `Sources/`.
///
/// **Es el método de A-14 (H-72), escrito**: `grep -rhoE 'code: "[A-Z_]+"' Sources/`.
/// Un código que se construyera de otra forma —interpolado, o desde una tabla—
/// no saldría aquí. Hoy no hay ninguno así: los 31 son literales.
public func emittedProblemCodes(in sources: [SourceFile]) -> [CodeEmission] {
    sources.flatMap { file in
        file.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .flatMap { index, line in
                line.matches(of: /code: "([A-Z_]+)"/).map {
                    CodeEmission(code: String($0.1), file: file.path, line: index + 1)
                }
            }
    }
}

/// Los ficheros de test que **nombran** el código, entre comillas.
///
/// **Nombrar no es afirmar** (`A-7`·H-47): un `"TEAM_NOT_FOUND"` dentro de un
/// comentario cuenta igual. Sirve para levantar la sospecha de un hueco, no para
/// cerrarla; lo que la cierra es la mutación.
public func filesMentioning(code: String, in tests: [SourceFile]) -> [String] {
    // Las comillas son el borde: `"NOT_FOUND"` no está dentro de `"TEAM_NOT_FOUND"`.
    tests.filter { $0.text.contains("\"\(code)\"") }.map(\.path)
}

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

/// Los códigos `Problem` que el código puede emitir: cada `code: "X"` y cada
/// `code: .X` de `Sources/`.
///
/// **Es el método de A-14 (H-72), escrito**: `grep -rhoE 'code: "[A-Z_]+"' Sources/`.
/// Y desde R1.4, también `code: .X`: la función `problem(...)` de los *handlers*
/// recibe el código de la lista del catálogo (`ProblemCode`), y sus llamadas ya no
/// lo escriben entre comillas.
///
/// Un código que se construyera de otra forma —interpolado, o desde una tabla—
/// no saldría aquí. Hoy hay uno: el `NOT_FOUND` de `ProblemMiddleware`, que sale
/// de una condición (`… == 404 ? "NOT_FOUND" : "BAD_REQUEST"`).
public func emittedProblemCodes(in sources: [SourceFile]) -> [CodeEmission] {
    sources.flatMap { file in
        file.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .flatMap { index, line in
                line.matches(of: /code: (?:"([A-Z_]+)"|\.([A-Z_]+)(?![A-Za-z0-9_]))/).map {
                    CodeEmission(code: String($0.1 ?? $0.2!), file: file.path, line: index + 1)
                }
            }
    }
}

/// Los ficheros de test que **nombran** el código: entre comillas (`"X"`) o como
/// caso de la lista del catálogo (`.X`, desde R1.4).
///
/// **Nombrar no es afirmar** (`A-7`·H-47): un `"TEAM_NOT_FOUND"` dentro de un
/// comentario cuenta igual. Sirve para levantar la sospecha de un hueco, no para
/// cerrarla; lo que la cierra es la mutación.
public func filesMentioning(code: String, in tests: [SourceFile]) -> [String] {
    // Las comillas son el borde: `"NOT_FOUND"` no está dentro de `"TEAM_NOT_FOUND"`.
    // Con `.X`, el punto es el borde de delante (en `.TEAM_NOT_FOUND`, delante de
    // `NOT_FOUND` hay un `_`) y el de detrás es el de un identificador de Swift.
    // Los códigos son `[A-Z_]`, así que no hay nada que escapar en el patrón.
    let member = try! Regex("\\.\(code)(?![A-Za-z0-9_])")
    return tests.filter { $0.text.contains("\"\(code)\"") || $0.text.contains(member) }.map(\.path)
}

/// La lista cerrada de códigos del catálogo: el `enum` del esquema `ProblemCode`
/// (R1.4, decisión 3 del plan R1). `nil` si el catálogo no la tiene.
public func contractProblemCodes(spec: [String: Any]) -> [String]? {
    let schemas = (spec["components"] as? [String: Any])?["schemas"] as? [String: Any]
    return (schemas?["ProblemCode"] as? [String: Any])?["enum"] as? [String]
}

/// Los códigos que el servidor emite y **no están en la lista** del catálogo.
///
/// Es la mitad de la garantía que el compilador no da (LLD-B §4.5 *b*): los
/// *handlers* ya construyen el error con la lista, pero `ProblemMiddleware`
/// escribe el código como texto, y uno nuevo que se olvide en el catálogo
/// compilaría igual. Una web generada del catálogo no tendría mensaje para él.
public func codesMissingFromContract(emitted: [String], contract: [String]) -> [String] {
    Set(emitted).subtracting(contract).sorted()
}

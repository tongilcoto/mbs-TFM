/// Por qué una mutación **no llegó a aplicarse**.
///
/// Es la lección de F4 y de F7: un patrón que no casaba producía un
/// *"sobrevive"* sin haber mutado nada. Una mutación sin aplicar no es un
/// resultado, así que aquí no hay veredicto posible: hay un motivo.
public enum NotApplied: Error, Equatable, Sendable, CustomStringConvertible {
    case fileNotFound(String)
    case patternNotFound(edit: Int)
    /// Si el texto aparece más de una vez no se sabe qué sitio se quería romper,
    /// y romper el que no era da un resultado sobre otra línea.
    case patternAmbiguous(edit: Int, occurrences: Int)
    /// El reemplazo deja el fichero igual: no hay nada que medir.
    case noChange

    public var description: String {
        switch self {
        case .fileNotFound(let path): "no existe \(path)"
        case .patternNotFound(let edit): "el cambio \(edit) no casa con el fichero"
        case .patternAmbiguous(let edit, let occurrences):
            "el cambio \(edit) casa \(occurrences) veces; tiene que casar una"
        case .noChange: "el fichero queda igual"
        }
    }
}

/// Aplica `edits` en orden, cada uno sobre el resultado del anterior.
///
/// **El reemplazo es literal, sin expresiones regulares ni intérprete de por
/// medio.** En F7 un `$0` sin escapar en el reemplazo de `perl` hizo que una
/// mutación no compilara, y se contó como superviviente: aquí `$0` es `$0`.
/// Cada búsqueda tiene que casar **exactamente una vez**.
public func applying(_ edits: [Edit], to source: String) -> Result<String, NotApplied> {
    var result = source
    for (index, edit) in edits.enumerated() {
        let ranges = result.ranges(of: edit.find)
        switch ranges.count {
        case 0: return .failure(.patternNotFound(edit: index + 1))
        case 1: result.replaceSubrange(ranges[0], with: edit.replace)
        default: return .failure(.patternAmbiguous(edit: index + 1, occurrences: ranges.count))
        }
    }
    guard result != source else { return .failure(.noChange) }
    return .success(result)
}

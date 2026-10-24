import Yams

/// Escribe en Swift los nombres en español de cada lista del catálogo (`D-108`, `D-109`).
///
/// Cada lista de `components/schemas` con `enum` lleva su tabla `x-enum-names`, menos `ProblemCode`, cuyos mensajes
/// escribe cada cliente. De cada una sale una extensión del tipo que ya genera `swift-openapi-generator`:
/// `Components.Schemas.TeamCategory.alevin.displayName` es «Alevín». Así el servidor no escribe ningún nombre a mano.
///
/// Comprueba lo mismo que la web al fabricar sus esquemas (`gen-schemas.mjs`): que no falte ni sobre ningún
/// nombre. Y una cosa más, que solo importa aquí: que la lista esté en `filter: schemas` de la configuración del
/// generador, porque el generador solo fabrica los tipos que el servidor usa, y sin el tipo la extensión no compila.
public enum EnumNames {
    /// Lo que impide generar: todos los fallos a la vez.
    public struct Problems: Error, Equatable, CustomStringConvertible {
        public let lines: [String]
        public init(_ lines: [String]) { self.lines = lines }
        public var description: String { lines.joined(separator: "\n") }
    }

    /// La lista cuyos valores no llevan nombre: sus mensajes los escribe cada cliente (`D-108`, punto 3).
    static let unnamedList = "ProblemCode"

    public static func swiftSource(catalog: String, generatorConfig: String) throws -> String {
        let lists = try namedLists(in: catalog)
        let generated = try filteredSchemas(in: generatorConfig)

        var problems: [String] = []
        for list in lists {
            problems += list.problems
            if !generated.contains(list.name) {
                problems.append(
                    "\(list.name): añádela a `filter: schemas` en openapi-generator-config.yaml, o el contrato no tendrá su tipo")
            }
        }
        guard problems.isEmpty else { throw Problems(problems) }

        return header + lists.map(\.swiftExtension).joined(separator: "\n")
    }

    // ── Lo que lee ──────────────────────────────────────────────────────────

    struct List {
        let name: String
        let values: [String]
        let names: [(value: String, name: String)]?

        var problems: [String] {
            guard let names else { return ["\(name): le falta x-enum-names"] }
            var problems: [String] = []
            let named = Set(names.map(\.value))
            let missing = values.filter { !named.contains($0) }
            let extra = names.map(\.value).filter { !values.contains($0) }
            if !missing.isEmpty { problems.append("\(name): sin nombre para \(missing.joined(separator: ", "))") }
            if !extra.isEmpty {
                problems.append("\(name): nombres de valores que la lista no tiene: \(extra.joined(separator: ", "))")
            }
            return problems
        }

        /// Un `switch` con un caso por valor, en el orden del catálogo: si el contrato cambia un valor y aquí no, no
        /// compila.
        var swiftExtension: String {
            let byValue = Dictionary(uniqueKeysWithValues: (names ?? []).map { ($0.value, $0.name) })
            let cases = values.map { "        case .\($0): \(swiftLiteral(byValue[$0] ?? ""))" }
            return """
                extension Components.Schemas.\(name) {
                    /// El nombre en español de este valor, de `x-enum-names` en el catálogo.
                    public var displayName: String {
                        switch self {
                \(cases.joined(separator: "\n"))
                        }
                    }
                }

                """
        }
    }

    /// Las listas del catálogo, en su orden: los esquemas con `enum`, menos `ProblemCode`.
    static func namedLists(in catalog: String) throws -> [List] {
        guard let root = try Yams.compose(yaml: catalog),
              let schemas = root["components"]?["schemas"]?.mapping
        else { throw Problems(["el catálogo no tiene components/schemas"]) }

        return schemas.compactMap { key, schema in
            guard let name = key.string, name != unnamedList,
                  let values = schema["enum"]?.sequence?.compactMap(\.string)
            else { return nil }
            let names = schema["x-enum-names"]?.mapping?.compactMap { value, name -> (String, String)? in
                guard let value = value.string, let name = name.string else { return nil }
                return (value, name)
            }
            return List(name: name, values: values, names: names.map { $0.map { (value: $0.0, name: $0.1) } })
        }
    }

    /// Los esquemas que el generador fabrica aunque ninguna operación servida los use (`filter: schemas`).
    static func filteredSchemas(in config: String) throws -> Set<String> {
        guard let root = try Yams.compose(yaml: config) else { return [] }
        return Set(root["filter"]?["schemas"]?.sequence?.compactMap(\.string) ?? [])
    }

    // ── Lo que escribe ──────────────────────────────────────────────────────

    static let header = """
        // Generado al compilar por EnumNamesTool, desde `x-enum-names` de openapi.yaml (D-108, D-109).
        // No se toca a mano: los nombres se cambian en el catálogo.

        """

    /// Un texto de Swift entre comillas, con las comillas y las barras escapadas.
    static func swiftLiteral(_ text: String) -> String {
        let escaped = text
            .replacing("\\", with: "\\\\")
            .replacing("\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

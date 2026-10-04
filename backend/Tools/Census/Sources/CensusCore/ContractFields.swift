import Foundation

/// Un campo del contrato: la propiedad de un esquema.
///
/// `owner` es el nombre del esquema de `components/schemas` cuando lo tiene; un
/// objeto anidado sin nombre propio se nombra por su ruta desde el último que lo
/// tiene (`IngestionRunResponse.counters`, `…items[]`). Dos operaciones que
/// devuelven el mismo esquema **no** duplican sus campos: se cuenta el campo,
/// no cada sitio por el que se llega a él.
public struct ContractField: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var owner: String
    public var property: String

    public init(owner: String, property: String) {
        self.owner = owner
        self.property = property
    }

    public var description: String { "\(owner).\(property)" }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.description < rhs.description }
}

public enum SpecError: Error, Equatable, CustomStringConvertible {
    /// Una operación del `filter` que no está en el *spec*: el censo contaría de
    /// menos sin decirlo.
    case operationNotFound(String)
    case unresolvedReference(String)

    public var description: String {
        switch self {
        case .operationNotFound(let id): "la operación \(id) del filter no está en el spec"
        case .unresolvedReference(let ref): "no se resuelve \(ref)"
        }
    }
}

/// Los campos que alcanza un cliente desde las respuestas **2xx** de
/// `operations`.
///
/// El recorrido: cada respuesta 2xx (resolviendo `components/responses`), su
/// `application/json`, y desde su esquema, `$ref`, `allOf`/`oneOf`/`anyOf`,
/// `properties`, `items` y `additionalProperties`, en profundidad. Las
/// respuestas de error no entran: su forma es `Problem`, y lo que se censa de
/// ellas es el código (`emittedProblemCodes`).
public func reachableFields(spec: [String: Any], operations: [String]) throws -> Set<ContractField> {
    var walker = SchemaWalker(spec: spec)
    let methods = ["get", "put", "post", "patch", "delete"]
    var found = Set<String>()

    let paths = spec["paths"] as? [String: Any] ?? [:]
    for item in paths.values {
        guard let item = item as? [String: Any] else { continue }
        for method in methods {
            guard let operation = item[method] as? [String: Any],
                  let id = operation["operationId"] as? String,
                  operations.contains(id)
            else { continue }
            found.insert(id)
            let responses = operation["responses"] as? [String: Any] ?? [:]
            for (status, response) in responses where status.hasPrefix("2") {
                let response = try walker.resolve(response)
                let content = response["content"] as? [String: Any]
                guard let json = content?["application/json"] as? [String: Any],
                      let schema = json["schema"]
                else { continue }
                try walker.walk(schema, owner: "\(id).\(status)")
            }
        }
    }

    if let missing = operations.first(where: { !found.contains($0) }) {
        throw SpecError.operationNotFound(missing)
    }
    return walker.fields
}

/// El recorrido en profundidad de un esquema, con lo visitado para no entrar
/// dos veces en el mismo `$ref` (y no colgarse en uno recursivo).
struct SchemaWalker {
    let spec: [String: Any]
    var fields = Set<ContractField>()
    var visited = Set<String>()

    init(spec: [String: Any]) { self.spec = spec }

    /// Si `node` es un `{"$ref": …}`, el nodo al que apunta.
    func resolve(_ node: Any) throws -> [String: Any] {
        guard let dictionary = node as? [String: Any] else { return [:] }
        guard let ref = dictionary["$ref"] as? String else { return dictionary }
        var target: Any = spec
        for part in ref.split(separator: "/").dropFirst() {
            guard let next = (target as? [String: Any])?[String(part)] else {
                throw SpecError.unresolvedReference(ref)
            }
            target = next
        }
        guard let resolved = target as? [String: Any] else { throw SpecError.unresolvedReference(ref) }
        return resolved
    }

    mutating func walk(_ node: Any, owner: String) throws {
        guard let dictionary = node as? [String: Any] else { return }

        if let ref = dictionary["$ref"] as? String {
            // Un esquema con nombre es su propio dueño, venga de donde venga.
            guard visited.insert(ref).inserted else { return }
            let name = String(ref.split(separator: "/").last ?? "")
            try walk(try resolve(dictionary), owner: name)
            return
        }
        for key in ["allOf", "oneOf", "anyOf"] {
            for part in dictionary[key] as? [Any] ?? [] { try walk(part, owner: owner) }
        }
        for (property, schema) in dictionary["properties"] as? [String: Any] ?? [:] {
            fields.insert(ContractField(owner: owner, property: property))
            try walk(schema, owner: "\(owner).\(property)")
        }
        if let items = dictionary["items"] { try walk(items, owner: owner) }
        if let additional = dictionary["additionalProperties"] as? [String: Any] {
            try walk(additional, owner: owner)
        }
    }
}

/// Si algún test de API **nombra** la propiedad: como miembro (`.roundId`) o
/// como clave (`"roundId"`), con la palabra entera.
///
/// **El mismo límite que los códigos** (H-47): `.id` lo nombra media batería.
/// Es una red para encontrar huecos, no un certificado de cobertura.
public func mentions(property: String, in tests: [SourceFile]) -> Bool {
    // El borde es el de un **identificador de Swift**, explícito, y no `\b`: con
    // el de Unicode (UAX #29) un punto entre letras no separa palabras, y
    // `.competition.ageCategory` no casaba con `.competition` (el estreno).
    let escaped = NSRegularExpression.escapedPattern(for: property)
    guard let pattern = try? Regex(#"\.\#(escaped)(?![A-Za-z0-9_])|"\#(escaped)""#) else { return false }
    return tests.contains { $0.text.contains(pattern) }
}

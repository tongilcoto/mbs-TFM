import Foundation

/// Las mutaciones de una fase o de una ronda de arreglos, con lo que cada una
/// tiene que hacer caer.
///
/// **El catálogo es lo que hace citable una cifra.** Hasta `A-15`·H-52 las
/// mutaciones vivían en la sesión que las hacía: un *"14/14"* se podía creer,
/// no repetir. Un catálogo versionado junto al código es la afirmación entera
/// —qué se rompió, dónde, y qué tests debían notarlo—, y cualquiera la vuelve a
/// ejecutar.
public struct Catalog: Decodable, Sendable, Equatable {
    public var title: String
    /// El `--filter` de `swift test` para las mutaciones que no traen el suyo.
    /// Sin ninguno de los dos, la mutación corre contra la batería entera.
    public var filter: String?
    public var mutations: [Mutation]

    public init(title: String, filter: String? = nil, mutations: [Mutation]) {
        self.title = title
        self.filter = filter
        self.mutations = mutations
    }

    /// El filtro con el que se prueba `mutation`: el suyo, o el del catálogo.
    public func filter(for mutation: Mutation) -> String? {
        mutation.filter ?? filter
    }

    /// Lo que un catálogo tiene que cumplir para que su resultado signifique algo.
    public func validate() throws {
        var problems: [String] = []
        if mutations.isEmpty { problems.append("el catálogo no tiene mutaciones") }
        var seen = Set<String>()
        for mutation in mutations {
            if !seen.insert(mutation.id).inserted {
                problems.append("el id \(mutation.id) se repite")
            }
            if mutation.edits.isEmpty {
                problems.append("\(mutation.id): no cambia nada")
            }
            for (index, edit) in mutation.edits.enumerated() where edit.find.isEmpty {
                problems.append("\(mutation.id): el cambio \(index + 1) no busca nada")
            }
        }
        if !problems.isEmpty { throw CatalogError(problems: problems) }
    }
}

public struct CatalogError: Error, CustomStringConvertible, Equatable {
    public var problems: [String]
    public var description: String {
        "catálogo inválido:\n" + problems.map { "  · \($0)" }.joined(separator: "\n")
    }
}

/// Una mutación: uno o varios cambios **literales** sobre un fichero.
public struct Mutation: Decodable, Sendable, Equatable {
    public var id: String
    public var description: String
    /// Relativo al paquete que se prueba (`backend/`).
    public var file: String
    public var edits: [Edit]
    public var filter: String?
    /// Si se declara, la mutación **debe** sobrevivir y aquí va por qué: el
    /// programa mutado es el mismo programa (la tercera lectura de F5).
    public var equivalent: String?

    public init(id: String, description: String, file: String, edits: [Edit],
                filter: String? = nil, equivalent: String? = nil) {
        self.id = id
        self.description = description
        self.file = file
        self.edits = edits
        self.filter = filter
        self.equivalent = equivalent
    }

    enum CodingKeys: String, CodingKey {
        case id, description, file, edits, find, replace, filter, equivalent
    }

    /// Acepta `edits: [{find, replace}]` o, para el caso común de un solo
    /// cambio, `find` y `replace` sueltos. Las dos formas a la vez, no: no se
    /// sabría cuál manda.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        description = try container.decode(String.self, forKey: .description)
        file = try container.decode(String.self, forKey: .file)
        filter = try container.decodeIfPresent(String.self, forKey: .filter)
        equivalent = try container.decodeIfPresent(String.self, forKey: .equivalent)

        let list = try container.decodeIfPresent([Edit].self, forKey: .edits)
        let find = try container.decodeIfPresent(String.self, forKey: .find)
        let replace = try container.decodeIfPresent(String.self, forKey: .replace)
        switch (list, find, replace) {
        case let (list?, nil, nil):
            edits = list
        case let (nil, find?, replace?):
            edits = [Edit(find: find, replace: replace)]
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .edits, in: container,
                debugDescription: "\(id): o `edits`, o `find` y `replace`; no las dos formas ni media")
        }
    }
}

public struct Edit: Codable, Sendable, Equatable {
    public var find: String
    public var replace: String

    public init(find: String, replace: String) {
        self.find = find
        self.replace = replace
    }
}

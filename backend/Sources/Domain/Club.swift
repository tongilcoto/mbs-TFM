public import struct Foundation.Date

/// El club. **Raíz de agregado y *singleton* del tenant** (§4.2): hay exactamente
/// una fila por *schema*, y por eso su recurso REST no lleva `{id}` (D-23).
///
/// El alta y la baja **no son operaciones de esta API**: son provisión (§6.3).
/// Lo editable es el contenido — nombre, escudo, preferencias.
public struct Club: Identifiable, Equatable, Sendable {
    public let id: ClubID
    public let name: String
    public let shortName: String

    /// Inmutable (§3.2). No aparece en ningún DTO de escritura.
    public let slug: Slug

    /// Clave del objeto en Storage, **no una URL** (D-19): la URL se compone en
    /// la respuesta, para no atar el modelo a un dominio ni a un *bucket*.
    public let crestKey: String?

    /// Se fija al aprovisionar y ninguna operación la cambia: determina a qué
    /// API se sincroniza el tenant entero (§3.6).
    public let federation: FederationCode

    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: ClubID,
        name: String,
        shortName: String,
        slug: Slug,
        crestKey: String? = nil,
        federation: FederationCode,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        guard !name.trimmed.isEmpty else {
            throw DomainError.invalidValue(field: "name", reason: "no puede estar vacío")
        }
        guard !shortName.trimmed.isEmpty else {
            throw DomainError.invalidValue(field: "shortName", reason: "no puede estar vacío")
        }
        self.id = id
        self.name = name
        self.shortName = shortName
        self.slug = slug
        self.crestKey = crestKey
        self.federation = federation
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Derivadas del catálogo en código, **no almacenadas** (D-17): viajan en
    /// `ClubResponse` para que el backoffice sepa rotular la clasificación
    /// calculada (D-29) y ocultar la pantalla de goleadores (D-48).
    public var federationCapabilities: FederationCapabilities { federation.capabilities }
}

extension String {
    var trimmed: String {
        var characters = Substring(self)
        while let first = characters.first, first == " " || first == "\t" || first == "\n" {
            characters = characters.dropFirst()
        }
        while let last = characters.last, last == " " || last == "\t" || last == "\n" {
            characters = characters.dropLast()
        }
        return String(characters)
    }
}

extension Club {
    /// Aplica una modificación **parcial** (§5.5): un campo ausente (`nil`) no
    /// se toca. La convención del `PATCH` la fija el contrato y la hace cumplir
    /// esta función, no el código generado (D-65).
    ///
    /// Devuelve un `Club` nuevo en vez de mutar: la entidad es un `struct` y sus
    /// invariantes se validan en el `init`, así que **el resultado de un cambio
    /// pasa por la misma puerta que un alta**. Si `name` llegara vacío, el `init`
    /// lanza, y da igual por dónde haya venido.
    public func applying(name: String?, shortName: String?) throws -> Club {
        try Club(
            id: id,
            name: name ?? self.name,
            shortName: shortName ?? self.shortName,
            slug: slug,            // inmutable (§3.2): no se acepta ni se ignora, no existe
            crestKey: crestKey,    // el escudo no viaja en un PATCH JSON (§5.2)
            federation: federation, // se fija al aprovisionar; ninguna operación la cambia
            createdAt: createdAt,
            updatedAt: updatedAt   // lo pone la BD (@Timestamp on: .update)
        )
    }
}

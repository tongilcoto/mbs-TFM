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

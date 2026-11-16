public import struct Foundation.UUID
public import struct Foundation.Date
public import struct Domain.Slug

// ── La clave de una foto (D-115) ─────────────────────────────────────────────

/// Dónde vive una foto en el almacén: **`<club>/<código>.jpg`**.
///
/// - **El club delante** (`D-115`, punto 3): las fotos de un club se borran juntas, como su *schema*.
/// - **Un código nuevo en cada subida**, no el del jugador: una foto puede ser de varias filas y de su perfil
///   (`D-122`), y subir otra a una fila pasada no debe cambiar la de la temporada en curso.
/// - **Siempre `.jpg`**: el saneado guarda en JPEG lo que llegue (`D-116`).
///
/// La base la guarda como texto (`photo_key`); este tipo es lo que el almacén acepta. **Leer una clave de fuera**
/// (`init?(_:)`) solo admite esa forma exacta: la clave llega en el enlace de la foto, y una con `..` o `/` de
/// más saldría de la carpeta del club.
public struct PhotoKey: Hashable, Sendable, CustomStringConvertible {
    public let club: Slug
    public let id: UUID

    public init(club: Slug, id: UUID) {
        self.club = club
        self.id = id
    }

    /// `nil` si no es exactamente `<club>/<código>.jpg`, con el código en minúsculas.
    public init?(_ raw: String) {
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1].hasSuffix(".jpg"),
              let club = try? Slug(String(parts[0])) else { return nil }
        let code = String(parts[1].dropLast(4))
        guard let id = UUID(uuidString: code), id.uuidString.lowercased() == code else { return nil }
        self.init(club: club, id: id)
    }

    public var value: String { "\(club.value)/\(id.uuidString.lowercased()).jpg" }
    public var description: String { value }
}

// ── El almacén (D-115) ───────────────────────────────────────────────────────

/// El almacén de las fotos, como **puerto** (§4.3, `D-115`): guardar, leer y borrar un fichero por su clave.
///
/// Hoy lo hace una carpeta del disco (la pieza `Storage`); al desplegar, Supabase Storage, en la misma pieza.
/// Nada fuera del adaptador cambia.
///
/// Lo que cada adaptador promete:
/// 1. **Guardar con una clave que ya existe la reemplaza.** No pasa en la práctica (cada subida trae un código
///    nuevo), pero así repetir una subida que falló a medias no da error.
/// 2. **Leer o borrar una clave que no está no es un error**: leer da `nil`, borrar no hace nada. El fichero de
///    antes se borra «si ya no lo usa nadie», y puede que otro ya lo hubiera borrado.
/// 3. **El enlace dura una hora y es nuevo en cada lectura** (`D-117`): es lo que va en `photoUrl`, y la web lo
///    usa tal cual, venga de la carpeta o de Supabase.
public protocol PhotoStore: Sendable {
    func save(_ bytes: [UInt8], at key: PhotoKey) async throws
    func read(_ key: PhotoKey) async throws -> [UInt8]?
    func delete(_ key: PhotoKey) async throws

    /// El enlace firmado de una foto, que caduca una hora después de `now` (`D-117`).
    func link(to key: PhotoKey, now: Date) -> String

    /// **Solo para el almacén en disco**: el fichero, si el enlace que lo pide vale (la firma es la buena y no
    /// ha caducado). Es lo que hace la ruta a la que apunta su enlace (`getPlayerPhotoFile`). `nil` para todo lo
    /// que no vale, sin decir por qué: así no se sabe qué claves hay. Con Supabase, la ruta desaparece.
    func readSigned(_ key: PhotoKey, expires: Int64, signature: String, now: Date) async throws -> [UInt8]?
}

// ── El saneado (D-35, D-116) ─────────────────────────────────────────────────

/// Los dos formatos que se aceptan (`D-35`): los que produce cualquier portátil, y en los que el navegador del
/// iPhone convierte sus fotos al subirlas.
public enum PhotoFormat: Sendable, Equatable {
    case jpeg, png
}

/// Por qué no se acepta una foto.
public enum PhotoRejection: Error, Sendable, Equatable {
    /// Los bytes no son una imagen del formato declarado que se pueda abrir: un `.heic` o un `.pdf` renombrado,
    /// un JPEG que dice ser PNG, un fichero cortado.
    case notAnImage(declared: PhotoFormat)
    /// Más de `PhotoRules.maxPoints` puntos, leídos en la cabecera **antes de abrirla** (R6.8): un fichero pequeño
    /// puede guardar una imagen enorme, y abrirla tumbaría el servidor.
    case tooManyPoints(width: Int, height: Int)
}

/// Lo que se decidió de la foto guardada (R6.8, 2026-11-16).
public enum PhotoRules {
    /// El lado largo, en puntos. La ficha la enseña a 240 × 320 y una pantalla de Mac pide el doble.
    public static let maxSide = 800
    /// En la escala de 0 a 100 de los programas de fotos.
    public static let quality = 75
    /// Un móvil normal hace fotos de 12 a 25 millones de puntos.
    public static let maxPoints = 30_000_000
}

/// El saneado de la foto, como **puerto** (`D-116`): la pieza `Imaging` es la única que ve las librerías.
///
/// Lo que hace, en este orden: **comprueba** que los bytes son del formato declarado y que no pasan de
/// `PhotoRules.maxPoints`; la **abre** hasta sus puntos de color; la **gira** según su nota de orientación; la
/// **reduce** a `PhotoRules.maxSide` sin agrandar nunca; y la **guarda como JPEG** con `PhotoRules.quality`, sin
/// copiar nada más que los puntos: ni la ubicación, ni el móvil, ni la nota de orientación, que ya no hace falta.
/// Lo transparente de un PNG queda en blanco.
public protocol PhotoSanitizer: Sendable {
    func sanitize(_ bytes: [UInt8], declared: PhotoFormat) throws(PhotoRejection) -> [UInt8]
}

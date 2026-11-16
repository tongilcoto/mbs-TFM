public import struct Foundation.URL
public import Storage
import Foundation
import Vapor

/// La carpeta de las fotos (`D-115`, punto 2), por entorno, como la base de datos (`DatabaseConfig`).
///
/// - **`PHOTOS_DIR`**, si está: una ruta absoluta, o relativa a la carpeta desde la que se lanza el servidor.
/// - **Si no, `fotos/`** dentro de esa carpeta: con `swift run Run serve` desde `backend/`, `backend/fotos/`,
///   que `.gitignore` deja fuera (decidido en la R6.8: el desarrollador no usa fotos de verdad).
///
/// Los escenarios de la web ponen la suya (LLD-B §11.1), y cada test de nivel 4, una temporal (`TestSupport`):
/// las fotos de una no se mezclan con las de otra.
public struct PhotosConfig: Sendable, Equatable {
    public var folder: URL
    /// Por dónde empieza el enlace de la foto (`D-117`, punto 5): el recepcionista de la web pasa al servidor lo
    /// que empieza por `/api`.
    public var urlPrefix: String
    /// La clave que firma los enlaces (`D-117`, punto 7); `nil`, una al azar en cada arranque.
    public var signingKey: String?

    public init(folder: URL, urlPrefix: String = defaultURLPrefix, signingKey: String? = nil) {
        self.folder = folder
        self.urlPrefix = urlPrefix
        self.signingKey = signingKey
    }

    public static let defaultFolder = "fotos"
    public static let defaultURLPrefix = "/api"

    /// El almacén en la carpeta, con su firma.
    public func store() -> DiskPhotoStore {
        DiskPhotoStore(folder: folder, signer: PhotoLinkSigner(secret: signingKey, prefix: urlPrefix))
    }

    public static func fromEnvironment(
        _ value: String? = Environment.get("PHOTOS_DIR"),
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        urlPrefix: String? = Environment.get("PHOTOS_URL_PREFIX"),
        signingKey: String? = Environment.get("PHOTOS_SIGNING_KEY")
    ) -> PhotosConfig {
        let path = (value?.isEmpty ?? true) ? defaultFolder : value!
        let base = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        return PhotosConfig(
            folder: URL(fileURLWithPath: path, isDirectory: true, relativeTo: base).standardizedFileURL,
            urlPrefix: urlPrefix ?? defaultURLPrefix,
            signingKey: (signingKey?.isEmpty ?? true) ? nil : signingKey)
    }
}

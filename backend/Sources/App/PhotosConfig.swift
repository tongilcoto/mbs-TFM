public import struct Foundation.URL
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

    public init(folder: URL) {
        self.folder = folder
    }

    public static let defaultFolder = "fotos"

    public static func fromEnvironment(
        _ value: String? = Environment.get("PHOTOS_DIR"),
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) -> PhotosConfig {
        let path = (value?.isEmpty ?? true) ? defaultFolder : value!
        let base = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        return PhotosConfig(folder: URL(fileURLWithPath: path, isDirectory: true, relativeTo: base).standardizedFileURL)
    }
}

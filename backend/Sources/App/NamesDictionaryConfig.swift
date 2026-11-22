public import struct Foundation.URL
public import Storage
import Foundation
import Vapor

/// Dónde está el diccionario de nombres (`D-123`; decisión 1 de R6.19), por entorno, como la carpeta de las fotos
/// (`PhotosConfig`):
///
/// - **`NAMES_DICTIONARY_FILE`**, si está: una ruta absoluta, o relativa a la carpeta desde la que se lanza el
///   servidor. Los escenarios de la web ponen la ruta entera, porque lanzan el servidor desde `backoffice/`.
/// - **Si no, `diccionario-nombres.txt`** en esa carpeta: con `swift run Run serve` desde `backend/`, el del
///   repositorio. También el de `swift test`, que corre desde `backend/`.
public enum NamesDictionaryConfig {
    public static let defaultFile = "diccionario-nombres.txt"

    public static func fromEnvironment(
        _ value: String? = Environment.get("NAMES_DICTIONARY_FILE"),
        workingDirectory: String = FileManager.default.currentDirectoryPath
    ) -> NameDictionaryFile {
        let path = (value?.isEmpty ?? true) ? defaultFile : value!
        let base = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        return NameDictionaryFile(file: URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL)
    }
}

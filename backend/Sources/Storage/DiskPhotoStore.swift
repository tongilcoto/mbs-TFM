public import Application
public import struct Foundation.URL
public import struct Foundation.Date
import Foundation

/// El almacén de las fotos en **una carpeta del disco** (`D-115`): el adaptador del puerto `PhotoStore` mientras no
/// haya Supabase.
///
/// Cada foto es un fichero en **`<carpeta>/<club>/<código>.jpg`**: la clave (`PhotoKey`) ya trae esa forma, y solo
/// esa, así que nada se sale de la carpeta. **La carpeta la elige la configuración del servidor** (`D-115`, punto
/// 2): la del desarrollador, la de los escenarios y la de cada test son distintas.
///
/// Las fotos de la carpeta **no van en las copias de la base** (`D-115`, «lo que se asume»): quien copie la base
/// se lleva las claves sin los ficheros, y la ficha enseñará las iniciales.
public struct DiskPhotoStore: PhotoStore {

    public let folder: URL
    public let signer: PhotoLinkSigner

    public init(folder: URL, signer: PhotoLinkSigner) {
        self.folder = folder
        self.signer = signer
    }

    func file(_ key: PhotoKey) -> URL {
        // `value` es `<club>/<código>.jpg`: una carpeta por club y, dentro, el fichero.
        folder.appendingPathComponent(key.value, isDirectory: false)
    }

    /// Se escribe entero en un fichero aparte y después se pone en su sitio (`.atomic`): quien lea a la vez ve el
    /// de antes o el nuevo, nunca uno a medias.
    public func save(_ bytes: [UInt8], at key: PhotoKey) async throws {
        let file = file(key)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(bytes).write(to: file, options: .atomic)
    }

    public func read(_ key: PhotoKey) async throws -> [UInt8]? {
        let file = file(key)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return [UInt8](try Data(contentsOf: file))
    }

    public func delete(_ key: PhotoKey) async throws {
        do {
            try FileManager.default.removeItem(at: file(key))
        } catch CocoaError.fileNoSuchFile {
            // Ya no estaba: no es un error (`PhotoStore`, promesa 2).
        }
    }

    public func link(to key: PhotoKey, now: Date) -> String {
        signer.link(to: key, now: now)
    }

    public func readSigned(_ key: PhotoKey, expires: Int64, signature: String, now: Date) async throws -> [UInt8]? {
        guard signer.isValid(key, expires: expires, signature: signature, now: now) else { return nil }
        return try await read(key)
    }
}

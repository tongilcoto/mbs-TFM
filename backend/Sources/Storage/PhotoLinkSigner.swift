import Crypto
import Foundation
public import Application

/// La firma del enlace de la foto con la carpeta del disco (`D-117`): **HMAC-SHA256** de la clave entera y de la
/// hora en que caduca, con una clave secreta.
///
/// - **La clave secreta** sale de `PHOTOS_SIGNING_KEY`; si no está, una al azar al arrancar, que no se guarda
///   (`D-117`, punto 7): al relanzar el servidor, los enlaces de antes caducan como al pasar la hora.
/// - **La firma es de la clave entera, con su club** (`<club>/<código>.jpg`), aunque el enlace lleve solo el
///   fichero (`D-117`, punto 6): el enlace de un club, en la dirección de otro, no vale.
/// - **El enlace empieza por el prefijo** de la configuración (`PHOTOS_URL_PREFIX`, `/api` por defecto; punto 5).
public struct PhotoLinkSigner: Sendable {
    let secret: SymmetricKey
    public let prefix: String
    public let lifetime: Int64

    /// `secret` vacío o `nil`: una al azar.
    public init(secret: String?, prefix: String, lifetime: Int64 = 3600) {
        if let secret, !secret.isEmpty {
            self.secret = SymmetricKey(data: Data(secret.utf8))
        } else {
            self.secret = SymmetricKey(size: .bits256)
        }
        self.prefix = prefix.hasSuffix("/") ? String(prefix.dropLast()) : prefix
        self.lifetime = lifetime
    }

    public func link(to key: PhotoKey, now: Date) -> String {
        let expires = Int64(now.timeIntervalSince1970.rounded(.down)) + lifetime
        let file = "\(key.id.uuidString.lowercased()).jpg"
        return "\(prefix)/v1/player-photos/\(file)?expires=\(expires)&signature=\(signature(key, expires))"
    }

    /// La firma es la buena y el enlace no ha caducado. La comparación tarda lo mismo acierte o falle.
    public func isValid(_ key: PhotoKey, expires: Int64, signature: String, now: Date) -> Bool {
        guard Int64(now.timeIntervalSince1970) <= expires, let mac = Self.decode(signature) else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: Self.message(key, expires), using: secret)
    }

    func signature(_ key: PhotoKey, _ expires: Int64) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Self.message(key, expires), using: secret)
        return Data(mac).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func message(_ key: PhotoKey, _ expires: Int64) -> Data { Data("\(key.value)\n\(expires)".utf8) }

    /// De base64 «para direcciones» (sin `+`, `/` ni `=`) a bytes.
    static func decode(_ signature: String) -> Data? {
        var text = signature.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while text.count % 4 != 0 { text += "=" }
        return Data(base64Encoded: text)
    }
}

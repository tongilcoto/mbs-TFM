import Application
import Domain
import Foundation
import Testing

@testable import Storage

/// El almacén de las fotos en una carpeta del disco (`D-115`, R6.8), **sin Docker**: cada test, su carpeta
/// temporal, que se borra al acabar.
@Suite("Storage · R6.8 · el almacén de fotos en una carpeta")
struct DiskPhotoStoreTests {

    static func withStore(_ body: (DiskPhotoStore, URL) async throws -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("tfm-fotos-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await body(DiskPhotoStore(folder: folder, signer: PhotoLinkSigner(secret: "secreto", prefix: "/api")), folder)
    }

    static func key(_ club: String = "celtic-castilla") throws -> PhotoKey {
        PhotoKey(club: try Slug(club), id: UUID())
    }

    @Test("lo guardado se lee igual, y está en <carpeta>/<club>/<código>.jpg (D-115)")
    func saveAndRead() async throws {
        try await Self.withStore { store, folder in
            let key = try Self.key()
            let bytes: [UInt8] = [0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]
            try await store.save(bytes, at: key)
            #expect(try await store.read(key) == bytes)
            let file = folder.appendingPathComponent(key.value)
            #expect(FileManager.default.fileExists(atPath: file.path))
            #expect(file.deletingLastPathComponent().lastPathComponent == "celtic-castilla")
        }
    }

    @Test("guardar con una clave que ya existe la reemplaza (PhotoStore, promesa 1)")
    func saveReplaces() async throws {
        try await Self.withStore { store, _ in
            let key = try Self.key()
            try await store.save([1, 1, 1, 1], at: key)
            try await store.save([2], at: key)
            #expect(try await store.read(key) == [2])
        }
    }

    @Test("leer o borrar lo que no está no es un error (PhotoStore, promesa 2)")
    func missingIsNotAnError() async throws {
        try await Self.withStore { store, _ in
            let key = try Self.key()
            #expect(try await store.read(key) == nil)
            try await store.delete(key)
        }
    }

    @Test("borrar quita el fichero, y solo ese (D-115)")
    func deleteRemovesOnlyThatOne() async throws {
        try await Self.withStore { store, _ in
            let (gone, kept, otherClub) = (try Self.key(), try Self.key(), try Self.key("otro-club"))
            for key in [gone, kept, otherClub] { try await store.save([7], at: key) }
            try await store.delete(gone)
            #expect(try await store.read(gone) == nil)
            #expect(try await store.read(kept) == [7])
            #expect(try await store.read(otherClub) == [7])
        }
    }
}

/// El enlace firmado de la foto (`D-117`, R6.9).
@Suite("Storage · R6.9 · el enlace firmado de la foto")
struct PhotoLinkSignerTests {

    static let now = Date(timeIntervalSince1970: 1_794_700_000)
    let signer = PhotoLinkSigner(secret: "secreto", prefix: "/api")

    static func key(_ club: String = "celtic-castilla", id: UUID = UUID()) throws -> PhotoKey {
        PhotoKey(club: try Slug(club), id: id)
    }

    /// Lo que el navegador mandará de vuelta: el fichero, `expires` y `signature`.
    static func parts(_ link: String) throws -> (path: String, expires: Int64, signature: String) {
        let components = try #require(URLComponents(string: link))
        let items = components.queryItems ?? []
        return (components.path,
                try #require(items.first { $0.name == "expires" }?.value.flatMap { Int64($0) }),
                try #require(items.first { $0.name == "signature" }?.value))
    }

    @Test("el enlace: el prefijo, la ruta con solo el fichero, y caduca en una hora (D-117, puntos 5 y 6)")
    func shape() throws {
        let key = try Self.key()
        let (path, expires, _) = try Self.parts(signer.link(to: key, now: Self.now))
        #expect(path == "/api/v1/player-photos/\(key.id.uuidString.lowercased()).jpg")
        #expect(expires == 1_794_700_000 + 3600)
        #expect(!PhotoLinkSigner(secret: "s", prefix: "/api/").link(to: key, now: Self.now).contains("//v1"))
    }

    @Test("vale hasta su hora, y no un segundo después (D-117)")
    func validUntilItExpires() throws {
        let key = try Self.key()
        let (_, expires, signature) = try Self.parts(signer.link(to: key, now: Self.now))
        #expect(signer.isValid(key, expires: expires, signature: signature, now: Self.now))
        #expect(signer.isValid(key, expires: expires, signature: signature, now: Self.now.addingTimeInterval(3600)))
        #expect(!signer.isValid(key, expires: expires, signature: signature, now: Self.now.addingTimeInterval(3601)))
    }

    @Test("no vale si se toca la hora, la firma, el fichero o el club (D-117, punto 6)")
    func tamperingFails() throws {
        let key = try Self.key()
        let (_, expires, signature) = try Self.parts(signer.link(to: key, now: Self.now))
        #expect(!signer.isValid(key, expires: expires + 3600, signature: signature, now: Self.now), "otra hora")
        #expect(!signer.isValid(key, expires: expires, signature: "A" + signature.dropFirst(), now: Self.now))
        #expect(!signer.isValid(key, expires: expires, signature: "no-es-base64!", now: Self.now))
        #expect(!signer.isValid(try Self.key(), expires: expires, signature: signature, now: Self.now), "otro fichero")
        #expect(!signer.isValid(try Self.key("otro-club", id: key.id), expires: expires, signature: signature,
                                now: Self.now), "el mismo fichero en la dirección de otro club")
    }

    @Test("con otra clave secreta no vale; sin PHOTOS_SIGNING_KEY, cada arranque inventa una (D-117, punto 7)")
    func secretMatters() throws {
        let key = try Self.key()
        let (_, expires, signature) = try Self.parts(signer.link(to: key, now: Self.now))
        #expect(!PhotoLinkSigner(secret: "otro", prefix: "/api").isValid(key, expires: expires, signature: signature,
                                                                          now: Self.now))
        let (a, b) = (PhotoLinkSigner(secret: nil, prefix: "/api"), PhotoLinkSigner(secret: "", prefix: "/api"))
        let (_, e, s) = try Self.parts(a.link(to: key, now: Self.now))
        #expect(a.isValid(key, expires: e, signature: s, now: Self.now))
        #expect(!b.isValid(key, expires: e, signature: s, now: Self.now), "otro arranque, otra clave")
    }

    @Test("el almacén entrega el fichero solo con un enlace que vale (D-117)")
    func readSigned() async throws {
        try await DiskPhotoStoreTests.withStore { store, _ in
            let key = try Self.key()
            try await store.save([1, 2, 3], at: key)
            let (_, expires, signature) = try Self.parts(store.link(to: key, now: Self.now))
            #expect(try await store.readSigned(key, expires: expires, signature: signature, now: Self.now) == [1, 2, 3])
            #expect(try await store.readSigned(key, expires: expires, signature: "x", now: Self.now) == nil)
            #expect(try await store.readSigned(key, expires: expires, signature: signature,
                                               now: Self.now.addingTimeInterval(7200)) == nil)
        }
    }
}

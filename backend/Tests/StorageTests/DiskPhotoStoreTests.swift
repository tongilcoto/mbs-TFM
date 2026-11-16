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
        try await body(DiskPhotoStore(folder: folder), folder)
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

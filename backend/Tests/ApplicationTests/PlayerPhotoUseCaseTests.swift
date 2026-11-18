import Domain
import Foundation
import Testing
@testable import Application

/// Nivel 2 (§8.1): subir y quitar la foto (R6.9), con el almacén y el saneado falseados.
///
/// Lo que deciden los casos de uso: **qué clave** lleva la foto (nueva en cada subida, con el club delante,
/// `D-115`), **que pasa al perfil** (`D-122`), y **qué fichero se borra**: solo el que ya no usa nadie, ni una fila
/// de otra temporada, ni una dada de baja, ni un perfil.
@Suite("Players · R6.9 · la foto: subirla, cambiarla y quitarla")
struct PlayerPhotoUseCaseTests {

    typealias Seeded = PlayerUseCaseTests.Seeded
    static let now = PlayerUseCaseTests.now
    static let actor = ActorContext(clubSlug: try! Slug("celtic-castilla"))

    /// El almacén en memoria: lo guardado, por clave.
    actor MemoryStore: PhotoStore {
        var files: [String: [UInt8]] = [:]
        var failOnSave = false
        func save(_ bytes: [UInt8], at key: PhotoKey) async throws {
            files[key.value] = bytes
        }
        func read(_ key: PhotoKey) async throws -> [UInt8]? { files[key.value] }
        func delete(_ key: PhotoKey) async throws { files[key.value] = nil }
        nonisolated func link(to key: PhotoKey, now: Date) -> String { "/enlace/\(key.value)" }
        func readSigned(_ key: PhotoKey, expires: Int64, signature: String, now: Date) async throws -> [UInt8]? {
            signature == "buena" ? files[key.value] : nil
        }
    }

    /// El saneado falso: «sanea» poniendo una marca delante, o rechaza lo que se le diga.
    struct FakeSanitizer: PhotoSanitizer {
        var rejection: PhotoRejection?
        func sanitize(_ bytes: [UInt8], declared: PhotoFormat) throws(PhotoRejection) -> [UInt8] {
            if let rejection { throw rejection }
            return [0xAA] + bytes
        }
    }

    /// `at`: cuándo; la fila de la temporada anterior se toca cuando estaba en curso
    /// (`PlayerUseCaseTests.then`).
    static func upload(_ s: Seeded, _ store: MemoryStore, rejection: PhotoRejection? = nil,
                       at instant: Date = now) -> UploadPlayerPhoto {
        UploadPlayerPhoto(unitOfWork: FakeUnitOfWork(store: s.store), store: store,
                          sanitizer: FakeSanitizer(rejection: rejection), clock: FixedClock(instant: instant),
                          ids: SequentialUUIDProvider())
    }

    static func remove(_ s: Seeded, _ store: MemoryStore) -> DeletePlayerPhoto {
        DeletePlayerPhoto(unitOfWork: FakeUnitOfWork(store: s.store), store: store, clock: FixedClock(instant: now))
    }

    static func profile(_ s: Seeded, _ entry: RosterEntry) async -> PlayerProfile? {
        await s.store.playerProfiles.first { $0.id == entry.profile.id }
    }

    // ── Subir ───────────────────────────────────────────────────────────────

    @Test("subir guarda la foto saneada con una clave nueva del club, en la fila y en el perfil (D-115, D-122)")
    func uploadStoresAndCopies() async throws {
        let s = try await PlayerUseCaseTests.seed()
        let store = MemoryStore()
        let juan = try await PlayerUseCaseTests.newPlayer(s)

        let entry = try await Self.upload(s, store).execute(juan.player.id, bytes: [1, 2], declared: .jpeg,
                                                            actor: Self.actor)

        let key = try #require(entry.player.photoKey)
        #expect(key.hasPrefix("celtic-castilla/") && PhotoKey(key) != nil)
        #expect(await store.files[key] == [0xAA, 1, 2], "lo que se guarda es lo saneado")
        #expect(await Self.profile(s, juan)?.lastPhotoKey == key)
    }

    @Test("cambiar la foto pone otra clave y borra el fichero de antes, que ya no usa nadie (D-115, D-122)")
    func replaceDeletesTheOldOne() async throws {
        let s = try await PlayerUseCaseTests.seed()
        let store = MemoryStore()
        let juan = try await PlayerUseCaseTests.newPlayer(s)
        let first = try #require(try await Self.upload(s, store).execute(
            juan.player.id, bytes: [1], declared: .jpeg, actor: Self.actor).player.photoKey)

        let second = try #require(try await Self.upload(s, store).execute(
            juan.player.id, bytes: [2], declared: .png, actor: Self.actor).player.photoKey)

        #expect(first != second)
        #expect(await store.files[first] == nil)
        #expect(await store.files[second] != nil)
    }

    @Test("el fichero de antes se queda si lo usa la fila de otra temporada (D-122)")
    func oldFileStaysWhileUsed() async throws {
        let s = try await PlayerUseCaseTests.seed()
        let store = MemoryStore()
        let pasado = try await PlayerUseCaseTests.newPlayer(s, season: s.anterior)
        let old = try #require(try await Self.upload(s, store, at: PlayerUseCaseTests.then).execute(
            pasado.player.id, bytes: [1], declared: .jpeg, actor: Self.actor).player.photoKey)
        // El alta con su perfil empieza con la misma foto (D-122, corregido en la R6.9).
        let actual = try await PlayerUseCaseTests.create(s.store).execute(.init(
            teamID: s.cadeteA.id, seasonID: s.vigente.id, who: .profile(pasado.profile.id),
            shirtNumber: nil, position: nil))
        #expect(actual.player.photoKey == old)

        _ = try await Self.upload(s, store).execute(actual.player.id, bytes: [2], declared: .jpeg, actor: Self.actor)

        #expect(await store.files[old] != nil, "la fila de la temporada pasada la sigue usando")
    }

    @Test("la foto que no se acepta no toca nada (D-116)")
    func rejectedTouchesNothing() async throws {
        let s = try await PlayerUseCaseTests.seed()
        let store = MemoryStore()
        let juan = try await PlayerUseCaseTests.newPlayer(s)

        await #expect(throws: PhotoRejection.tooManyPoints(width: 9000, height: 9000)) {
            try await Self.upload(s, store, rejection: .tooManyPoints(width: 9000, height: 9000))
                .execute(juan.player.id, bytes: [1], declared: .png, actor: Self.actor)
        }
        #expect(await store.files.isEmpty)
        #expect(await s.store.players.first?.photoKey == nil)
    }

    @Test("si falla apuntar la clave, el fichero nuevo se borra: no lo usaría nadie (R6.9)")
    func failedRecordDeletesTheNewFile() async throws {
        let s = try await PlayerUseCaseTests.seed()
        let store = MemoryStore()
        let juan = try await PlayerUseCaseTests.newPlayer(s)
        // La primera transacción mira la fila; la segunda, la que apunta la clave, falla.
        let upload = UploadPlayerPhoto(
            unitOfWork: FailOnNthScope(wrapping: FakeUnitOfWork(store: s.store), failOn: 2), store: store,
            sanitizer: FakeSanitizer(), clock: FixedClock(instant: Self.now), ids: SequentialUUIDProvider())

        await #expect(throws: FakeOutage.self) {
            try await upload.execute(juan.player.id, bytes: [1], declared: .jpeg, actor: Self.actor)
        }
        #expect(await store.files.isEmpty)
    }

    /// Una temporada terminada se ve, pero no se cambia (`SEASON_ENDED`, R6.17), y no se
    /// guarda ningún fichero: se mira antes de sanear.
    @Test("en una temporada terminada, ni subir ni quitar la foto (R6.17)")
    func endedSeasonRejectsPhotos() async throws {
        let s = try await PlayerUseCaseTests.seed()
        let store = MemoryStore()
        let juan = try await PlayerUseCaseTests.newPlayer(s, season: s.anterior)
        await #expect(throws: DomainError.seasonEnded(label: "2025/26")) {
            try await Self.upload(s, store).execute(juan.player.id, bytes: [1], declared: .jpeg, actor: Self.actor)
        }
        await #expect(throws: DomainError.seasonEnded(label: "2025/26")) {
            try await Self.remove(s, store).execute(juan.player.id, actor: Self.actor)
        }
        #expect(await store.files.isEmpty)
    }

    @Test("un jugador que no existe, 404; una temporada archivada, 422; sin guardar fichero (§5.1)")
    func notFoundAndArchived() async throws {
        let s = try await PlayerUseCaseTests.seed()
        let store = MemoryStore()
        let nadie = PlayerID(raw: UUID())
        await #expect(throws: ApplicationError.playerNotFound(id: "\(nadie)")) {
            try await Self.upload(s, store).execute(nadie, bytes: [1], declared: .jpeg, actor: Self.actor)
        }
        let juan = try await PlayerUseCaseTests.newPlayer(s, season: s.anterior)
        await s.store.save(try Season(
            id: s.anterior.id, label: s.anterior.label, federationSeasonID: nil, archivedAt: Self.now,
            createdAt: Self.now, updatedAt: Self.now))
        await #expect(throws: DomainError.seasonArchived(label: "2025/26")) {
            try await Self.upload(s, store).execute(juan.player.id, bytes: [1], declared: .jpeg, actor: Self.actor)
        }
        await #expect(throws: DomainError.seasonArchived(label: "2025/26")) {
            try await Self.remove(s, store).execute(juan.player.id, actor: Self.actor)
        }
        #expect(await store.files.isEmpty)
    }

    // ── Quitar ──────────────────────────────────────────────────────────────

    @Test("quitar la deja vacía en la fila y en el perfil, y borra el fichero (D-122)")
    func removeClearsBoth() async throws {
        let s = try await PlayerUseCaseTests.seed()
        let store = MemoryStore()
        let juan = try await PlayerUseCaseTests.newPlayer(s)
        let key = try #require(try await Self.upload(s, store).execute(
            juan.player.id, bytes: [1], declared: .jpeg, actor: Self.actor).player.photoKey)

        try await Self.remove(s, store).execute(juan.player.id, actor: Self.actor)

        #expect(await s.store.players.first?.photoKey == nil)
        #expect(await Self.profile(s, juan)?.lastPhotoKey == nil)
        #expect(await store.files[key] == nil)
    }

    @Test("quitarla a un jugador sin foto no hace nada, ni toca la del perfil (idempotente)")
    func removeWithoutPhotoIsNoOp() async throws {
        let s = try await PlayerUseCaseTests.seed()
        let store = MemoryStore()
        // El mismo jugador en dos temporadas: la fila de esta, sin foto; la pasada, con una, que tiene el perfil.
        let pasado = try await PlayerUseCaseTests.newPlayer(s, season: s.anterior)
        let actual = try await PlayerUseCaseTests.create(s.store).execute(.init(
            teamID: s.cadeteA.id, seasonID: s.vigente.id, who: .profile(pasado.profile.id),
            shirtNumber: nil, position: nil))
        let key = try #require(try await Self.upload(s, store, at: PlayerUseCaseTests.then).execute(
            pasado.player.id, bytes: [1], declared: .jpeg, actor: Self.actor).player.photoKey)
        #expect(actual.player.photoKey == nil)

        try await Self.remove(s, store).execute(actual.player.id, actor: Self.actor)

        #expect(await Self.profile(s, pasado)?.lastPhotoKey == key, "el perfil conserva la suya")
        #expect(await store.files[key] != nil)
    }

    @Test("el fichero de un dado de baja no se borra: la baja se puede deshacer (D-35)")
    func softDeletedRowKeepsTheFile() async throws {
        let s = try await PlayerUseCaseTests.seed()
        let store = MemoryStore()
        let pasado = try await PlayerUseCaseTests.newPlayer(s, season: s.anterior)
        let key = try #require(try await Self.upload(s, store, at: PlayerUseCaseTests.then).execute(
            pasado.player.id, bytes: [1], declared: .jpeg, actor: Self.actor).player.photoKey)
        let actual = try await PlayerUseCaseTests.create(s.store).execute(.init(
            teamID: s.cadeteA.id, seasonID: s.vigente.id, who: .profile(pasado.profile.id),
            shirtNumber: nil, position: nil))
        try await PlayerUseCaseTests.delete(s.store, at: PlayerUseCaseTests.then).execute(pasado.player.id)

        try await Self.remove(s, store).execute(actual.player.id, actor: Self.actor)

        #expect(await store.files[key] != nil, "la fila dada de baja aún la tiene")
    }

    // ── El fichero por su enlace ────────────────────────────────────────────

    @Test("el fichero sale por su nombre con el club de la dirección, y solo con un enlace que vale (D-117)")
    func fileByLink() async throws {
        let s = try await PlayerUseCaseTests.seed()
        let store = MemoryStore()
        let juan = try await PlayerUseCaseTests.newPlayer(s)
        let raw = try #require(try await Self.upload(s, store).execute(
            juan.player.id, bytes: [1], declared: .jpeg, actor: Self.actor).player.photoKey)
        let key = try #require(PhotoKey(raw))
        let file = "\(key.id.uuidString.lowercased()).jpg"
        let get = GetPlayerPhotoFile(store: store, clock: FixedClock(instant: Self.now))

        #expect(try await get.execute(file: file, expires: 0, signature: "buena", actor: Self.actor) == [0xAA, 1])
        #expect(try await get.execute(file: file, expires: 0, signature: "mala", actor: Self.actor) == nil)
        #expect(try await get.execute(file: "../x.jpg", expires: 0, signature: "buena", actor: Self.actor) == nil)
        let otro = ActorContext(clubSlug: try Slug("otro-club"))
        #expect(try await get.execute(file: file, expires: 0, signature: "buena", actor: otro) == nil)
    }
}

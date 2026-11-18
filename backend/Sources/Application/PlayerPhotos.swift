import Foundation
public import Domain

// ── La foto del jugador (R6.9) ───────────────────────────────────────────────
//
// **Por qué en tres tiempos y no en una sola transacción.** El acceso a los datos de
// un club va por **una sola conexión** (`D-100`): mientras una transacción está
// abierta, las demás peticiones esperan. Sanear una foto tarda hasta 2 s (`D-116`),
// así que se hace **fuera**: primero se mira la fila, después se sanea y se guarda
// el fichero, y después se apunta su clave. Si apuntarla falla, el fichero nuevo se
// borra. El de antes se borra al final, y solo si ya no lo usa nadie (`D-122`).

/// Lo que hace falta para leer y escribir la plantilla en un club.
func rosterScope<T: Sendable>(
    _ unitOfWork: any TenantUnitOfWork, _ actor: ActorContext,
    _ work: @escaping @Sendable (any Repositories) async throws -> T
) async throws -> T {
    try await unitOfWork.withRepositories(actor: actor, work)
}

/// La fila, que exista y que su temporada no esté archivada (§5.1) ni terminada
/// (decisión 4 de R6.14).
func editableRow(_ id: PlayerID, now: Date, in r: any Repositories) async throws -> Player {
    guard let row = try await r.players.find(id) else { throw ApplicationError.playerNotFound(id: "\(id)") }
    try await requireEditable(row.seasonID, seasons: r.seasons, now: now)
    return row
}

/// Guarda la fila con otra foto y se la copia al perfil (`D-122`, punto 3: también
/// el vacío). Devuelve la fila con su perfil y las claves que tenían antes.
func storePhoto(_ key: String?, on id: PlayerID, now: Date, in r: any Repositories) async throws
    -> (entry: RosterEntry, before: [String])
{
    let row = try await editableRow(id, now: now, in: r)
    guard let profile = try await r.playerProfiles.find(row.profileID) else {
        throw ApplicationError.playerProfileMissing(player: "\(id)")
    }
    let updated = row.with(photoKey: key, updatedAt: now)
    try await r.players.save(updated)
    try await r.playerProfiles.save(profile.remembering(updated))
    let entry = try await GetPlayer(players: r.players, profiles: r.playerProfiles).execute(id)
    return (entry, [row.photoKey, profile.lastPhotoKey].compactMap { $0 })
}

/// **Borra los ficheros que ya no usa nadie** (`D-122`). Lo que falle aquí no se
/// devuelve: la foto ya está puesta o quitada, y un fichero de más no estorba.
func deleteUnused(_ keys: [String], store: any PhotoStore,
                  unitOfWork: any TenantUnitOfWork, actor: ActorContext) async
{
    // Son las claves de **antes** de cambiar la fila: la nueva nunca está entre ellas.
    for raw in Set(keys) {
        guard let key = PhotoKey(raw) else { continue }
        do {
            let inUse = try await rosterScope(unitOfWork, actor) { try await $0.players.isPhotoInUse(raw) }
            if !inUse { try await store.delete(key) }
        } catch {
            continue
        }
    }
}

/// Subir o cambiar la foto (`PUT /players/{id}/photo`, `D-35`).
///
/// La foto **se sanea** (`D-116`), se guarda con **una clave nueva** (`D-115`, punto
/// 3) y **pasa también al perfil** (`D-122`).
public struct UploadPlayerPhoto: Sendable {
    private let unitOfWork: any TenantUnitOfWork
    private let store: any PhotoStore
    private let sanitizer: any PhotoSanitizer
    private let clock: any Clock
    private let ids: any UUIDProvider

    public init(unitOfWork: any TenantUnitOfWork, store: any PhotoStore, sanitizer: any PhotoSanitizer,
                clock: any Clock, ids: any UUIDProvider) {
        self.unitOfWork = unitOfWork
        self.store = store
        self.sanitizer = sanitizer
        self.clock = clock
        self.ids = ids
    }

    public func execute(_ id: PlayerID, bytes: [UInt8], declared: PhotoFormat, actor: ActorContext)
        async throws -> RosterEntry
    {
        // 1 · La fila existe y se puede escribir: antes de sanear, que es lo caro.
        let checkedAt = clock.now()
        _ = try await rosterScope(unitOfWork, actor) { try await editableRow(id, now: checkedAt, in: $0) }

        // 2 · Fuera de la transacción: sanear y guardar el fichero.
        let clean = try sanitizer.sanitize(bytes, declared: declared)
        let key = PhotoKey(club: actor.clubSlug, id: ids.next())
        try await store.save(clean, at: key)

        // 3 · Apuntar la clave. Si falla, el fichero nuevo no lo usa nadie.
        let now = clock.now()
        let stored: (entry: RosterEntry, before: [String])
        do {
            stored = try await rosterScope(unitOfWork, actor) { try await storePhoto(key.value, on: id, now: now, in: $0) }
        } catch {
            try? await store.delete(key)
            throw error
        }
        await deleteUnused(stored.before, store: store, unitOfWork: unitOfWork, actor: actor)
        return stored.entry
    }
}

/// Quitar la foto (`DELETE /players/{id}/photo`): **de la fila y de su perfil**
/// (`D-122`, punto 3). Si la fila no tenía, no se toca nada (idempotente).
public struct DeletePlayerPhoto: Sendable {
    private let unitOfWork: any TenantUnitOfWork
    private let store: any PhotoStore
    private let clock: any Clock

    public init(unitOfWork: any TenantUnitOfWork, store: any PhotoStore, clock: any Clock) {
        self.unitOfWork = unitOfWork
        self.store = store
        self.clock = clock
    }

    public func execute(_ id: PlayerID, actor: ActorContext) async throws {
        let now = clock.now()
        let before = try await rosterScope(unitOfWork, actor) { r -> [String] in
            let row = try await editableRow(id, now: now, in: r)
            guard row.photoKey != nil else { return [] }
            return try await storePhoto(nil, on: id, now: now, in: r).before
        }
        await deleteUnused(before, store: store, unitOfWork: unitOfWork, actor: actor)
    }
}

/// El fichero de una foto, si el enlace que lo pide vale (`GET /player-photos/{fichero}`,
/// `D-117`). **El club sale de la dirección** (punto 6), y la firma es de la clave entera.
public struct GetPlayerPhotoFile: Sendable {
    private let store: any PhotoStore
    private let clock: any Clock

    public init(store: any PhotoStore, clock: any Clock) {
        self.store = store
        self.clock = clock
    }

    /// `nil` para todo lo que no vale: el fichero no existe, la firma no es la buena o ha caducado.
    public func execute(file: String, expires: Int64, signature: String, actor: ActorContext) async throws
        -> [UInt8]?
    {
        guard let key = PhotoKey("\(actor.clubSlug.value)/\(file)") else { return nil }
        return try await store.readSigned(key, expires: expires, signature: signature, now: clock.now())
    }
}

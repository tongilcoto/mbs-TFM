public import APIContract
public import Application
import Domain
import Foundation
import OpenAPIRuntime

// Las tres operaciones de la foto (R6.9): subirla, quitarla y entregar el fichero por
// su enlace firmado (`D-35`, `D-115`, `D-116`, `D-117`, `D-122`).
//
// Los 404 del jugador y el 422 de la temporada archivada los traduce el middleware,
// como en el resto de la plantilla. Los de la imagen (400, 413) se devuelven aquí: son
// de esta operación y llevan su detalle. El 415 lo da el código generado antes de
// llegar aquí, y el middleware le pone su código (`UNSUPPORTED_IMAGE_TYPE`).
extension APIHandler {

    /// **El tope de peso** de la foto que se sube (`D-35`).
    static let maxPhotoBytes = 5 * 1024 * 1024

    /// El enlace firmado de una clave, nuevo en cada lectura (`D-117`); `nil` sin foto.
    func photoURL(_ key: String?) -> String? {
        guard let key, let photoKey = PhotoKey(key) else { return nil }
        return photos.link(to: photoKey, now: clock.now())
    }

    public func uploadPlayerPhoto(_ input: Operations.uploadPlayerPhoto.Input) async throws
        -> Operations.uploadPlayerPhoto.Output
    {
        let actor = try actors.currentActor()
        guard let id = UUID(uuidString: input.path.playerId).map(PlayerID.init(raw:)) else {
            return .notFound(.init(body: .application_problem_plus_json(
                Self.problem(status: 404, code: .PLAYER_NOT_FOUND, title: "Jugador desconocido",
                             detail: input.path.playerId))))
        }
        let (body, format): (HTTPBody, PhotoFormat) = switch input.body {
        case .jpeg(let body): (body, .jpeg)
        case .png(let body): (body, .png)
        }
        let bytes: [UInt8]
        do {
            bytes = try await [UInt8](collecting: body, upTo: Self.maxPhotoBytes)
        } catch {
            return .contentTooLarge(.init(body: .application_problem_plus_json(
                Self.problem(status: 413, code: .IMAGE_TOO_LARGE, title: "La imagen es demasiado grande",
                             detail: "pesa más de 5 MB"))))
        }
        let entry: RosterEntry
        do {
            entry = try await UploadPlayerPhoto(unitOfWork: unitOfWork, store: photos, sanitizer: sanitizer,
                                                clock: clock, ids: ids)
                .execute(id, bytes: bytes, declared: format, actor: actor)
        } catch let rejection as PhotoRejection {
            switch rejection {
            case .notAnImage(let declared):
                return .badRequest(.init(body: .application_problem_plus_json(
                    Self.problem(status: 400, code: .NOT_AN_IMAGE, title: "No es una imagen",
                                 detail: "no es un \(declared == .jpeg ? "JPEG" : "PNG") que se pueda abrir"))))
            case .tooManyPoints(let width, let height):
                return .contentTooLarge(.init(body: .application_problem_plus_json(
                    Self.problem(status: 413, code: .IMAGE_TOO_LARGE, title: "La imagen es demasiado grande",
                                 detail: "tiene más de 30 millones de puntos (\(width) × \(height))"))))
            }
        }
        return .ok(.init(body: .json(entry.toResponse(photoURL))))
    }

    public func deletePlayerPhoto(_ input: Operations.deletePlayerPhoto.Input) async throws
        -> Operations.deletePlayerPhoto.Output
    {
        let actor = try actors.currentActor()
        guard let id = UUID(uuidString: input.path.playerId).map(PlayerID.init(raw:)) else {
            return .notFound(.init(body: .application_problem_plus_json(
                Self.problem(status: 404, code: .PLAYER_NOT_FOUND, title: "Jugador desconocido",
                             detail: input.path.playerId))))
        }
        try await DeletePlayerPhoto(unitOfWork: unitOfWork, store: photos, clock: clock).execute(id, actor: actor)
        return .noContent(.init())
    }

    public func getPlayerPhotoFile(_ input: Operations.getPlayerPhotoFile.Input) async throws
        -> Operations.getPlayerPhotoFile.Output
    {
        let actor = try actors.currentActor()
        let file = try await GetPlayerPhotoFile(store: photos, clock: clock)
            .execute(file: input.path.photoKey, expires: input.query.expires, signature: input.query.signature,
                     actor: actor)
        guard let file else {
            // **La misma respuesta para todo lo que no vale** (`D-117`, punto 3): no dice qué claves hay.
            return .notFound(.init(body: .application_problem_plus_json(
                Self.problem(status: 404, code: .NOT_FOUND, title: "No se ha encontrado"))))
        }
        return .ok(.init(body: .jpeg(HTTPBody(file))))
    }
}

/// El almacén de quien no lo configura: **falla si se usa**. Lo usan los tests que
/// construyen el *handler* sin tocar fotos; el servidor siempre lo pone (`configure`).
public struct NoPhotoStore: PhotoStore, PhotoSanitizer {
    struct NotConfigured: Error {}
    public init() {}
    public func save(_ bytes: [UInt8], at key: PhotoKey) async throws { throw NotConfigured() }
    public func read(_ key: PhotoKey) async throws -> [UInt8]? { throw NotConfigured() }
    public func delete(_ key: PhotoKey) async throws { throw NotConfigured() }
    public func link(to key: PhotoKey, now: Date) -> String { "" }
    public func readSigned(_ key: PhotoKey, expires: Int64, signature: String, now: Date) async throws -> [UInt8]? {
        throw NotConfigured()
    }
    public func sanitize(_ bytes: [UInt8], declared: PhotoFormat) throws(PhotoRejection) -> [UInt8] {
        throw .notAnImage(declared: declared)
    }
}

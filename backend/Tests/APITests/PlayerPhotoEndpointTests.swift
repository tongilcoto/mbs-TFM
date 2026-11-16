import APIContract
import Foundation
import Testing
import Vapor
import VaporTesting
@testable import App
import TestSupport

/// **Dentro de `PlayerEndpointTests`** para ir en fila con él: los dos usan el mismo club de prueba.
///
/// Nivel 4 (§8.1): las tres operaciones de la foto (R6.9), **con el saneado de verdad** y el almacén en una carpeta
/// temporal del test (`TestSupport`). Los casos de uso están probados en el nivel 2; aquí, el borde: cada ruta,
/// su respuesta y cada error con su estado y su código.
extension PlayerEndpointTests {
    @Suite("Players · R6.9 · la foto, por HTTP", .serialized)
    struct Photo {

        typealias E = PlayerEndpointTests

        /// Un PNG de verdad, de 16 × 8 puntos rojos.
        static let png = [UInt8](Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAABAAAAAICAIAAAB/FOjAAAAAE0lEQVR4nGM4ISdHEmIY1UALDQDkVYIBxErvjQAAAABJRU5ErkJggg==")!)

        /// Solo la cabecera de un PNG que dice medir 20.000 × 20.000: el servidor no debe abrirlo.
        static let hugePNGHeader: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13]
            + Array("IHDR".utf8) + [0, 0, 0x4E, 0x20, 0, 0, 0x4E, 0x20, 8, 2, 0, 0, 0, 0, 0, 0, 0]

        static func put(_ app: Application, _ id: String, _ bytes: [UInt8], type: String = "image/png",
                        _ check: @escaping @Sendable (TestingHTTPResponse) async throws -> Void) async throws {
            try await app.testing().test(
                .PUT, "/v1/players/\(id)/photo",
                beforeRequest: { request in
                    request.headers.add(name: "X-Club", value: E.slug)
                    request.headers.replaceOrAdd(name: .contentType, value: type)
                    request.body = ByteBuffer(bytes: bytes)
                }, afterResponse: check)
        }

        static func get(_ app: Application, _ path: String, club: String = E.slug,
                        _ check: @escaping @Sendable (TestingHTTPResponse) async throws -> Void) async throws {
            try await app.testing().test(
                .GET, path, beforeRequest: { $0.headers.add(name: "X-Club", value: club) }, afterResponse: check)
        }

        /// Un jugador nuevo del Cadete A; devuelve su id.
        static func newPlayer(_ app: Application, _ s: E.Seeded, name: String = "Juan García") async throws -> String {
            let box = Box()
            try await E.send(app, .POST, "/v1/players", json: E.newPlayerJSON(s, name: name)) { (r: TestingHTTPResponse) async throws in
                #expect(r.status == .created)
                box.value = try E.player(r).id
            }
            return box.value
        }

        final class Box: @unchecked Sendable { var value = "" }

        /// El enlace, sin el prefijo `/api` del recepcionista de la web (`D-117`, punto 5): lo que le llega al servidor.
        static func serverPath(_ url: String) throws -> String {
            #expect(url.hasPrefix("/api/v1/player-photos/"))
            return String(url.dropFirst("/api".count))
        }

        static func code(_ r: TestingHTTPResponse) -> String? {
            (try? JSONSerialization.jsonObject(with: Data(r.body.readableBytesView)) as? [String: Any])?["code"] as? String
        }

        // ── Subir y ver ─────────────────────────────────────────────────────────

        @Test("subir la foto devuelve el jugador con su enlace, y el enlace entrega un JPEG (D-35, D-117)")
        func uploadThenFetch() async throws {
            try await E.withSeededClub { app, s in
                let id = try await Self.newPlayer(app, s)
                let url = Box()
                try await Self.put(app, id, Self.png) { (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .ok)
                    url.value = try #require(try E.player(r).photoUrl)
                }
                try await Self.get(app, try Self.serverPath(url.value)) { (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .ok)
                    #expect(r.headers.contentType == .jpeg)
                    #expect(Array(r.body.readableBytesView.prefix(3)) == [0xFF, 0xD8, 0xFF], "saneada: un JPEG")
                }
                // La ficha y la plantilla también la traen, con un enlace nuevo en cada lectura.
                try await E.send(app, .GET, "/v1/players/\(id)") { (r: TestingHTTPResponse) async throws in
                    #expect(try E.player(r).photoUrl?.hasPrefix("/api/v1/player-photos/") == true)
                }
                try await E.send(app, .GET, "/v1/players?teamId=\(s.cadeteA)&seasonId=\(s.vigente)") { (r: TestingHTTPResponse) async throws in
                    #expect(try E.roster(r).first?.photoUrl != nil)
                }
                // El buscador del alta, desde otro equipo, trae la foto del perfil (`D-122`, punto 5).
                try await E.send(app, .GET, "/v1/player-profiles?q=juan&teamId=\(s.cadeteB)&seasonId=\(s.vigente)") {
                    (r: TestingHTTPResponse) async throws in
                    let found = try JSONDecoder().decode([Components.Schemas.PlayerProfileSearchResult].self,
                                                         from: Data(r.body.readableBytesView))
                    #expect(found.first?.lastPhotoUrl?.hasPrefix("/api/v1/player-photos/") == true)
                }
            }
        }

        @Test("un enlace tocado, o en la dirección de otro club, da 404 NOT_FOUND (D-117, punto 6)")
        func badLinksAre404() async throws {
            try await E.withSeededClub { app, s in
                let id = try await Self.newPlayer(app, s)
                let url = Box()
                try await Self.put(app, id, Self.png) { (r: TestingHTTPResponse) async throws in url.value = try #require(try E.player(r).photoUrl) }
                let path = try Self.serverPath(url.value)
                try await Self.get(app, path.replacingOccurrences(of: "signature=", with: "signature=x")) { (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .notFound)
                    #expect(Self.code(r) == "NOT_FOUND")
                }
                try await Self.get(app, "/v1/player-photos/00000000-0000-0000-0000-000000000000.jpg?expires=9999999999&signature=abc") { (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .notFound)
                }
            }
        }

        // ── Lo que no se acepta ─────────────────────────────────────────────────

        @Test("lo que no es una imagen del tipo que dice, 400 NOT_AN_IMAGE (D-35)")
        func notAnImage() async throws {
            try await E.withSeededClub { app, s in
                let id = try await Self.newPlayer(app, s)
                try await Self.put(app, id, Array("%PDF-1.7".utf8), type: "image/jpeg") { (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .badRequest)
                    #expect(Self.code(r) == "NOT_AN_IMAGE")
                }
                try await Self.put(app, id, Self.png, type: "image/jpeg") { (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .badRequest, "un PNG que dice ser JPEG")
                }
                // Una foto de móvil pesa unos MB: el cuerpo tiene que llegar entero al saneado (Vapor corta en 16 KB
                // si no se le dice otra cosa). Con 5 MB justos, el tope, llega: el saneado dice que no es una imagen.
                try await Self.put(app, id, [UInt8](repeating: 0, count: 5 * 1024 * 1024), type: "image/jpeg") {
                    (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .badRequest, "5 MB justos llegan enteros")
                    #expect(Self.code(r) == "NOT_AN_IMAGE")
                }
            }
        }

        @Test("más de 30 millones de puntos o más de 5 MB, 413 IMAGE_TOO_LARGE (R6.8)")
        func tooLarge() async throws {
            try await E.withSeededClub { app, s in
                let id = try await Self.newPlayer(app, s)
                try await Self.put(app, id, Self.hugePNGHeader) { (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .payloadTooLarge)
                    #expect(Self.code(r) == "IMAGE_TOO_LARGE")
                }
                try await Self.put(app, id, [UInt8](repeating: 0, count: 5 * 1024 * 1024 + 1), type: "image/jpeg") { (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .payloadTooLarge)
                    #expect(Self.code(r) == "IMAGE_TOO_LARGE")
                }
            }
        }

        @Test("un tipo que no es JPEG ni PNG, 415 UNSUPPORTED_IMAGE_TYPE (D-35)")
        func unsupportedType() async throws {
            try await E.withSeededClub { app, s in
                let id = try await Self.newPlayer(app, s)
                try await Self.put(app, id, Self.png, type: "image/heic") { (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .unsupportedMediaType)
                    #expect(Self.code(r) == "UNSUPPORTED_IMAGE_TYPE")
                }
            }
        }

        @Test("un jugador que no existe, 404 PLAYER_NOT_FOUND")
        func unknownPlayer() async throws {
            try await E.withSeededClub { app, _ in
                try await Self.put(app, "\(UUID())", Self.png) { (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .notFound)
                    #expect(Self.code(r) == "PLAYER_NOT_FOUND")
                }
                try await E.send(app, .DELETE, "/v1/players/no-es-un-uuid/photo") { (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .notFound)
                }
            }
        }

        // ── Quitar ──────────────────────────────────────────────────────────────

        @Test("quitar la foto da 204, la ficha vuelve sin enlace y el de antes ya no entrega nada (D-122)")
        func removePhoto() async throws {
            try await E.withSeededClub { app, s in
                let id = try await Self.newPlayer(app, s)
                let url = Box()
                try await Self.put(app, id, Self.png) { (r: TestingHTTPResponse) async throws in url.value = try #require(try E.player(r).photoUrl) }
                try await E.send(app, .DELETE, "/v1/players/\(id)/photo") { (r: TestingHTTPResponse) async throws in #expect(r.status == .noContent) }
                try await E.send(app, .GET, "/v1/players/\(id)") { (r: TestingHTTPResponse) async throws in #expect(try E.player(r).photoUrl == nil) }
                try await Self.get(app, try Self.serverPath(url.value)) { (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .notFound, "el fichero se borró: no lo usaba nadie más")
                }
                try await E.send(app, .DELETE, "/v1/players/\(id)/photo") { (r: TestingHTTPResponse) async throws in
                    #expect(r.status == .noContent, "otra vez: idempotente")
                }
            }
        }
    }
}

import Application
import JPEG
import Testing

@testable import Imaging

/// El saneado de la foto (`D-116`, R6.8), **sin Docker**: bytes en memoria y fotos fabricadas
/// (`PhotoFixtures`).
@Suite("Imaging · R6.8 · el saneado de la foto")
struct PhotoSanitizerTests {

    let sanitizer = LibraryPhotoSanitizer()
    typealias F = PhotoFixtures

    // ── El tamaño ────────────────────────────────────────────────────────────

    @Test("la grande se reduce a 800 en el lado largo, sin deformarla (R6.8)")
    func shrinks() throws {
        let landscape = try F.decode(try sanitizer.sanitize(try F.jpeg(width: 1000, height: 750), declared: .jpeg))
        #expect((landscape.width, landscape.height) == (800, 600))
        let portrait = try F.decode(try sanitizer.sanitize(try F.png(width: 450, height: 900), declared: .png))
        #expect((portrait.width, portrait.height) == (400, 800))
    }

    @Test("la pequeña no se agranda (R6.8)")
    func neverEnlarges() throws {
        let out = try F.decode(try sanitizer.sanitize(try F.jpeg(width: 300, height: 200), declared: .jpeg))
        #expect((out.width, out.height) == (300, 200))
    }

    @Test("los colores salen donde estaban, reducida o no (R6.8)")
    func keepsColours() throws {
        for width in [64, 1000] {
            let out = try F.decode(try sanitizer.sanitize(try F.jpeg(width: width, height: width / 2), declared: .jpeg))
            let (w, h) = (out.width, out.height)
            #expect(F.close(out.at(w / 4, h / 4), F.red), "arriba a la izquierda, con \(width)")
            #expect(F.close(out.at(3 * w / 4, h / 4), F.green), "arriba a la derecha, con \(width)")
            #expect(F.close(out.at(w / 4, 3 * h / 4), F.blue), "abajo a la izquierda, con \(width)")
            #expect(F.close(out.at(3 * w / 4, 3 * h / 4), F.white), "abajo a la derecha, con \(width)")
        }
    }

    // ── El giro ──────────────────────────────────────────────────────────────

    /// Dónde acaba cada cuarto de la foto guardada (rojo, verde, azul, blanco) según su nota, **tal como lo dice
    /// la norma EXIF**: 2 y 4 son espejos, 3 media vuelta, 6 un cuarto a la derecha, 8 a la izquierda, 5 y 7 los
    /// espejos en diagonal. Arriba-izquierda, arriba-derecha, abajo-izquierda, abajo-derecha.
    static let turns: [(UInt16, [F.RGB])] = [
        (1, [F.red, F.green, F.blue, F.white]),
        (2, [F.green, F.red, F.white, F.blue]),
        (3, [F.white, F.blue, F.green, F.red]),
        (4, [F.blue, F.white, F.red, F.green]),
        (5, [F.red, F.blue, F.green, F.white]),
        (6, [F.blue, F.red, F.white, F.green]),
        (7, [F.white, F.green, F.blue, F.red]),
        (8, [F.green, F.white, F.red, F.blue]),
    ]

    @Test("sale derecha con cualquiera de las ocho notas de orientación (D-116)", arguments: turns)
    func turnsUpright(orientation: UInt16, corners: [F.RGB]) throws {
        let stored = try F.jpeg(width: 64, height: 32, exif: F.exif(orientation: orientation))
        let out = try F.decode(try sanitizer.sanitize(stored, declared: .jpeg))
        let lying = orientation >= 5
        #expect((out.width, out.height) == (lying ? (32, 64) : (64, 32)))
        let (w, h) = (out.width, out.height)
        let seen = [out.at(w / 4, h / 4), out.at(3 * w / 4, h / 4), out.at(w / 4, 3 * h / 4), out.at(3 * w / 4, 3 * h / 4)]
        for (corner, (got, want)) in zip(["arriba-izquierda", "arriba-derecha", "abajo-izquierda", "abajo-derecha"],
                                         zip(seen, corners)) {
            #expect(F.close(got, want), "\(corner) con la nota \(orientation): \(got)")
        }
    }

    // ── Lo que lleva dentro ──────────────────────────────────────────────────

    @Test("no le queda nada dentro: ni la ubicación, ni el EXIF, ni la nota (D-35)")
    func stripsEverything() throws {
        let stored = try F.jpeg(width: 64, height: 32, exif: F.exif(orientation: 6))
        #expect(stored.contains(F.secret), "la de entrada sí lo lleva")
        let out = try sanitizer.sanitize(stored, declared: .jpeg)
        #expect(!out.contains(F.secret))
        #expect(!out.contains(Array("Exif".utf8)))
        let decoded = try F.decode(out)
        #expect(decoded.metadata.count == 1)
        if case .jfif = decoded.metadata.first {} else { Issue.record("solo la cabecera JFIF: \(decoded.metadata)") }
    }

    @Test("se guarda con calidad 75: la primera cifra de su tabla es la de esa calidad (R6.8)")
    func quality() throws {
        let out = try sanitizer.sanitize(try F.jpeg(width: 100, height: 100), declared: .jpeg)
        // La tabla de la luz (DQT, FF DB) empieza por 16 en la norma; con calidad 75 se queda en la mitad.
        let dqt = try #require(out.indices.first { out[$0] == 0xFF && out[$0 + 1] == 0xDB })
        #expect(out[dqt + 5] == 8)
    }

    @Test("lo transparente de un PNG queda en blanco (R6.8)")
    func transparentIsWhite() throws {
        let out = try F.decode(try sanitizer.sanitize(
            try F.png(width: 40, height: 40, alpha: 0, pixels: Array(repeating: F.red, count: 1600)), declared: .png))
        #expect(F.close(out.at(20, 20), F.white))
    }

    // ── Lo que no se acepta ──────────────────────────────────────────────────

    @Test("lo que no es una imagen del formato que dice, no entra (D-35)",
          arguments: [("unos bytes cualquiera", .jpeg), ("un JPEG que dice ser PNG", .png),
                      ("un PNG que dice ser JPEG", .jpeg), ("un JPEG cortado", .jpeg), ("nada", .png)]
              as [(String, PhotoFormat)])
    func rejectsWhatIsNot(_ what: String, declared: PhotoFormat) throws {
        let bytes: [UInt8] = switch what {
        case "unos bytes cualquiera": Array("%PDF-1.7 esto no es una foto".utf8)
        case "un JPEG que dice ser PNG": try F.jpeg(width: 40, height: 40)
        case "un PNG que dice ser JPEG": try F.png(width: 40, height: 40)
        case "un JPEG cortado": Array(try F.jpeg(width: 400, height: 400).prefix(600))
        default: []
        }
        #expect(throws: PhotoRejection.notAnImage(declared: declared)) {
            try sanitizer.sanitize(bytes, declared: declared)
        }
    }

    @Test("más de 30 millones de puntos no se abre: se mira en la cabecera (R6.8)")
    func rejectsTooManyPoints() throws {
        #expect(throws: PhotoRejection.tooManyPoints(width: 20_000, height: 20_000)) {
            try sanitizer.sanitize(F.pngHeader(width: 20_000, height: 20_000), declared: .png)
        }
        #expect(throws: PhotoRejection.tooManyPoints(width: 8_000, height: 4_000)) {
            try sanitizer.sanitize(F.jpegHeader(width: 8_000, height: 4_000), declared: .jpeg)
        }
        #expect(throws: PhotoRejection.tooManyPoints(width: 8_000, height: 4_000),
                "con unas tablas delante del marco, que no son el marco") {
            try sanitizer.sanitize(F.jpegHeader(width: 8_000, height: 4_000, tablesFirst: true), declared: .jpeg)
        }
    }

    @Test("con 30 millones justos sí se intenta abrir (R6.8)")
    func exactlyTheLimitIsOpened() throws {
        // Solo hay cabecera, así que al abrirla falla: lo que se prueba es que el tope la dejó pasar.
        #expect(throws: PhotoRejection.notAnImage(declared: .png)) {
            try sanitizer.sanitize(F.pngHeader(width: 6_000, height: 5_000), declared: .png)
        }
        #expect(throws: PhotoRejection.notAnImage(declared: .jpeg)) {
            try sanitizer.sanitize(F.jpegHeader(width: 6_000, height: 5_000), declared: .jpeg)
        }
    }
}

extension Array where Element == UInt8 {
    func contains(_ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty, count >= needle.count else { return false }
        return (0 ... count - needle.count).contains { self[$0 ..< $0 + needle.count].elementsEqual(needle) }
    }
}

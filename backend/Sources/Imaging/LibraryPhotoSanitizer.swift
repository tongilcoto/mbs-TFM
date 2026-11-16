public import Application
import JPEG
import PNG

/// El saneado de la foto con `swift-jpeg` y `swift-png` (`D-116`): el adaptador del puerto `PhotoSanitizer`.
///
/// **Lo que hace cada paso, y de quién es** (comprobado al empezar la R6.8, plan R6, decisión 2):
///
/// | Paso | Quién |
/// |---|---|
/// | Leer el ancho y el alto en la cabecera, sin abrirla | Nuestro (`PhotoHeader`) |
/// | Abrir el JPEG hasta sus planos de color | La librería |
/// | Juntar los colores y reducir, a la vez | **Nuestro** (`Points.shrinking`): el paso de la librería que junta los colores a tamaño completo tardaba 11 s en 12 megapíxeles; así, la foto entera tarda unos 2 s |
/// | Abrir el PNG | La librería |
/// | Leer la nota de orientación | La librería la deja en el EXIF; el número lo saca `orientation(in:)` |
/// | Girar | Nuestro (`Points.upright`) |
/// | Guardar como JPEG | La librería, con la tabla de calidad calculada aquí (`quanta`) |
///
/// **No se copia nada más que los puntos**: el JPEG nuevo solo lleva la cabecera JFIF, sin EXIF (ni ubicación, ni
/// móvil, ni la nota de orientación, que ya no hace falta porque la foto sale girada).
public struct LibraryPhotoSanitizer: PhotoSanitizer {

    public init() {}

    public func sanitize(_ bytes: [UInt8], declared: PhotoFormat) throws(PhotoRejection) -> [UInt8] {
        guard let size = PhotoHeader.size(of: bytes, as: declared) else { throw .notAnImage(declared: declared) }
        guard size.width * size.height <= PhotoRules.maxPoints else {
            throw .tooManyPoints(width: size.width, height: size.height)
        }
        let points: Points
        do {
            points = switch declared {
            case .jpeg: try Self.openJPEG(bytes)
            case .png: try Self.openPNG(bytes)
            }
        } catch {
            throw .notAnImage(declared: declared)
        }
        return Self.saveJPEG(points)
    }

    // ── Abrir ────────────────────────────────────────────────────────────────

    struct Unreadable: Error {}

    /// Ya girada y reducida: con la foto aún grande solo se trabaja en planos, que es lo barato.
    static func openJPEG(_ bytes: [UInt8]) throws -> Points {
        var source = Bytes(bytes)
        let spectral = try JPEG.Data.Spectral<JPEG.Common>.decompress(stream: &source)
        switch spectral.layout.format {
        case .y8, .ycc8, .nonconforming1x8: break
        default: throw Unreadable()   // las de 16 bits o CMYK no las hace ningún móvil
        }
        let planar = spectral.idct()
        let turn = orientation(in: spectral.metadata)
        // Si va a quedar tumbada, el lado largo se mide igual: reducir antes de girar da lo mismo.
        return Points.shrinking(planar, maxSide: PhotoRules.maxSide).upright(turn)
    }

    static func openPNG(_ bytes: [UInt8]) throws -> Points {
        var source = Bytes(bytes)
        let image = try PNG.Image.decompress(stream: &source)
        let rgba = image.unpack(as: PNG.RGBA<UInt8>.self)
        var rgb = [UInt8](repeating: 0, count: rgba.count * 3)
        for (i, c) in rgba.enumerated() {
            // Lo transparente, sobre blanco: el JPEG no tiene transparencia.
            let a = Int(c.a)
            rgb[3 * i] = UInt8((Int(c.r) * a + 255 * (255 - a)) / 255)
            rgb[3 * i + 1] = UInt8((Int(c.g) * a + 255 * (255 - a)) / 255)
            rgb[3 * i + 2] = UInt8((Int(c.b) * a + 255 * (255 - a)) / 255)
        }
        return Points(width: image.size.x, height: image.size.y, rgb: rgb).shrunk(maxSide: PhotoRules.maxSide)
    }

    /// La nota de orientación (la etiqueta 0x0112 del EXIF). Si no está, 1: tal cual; un valor fuera de 1 a 8 lo
    /// deja tal cual `Points.upright`.
    static func orientation(in metadata: [JPEG.Metadata]) -> Int {
        for record in metadata {
            guard case .exif(let exif) = record, let field = exif[tag: 0x0112] else { continue }
            let c = field.box.contents
            let value = exif.endianness == .bigEndian ? Int(c.0) << 8 | Int(c.1) : Int(c.1) << 8 | Int(c.0)
            return value
        }
        return 1
    }

    // ── Guardar ──────────────────────────────────────────────────────────────

    static func saveJPEG(_ points: Points) -> [UInt8] {
        let layout = JPEG.Layout<JPEG.Common>(
            format: .ycc8, process: .baseline,
            components: [1: (factor: (2, 2), qi: 0 as JPEG.Table.Quantization.Key),
                         2: (factor: (1, 1), qi: 1 as JPEG.Table.Quantization.Key),
                         3: (factor: (1, 1), qi: 1 as JPEG.Table.Quantization.Key)],
            scans: [.sequential((1, \.0, \.0)), .sequential((2, \.1, \.1), (3, \.1, \.1))])
        let rgb = points.rgb
        let pixels = (0 ..< points.width * points.height).map { JPEG.RGB(rgb[3 * $0], rgb[3 * $0 + 1], rgb[3 * $0 + 2]) }
        // Solo la cabecera JFIF: es lo que hace que no pase nada de lo que la foto traía.
        let image = JPEG.Data.Rectangular<JPEG.Common>.pack(
            size: (points.width, points.height), layout: layout,
            metadata: [.jfif(.init(version: .v1_2, density: (1, 1, .centimeters)))], pixels: pixels)
        var destination = Bytes([])
        do {
            try image.compress(stream: &destination, quanta: [
                0: quanta(.luminance(1), quality: PhotoRules.quality),
                1: quanta(.chrominance(1), quality: PhotoRules.quality),
            ])
        } catch {
            // Escribir en memoria no falla; si la librería cambiara y fallase, es un fallo nuestro, no de la foto.
            preconditionFailure("guardar el JPEG en memoria no puede fallar: \(error)")
        }
        return destination.data
    }

    /// La tabla de una calidad de 0 a 100, **como la calculan los programas de fotos** (la de libjpeg): la tabla
    /// de la norma, escalada. La librería trae otra escala (`CompressionLevel`), que no casa con esta; con el
    /// nivel 1 da la tabla de la norma tal cual, y de ahí se parte.
    static func quanta(_ level: JPEG.CompressionLevel, quality: Int) -> [UInt16] {
        let q = max(1, min(100, quality))
        let scale = q < 50 ? 5000 / q : 200 - 2 * q
        return level.quanta.map { UInt16(max(1, min(255, (Int($0) * scale + 50) / 100))) }
    }
}

/// Los bytes en memoria, por donde las dos librerías leen y escriben.
struct Bytes: JPEG.Bytestream.Source, JPEG.Bytestream.Destination, PNG.BytestreamSource, PNG.BytestreamDestination {
    private(set) var data: [UInt8]
    private var position = 0

    init(_ data: [UInt8]) { self.data = data }

    mutating func read(count: Int) -> [UInt8]? {
        guard count >= 0, position + count <= data.count else { return nil }
        defer { position += count }
        return Array(data[position ..< position + count])
    }

    mutating func write(_ bytes: [UInt8]) -> Void? {
        data.append(contentsOf: bytes)
        return ()
    }
}

import JPEG
import PNG

/// Las fotos de las pruebas, **fabricadas aquí**: ni ficheros en el repositorio ni la cara de nadie.
///
/// La foto de verdad del iPhone del desarrollador se usó en la prueba del arranque de la R6.8 (plan R6, decisión
/// 2) y no se guarda: llevaba su ubicación. Lo que aquí se fabrica tiene lo mismo que importaba de ella: la nota
/// de orientación y un bloque de ubicación con algo reconocible dentro.
enum PhotoFixtures {

    struct Blob: JPEG.Bytestream.Source, JPEG.Bytestream.Destination, PNG.BytestreamSource,
                 PNG.BytestreamDestination {
        var data: [UInt8]
        var position = 0
        init(_ data: [UInt8]) { self.data = data }
        mutating func read(count: Int) -> [UInt8]? {
            guard position + count <= data.count else { return nil }
            defer { position += count }
            return Array(data[position ..< position + count])
        }
        mutating func write(_ bytes: [UInt8]) -> Void? { data.append(contentsOf: bytes); return () }
    }

    typealias RGB = (r: UInt8, g: UInt8, b: UInt8)
    static let red: RGB = (255, 0, 0), green: RGB = (0, 255, 0), blue: RGB = (0, 0, 255),
               white: RGB = (255, 255, 255)

    /// Cuatro cuartos de colores distintos (arriba: rojo, verde; abajo: azul, blanco), para saber hacia dónde
    /// ha girado.
    static func quadrants(width: Int, height: Int) -> [RGB] {
        (0 ..< width * height).map { i in
            let (x, y) = (i % width, i / width)
            switch (x < width / 2, y < height / 2) {
            case (true, true): return red
            case (false, true): return green
            case (true, false): return blue
            case (false, false): return white
            }
        }
    }

    /// Un JPEG de verdad, con los bloques que se le pidan delante de la imagen.
    static func jpeg(width: Int, height: Int, pixels: [RGB]? = nil, exif: [UInt8]? = nil) throws -> [UInt8] {
        let layout = JPEG.Layout<JPEG.Common>(
            format: .ycc8, process: .baseline,
            components: [1: (factor: (2, 2), qi: 0 as JPEG.Table.Quantization.Key),
                         2: (factor: (1, 1), qi: 1 as JPEG.Table.Quantization.Key),
                         3: (factor: (1, 1), qi: 1 as JPEG.Table.Quantization.Key)],
            scans: [.sequential((1, \.0, \.0)), .sequential((2, \.1, \.1), (3, \.1, \.1))])
        let points = (pixels ?? quadrants(width: width, height: height)).map { JPEG.RGB($0.r, $0.g, $0.b) }
        let image = JPEG.Data.Rectangular<JPEG.Common>.pack(
            size: (width, height), layout: layout,
            metadata: [.jfif(.init(version: .v1_2, density: (1, 1, .centimeters)))], pixels: points)
        var blob = Blob([])
        try image.compress(stream: &blob, quanta: [0: JPEG.CompressionLevel.luminance(0.1).quanta,
                                                   1: JPEG.CompressionLevel.chrominance(0.1).quanta])
        guard let exif else { return blob.data }
        // El bloque EXIF (APP1) va justo detrás del comienzo (FF D8), como lo pone un móvil.
        let segment = [0xFF, 0xE1] + be16(exif.count + 2) + exif
        return Array(blob.data[0 ..< 2]) + segment + Array(blob.data[2...])
    }

    static let secret = Array("UBICACION-SECRETA".utf8)

    /// Un EXIF como el de un móvil: la nota de orientación, una descripción con `secret` dentro y un bloque de
    /// ubicación (GPS). Escrito a mano, en el orden de bytes de Motorola («MM»).
    static func exif(orientation: UInt16) -> [UInt8] {
        // Desplazamientos desde el comienzo de la cabecera TIFF.
        let ifd0 = 8, ifd0Entries = 3
        let ifd0Size = 2 + 12 * ifd0Entries + 4
        let gps = ifd0 + ifd0Size, gpsSize = 2 + 12 * 1 + 4
        let text = gps + gpsSize
        let description = secret + [0]

        var tiff: [UInt8] = Array("MM".utf8) + [0x00, 0x2A] + be32(ifd0)
        tiff += be16(ifd0Entries)
        tiff += be16(0x010E) + be16(2) + be32(description.count) + be32(text)        // ImageDescription
        tiff += be16(0x0112) + be16(3) + be32(1) + be16(Int(orientation)) + [0, 0]   // Orientation
        tiff += be16(0x8825) + be16(4) + be32(1) + be32(gps)                         // el bloque GPS
        tiff += be32(0)
        tiff += be16(1)
        tiff += be16(0x0001) + be16(2) + be32(2) + Array("N".utf8) + [0, 0, 0]       // GPSLatitudeRef
        tiff += be32(0)
        tiff += description
        return Array("Exif".utf8) + [0, 0] + tiff
    }

    /// Un PNG de verdad, con transparencia si se pide.
    static func png(width: Int, height: Int, alpha: UInt8 = 255, pixels: [RGB]? = nil) throws -> [UInt8] {
        let points = (pixels ?? quadrants(width: width, height: height)).map {
            PNG.RGBA<UInt8>($0.r, $0.g, $0.b, alpha)
        }
        let image = PNG.Image(packing: points, size: (width, height),
                              layout: .init(format: .rgba8(palette: [], fill: nil)))
        var blob = Blob([])
        try image.compress(stream: &blob, level: 0)   // sin apenas comprimir: en modo de pruebas, lo lento
        return blob.data
    }

    /// Solo la cabecera de un PNG que dice medir `width` × `height`: lo que el saneado lee **antes** de abrirla.
    static func pngHeader(width: Int, height: Int) -> [UInt8] {
        let ihdr = be32(width) + be32(height) + [8, 2, 0, 0, 0]
        return [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + be32(13) + Array("IHDR".utf8) + ihdr
            + [0, 0, 0, 0]
    }

    /// Solo el comienzo de un JPEG cuyo marco dice medir `width` × `height`.
    static func jpegHeader(width: Int, height: Int) -> [UInt8] {
        [0xFF, 0xD8, 0xFF, 0xC0] + be16(17) + [8] + be16(height) + be16(width) + [3]
            + [1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1]
    }

    static func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    static func be32(_ v: Int) -> [UInt8] {
        [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
    }

    // ── Leer lo que sale ─────────────────────────────────────────────────────

    struct Decoded {
        let width: Int, height: Int
        let pixels: [JPEG.RGB]
        let metadata: [JPEG.Metadata]
        func at(_ x: Int, _ y: Int) -> JPEG.RGB { pixels[y * width + x] }
    }

    static func decode(_ bytes: [UInt8]) throws -> Decoded {
        var blob = Blob(bytes)
        let image = try JPEG.Data.Rectangular<JPEG.Common>.decompress(stream: &blob)
        return Decoded(width: image.size.x, height: image.size.y, pixels: image.unpack(as: JPEG.RGB.self),
                       metadata: image.metadata)
    }

    /// El color se parece, con el margen que da guardar en JPEG.
    static func close(_ a: JPEG.RGB, _ b: RGB, tolerance: Int = 40) -> Bool {
        abs(Int(a.r) - Int(b.r)) <= tolerance && abs(Int(a.g) - Int(b.g)) <= tolerance
            && abs(Int(a.b) - Int(b.b)) <= tolerance
    }
}

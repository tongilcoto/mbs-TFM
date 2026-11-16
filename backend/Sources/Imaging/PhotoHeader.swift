import Application

/// El ancho y el alto de la foto, leídos en su cabecera **sin abrirla** (R6.8).
///
/// Es lo que hace posible el tope de puntos: un PNG de 1,2 MB con 20.000 × 20.000 puntos pasa el tope de 5 MB, y
/// abrirlo costó 35 s y 1,9 GB. Aquí solo se leen unos pocos bytes.
///
/// `nil` si los bytes no empiezan como el formato declarado: es la primera comprobación de que lo son (`D-35`).
enum PhotoHeader {

    static func size(of bytes: [UInt8], as format: PhotoFormat) -> (width: Int, height: Int)? {
        switch format {
        case .png: png(bytes)
        case .jpeg: jpeg(bytes)
        }
    }

    /// La firma de 8 bytes y, justo detrás, el bloque `IHDR`, que la norma pone siempre el primero.
    static func png(_ b: [UInt8]) -> (width: Int, height: Int)? {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard b.count >= 24, b.starts(with: signature), Array(b[12 ..< 16]) == Array("IHDR".utf8) else { return nil }
        let (w, h) = (be32(b, 16), be32(b, 20))
        return w > 0 && h > 0 ? (w, h) : nil
    }

    /// Se recorren los bloques del comienzo (`FF xx` y su largo) hasta el del marco (`SOFn`), que dice el
    /// tamaño. Si se llega a la imagen (`SOS`) o al final sin encontrarlo, no es un JPEG que se pueda abrir.
    static func jpeg(_ b: [UInt8]) -> (width: Int, height: Int)? {
        guard b.count >= 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
        var i = 2
        while i + 3 < b.count {
            guard b[i] == 0xFF else { return nil }
            let marker = b[i + 1]
            if marker == 0xFF { i += 1; continue }                  // relleno
            if marker == 0xD8 || (0xD0 ... 0xD7).contains(marker) { i += 2; continue }   // sin largo
            if marker == 0xDA || marker == 0xD9 { return nil }      // la imagen o el final, sin marco
            let length = be16(b, i + 2)
            // Los marcos: C0 a CF, menos C4 (tablas), C8 (reservado) y CC (aritmética).
            if (0xC0 ... 0xCF).contains(marker), ![0xC4, 0xC8, 0xCC].contains(marker) {
                guard i + 8 < b.count else { return nil }
                let (h, w) = (be16(b, i + 5), be16(b, i + 7))
                return w > 0 && h > 0 ? (w, h) : nil
            }
            guard length >= 2 else { return nil }
            i += 2 + length
        }
        return nil
    }

    static func be16(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) << 8 | Int(b[i + 1]) }
    static func be32(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
    }
}

import JPEG

/// Una imagen ya abierta: sus puntos, tres bytes cada uno (rojo, verde, azul), fila a fila desde arriba.
///
/// **El giro y la reducción son código nuestro** (`D-116`, «lo que se asume a cambio»), con sus pruebas en
/// `PhotoSanitizerTests`.
struct Points {
    let width: Int
    let height: Int
    let rgb: [UInt8]

    /// El tamaño reducido: el lado largo a `maxSide`, sin deformar; **la pequeña no se agranda**.
    static func target(width: Int, height: Int, maxSide: Int) -> (width: Int, height: Int) {
        let side = max(width, height)
        guard side > maxSide else { return (width, height) }
        return (max(1, width * maxSide / side), max(1, height * maxSide / side))
    }

    /// Reduce haciendo la media de los puntos que caen en cada punto nuevo.
    func shrunk(maxSide: Int) -> Points {
        let (w, h) = Self.target(width: width, height: height, maxSide: maxSide)
        guard (w, h) != (width, height) else { return self }
        var out = [UInt8](repeating: 0, count: w * h * 3)
        for y in 0 ..< h {
            let (y0, y1) = Self.span(y, of: h, over: height)
            for x in 0 ..< w {
                let (x0, x1) = Self.span(x, of: w, over: width)
                var (r, g, b) = (0, 0, 0)
                for sy in y0 ..< y1 {
                    var s = (sy * width + x0) * 3
                    for _ in x0 ..< x1 {
                        r += Int(rgb[s]); g += Int(rgb[s + 1]); b += Int(rgb[s + 2])
                        s += 3
                    }
                }
                let n = (y1 - y0) * (x1 - x0), d = (y * w + x) * 3
                out[d] = UInt8(r / n); out[d + 1] = UInt8(g / n); out[d + 2] = UInt8(b / n)
            }
        }
        return Points(width: w, height: h, rgb: out)
    }

    /// **Abre y reduce a la vez**, desde los planos de color del JPEG (luz y dos de color, cada uno a su
    /// tamaño): la media de cada punto nuevo se hace en cada plano, y solo después se pasa a rojo, verde y azul.
    ///
    /// Sustituye al paso de la librería que junta los planos a tamaño completo (`interleaved()`), que en una
    /// foto de 12 megapíxeles tardaba 11 s; esto, una décima (R6.8).
    static func shrinking(_ planar: JPEG.Data.Planar<JPEG.Common>, maxSide: Int) -> Points {
        let (width, height) = planar.size
        let (w, h) = target(width: width, height: height, maxSide: maxSide)
        let scale = planar.layout.scale
        // Cada plano, a un vector propio: leerlo punto a punto a través de la librería es lo lento.
        let planes: [(stride: Int, fx: Int, fy: Int, values: [UInt16])] = planar.prefix(3).map { plane in
            let size = plane.size
            var values = [UInt16](repeating: 0, count: size.x * size.y)
            for y in 0 ..< size.y {
                for x in 0 ..< size.x { values[y * size.x + x] = plane[x: x, y: y] }
            }
            return (size.x, plane.factor.x, plane.factor.y, values)
        }
        var out = [UInt8](repeating: 0, count: w * h * 3)
        for y in 0 ..< h {
            let (y0, y1) = span(y, of: h, over: height)
            for x in 0 ..< w {
                let (x0, x1) = span(x, of: w, over: width)
                // Sin planos de color (gris), el color es el neutro: 128.
                var ycc: (Double, Double, Double) = (0, 128, 128)
                for (p, plane) in planes.enumerated() {
                    // Del punto de la imagen al del plano, que puede tener la mitad de puntos.
                    let px0 = x0 * plane.fx / scale.x, px1 = max(px0 + 1, x1 * plane.fx / scale.x)
                    let py0 = y0 * plane.fy / scale.y, py1 = max(py0 + 1, y1 * plane.fy / scale.y)
                    var sum = 0
                    for py in py0 ..< py1 {
                        let row = py * plane.stride
                        for px in px0 ..< px1 { sum += Int(plane.values[row + px]) }
                    }
                    let mean = Double(sum) / Double((py1 - py0) * (px1 - px0))
                    switch p {
                    case 0: ycc.0 = mean
                    case 1: ycc.1 = mean
                    default: ycc.2 = mean
                    }
                }
                // De luz y color a rojo, verde y azul: la fórmula de JFIF.
                let (luma, cb, cr) = (ycc.0, ycc.1 - 128, ycc.2 - 128), d = (y * w + x) * 3
                out[d] = clamp(luma + 1.402 * cr)
                out[d + 1] = clamp(luma - 0.344136 * cb - 0.714136 * cr)
                out[d + 2] = clamp(luma + 1.772 * cb)
            }
        }
        return Points(width: w, height: h, rgb: out)
    }

    /// Los puntos de origen que caen en el punto `i` de `n`, sobre un lado de `total`: siempre al menos uno.
    static func span(_ i: Int, of n: Int, over total: Int) -> (Int, Int) {
        let start = i * total / n
        return (start, max(start + 1, (i + 1) * total / n))
    }

    static func clamp(_ value: Double) -> UInt8 { UInt8(max(0, min(255, value.rounded()))) }

    /// La foto como debe verse, según su nota de orientación (EXIF, 1 a 8). Con 5 a 8 queda tumbada: se cambian
    /// el ancho y el alto.
    func upright(_ orientation: Int) -> Points {
        guard (2 ... 8).contains(orientation) else { return self }
        let lying = orientation >= 5
        let (w, h) = lying ? (height, width) : (width, height)
        var out = [UInt8](repeating: 0, count: w * h * 3)
        for y in 0 ..< h {
            for x in 0 ..< w {
                // De qué punto de la foto guardada sale el punto (x, y) de la que se ve.
                let (sx, sy): (Int, Int) = switch orientation {
                case 2: (width - 1 - x, y)                    // espejo
                case 3: (width - 1 - x, height - 1 - y)       // media vuelta
                case 4: (x, height - 1 - y)                   // espejo de arriba abajo
                case 5: (y, x)                                // espejo en diagonal
                case 6: (y, height - 1 - x)                   // un cuarto a la derecha
                case 7: (width - 1 - y, height - 1 - x)       // el otro espejo en diagonal
                default: (width - 1 - y, x)                   // 8: un cuarto a la izquierda
                }
                let s = (sy * width + sx) * 3, d = (y * w + x) * 3
                out[d] = rgb[s]; out[d + 1] = rgb[s + 1]; out[d + 2] = rgb[s + 2]
            }
        }
        return Points(width: w, height: h, rgb: out)
    }
}

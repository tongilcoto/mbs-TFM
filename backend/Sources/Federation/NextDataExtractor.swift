import Foundation
import enum Application.FederationError

/// Saca el JSON incrustado de una página Next.js de la RFFM.
///
/// [Anexo RFFM §F.7] separa las **dos familias** de endpoints del proveedor: las
/// rutas `/api/…` devuelven JSON directo, pero las páginas `/competicion/…` —y el
/// **calendario es una de ellas**— devuelven HTML con el JSON dentro de un
/// `<script id="__NEXT_DATA__" type="application/json">`.
///
/// Conviene tenerlo presente al leer el resumen de `AGENTS.md`: el atajo *"RFFM =
/// JSON"* no vale para el calendario, que es la llamada más importante de la
/// ingesta.
enum NextDataExtractor {

    /// El cuerpo del `<script id="__NEXT_DATA__">`, sin el `</script>` de cierre.
    ///
    /// **Ese cierre es el motivo de que esto exista** y no baste con buscar la
    /// primera `{`: el JSON va seguido de `</script>` y del resto de la página, así
    /// que un *decoder* al que se le pase el fichero entero se queda a mitad con un
    /// error de "datos de más" que no dice nada sobre lo que pasó.
    ///
    /// Se corta por la etiqueta de cierre y no contando llaves: Next.js **escapa**
    /// las secuencias `</` dentro del JSON precisamente para que esto sea seguro.
    static func json(from html: String) throws -> Substring {
        guard let scriptTag = html.range(of: #"id="__NEXT_DATA__""#),
              let openingEnd = html[scriptTag.upperBound...].firstIndex(of: ">")
        else {
            throw FederationError.malformedResponse(
                field: "__NEXT_DATA__",
                reason: "la respuesta no es una página de la RFFM: no lleva el script de datos"
            )
        }

        let body = html[html.index(after: openingEnd)...]
        guard let closing = body.range(of: "</script>") else {
            throw FederationError.malformedResponse(
                field: "__NEXT_DATA__", reason: "el script de datos no está cerrado"
            )
        }
        return body[..<closing.lowerBound]
    }
}

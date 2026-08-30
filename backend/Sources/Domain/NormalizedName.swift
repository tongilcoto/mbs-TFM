import Foundation

/// El nombre de un club reducido a lo que **sirve para emparejar** (§3.7, paso 2).
///
/// # Por qué existe
///
/// La cadena de emparejamiento degrada a *"nombre normalizado + categoría"*
/// cuando la clave de federación no viene ([Anexo RFFM §F.4]). Ese paso compara
/// dos textos que **nadie garantiza que se escriban igual**: la fuente publica
/// `"C.D. FUTBOL TRES CANTOS"` —mayúsculas y sin acentos, [Anexo RFFM §F.5]— y
/// el administrador lo corrige a `"C.D. Fútbol Tres Cantos"`, porque el nombre
/// es campo **descriptivo** y su valor bueno es el suyo (§3.7). Comparar las dos
/// cadenas tal cual haría que **la primera corrección rompiera el emparejamiento
/// de la semana siguiente**.
///
/// # Por qué es un tipo y no una función
///
/// Igual que `Slug`: un `NormalizedName` que existe ya está normalizado, así que
/// no hay forma de comparar por descuido un nombre crudo con uno normalizado —
/// sería un error de compilación. Una `func normalize(_:) -> String` deja los dos
/// lados indistinguibles y la comparación mal hecha compila.
///
/// # Lo que este tipo **no** hace, y en particular la letra
///
/// §3.7 pide el nombre *"sin la letra"*, y **eso ya está hecho cuando el texto
/// llega aquí**: la RFFM embebe la letra entre comillas simples al final del
/// nombre y quien la separa es el adaptador, en `RFFMValue.teamName` (F2, §F.5).
/// `FederationTeamRef` la trae en su propio campo, y del lado del modelo
/// `OpponentClub.name` tampoco la lleva —la letra es de `Team`, no del club
/// (§3.2)—. Repetir el recorte aquí sería una **segunda versión de la misma
/// regla** en otra capa, que es exactamente lo que `UpsertPolicy` documenta como
/// forma de acabar con tres implementaciones divergentes. Y sería frágil: quitar
/// *"la última letra suelta"* se comería la `F` de `"C.F."`.
///
/// # Lo que este tipo **no** hace
///
/// **No valida y no lanza**, a diferencia de `Slug` o `SeasonLabel`. No hay
/// nombre de club inválido: hay nombres que emparejan y nombres que no. Y **no
/// es identidad**: `OpponentClub.name` se sigue guardando con su grafía, que es
/// lo que se muestra; esto es una **clave de comparación** derivada, y vive solo
/// el tiempo de una pasada de ingesta.
public struct NormalizedName: Hashable, Sendable {
    /// El nombre reducido a letras y dígitos: minúsculas, sin acentos, sin
    /// puntuación y sin espacios.
    public let value: String

    public init(_ raw: String) {
        self.value = Self.normalize(raw)
    }

    private static func normalize(_ raw: String) -> String {
        // El plegado va con locale **fijo**, no con el del sistema: con `es_ES`
        // la `ñ` no se pliega —en español es letra propia, no una `n` con
        // adorno— y entonces `"PEÑA"` y `"PENA"` serían dos clubes distintos.
        // Aquí se quiere lo contrario: en un paso ya declarado inexacto, el
        // riesgo que importa es no reconocer al mismo club, no confundir dos.
        // Fijarlo además hace la comparación **determinista**, que es condición
        // para que un test signifique algo.
        let folded = raw.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )

        // Todo lo que no sea letra o dígito **desaparece**, espacios incluidos.
        //
        // La versión evidente —tratar cada signo como separador— es la que hay
        // que no escribir: `"C.D."` daría `"c d"` y `"CD"` daría `"cd"`, así que
        // el administrador escribiendo las siglas sin puntos rompería el
        // emparejamiento, que es literalmente lo que este tipo existe para
        // impedir. Y el miedo que la justificaba —que `"C.D."` se pegue a la
        // palabra siguiente— se disuelve al quitar también los espacios: no
        // queda nada a lo que pegarse, porque no queda ninguna frontera.
        return folded.filter { $0.isLetter || $0.isNumber }
    }
}

import Testing
@testable import Domain

/// Nivel 1 (§8.1). El paso 2 de la cadena de §3.7 —*"nombre normalizado (sin la
/// letra, sin puntuación, sin acentos)"*— es el escalón **inexacto**, y lo que
/// decide cuánto lo es son estas reglas.
@Suite("Nombre normalizado · §3.7 · Anexo RFFM §F.5")
struct NormalizedNameTests {

    /// [Anexo RFFM §F.5]: *"nombres en **mayúsculas** y con puntuación irregular
    /// (`C.D.`, `C.F.`, `CELTIC CASTILLA C.F.`)"* → *"normalizar para el
    /// emparejamiento por nombre (paso 2 de la cadena de degradación), y dejar la
    /// grafía a corrección manual"*.
    ///
    /// Las dos grafías son **el mismo club**: la de la fuente y la que el
    /// administrador corrigió (§3.7, campo descriptivo). Si no normalizasen
    /// igual, la primera corrección de nombre rompería el emparejamiento de la
    /// semana siguiente.
    @Test("la caja, los acentos y la puntuación no distinguen dos clubes (§F.5)")
    func foldsCaseAccentsAndPunctuation() {
        let queDiceLaFuente = NormalizedName("C.D. FUTBOL TRES CANTOS")
        let corregidoPorElAdministrador = NormalizedName("C.D. Fútbol Tres Cantos")

        #expect(queDiceLaFuente == corregidoPorElAdministrador)
    }

    /// **La puntuación desaparece; no separa.** Lo descubrió el fixture de la
    /// cadena, que se escribió creyendo que estos dos nombres colisionaban.
    ///
    /// La primera versión trataba cada signo como separador, para que `"C.D."` no
    /// se pegase a la palabra siguiente. Suena prudente y es justo el fallo que
    /// este VO existe para evitar: `"C.D."` daba `"c d"` y `"CD"` daba `"cd"`, así
    /// que **el administrador escribiendo las siglas sin puntos rompía el
    /// emparejamiento** — exactamente el escenario del primer test, con otro
    /// signo. Y el miedo a que las palabras se peguen no tiene consecuencia: si
    /// desaparecen **todos** los separadores, los espacios incluidos, no queda
    /// nada a lo que pegarse.
    ///
    /// El sesgo es el mismo que con la `ñ`: en un escalón ya declarado inexacto
    /// (§3.7), el error que importa es **no reconocer al mismo club**.
    @Test("las siglas con puntos y sin puntos son el mismo club (§F.5)")
    func punctuationVanishesInsteadOfSplitting() {
        #expect(NormalizedName("C.D. Fútbol Tres Cantos") == NormalizedName("CD Futbol Tres Cantos"))
    }
}

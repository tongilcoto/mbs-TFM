/// **El diccionario de nombres y apellidos en castellano** (`D-123`): solo las palabras que
/// llevan tilde, eñe o diéresis, escritas bien y en mayúsculas. La sincronización busca
/// en él cada palabra que llega de la federación sin mirar tildes ni eñes («FERNANDEZ»), y
/// si está, la guarda como aquí («FERNÁNDEZ»). Lo que no está, como llega.
///
/// Con dos formas, **la castellana** («Jesus» no existe en castellano: es «Jesús»). Las que
/// existen de las dos maneras se decidieron una a una con el desarrollador (R6.17): entran
/// Díez, Sáez, Martí, Mía y Éric; se quedan fuera Saiz, Zoe e Iker, que se escriben sin
/// tilde. Un nombre que también es apellido (Martín, Román) va una sola vez: el
/// diccionario es uno.
///
/// Escrito por Claude y revisado por el desarrollador (R6.17). Se amplía con lo que salga.
enum CastilianNames {

    // ── Nombres ──────────────────────────────────────────────────────────────

    static let givenNames: [String] = [
        // De chico
        "ABDÓN", "ADÁN", "ADRIÁN", "AGUSTÍN", "ÁLVARO", "ANDRÉS", "ÁNGEL", "ANÍBAL", "ANTÓN",
        "BENJAMÍN", "BERNABÉ", "CÉSAR", "CRISTIÁN", "CRISTÓBAL", "DAMIÁN", "DARÍO", "EFRÉN",
        "ELÍAS", "FABIÁN", "FÉLIX", "FERMÍN", "FERNÁN", "GASTÓN", "GERMÁN", "HÉCTOR", "HERNÁN",
        "IÑAKI", "IÑIGO", "ISAÍAS", "IVÁN", "JERÓNIMO", "JESÚS", "JOAQUÍN", "JOSÉ", "JOSUÉ",
        "JULIÁN", "LEÓN", "MARTÍN", "MATÍAS", "MÁXIMO", "MOISÉS", "NICOLÁS", "NOÉ", "ÓSCAR",
        "PLÁCIDO", "RAMÓN", "RAÚL", "RENÉ", "ROMÁN", "RUBÉN", "SAÚL", "SEBASTIÁN", "SERAFÍN",
        "SIMÓN", "TOMÁS", "VALENTÍN", "VÍCTOR", "ZACARÍAS", "ÉRIC",
        "AARÓN", "ÁLEX", "CÁNDIDO", "DÁMASO", "GÉNESIS", "LEÓNIDAS", "NÉSTOR", "TEÓFILO", "TRISTÁN",
        // De chica
        "ÁFRICA", "ÁNGELA", "ÁNGELES", "ARÁNZAZU", "ASUNCIÓN", "BEGOÑA", "BELÉN", "CONCEPCIÓN",
        "DÉBORA", "ENCARNACIÓN", "ESTÍBALIZ", "INÉS", "LUCÍA", "MARÍA", "MÓNICA", "ROCÍO",
        "ROSALÍA", "SOFÍA", "VERÓNICA",
        "ANAÍS", "ELOÍSA", "ESTEFANÍA", "NOEMÍ", "SALOMÉ", "ÚRSULA", "MÍA",
    ]

    // ── Apellidos ────────────────────────────────────────────────────────────

    static let surnames: [String] = [
        // Los acabados en «-EZ», que casi siempre llevan tilde
        "ÁLVAREZ", "BENÍTEZ", "BERMÚDEZ", "BLÁZQUEZ", "DOMÍNGUEZ", "ESTÉVEZ", "FERNÁNDEZ",
        "GALÍNDEZ", "GÁLVEZ", "GIMÉNEZ", "GÓMEZ", "GONZÁLEZ", "GONZÁLVEZ", "GUTIÉRREZ",
        "HERNÁNDEZ", "ÍÑIGUEZ", "JIMÉNEZ", "JUÁREZ", "LÓPEZ", "MÁRQUEZ", "MARTÍNEZ", "MELÉNDEZ",
        "MÉNDEZ", "NÚÑEZ", "ORDÓÑEZ", "PÁEZ", "PELÁEZ", "PÉREZ", "PERIÁÑEZ", "RAMÍREZ",
        "RODRÍGUEZ", "SÁNCHEZ", "SUÁREZ", "TÉLLEZ", "VÁZQUEZ", "VELÁZQUEZ", "VÉLEZ", "VÍLCHEZ",
        "YÁÑEZ", "BÁEZ", "DÍEZ", "SÁEZ", "IBÁÑEZ", "MENÉNDEZ", "NARVÁEZ", "AMÉZQUITA", "FERRÁNDEZ", "FERRÁNDIZ",
        "MIGUÉLEZ", "ESTÉBANEZ", "HERNÁEZ",
        // Los demás con tilde
        "ALARCÓN", "ALBÉNIZ", "ALCÁNTARA", "ALCÁZAR", "ALEGRÍA", "ANDÚJAR", "ARAGÓN",
        "ARAGONÉS", "ARÉVALO", "ÁVILA", "BARBERÁ", "BARRAGÁN", "BELTRÁN", "CÁCERES", "CALDERÓN",
        "CALLEJÓN", "CÁRDENAS", "CARRIÓN", "CEBRIÁN", "CERDÁN", "CHACÓN", "COLÓN", "CÓRDOBA",
        "CORTÉS", "CUÉLLAR", "DÁVILA", "DURÁN", "ECHEVARRÍA", "GALÁN", "GALVÁN", "GARCÉS",
        "GARCÍA", "GARZÓN", "GIRÓN", "GUZMÁN", "HERNÁIZ", "HERRÁIZ", "JAÉN", "LAÍNEZ",
        "LÁZARO", "LIÉBANA", "MACÍAS", "MARÍN", "MARQUÉS", "MESÍAS", "MILLÁN", "MONTALBÁN",
        "MONTAÑÉS", "MORÁN", "PADRÓN", "PAVÓN", "QUIRÓS", "RINCÓN", "RÍO", "RÍOS", "ROLDÁN",
        "SALOMÓN", "SANTAMARÍA", "SOLÍS", "TOMÉ", "TORRÓN", "URÍA", "VALDÉS", "VARÓN", "YÉBENES",
        "DÍAZ", "MARTÍ", "ALBARRÁN", "ALMAZÁN", "ARAÚJO", "ASÍN", "BARRÓN", "BOLÍVAR", "CASTELLÓN",
        "CASTRILLÓN", "CORDÓN", "ECHEVERRÍA", "ESPÍN", "FALCÓN", "GARRIGÓS", "GASCÓN", "GAVILÁN",
        "GUILLÉN", "HERRÁN", "JORDÁN", "LAÍN", "LUJÁN", "MAGÁN", "MÁRMOL", "MÉRIDA", "NÁJERA",
        "OLIVÁN", "OREJÓN", "PALACÍN", "PICÓN", "SARRIÓN", "TERÁN", "VALLÉS", "VILLALÓN",
        // Con eñe
        "ACUÑA", "ARIÑO", "AZAÑA", "BAÑOS", "BOLAÑOS", "CABAÑAS", "CAMPAÑA", "CAÑADA",
        "CARDEÑOSA", "CASTAÑEDA", "CASTAÑO", "ESPAÑA", "ESPAÑOL", "LARRAÑAGA", "MAÑAS",
        "MONTAÑO", "MUÑIZ", "MUÑOZ", "OCAÑA", "PEÑA", "PEÑALOSA", "PEÑALVER", "PIÑA",
        "PIÑEIRO", "PIÑERO", "QUIÑONES", "RIAÑO", "SALDAÑA", "TREVIÑO", "ZÚÑIGA",
        "BAÑUELOS", "BRAÑA", "CAÑAS", "CAÑETE", "CAÑIZARES", "CARREÑO", "CASTAÑÓN", "FARIÑA",
        "LIÑÁN", "MARAÑÓN", "OÑATE", "PARDIÑAS", "PATIÑO", "PEÑAS", "PIÑÓN", "QUIÑONERO",
        "BAÑÓN", "CEDEÑO", "ORDOÑO",
        // Con diéresis
        "AGÜERO", "ARGÜELLES", "SIGÜENZA", "GÜELL",
    ]

    // ── Buscar en ella ──────────────────────────────────────────────────────

    /// Cada palabra, por su forma sin tildes, diéresis ni eñes: el pliegue del buscador
    /// (`PlayerSearch.fold`), el mismo que usa la base.
    private static let byKey: [String: String] = Dictionary(
        uniqueKeysWithValues: (givenNames + surnames).map { (PlayerSearch.fold($0), $0) })

    /// La palabra como en la lista, si está; si no, como llega.
    static func spelled(_ word: Substring) -> String {
        byKey[PlayerSearch.fold(String(word))] ?? String(word)
    }
}

import struct Foundation.Locale

/// Lo que se ha tecleado en el buscador del alta (`D-120`), listo para buscar.
///
/// # No compara: ayuda a encontrar
///
/// «El mismo nombre» de la sincronización es estricto (la eñe cuenta). El buscador
/// no: **sin tildes, diéresis ni mayúsculas, y la eñe es una «n»** (R6.3), porque
/// lo que importa es que quien no la teclea también encuentre a «Muñoz». Y busca
/// **palabra a palabra**: cada palabra escrita tiene que ser el comienzo de una
/// palabra del nombre («juan fuen» encuentra a JUAN GARCÍA FUENTE).
///
/// # Por qué una tabla de letras propia, y no el plegado de Foundation
///
/// La búsqueda la hace la base, con `translate`, y tiene que plegar **exactamente
/// igual** que este tipo, que es el que pliega lo tecleado. Con dos plegados
/// distintos, una letra que uno quite y el otro no haría que no se encontrara a
/// nadie. Así que los dos usan la misma tabla, `foldFrom` → `foldTo`, y el
/// repositorio construye su `translate` con ella.
public struct PlayerSearch: Equatable, Sendable {
    /// Las palabras escritas, plegadas, en el orden en que se escribieron.
    public let words: [String]

    /// Hacen falta tres letras, contando todas las palabras (`D-120`).
    public static let minimumLetters = 3

    /// Las letras que se pliegan, y en qué. El guion y los apóstrofos pasan a
    /// espacio: tras ellos empieza otra palabra («PÉREZ-GIL», «O'BRIEN»).
    public static let foldFrom = Array("ÁÀÄÂÃÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÑÇ'’-")
    public static let foldTo = Array("AAAAAEEEEIIIIOOOOOUUUUNC   ")

    /// `nil` con menos de tres letras: el buscador no busca.
    public init?(_ raw: String) {
        let words = Self.fold(raw)
            .split(separator: " ")
            .map { String($0.filter(\.isLetter)) }
            .filter { !$0.isEmpty }
        guard words.joined().count >= Self.minimumLetters else { return nil }
        self.words = words
    }

    /// Si el nombre tiene, para cada palabra escrita, una palabra que empieza así.
    public func matches(_ name: PlayerName) -> Bool {
        let nameWords = Self.fold(name.value).split(separator: " ")
        return words.allSatisfy { word in nameWords.contains { $0.hasPrefix(word) } }
    }

    /// En mayúsculas, como se guarda el nombre (`PlayerName`), y con la tabla.
    public static func fold(_ text: String) -> String {
        let table = Dictionary(uniqueKeysWithValues: zip(foldFrom, foldTo))
        return String(
            text.precomposedStringWithCanonicalMapping
                .uppercased(with: Locale(identifier: "es_ES"))
                .map { table[$0] ?? $0 })
    }
}

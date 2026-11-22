import Foundation

/// **El diccionario de nombres y apellidos en castellano** (`D-123`): las palabras que
/// llevan tilde, eñe o diéresis, escritas bien y en mayúsculas. La sincronización busca
/// en él cada palabra que llega de la federación sin mirar tildes ni eñes («FERNANDEZ»), y
/// si está, la guarda como aquí («FERNÁNDEZ»). Lo que no está, como llega.
///
/// **La lista no está aquí**: vive en un fichero de texto, `backend/diccionario-nombres.txt`,
/// que se cambia en caliente (enmienda a `D-123`, R6.19). Esto es lo que se construye al
/// leerlo: una palabra por línea; las líneas vacías y las que empiezan por `#` no
/// cuentan. **Una línea mala no se usa** y se apunta con su motivo, para que el resumen de
/// la sincronización la nombre; las demás, sí (decisión 2 de R6.19). De una palabra dos
/// veces, vale la primera.
///
/// Cero I/O: quien lee el fichero es el adaptador (`Storage`), y le pasa aquí su texto.
public struct CastilianNames: Sendable, Equatable {

    /// Una línea del fichero que no se ha usado, y por qué.
    public struct Problem: Sendable, Equatable {
        public enum Reason: Sendable, Equatable {
            /// Sin tilde, eñe ni diéresis: no hace falta, porque ya llega bien.
            case noMark
            /// En minúsculas, con un espacio, un guion, una cifra u otro signo: no es una palabra
            /// en mayúsculas.
            case notOneUppercaseWord
            /// Otra forma de una palabra que ya está en la línea `line` (la misma, o con otras
            /// tildes): vale la primera.
            case repeated(line: Int)
        }

        /// Contando desde 1, como un editor.
        public let line: Int
        /// La línea, sin los espacios de los lados.
        public let text: String
        public let reason: Reason

        public init(line: Int, text: String, reason: Reason) {
            self.line = line
            self.text = text
            self.reason = reason
        }
    }

    /// Las palabras que valen, en el orden del fichero.
    public let words: [String]
    /// Las líneas que no se han usado.
    public let problems: [Problem]

    /// Cada palabra, por su forma sin tildes, diéresis ni eñes: el pliegue del buscador
    /// (`PlayerSearch.fold`), el mismo que usa la base.
    private let byKey: [String: String]

    /// Sin palabras: cuando no hay fichero, los nombres se quedan como llegan.
    public static let empty = CastilianNames(text: "")

    /// El diccionario a partir del texto del fichero.
    public init(text: String) {
        var words: [String] = []
        var problems: [Problem] = []
        var byKey: [String: String] = [:]
        var lineOf: [String: Int] = [:]
        // Por saltos de línea, también los de Windows.
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for (index, raw) in lines.enumerated() {
            let line = index + 1
            let word = raw.trimmingCharacters(in: .whitespaces)
            if word.isEmpty || word.hasPrefix("#") { continue }
            guard word.allSatisfy(Self.isUppercaseLetter) else {
                problems.append(Problem(line: line, text: word, reason: .notOneUppercaseWord))
                continue
            }
            let key = PlayerSearch.fold(word)
            guard key != word else {
                problems.append(Problem(line: line, text: word, reason: .noMark))
                continue
            }
            if let first = lineOf[key] {
                problems.append(Problem(line: line, text: word, reason: .repeated(line: first)))
                continue
            }
            lineOf[key] = line
            byKey[key] = word
            words.append(word)
        }
        self.words = words
        self.problems = problems
        self.byKey = byKey
    }

    /// La palabra como en la lista, si está; si no, como llega.
    public func spelled(_ word: Substring) -> String {
        byKey[PlayerSearch.fold(String(word))] ?? String(word)
    }

    /// Una letra mayúscula: la que no cambia al pasarla a mayúsculas y sí al pasarla a
    /// minúsculas. Así valen la Ñ, la Ü y las vocales con tilde, y no las cifras ni los signos.
    private static func isUppercaseLetter(_ character: Character) -> Bool {
        character.isLetter && character.uppercased() == String(character)
            && character.lowercased() != String(character)
    }

    public static func == (lhs: CastilianNames, rhs: CastilianNames) -> Bool {
        lhs.words == rhs.words && lhs.problems == rhs.problems
    }
}

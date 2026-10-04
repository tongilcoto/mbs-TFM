import Testing
@testable import MutateCore

@Suite("Aplicar una mutación: literal, y casando una sola vez (A-15·H-52)")
struct ApplyingTests {

    @Test("el reemplazo es literal: `$0` y `\\1` llegan tal cual (F7)")
    func replacementIsLiteral() {
        let result = applying([Edit(find: "== true", replace: #"$0 != \1"#)],
                              to: "confirmed: x == true")
        #expect(result == .success(#"confirmed: x $0 != \1"#))
    }

    @Test("la búsqueda también es literal: un `.` o un `(` no son comodines")
    func findIsLiteral() {
        let result = applying([Edit(find: "a.b(", replace: "X")], to: "axb( a.b(")
        #expect(result == .success("axb( X"))
    }

    @Test("un patrón que no casa no se aplica, y eso no es un superviviente (F4, F7)")
    func patternNotFound() {
        let result = applying([Edit(find: "no está", replace: "x")], to: "let a = 1")
        #expect(result == .failure(.patternNotFound(edit: 1)))
    }

    @Test("un patrón que casa dos veces no se aplica: no se sabe qué línea se quería romper")
    func patternAmbiguous() {
        let result = applying([Edit(find: "isEmpty", replace: "isFull")],
                              to: "a.isEmpty || b.isEmpty")
        #expect(result == .failure(.patternAmbiguous(edit: 1, occurrences: 2)))
    }

    @Test("un reemplazo que deja el fichero igual no es una mutación")
    func noChange() {
        let result = applying([Edit(find: "x", replace: "x")], to: "let x = 1")
        #expect(result == .failure(.noChange))
    }

    @Test("varios cambios van en orden, cada uno sobre el resultado del anterior")
    func editsInOrder() {
        let result = applying(
            [Edit(find: "a", replace: "bb"), Edit(find: "bbc", replace: "X")], to: "ac")
        #expect(result == .success("X"))
    }

    @Test("si el segundo cambio no casa, la mutación entera no se aplica, y dice cuál")
    func secondEditMissing() {
        let result = applying(
            [Edit(find: "a", replace: "b"), Edit(find: "zzz", replace: "y")], to: "a")
        #expect(result == .failure(.patternNotFound(edit: 2)))
    }
}

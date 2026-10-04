import Testing
@testable import CensusCore

@Suite("Los códigos Problem: los que el código emite, y los que nombra algún test (A-15·H-72)")
struct ProblemCodesTests {

    static let middleware = SourceFile(path: "Sources/HTTPAdapter/ProblemMiddleware.swift", text: """
        case .teamNotFound:
            return Problem(status: 404, code: "TEAM_NOT_FOUND", title: "…")
        case .invalidLimit:
            return Problem(status: 400, code: "INVALID_LIMIT", title: "…")
        // un comentario que dice code: "NO_ES_UN_CODIGO" no cuenta igual
        """)

    @Test("cada `code: \"X\"` de Sources es un código emitido, con su fichero y su línea")
    func emitted() {
        let codes = emittedProblemCodes(in: [Self.middleware])
        #expect(codes.contains(CodeEmission(
            code: "TEAM_NOT_FOUND", file: "Sources/HTTPAdapter/ProblemMiddleware.swift", line: 2)))
        #expect(codes.contains(CodeEmission(
            code: "INVALID_LIMIT", file: "Sources/HTTPAdapter/ProblemMiddleware.swift", line: 4)))
    }

    @Test("el patrón es el de A-14, literal: también casa dentro de un comentario")
    func patternIsTheDocumentedOne() {
        // Se deja escrito a propósito: el método es `grep`, y `grep` no sabe qué es
        // un comentario. Si un día molesta, se cambia aquí y en el README a la vez.
        let codes = emittedProblemCodes(in: [Self.middleware]).map(\.code)
        #expect(codes.contains("NO_ES_UN_CODIGO"))
    }

    @Test("un test nombra el código si lo escribe entre comillas")
    func mentionedWithQuotes() {
        let tests = [
            SourceFile(path: "Tests/APITests/A.swift", text: #"#expect(problem.code == "TEAM_NOT_FOUND")"#),
            SourceFile(path: "Tests/APITests/B.swift", text: "// TEAM_NOT_FOUND sin comillas no cuenta"),
        ]
        #expect(filesMentioning(code: "TEAM_NOT_FOUND", in: tests) == ["Tests/APITests/A.swift"])
    }

    @Test("un código que es prefijo de otro no cuenta como nombrado (`NOT_FOUND` frente a `TEAM_NOT_FOUND`)")
    func prefixIsNotAMention() {
        let tests = [SourceFile(path: "T.swift", text: #"#expect(code == "TEAM_NOT_FOUND")"#)]
        #expect(filesMentioning(code: "NOT_FOUND", in: tests).isEmpty)
    }
}

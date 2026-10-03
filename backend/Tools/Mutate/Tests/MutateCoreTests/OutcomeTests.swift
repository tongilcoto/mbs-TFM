import Foundation
import Testing
@testable import MutateCore

@Suite("El desenlace de una mutación, y la cifra que se cita (A-15·H-52)")
struct OutcomeTests {

    @Test("una mutación que no compila no sobrevive: no se probó (F7)")
    func doesNotCompileIsInvalid() {
        let result = outcome(applied: .success("mutado"), compiled: false, test: nil,
                             declaredEquivalent: false)
        #expect(result == .invalid(.doesNotCompile))
    }

    @Test("una mutación sin aplicar no sobrevive, aunque la batería pase (F4)")
    func notAppliedIgnoresTheBattery() {
        let result = outcome(applied: .failure(.patternNotFound(edit: 1)), compiled: true,
                             test: .passed, declaredEquivalent: false)
        #expect(result == .invalid(.notApplied(.patternNotFound(edit: 1))))
    }

    @Test("aplicada, compilada y con la batería en rojo: cazada")
    func killed() {
        #expect(outcome(applied: .success("m"), compiled: true, test: .failed,
                        declaredEquivalent: false) == .killed)
    }

    @Test("aplicada, compilada y con la batería en verde: sobrevive")
    func survived() {
        #expect(outcome(applied: .success("m"), compiled: true, test: .passed,
                        declaredEquivalent: false) == .survived)
    }

    @Test("la equivalente declarada que sobrevive es equivalente, no superviviente (F5)")
    func declaredEquivalent() {
        #expect(outcome(applied: .success("m"), compiled: true, test: .passed,
                        declaredEquivalent: true) == .equivalent)
    }

    @Test("una ejecución inválida hace inválida la mutación")
    func invalidRun() {
        #expect(outcome(applied: .success("m"), compiled: true, test: .invalid(.noTestsRan),
                        declaredEquivalent: false) == .invalid(.run(.noTestsRan)))
    }

    static func result(_ id: String, _ outcome: Outcome, equivalent: String? = nil) -> MutationResult {
        MutationResult(
            mutation: Mutation(id: id, description: "rompe \(id)", file: "Sources/X.swift",
                               edits: [Edit(find: "a", replace: "b")], equivalent: equivalent),
            filter: "XTests", outcome: outcome)
    }

    @Test("el resumen cuenta cada desenlace por separado")
    func headline() {
        let summary = Summary(title: "F", results: [
            Self.result("M1", .killed), Self.result("M2", .killed),
            Self.result("M3", .survived), Self.result("M4", .equivalent, equivalent: "simétrico"),
            Self.result("M5", .invalid(.doesNotCompile)),
        ])
        #expect(summary.headline
                == "5 mutaciones, 2 cazadas, 1 sobreviven, 1 equivalentes, 1 inválidas")
    }

    @Test("código de salida: 0 todo cazado, 1 si sobrevive alguna, 2 si hay inválidas")
    func exitCodes() {
        #expect(Summary(title: "", results: [Self.result("M1", .killed),
                                             Self.result("M2", .equivalent, equivalent: "x")])
            .exitCode == 0)
        #expect(Summary(title: "", results: [Self.result("M1", .survived)]).exitCode == 1)
        #expect(Summary(title: "", results: [Self.result("M1", .survived),
                                             Self.result("M2", .invalid(.doesNotCompile))])
            .exitCode == 2)
    }

    @Test("si la batería sin mutar no cierra en verde, la pasada entera no vale")
    func closingBaseline() {
        let summary = Summary(title: "", results: [Self.result("M1", .killed)],
                              closingBaselinePassed: false)
        #expect(summary.exitCode == 2)
        #expect(summary.markdown().contains("no cerró en verde"))
    }

    @Test("el informe avisa de las inválidas y dice por qué cada una")
    func markdownWarnsAboutInvalid() {
        let markdown = Summary(title: "F", results: [
            Self.result("M1", .invalid(.notApplied(.patternNotFound(edit: 1)))),
        ]).markdown(date: Date(timeIntervalSince1970: 0))
        #expect(markdown.contains("Hay inválidas"))
        #expect(markdown.contains("no se aplicó: el cambio 1 no casa con el fichero"))
    }

    @Test("una declarada equivalente que cae se marca: la declaración sobra")
    func killedDespiteEquivalent() {
        let markdown = Summary(title: "F", results: [
            Self.result("M1", .killed, equivalent: "creía que era simétrico"),
        ]).markdown()
        #expect(markdown.contains("declarada equivalente y cazada"))
    }
}

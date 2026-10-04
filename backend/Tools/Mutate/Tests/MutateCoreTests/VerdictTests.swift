import Testing
@testable import MutateCore

@Suite("El veredicto de swift test: manda el código de salida, lo confirma el ✘ (A-15·H-52)")
struct VerdictTests {

    @Test("la batería en verde, con tests que corrieron, es un pase")
    func passing() {
        let evidence = TestRunEvidence(exitCode: 0, output: Fixture.passingOutput,
                                       xunitReports: [Fixture.passingXML])
        #expect(evidence.executed == 4)
        #expect(verdict(of: evidence) == .passed)
    }

    @Test("manda el ✘ y no el `error:`: una expectativa que cae trae `(error)` y es una cazada (F7)")
    func crossMarkBeatsErrorWord() {
        let evidence = TestRunEvidence(exitCode: 1, output: Fixture.failingOutput,
                                       xunitReports: [Fixture.failingXML])
        #expect(evidence.failures == 5)
        #expect(verdict(of: evidence) == .failed)
    }

    @Test("`error:` en los logs de una batería verde es un pase, no una inválida (F10-bis)")
    func errorWordInLogsIsNotInvalid() {
        let evidence = TestRunEvidence(
            exitCode: 0, output: Fixture.apiLogsWithError + Fixture.passingOutput,
            xunitReports: [Fixture.passingXML])
        #expect(verdict(of: evidence) == .passed)
    }

    @Test("un parametrizado que cae cuenta: se lee el ✘, no el nombre del test (F1)")
    func parameterizedFailureCounts() {
        let line = #"✘ Test "deriva el slug" with 6 test cases failed after 0.001 seconds with 5 issues."#
        let evidence = TestRunEvidence(exitCode: 1, output: line, xunitReports: [])
        #expect(evidence.crossMarks == 1)
        #expect(verdict(of: evidence) == .failed)
    }

    @Test("un filtro que no casa sale con 0, y eso no es un pase (README §5.1)")
    func noTestsRanIsNotAPass() {
        let evidence = TestRunEvidence(exitCode: 0, output: Fixture.noMatchOutput,
                                       xunitReports: [Fixture.noMatchXML])
        #expect(verdict(of: evidence) == .invalid(.noTestsRan))
    }

    @Test("los omitidos no corrieron: una batería entera omitida no es un pase (H-07)")
    func skippedAreNotExecuted() {
        let xml = """
            <testsuites><testsuite tests="3" failures="0" skipped="3">
            <testcase name="a"><skipped/></testcase><testcase name="b"><skipped/></testcase>
            <testcase name="c"><skipped/></testcase></testsuite></testsuites>
            """
        let evidence = TestRunEvidence(exitCode: 0, output: "", xunitReports: [xml])
        #expect(evidence.executed == 0)
        #expect(verdict(of: evidence) == .invalid(.noTestsRan))
    }

    /// Medido en la batería entera (2026-10-03): el grupo del canario escribe
    /// `tests="82" skipped="1"` con **83** `<testcase>`, y la salida dice *"83
    /// tests"*. El atributo `tests` ya **excluye** los omitidos, así que restarlos
    /// otra vez cuenta de menos: aquí daría cero ejecutados con uno que corrió.
    @Test("los ejecutados se cuentan por <testcase>: el atributo `tests` de swift-testing ya excluye los omitidos")
    func executedCountsTestcases() {
        let xml = """
            <testsuites><testsuite name="TestResults" errors="0" tests="1" failures="0" skipped="1">
            <testcase classname="FederationTests.RFFMCanaryTests" name="live()">
                <skipped>canario: exige FEDERATION_LIVE=1</skipped>
            </testcase>
            <testcase classname="FederationTests.RFFMSeasonLabelTests" name="reformats(_:_:)" time="0.05"/>
            </testsuite></testsuites>
            """
        let evidence = TestRunEvidence(exitCode: 0, output: "", xunitReports: [xml])
        #expect(evidence.tests == 2)
        #expect(evidence.executed == 1)
        #expect(verdict(of: evidence) == .passed)
    }

    @Test("sin informe XML no hay pase: no se sabe si corrió algo")
    func noReportIsNotAPass() {
        let evidence = TestRunEvidence(exitCode: 0, output: Fixture.passingOutput, xunitReports: [])
        #expect(verdict(of: evidence) == .invalid(.noReport))
    }

    @Test("salir mal sin un solo ✘ ni fallo en el XML no es cazar: la batería no dijo nada")
    func failingExitWithoutFailuresIsInvalid() {
        let evidence = TestRunEvidence(exitCode: 139, output: "Segmentation fault",
                                       xunitReports: [])
        #expect(verdict(of: evidence) == .invalid(.failedWithoutFailures(exitCode: 139)))
    }

    @Test("un ✘ con salida 0 es una contradicción, no un resultado")
    func crossMarkWithZeroExitIsContradictory() {
        let evidence = TestRunEvidence(exitCode: 0, output: Fixture.failingOutput,
                                       xunitReports: [Fixture.passingXML])
        #expect(verdict(of: evidence) == .invalid(.contradictory))
    }

    @Test("un fallo que solo está en el XML también cuenta")
    func failureOnlyInXML() {
        let evidence = TestRunEvidence(exitCode: 1, output: "", xunitReports: [Fixture.failingXML])
        #expect(verdict(of: evidence) == .failed)
    }

    @Test("los recuentos se suman sobre todos los informes y todos los <testsuite>")
    func totalsAcrossReports() {
        let evidence = TestRunEvidence(exitCode: 1, output: "",
                                       xunitReports: [Fixture.passingXML, Fixture.failingXML])
        #expect(evidence.tests == 5)  // 4 <testcase> en uno, 1 en el otro (recortado)
        #expect(evidence.failures == 5)
    }
}

import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Lo que dejó una ejecución de `swift test`, leído de las tres fuentes que
/// no mienten: el código de salida, las líneas `✘` y el XML de `--xunit-output`.
///
/// **Lo que no se lee nunca es la palabra `error:`.** Aparece en los *logs* de
/// la suite de API y dentro de los fallos de Postgres, y las dos veces que un
/// guion la miró se equivocó: en F7 leyó dos mutaciones cazadas como fallos de
/// compilación, y en F10-bis escondió dos supervivientes reales detrás de la
/// palabra *"inválida"*. El propio XML de swift-testing escribe `(error)` en el
/// mensaje de cada expectativa fallida.
public struct TestRunEvidence: Equatable, Sendable {
    public var exitCode: Int32
    /// Las líneas que empiezan por `✘`: el fallo según swift-testing.
    public var crossMarks: Int
    /// Si `--xunit-output` dejó al menos un fichero.
    public var reportFound: Bool
    public var tests: Int
    public var skipped: Int
    public var failures: Int

    /// Los tests que **corrieron**: un omitido no prueba nada.
    public var executed: Int { max(0, tests - skipped) }

    public init(exitCode: Int32, crossMarks: Int, reportFound: Bool,
                tests: Int, skipped: Int, failures: Int) {
        self.exitCode = exitCode
        self.crossMarks = crossMarks
        self.reportFound = reportFound
        self.tests = tests
        self.skipped = skipped
        self.failures = failures
    }

    /// Reúne la evidencia de la salida de `swift test` y de sus ficheros XML
    /// (swift-testing escribe `<nombre>-swift-testing.xml`; XCTest, `<nombre>.xml`).
    public init(exitCode: Int32, output: String, xunitReports: [String]) {
        let marks = output.split(whereSeparator: \.isNewline).filter {
            $0.drop { $0 == " " }.hasPrefix("✘")
        }
        var totals = XUnitTotals()
        for report in xunitReports { totals += XUnitTotals(parsing: report) }
        self.init(exitCode: exitCode, crossMarks: marks.count,
                  reportFound: !xunitReports.isEmpty,
                  tests: totals.tests, skipped: totals.skipped, failures: totals.failures)
    }
}

/// Lo que una ejecución de `swift test` dice, o por qué no dice nada.
public enum TestRunVerdict: Equatable, Sendable {
    case failed
    case passed
    case invalid(InvalidRun)
}

/// Por qué una ejecución **no es un resultado**. Ninguno de estos casos se puede
/// leer como *"sobrevive"* ni como *"cazada"*: es el error de `H-07`, confundir
/// *"no se ejecutó"* con un resultado.
public enum InvalidRun: Equatable, Sendable, CustomStringConvertible {
    /// El filtro no casó con nada: `swift test` sale con `0` y la palabra
    /// *passed* en la pantalla (README §5.1).
    case noTestsRan
    case noReport
    /// Salió mal sin un solo `✘` ni fallo en el XML: una caída, o algo que no
    /// llegó a ser un test.
    case failedWithoutFailures(exitCode: Int32)
    /// Un `✘` con salida `0`: dos fuentes que se contradicen.
    case contradictory

    public var description: String {
        switch self {
        case .noTestsRan: "no se ejecutó ningún test (¿el filtro no casa?)"
        case .noReport: "swift test no dejó informe XML"
        case .failedWithoutFailures(let code):
            "swift test salió con \(code) sin un solo ✘ ni fallo en el XML"
        case .contradictory: "hay ✘ pero swift test salió con 0"
        }
    }
}

/// **Manda el código de salida, y lo confirma el `✘` o el XML** (F1: nunca
/// raspar el nombre del test, que en los parametrizados lleva
/// *"with 6 test cases failed"*). *"No hay `✘`"* solo significa *"pasó"* si la
/// batería **dijo** que pasó y **algo corrió** (F10-bis).
public func verdict(of evidence: TestRunEvidence) -> TestRunVerdict {
    let failureSeen = evidence.crossMarks > 0 || evidence.failures > 0
    if evidence.exitCode != 0 {
        return failureSeen ? .failed : .invalid(.failedWithoutFailures(exitCode: evidence.exitCode))
    }
    if failureSeen { return .invalid(.contradictory) }
    guard evidence.reportFound else { return .invalid(.noReport) }
    guard evidence.executed > 0 else { return .invalid(.noTestsRan) }
    return .passed
}

/// Los recuentos de un informe xUnit, sumados sobre todos sus `<testsuite>`.
///
/// **Los tests y los omitidos se cuentan por elemento** —`<testcase>` y
/// `<skipped>`—, no por atributo: swift-testing escribe `tests="82"
/// skipped="1"` para 83 `<testcase>`, porque su `tests` ya excluye los omitidos
/// (medido en la batería entera el 2026-10-03), y restarlos otra vez contaba de
/// menos. Los fallos se cuentan de las dos maneras —el atributo
/// `failures`/`errors` y los elementos `<failure>`/`<error>`— y vale la mayor:
/// así un informe que solo rellena una no esconde un fallo.
struct XUnitTotals: Equatable {
    var tests = 0
    var skipped = 0
    var failures = 0

    static func += (lhs: inout XUnitTotals, rhs: XUnitTotals) {
        lhs.tests += rhs.tests
        lhs.skipped += rhs.skipped
        lhs.failures += rhs.failures
    }

    init() {}

    init(parsing xml: String) {
        let collector = Collector()
        let parser = XMLParser(data: Data(xml.utf8))
        parser.delegate = collector
        parser.parse()
        tests = collector.testcases
        skipped = collector.skippedElements
        failures = max(collector.failureAttributes, collector.failureElements)
    }

    private final class Collector: NSObject, XMLParserDelegate {
        var testcases = 0
        var skippedElements = 0
        var failureAttributes = 0
        var failureElements = 0

        func parser(_ parser: XMLParser, didStartElement name: String,
                    namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            func count(_ key: String) -> Int { attributes[key].flatMap(Int.init) ?? 0 }
            switch name {
            case "testsuite":
                failureAttributes += count("failures") + count("errors")
            case "testcase":
                testcases += 1
            case "failure", "error":
                failureElements += 1
            case "skipped":
                skippedElements += 1
            default:
                break
            }
        }
    }
}

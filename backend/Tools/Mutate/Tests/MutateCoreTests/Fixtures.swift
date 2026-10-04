/// Salidas **medidas** de `REQUIRE_DB=1 swift test --filter SlugTests --xunit-output`
/// el 2026-10-03 (Swift 6.4), recortadas. No inventadas: el formato es lo que se
/// está probando, y un formato imaginado prueba la imaginación.
enum Fixture {
    /// La batería en verde: 4 tests, sin fallos.
    static let passingOutput = """
        ◇ Test run started.
        ✔ Test "deriva el slug del nombre que publica la federación (D-82)" with 6 test cases passed after 0.001 seconds.
        ✔ Suite "Slug · §4.1 · el pattern del spec lo hace cumplir el Dominio (D-65)" passed after 0.001 seconds.
        ✔ Test run with 4 tests in 1 suite passed after 0.001 seconds.
        """

    static let passingXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuites>
            <testsuite name="TestResults" errors="0" tests="0" failures="0" skipped="0" time="0.000153709"/>
            <testsuite name="TestResults" errors="0" tests="4" failures="0" skipped="0" time="0.001780875">
                <testcase classname="DomainTests.SlugTests" name="rejectsUnsluggableName()" time="0.001355"/>
                <testcase classname="DomainTests.SlugTests" name="derivesFromName(_:_:)" time="0.001"/>
                <testcase classname="DomainTests.SlugTests" name="rejectsInvalid(_:)" time="0.001"/>
                <testcase classname="DomainTests.SlugTests" name="emptyName()" time="0.001"/>
            </testsuite>
        </testsuites>
        """

    /// Una mutación cazada por un test **parametrizado**: el `✘` final lleva
    /// *"with 6 test cases failed"*, que es lo que en F1 se comió el raspado.
    static let failingOutput = """
        ◇ Test run started.
        ✘ Test "deriva el slug del nombre que publica la federación (D-82)" recorded an issue with 2 arguments input → "C.D. GALAPAGAR", expected → "c-d-galapagar" at SlugTests.swift:57:9: Expectation failed: try Slug(derivedFrom: input).value == expected
        ✘ Test "deriva el slug del nombre que publica la federación (D-82)" with 6 test cases failed after 0.001 seconds with 5 issues.
        ✘ Test run with 4 tests in 1 suite failed after 0.001 seconds with 5 issues.
        Note: Some test targets reported failures:
          - DomainTests (Swift Testing)
        """

    /// El mensaje de cada fallo trae `(error)`: un guion que mire esa palabra
    /// confunde la expectativa que cae con un fallo de compilación.
    static let failingXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuites>
            <testsuite name="TestResults" errors="0" tests="0" failures="0" skipped="0" time="0.00011375"/>
            <testsuite name="TestResults" errors="0" tests="4" failures="5" skipped="0" time="0.001469542">
                <testcase classname="DomainTests.SlugTests" name="derivesFromName(_:_:)" time="0.001060791">
                    <failure message="Expectation failed: try Slug(derivedFrom: input).value == expected (error)"/>
                </testcase>
            </testsuite>
        </testsuites>
        """

    /// Un filtro que no casa con nada: sale con **0**.
    static let noMatchOutput = "warning: No matching test cases were run\n"

    static let noMatchXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <testsuites>
            <testsuite name="TestResults" errors="0" tests="0" failures="0" skipped="0" time="8.3125e-05"/>
            <testsuite name="TestResults" errors="0" tests="0" failures="0" skipped="0" time="0.000129792"/>
        </testsuites>
        """

    /// Lo que la suite de API escribe en sus *logs* en una pasada **verde**: la
    /// palabra `error:` sin que nada haya fallado (F10-bis).
    static let apiLogsWithError = """
        [ ERROR ] error: tenant not resolved [request-id: 1F2E]
        [ WARNING ] PSQLError: error: duplicate key value violates unique constraint
        """
}

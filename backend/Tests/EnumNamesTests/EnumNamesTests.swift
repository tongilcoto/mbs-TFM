import Foundation
import Testing
@testable import EnumNamesCore

/// Nivel 1 (§8.1): la herramienta que escribe en Swift los nombres de cada lista del catálogo (`D-108`, `D-109`).
/// **Cero I/O**: recibe el texto del catálogo y el de la configuración del generador, y devuelve el Swift.
@Suite("EnumNames · D-109 · los nombres del servidor salen del catálogo")
struct EnumNamesTests {

    /// Un catálogo mínimo, con la forma del de verdad: una lista con nombres, `ProblemCode` sin ellos, y un esquema
    /// que no es una lista.
    static func catalog(teamCategory: String = """
            TeamCategory:
              type: string
              enum: [alevin, cadete]
              x-enum-names:
                alevin: Alevín
                cadete: Cadete
        """) -> String {
        """
        openapi: 3.1.0
        components:
          schemas:
            ProblemCode:
              type: string
              enum: [INTERNAL]
        \(teamCategory)
            SeasonLabel:
              type: string
              pattern: '^\\d{4}/\\d{2}$'
        """
    }

    static func config(schemas: [String] = ["TeamCategory"]) -> String {
        """
        generate:
          - types
        filter:
          operations:
            - getClub
          schemas:
        \(schemas.map { "    - \($0)" }.joined(separator: "\n"))
        """
    }

    // ── Lo que escribe ───────────────────────────────────────────────────────

    @Test("cada lista con nombres, una extensión de su tipo del contrato con el nombre de cada valor")
    func writesOneExtensionPerList() throws {
        let swift = try EnumNames.swiftSource(catalog: Self.catalog(), generatorConfig: Self.config())

        #expect(swift.contains("extension Components.Schemas.TeamCategory {"))
        #expect(swift.contains("case .alevin: \"Alevín\""))
        #expect(swift.contains("case .cadete: \"Cadete\""))
        #expect(swift.contains("public var displayName: String {"))
    }

    @Test("los valores, en el orden del catálogo")
    func keepsCatalogOrder() throws {
        let swift = try EnumNames.swiftSource(catalog: Self.catalog(), generatorConfig: Self.config())

        let alevin = try #require(swift.range(of: "case .alevin"))
        let cadete = try #require(swift.range(of: "case .cadete"))
        #expect(alevin.lowerBound < cadete.lowerBound)
    }

    @Test("ProblemCode no lleva nombres, y no sale; ni lo que no es una lista")
    func skipsProblemCodeAndNonLists() throws {
        let swift = try EnumNames.swiftSource(catalog: Self.catalog(), generatorConfig: Self.config())

        #expect(!swift.contains("ProblemCode"))
        #expect(!swift.contains("SeasonLabel"))
    }

    @Test("un nombre con comillas o barras sale como texto de Swift válido")
    func escapesNames() throws {
        let catalog = Self.catalog(teamCategory: """
                TeamCategory:
                  type: string
                  enum: [alevin]
                  x-enum-names:
                    alevin: 'Alevín "A" \\ B'
            """)

        let swift = try EnumNames.swiftSource(catalog: catalog, generatorConfig: Self.config())

        #expect(swift.contains(#"case .alevin: "Alevín \"A\" \\ B""#))
    }

    // ── Lo que la para ───────────────────────────────────────────────────────

    @Test("una lista sin tabla de nombres la para, diciendo cuál")
    func failsWithoutNames() throws {
        let catalog = Self.catalog(teamCategory: """
                TeamCategory:
                  type: string
                  enum: [alevin]
            """)

        #expect(throws: EnumNames.Problems(["TeamCategory: le falta x-enum-names"])) {
            try EnumNames.swiftSource(catalog: catalog, generatorConfig: Self.config())
        }
    }

    @Test("un valor sin nombre, o un nombre de más, la para, diciendo cuál")
    func failsOnMissingOrExtraNames() throws {
        let catalog = Self.catalog(teamCategory: """
                TeamCategory:
                  type: string
                  enum: [alevin, cadete]
                  x-enum-names:
                    alevin: Alevín
                    juvenil: Juvenil
            """)

        #expect(throws: EnumNames.Problems([
            "TeamCategory: sin nombre para cadete",
            "TeamCategory: nombres de valores que la lista no tiene: juvenil",
        ])) {
            try EnumNames.swiftSource(catalog: catalog, generatorConfig: Self.config())
        }
    }

    @Test("una lista con nombres que no está en `filter: schemas` la para: el generador no fabricaría su tipo")
    func failsWhenListIsNotGenerated() throws {
        #expect(throws: EnumNames.Problems([
            "TeamCategory: añádela a `filter: schemas` en openapi-generator-config.yaml, o el contrato no tendrá su tipo",
        ])) {
            try EnumNames.swiftSource(catalog: Self.catalog(), generatorConfig: Self.config(schemas: ["Otra"]))
        }
    }

    @Test("los fallos salen todos a la vez")
    func reportsAllProblems() throws {
        let catalog = Self.catalog(teamCategory: """
                TeamCategory:
                  type: string
                  enum: [alevin]
            """)

        #expect(throws: EnumNames.Problems([
            "TeamCategory: le falta x-enum-names",
            "TeamCategory: añádela a `filter: schemas` en openapi-generator-config.yaml, o el contrato no tendrá su tipo",
        ])) {
            try EnumNames.swiftSource(catalog: catalog, generatorConfig: Self.config(schemas: []))
        }
    }
}

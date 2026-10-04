import Testing
@testable import CensusCore

@Suite("Los campos del contrato: los que alcanza un cliente desde las respuestas 2xx (A-15·H-72)")
struct ContractFieldsTests {

    /// Un *spec* pequeño con todas las formas que tiene el real: `$ref` a
    /// esquemas y a respuestas, `allOf`, listas, un objeto anidado sin nombre, y
    /// un esquema compartido por dos operaciones.
    static var spec: [String: Any] { [
        "paths": [
            "/club": [
                "get": [
                    "operationId": "getClub",
                    "responses": [
                        "200": ["content": ["application/json": ["schema": ["$ref": "#/components/schemas/Club"]]]],
                        "404": ["content": ["application/problem+json": ["schema": ["$ref": "#/components/schemas/Problem"]]]],
                    ],
                ],
                "patch": [
                    "operationId": "updateClub",
                    "responses": ["200": ["$ref": "#/components/responses/ClubOK"]],
                ],
            ],
            "/runs": [
                "get": [
                    "operationId": "listRuns",
                    "responses": [
                        "200": ["content": ["application/json": ["schema": [
                            "type": "object",
                            "properties": [
                                "items": ["type": "array", "items": ["$ref": "#/components/schemas/Run"]],
                            ],
                        ]]]],
                    ],
                ],
            ],
            "/seasons": [
                "get": [
                    "operationId": "listSeasons",
                    "responses": ["200": ["content": ["application/json": ["schema": ["$ref": "#/components/schemas/Season"]]]]],
                ],
            ],
            "/jobs": [
                "post": [
                    "operationId": "enqueue",
                    "responses": ["202": ["content": ["application/json": ["schema": ["$ref": "#/components/schemas/Job"]]]]],
                ],
            ],
        ],
        "components": [
            "responses": [
                "ClubOK": ["content": ["application/json": ["schema": ["$ref": "#/components/schemas/Club"]]]],
            ],
            "schemas": [
                "Club": ["type": "object", "properties": ["name": ["type": "string"], "crestUrl": ["type": "string"]]],
                "Run": ["allOf": [
                    ["$ref": "#/components/schemas/RunBase"],
                    ["type": "object", "properties": [
                        "counters": ["type": "object", "properties": ["created": ["type": "integer"]]],
                    ]],
                ]],
                "RunBase": ["type": "object", "properties": ["id": ["type": "string"], "outcome": ["type": "string"]]],
                "Season": ["type": "object", "properties": ["label": ["type": "string"]]],
                "Job": ["type": "object", "properties": ["jobId": ["type": "string"]]],
                "Problem": ["type": "object", "properties": ["code": ["type": "string"]]],
            ],
        ],
    ] }

    static func field(_ text: String) -> ContractField {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        return ContractField(owner: parts.dropLast().joined(separator: "."), property: parts.last!)
    }

    @Test("solo las operaciones del filter, solo sus 2xx: ni `Problem` ni `Season` entran")
    func onlyFilteredSuccessResponses() throws {
        let fields = try reachableFields(spec: Self.spec, operations: ["getClub"])
        #expect(fields == [Self.field("Club.name"), Self.field("Club.crestUrl")])
    }

    @Test("un 202 también es una respuesta 2xx: el enganche y el disparador responden así (D-67)")
    func acceptedResponsesCount() throws {
        let fields = try reachableFields(spec: Self.spec, operations: ["enqueue"])
        #expect(fields == [Self.field("Job.jobId")])
    }

    /// Sola, y no junto a `getClub`: acompañada, `getClub` aporta los mismos dos
    /// campos y no se nota si ésta deja de aportar nada (la mutación `K5` lo
    /// enseñó sobreviviendo al test de abajo).
    @Test("una respuesta que es `$ref` a `components/responses` también se recorre")
    func sharedResponseIsResolved() throws {
        let fields = try reachableFields(spec: Self.spec, operations: ["updateClub"])
        #expect(fields == [Self.field("Club.name"), Self.field("Club.crestUrl")])
    }

    @Test("un esquema que devuelven dos operaciones cuenta sus campos una vez, también por `components/responses`")
    func sharedSchemaCountsOnce() throws {
        let fields = try reachableFields(spec: Self.spec, operations: ["getClub", "updateClub"])
        #expect(fields.count == 2)
    }

    @Test("se sigue `$ref`, `allOf`, `items` y el objeto anidado, que se nombra por su ruta")
    func walksEveryShape() throws {
        let fields = try reachableFields(spec: Self.spec, operations: ["listRuns"])
        #expect(fields == [
            Self.field("listRuns.200.items"),
            Self.field("RunBase.id"), Self.field("RunBase.outcome"),
            Self.field("Run.counters"), Self.field("Run.counters.created"),
        ])
    }

    @Test("una operación del filter que no está en el spec es un error, no un censo más corto")
    func unknownOperationThrows() {
        #expect(throws: SpecError.operationNotFound("noExiste")) {
            try reachableFields(spec: Self.spec, operations: ["getClub", "noExiste"])
        }
    }

    @Test("un `$ref` que no resuelve es un error, no un esquema vacío")
    func unresolvedReferenceThrows() {
        var spec = Self.spec
        spec["paths"] = ["/x": ["get": ["operationId": "x", "responses": [
            "200": ["content": ["application/json": ["schema": ["$ref": "#/components/schemas/Nada"]]]],
        ]]]]
        #expect(throws: SpecError.unresolvedReference("#/components/schemas/Nada")) {
            try reachableFields(spec: spec, operations: ["x"])
        }
    }

    @Test("un test nombra la propiedad como miembro o como clave, con la palabra entera")
    func propertyMentions() {
        let tests = [SourceFile(path: "T.swift", text: """
            #expect(standings.roundId == "x")
            let json = ["crestUrl": 1]
            #expect(run.outcomeLabel == nil)
            """)]
        #expect(mentions(property: "roundId", in: tests))
        #expect(mentions(property: "crestUrl", in: tests))
        #expect(!mentions(property: "outcome", in: tests), "`outcomeLabel` no nombra `outcome`")
        #expect(!mentions(property: "round", in: tests), "`roundId` no nombra `round`")
    }

    /// **El fallo del estreno.** Con el `\b` de Unicode (UAX #29) un punto entre
    /// dos letras **no separa palabras** —es lo que hace de "e.g." una sola—, así
    /// que `.competition` seguido de `.ageCategory` no casaba, y el censo daba por
    /// no nombrados campos que los tests sí leen (`preview.competition…`, medido
    /// contra `FederationLinkEndpointTests`).
    @Test("un miembro seguido de otro miembro también cuenta: `preview.competition.ageCategory`")
    func chainedMemberAccess() {
        let tests = [SourceFile(path: "T.swift", text: """
            #expect(preview.competition.ageCategory.value1 == .cadete)
            """)]
        #expect(mentions(property: "competition", in: tests))
        #expect(mentions(property: "ageCategory", in: tests))
        #expect(!mentions(property: "age", in: tests))
    }
}

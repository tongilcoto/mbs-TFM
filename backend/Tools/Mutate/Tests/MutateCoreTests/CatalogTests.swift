import Foundation
import Testing
@testable import MutateCore

@Suite("El catálogo: lo que hace citable una cifra (A-15·H-52)")
struct CatalogTests {

    func decode(_ json: String) throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(json.utf8))
    }

    @Test("un solo cambio se escribe con `find` y `replace` sueltos")
    func shorthand() throws {
        let catalog = try decode("""
            {"title": "T", "mutations": [
              {"id": "M1", "description": "d", "file": "f", "find": "a", "replace": "b"}]}
            """)
        #expect(catalog.mutations[0].edits == [Edit(find: "a", replace: "b")])
    }

    @Test("varios cambios, con `edits`")
    func editsList() throws {
        let catalog = try decode("""
            {"title": "T", "mutations": [
              {"id": "M1", "description": "d", "file": "f",
               "edits": [{"find": "a", "replace": "b"}, {"find": "c", "replace": "d"}]}]}
            """)
        #expect(catalog.mutations[0].edits.count == 2)
    }

    @Test("las dos formas a la vez no: no se sabría cuál manda")
    func bothFormsRejected() {
        #expect(throws: DecodingError.self) {
            try decode("""
                {"title": "T", "mutations": [
                  {"id": "M1", "description": "d", "file": "f", "find": "a", "replace": "b",
                   "edits": [{"find": "c", "replace": "d"}]}]}
                """)
        }
    }

    @Test("un `find` sin `replace` no es media mutación: es un error")
    func halfAMutation() {
        #expect(throws: DecodingError.self) {
            try decode("""
                {"title": "T", "mutations": [{"id": "M1", "description": "d", "file": "f", "find": "a"}]}
                """)
        }
    }

    @Test("el filtro de la mutación manda sobre el del catálogo")
    func filterInheritance() throws {
        let catalog = try decode("""
            {"title": "T", "filter": "Todos", "mutations": [
              {"id": "M1", "description": "d", "file": "f", "find": "a", "replace": "b"},
              {"id": "M2", "description": "d", "file": "f", "find": "a", "replace": "b", "filter": "Uno"}]}
            """)
        #expect(catalog.filter(for: catalog.mutations[0]) == "Todos")
        #expect(catalog.filter(for: catalog.mutations[1]) == "Uno")
    }

    @Test("un id repetido, una búsqueda vacía o un catálogo vacío no validan")
    func validation() {
        let edit = Edit(find: "a", replace: "b")
        let repeated = Catalog(title: "T", mutations: [
            Mutation(id: "M1", description: "", file: "f", edits: [edit]),
            Mutation(id: "M1", description: "", file: "f", edits: [Edit(find: "", replace: "b")]),
        ])
        #expect(throws: CatalogError(problems: [
            "el id M1 se repite", "M1: el cambio 1 no busca nada",
        ])) { try repeated.validate() }
        #expect(throws: CatalogError.self) { try Catalog(title: "T", mutations: []).validate() }
    }
}

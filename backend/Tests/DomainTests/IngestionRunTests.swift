import Foundation
import Testing

@testable import Domain

/// Nivel 1 (§8.1): el registro de una pasada de ingesta (`D-85`).
@Suite("IngestionRun · D-85 · el registro de una pasada")
struct IngestionRunTests {

    static func run(
        kind: IngestionKind = .calendar,
        started: TimeInterval = 0, finished: TimeInterval = 60,
        outcome: IngestionOutcome = .succeeded, error: String? = nil
    ) throws -> IngestionRun {
        try IngestionRun(
            id: IngestionRunID(raw: UUID()),
            competitionID: CompetitionID(raw: UUID()), kind: kind,
            startedAt: Date(timeIntervalSince1970: started),
            finishedAt: Date(timeIntervalSince1970: finished),
            outcome: outcome, error: error)
    }

    @Test("la clase de pasada viaja y se conserva (F7)")
    func thekindIsCarried() throws {
        // Sin esto, dos filas de la misma competición y la misma hora son
        // indistinguibles, y los ocho contadores del calendario a cero en la de
        // clasificación se leen como "no hizo nada" en vez de "no van con esto".
        #expect(try Self.run(kind: .standings).kind == .standings)
        #expect(try Self.run().kind == .calendar)
    }

    @Test("`timed` conserva la clase y los contadores de clasificación (F7)")
    func timedCarriesTheNewFields() throws {
        // `timed` copia campo a campo, así que es el sitio exacto donde un campo
        // nuevo se pierde en silencio: el `init` no se queja porque tiene valor
        // por defecto, y la fila sale con un cero que parece un dato.
        var run = try Self.run(kind: .standings)
        run.standingRowsCreated = 400
        run.standingRowsUpdated = 16

        let timed = try run.timed(
            from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 90))

        #expect(timed.kind == .standings)
        #expect(timed.standingRowsCreated == 400)
        #expect(timed.standingRowsUpdated == 16)
    }

    /// El par que el esquema ata con un `CHECK` y el tipo ata aquí: **una pasada
    /// que falló y no dice por qué no se puede depurar**, que es justo lo único
    /// para lo que existe la tabla.
    ///
    /// Este test lo pidió la comprobación de mutación: quitar la guarda no tumbaba
    /// nada. Las dos lecturas de una mutación superviviente son *"falta un test"*
    /// y *"sobra el código"*; aquí es la primera — la guarda es la mitad de
    /// dominio de una regla cuya otra mitad es el `CHECK` de la migración, como
    /// los enumerados de `D-02`.
    @Test("una pasada fallida tiene que decir por qué (D-85)")
    func failedRunNeedsAReason() {
        #expect(throws: DomainError.self) {
            try Self.run(outcome: .failed, error: nil)
        }
    }

    /// Y el reverso: un éxito con motivo de fallo es una contradicción, no un
    /// campo de sobra. Sin este, la guarda de arriba se podría escribir como
    /// *"pon siempre un motivo"* y pasaría igual.
    @Test("una pasada con éxito no lleva motivo de fallo (D-85)")
    func succeededRunCarriesNoReason() {
        #expect(throws: DomainError.self) {
            try Self.run(outcome: .succeeded, error: "algo")
        }
    }

    /// El equivalente de la invariante de `Round` (§3.2): un intervalo al revés
    /// no es un intervalo.
    @Test("una pasada no puede acabar antes de empezar (D-85)")
    func rejectsInvertedInterval() {
        #expect(throws: DomainError.self) {
            try Self.run(started: 60, finished: 0)
        }
    }

    /// Los dos casos buenos, para que las tres guardas de arriba no se puedan
    /// satisfacer rechazándolo todo.
    @Test("los dos desenlaces bien formados se construyen (D-85)")
    func wellFormedRunsAreAccepted() throws {
        #expect(try Self.run().succeeded)
        #expect(try Self.run(outcome: .failed, error: "la fuente devolvió otra competición")
                    .succeeded == false)
    }
}

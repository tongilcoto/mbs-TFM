import Application
import Domain
import Foundation
import Testing

@testable import App

/// Nivel 1 sobre el adaptador primario: **el parseo de argumentos es lógica
/// pura**, así que se prueba sin Docker y sin `Application` — igual que
/// `HostSlugExtractor` (§8.1: *"si un componente no hace I/O, se prueba sin él,
/// esté donde esté"*).
///
/// Existe porque la comprobación de mutación lo pidió: romper el `--competition`
/// para que solo cogiera el primer valor **no tumbaba nada**. Los tests del
/// recorrido pasan la lista ya construida, así que entre la cadena que teclea el
/// operador y el `IngestionScope` no había nadie mirando.
@Suite("IngestCommand · los argumentos de lista")
struct IngestArgumentsTests {

    @Test("una opción con comas es una lista (D-88)")
    func commasSeparateValues() {
        #expect(IngestCommand.list("atleti,galapagar") == ["atleti", "galapagar"])
        #expect(IngestCommand.list("c4a1,9b77,3e02").count == 3)
    }

    @Test("un solo valor sigue siendo una lista de uno")
    func aSingleValueIsStillAList() {
        #expect(IngestCommand.list("atleti") == ["atleti"])
    }

    @Test("los espacios alrededor de la coma no forman parte del valor")
    func whitespaceIsTrimmed() {
        // `-t "atleti, galapagar"` es lo que sale de copiar y pegar, y un slug
        // con un espacio delante no encuentra a nadie en `public.tenants`.
        #expect(IngestCommand.list("atleti, galapagar") == ["atleti", "galapagar"])
        #expect(IngestCommand.list(" atleti , galapagar ") == ["atleti", "galapagar"])
    }

    @Test("una coma de más no produce un valor vacío")
    func emptySegmentsAreDropped() {
        // Un valor vacío llegaría al filtro como un slug `""` o, peor, a
        // `UUID(uuidString:)` como un id inválido: un error de puntuación
        // convertido en un error del operador.
        #expect(IngestCommand.list("atleti,,galapagar") == ["atleti", "galapagar"])
        #expect(IngestCommand.list("atleti,") == ["atleti"])
    }

    // ── De la línea de comandos al ámbito del caso de uso ────────────────────

    @Test("`-c` con comas se convierte en varias competiciones (D-88)")
    func severalCompetitionsReachTheScope() throws {
        let a = UUID(), b = UUID()
        let scope = try IngestCommand.scope(
            season: nil, competition: "\(a),\(b)", minIntervalHours: nil, force: false)

        #expect(scope.competitionIDs?.map(\.raw) == [a, b])
    }

    @Test("`--force` gana sobre `--min-interval-hours` (D-87)")
    func forceBeatsTheGuard() throws {
        let scope = try IngestCommand.scope(
            season: nil, competition: nil, minIntervalHours: 24, force: true)

        // Es una precedencia que el `--help` no puede explicar y que, puesta al
        // revés, haría que `--force` no forzara nada.
        #expect(scope.minInterval == nil)
    }

    @Test("sin `--min-interval-hours` el antirrebote son 6 horas (D-87)")
    func theDefaultGuardIsSixHours() throws {
        let byDefault = try IngestCommand.scope(
            season: nil, competition: nil, minIntervalHours: nil, force: false)
        let explicit = try IngestCommand.scope(
            season: nil, competition: nil, minIntervalHours: 24, force: false)

        // Seis horas está muy por debajo del hueco más corto de la cadencia de
        // §5.6 (28 h), que es lo que hace que nunca suprima una pasada legítima.
        //
        // **El `Double(...)` no sobra.** Escrito `== 6 * 3600` esta aserción
        // **falla**, e imprimiendo `21600.0 == 21600` — los dos valores iguales.
        // El literal entero contra un `TimeInterval?` no compara lo que parece.
        // No "simplificar" quitándolo: se convierte en un test que no puede pasar.
        #expect(byDefault.minInterval == Double(6 * 3600))
        #expect(explicit.minInterval == Double(24 * 3600))
    }

    @Test("un UUID mal escrito se rechaza diciendo qué opción era")
    func aMalformedUUIDIsRejected() {
        #expect(throws: IngestionArgumentError.self) {
            try IngestCommand.scope(
                season: "no-soy-un-uuid", competition: nil, minIntervalHours: nil, force: false)
        }
        #expect(throws: IngestionArgumentError.self) {
            try IngestCommand.scope(
                season: nil, competition: "\(UUID()),roto", minIntervalHours: nil, force: false)
        }
    }
}

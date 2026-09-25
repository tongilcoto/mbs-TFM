import Foundation
import Testing

@testable import Domain

/// Nivel 1 (§8.1): el registro de una pasada de ingesta (`D-85`).
@Suite("IngestionRun · D-85 · el registro de una pasada")
struct IngestionRunTests {

    static func run(
        kind: IngestionKind = .calendar,
        roundID: RoundID? = nil,
        started: TimeInterval = 0, finished: TimeInterval? = 60,
        outcome: IngestionOutcome = .succeeded, error: String? = nil
    ) throws -> IngestionRun {
        try IngestionRun(
            id: IngestionRunID(raw: UUID()),
            competitionID: CompetitionID(raw: UUID()), kind: kind,
            roundID: roundID ?? (kind == .standings ? RoundID(raw: UUID()) : nil),
            startedAt: Date(timeIntervalSince1970: started),
            finishedAt: finished.map { Date(timeIntervalSince1970: $0) },
            outcome: outcome, error: error)
    }

    // ── C-A.4 · el tercer caso, y el `default` que lo habría dejado pasar ────

    /// **`D-96`: el `202` deja fila desde que se acepta.** `accepted` es el
    /// estado previo al desenlace — la pasada está pedida y todavía no ha
    /// corrido—, así que **no puede traer motivo de fallo**: no ha tenido ocasión
    /// de fallar. Es la misma contradicción que `(.succeeded, _?)` y merece el
    /// mismo trato.
    ///
    /// # La ironía que este test conserva a propósito
    ///
    /// Catorce líneas más arriba, en el mismo `init`, el `switch` de
    /// `kind`/`roundID` lleva escrito el riesgo con todas las letras: *"con un
    /// `default`, el caso que añada la fase siguiente entraría por él y aceptaría
    /// una jornada en silencio"*. El `switch` de al lado —éste— **no lo
    /// aplicó**, y se quedó con su `default: break`.
    ///
    /// **La fase siguiente llegó.** Sin nombrar los tres casos, una pasada
    /// `accepted` con un motivo de fallo dentro entra por el `default`, se
    /// escribe, y llega al backoffice diciendo a la vez *"todavía no ha corrido"*
    /// y *"falló por esto"*.
    @Test("una pasada aceptada no ha tenido ocasión de fallar: no lleva motivo (D-96)")
    func anAcceptedRunCannotCarryAnError() {
        #expect(throws: DomainError.invalidValue(
            field: "error",
            reason: "una pasada aceptada todavía no ha corrido: no lleva motivo de fallo"
        )) {
            // `finished: nil` para que lo que falle sea **esta** regla y no la
            // de `C-A.5`, que llegó después y se dispara antes.
            try Self.run(finished: nil, outcome: .accepted, error: "la RFFM no contesta")
        }
    }

    /// El otro lado, que es el camino normal del `202`: aceptada y sin motivo.
    @Test("la pasada que el 202 deja escrita es válida sin motivo (D-96)")
    func anAcceptedRunIsValidWithoutAnError() throws {
        // `finished: nil` lo trajo `C-A.5`: cuando este test se escribió, la
        // regla de que una aceptada no tiene fin todavía no existía.
        let accepted = try Self.run(finished: nil, outcome: .accepted)

        #expect(accepted.outcome == .accepted)
        #expect(accepted.error == nil)
        #expect(!accepted.succeeded)
    }

    // ── C-A.5 · una aceptada no tiene fin, y la invariante no aplica ─────────

    /// **`D-96`, y la alternativa que descartó.** La salida fácil era
    /// `finishedAt = startedAt` provisional, y es *"una fila que miente"* — el
    /// defecto exacto que F6 encontró mirando la tabla de verdad: toda pasada con
    /// éxito registraba duración cero y **la invariante no lo delataba**, porque
    /// `finishedAt >= startedAt` se cumple trivialmente cuando son iguales.
    /// Repetirlo aquí sería reintroducirlo a sabiendas.
    @Test("una pasada aceptada no tiene fin: todavía no ha corrido (D-96)")
    func anAcceptedRunHasNoFinish() throws {
        let accepted = try Self.run(finished: nil, outcome: .accepted)

        #expect(accepted.finishedAt == nil)
    }

    /// El otro lado de la pareja, y hace falta igual que en la jornada: sin él, el
    /// nulo dejaría de significar *"aceptada"* y pasaría a significar *"a saber"*.
    @Test("una pasada que ya acabó tiene que decir cuándo (D-96)")
    func aTerminatedRunMustSayWhenItFinished() {
        #expect(throws: DomainError.invalidValue(
            field: "finishedAt",
            reason: "una pasada que ya acabó tiene que decir cuándo"
        )) {
            try Self.run(finished: nil, outcome: .succeeded)
        }
    }

    /// Y el reverso: una aceptada **con** fin es la misma contradicción por el
    /// otro lado — dice que no ha corrido y a la vez cuándo terminó.
    @Test("una pasada aceptada con fecha de fin se contradice (D-96)")
    func anAcceptedRunCannotCarryAFinish() {
        #expect(throws: DomainError.invalidValue(
            field: "finishedAt",
            reason: "una pasada aceptada todavía no ha acabado"
        )) {
            try Self.run(outcome: .accepted)
        }
    }

    // ── C-A.6 · cerrar la aceptada (D-96) ───────────────────────────────────

    /// El desenlace que el `202` prometió: la pasada corre, termina bien, y la
    /// fila que ya existía **se cierra** en vez de aparecer una segunda.
    ///
    /// **`startedAt` no se toca, y es una decisión, no un descuido.** Es el
    /// instante en que el administrador lo pidió — lo que el `202` le dejó para
    /// consultar— y es la clave por la que el registro ordena (`C-D.6`). Moverlo
    /// al arranque real del job haría que la fila saltara de sitio en la lista
    /// justo cuando alguien la está mirando.
    @Test("una aceptada se cierra con éxito y conserva cuándo se pidió (D-96)")
    func anAcceptedRunClosesAsSucceeded() throws {
        var accepted = try Self.run(finished: nil, outcome: .accepted)
        accepted.matchesCreated = 240

        let closed = try accepted.closed(
            as: .succeeded, at: Date(timeIntervalSince1970: 90))

        #expect(closed.outcome == .succeeded)
        #expect(closed.finishedAt == Date(timeIntervalSince1970: 90))
        #expect(closed.startedAt == accepted.startedAt)
        #expect(closed.id == accepted.id)
        #expect(closed.matchesCreated == 240)
    }

    /// El otro desenlace, con su motivo — que el `init` ya exige (`D-85`).
    @Test("una aceptada se cierra como fallida diciendo por qué (D-96, D-85)")
    func anAcceptedRunClosesAsFailed() throws {
        let accepted = try Self.run(finished: nil, outcome: .accepted)

        let closed = try accepted.closed(
            as: .failed, at: Date(timeIntervalSince1970: 90),
            error: "la RFFM devolvió 503")

        #expect(closed.outcome == .failed)
        #expect(closed.error == "la RFFM devolvió 503")
        #expect(closed.finishedAt == Date(timeIntervalSince1970: 90))
    }

    /// **Solo se cierra lo que está abierto.** Cerrar una pasada ya terminada
    /// reescribiría cuándo acabó, que es un dato que ya se sirvió por el `GET`:
    /// la fila diría otra cosa que hace un minuto sin que nada haya pasado. Es la
    /// misma familia que `C-A.2` — una transición sale de **un** estado.
    @Test("una pasada ya cerrada no se vuelve a cerrar (D-96)")
    func aClosedRunDoesNotCloseAgain() throws {
        let finished = try Self.run(outcome: .succeeded)

        #expect(throws: DomainError.invalidValue(
            field: "outcome", reason: "solo se cierra una pasada aceptada"
        )) {
            try finished.closed(as: .failed, at: Date(timeIntervalSince1970: 90),
                                error: "tarde")
        }
    }

    /// Y no se cierra **a** `accepted`: eso no es cerrar, es volver a abrir.
    @Test("cerrar a «aceptada» no es cerrar (D-96)")
    func closingToAcceptedIsNotClosing() throws {
        let accepted = try Self.run(finished: nil, outcome: .accepted)

        #expect(throws: DomainError.invalidValue(
            field: "outcome", reason: "cerrar es acabar: ni con éxito ni con fallo no es un desenlace"
        )) {
            try accepted.closed(as: .accepted, at: Date(timeIntervalSince1970: 90))
        }
    }

    // ── La pareja de la jornada (F7) ─────────────────────────────────────────

    @Test("una pasada de clasificación tiene que decir de qué jornada es")
    func astandingsRunNeedsARound() {
        // Sin esto, las diez de un alta en la jornada 10 serían **diez filas
        // idénticas**: misma competición, misma clase, misma hora. Es el agujero
        // que F7 destapa, no un campo nuevo.
        #expect(throws: DomainError.invalidValue(
            field: "roundID", reason: "una pasada de clasificación es de una jornada")) {
            try IngestionRun(
                id: IngestionRunID(raw: UUID()),
                competitionID: CompetitionID(raw: UUID()), kind: .standings,
                roundID: nil,
                startedAt: Date(timeIntervalSince1970: 0),
                finishedAt: Date(timeIntervalSince1970: 60))
        }
    }

    @Test("la del calendario NO lleva jornada, y eso también se comprueba")
    func acalendarRunMustNotCarryARound() {
        // El otro lado de la pareja, y hace falta igual: el calendario es de la
        // **competición entera** —su endpoint la devuelve en una petición— así
        // que ponerle una jornada sería escribir algo que no es verdad. Sin este
        // test, una guarda que solo mirase el caso de arriba dejaría pasar la
        // mentira por el otro lado.
        #expect(throws: DomainError.self) {
            try IngestionRun(
                id: IngestionRunID(raw: UUID()),
                competitionID: CompetitionID(raw: UUID()), kind: .calendar,
                roundID: RoundID(raw: UUID()),
                startedAt: Date(timeIntervalSince1970: 0),
                finishedAt: Date(timeIntervalSince1970: 60))
        }
    }

    @Test("los dos casos buenos se construyen")
    func bothValidShapesAreAccepted() throws {
        #expect(try Self.run(kind: .calendar).roundID == nil)
        #expect(try Self.run(kind: .standings).roundID != nil)
    }

    /// **Era un test de `timed(from:to:)` y ahora lo es de `closed(as:at:)`**
    /// (F10-bis): la función se quitó por quedarse sin llamantes, pero lo que
    /// este test afirma **no era de ella** — es de la copia, y la copia sigue
    /// estando en `closed`. Borrarlo con la función habría tirado la guarda junto
    /// con lo guardado.
    ///
    /// Cerrar reconstruye por el `init`, así que un campo que no se copie se
    /// pierde — y aquí perderlo no daría un cero silencioso: haría **lanzar** al
    /// propio `init`, porque la pareja `kind`/`roundID` no cuadraría. Vale como
    /// prueba de que la guarda de arriba también protege la copia.
    @Test("cerrar conserva la jornada (F7, F10-bis)")
    func closingCarriesTheRound() throws {
        let run = try Self.run(kind: .standings, finished: nil, outcome: .accepted)
        let closed = try run.closed(as: .succeeded, at: Date(timeIntervalSince1970: 90))
        #expect(closed.roundID == run.roundID)
    }

    @Test("la clase de pasada viaja y se conserva (F7)")
    func thekindIsCarried() throws {
        // Sin esto, dos filas de la misma competición y la misma hora son
        // indistinguibles, y los ocho contadores del calendario a cero en la de
        // clasificación se leen como "no hizo nada" en vez de "no van con esto".
        #expect(try Self.run(kind: .standings).kind == .standings)
        #expect(try Self.run().kind == .calendar)
    }

    /// El hermano del de arriba, y el que de verdad vigila a `carryCounters`:
    /// copia campo a campo, así que **es el sitio exacto donde un campo nuevo se
    /// pierde en silencio** — el `init` no se queja porque tiene valor por
    /// defecto, y la fila sale con un cero que parece un dato.
    ///
    /// También era de `timed` hasta F10-bis, por lo mismo que su vecino.
    @Test("cerrar conserva la clase y los contadores de clasificación (F7, F10-bis)")
    func closingCarriesTheNewFields() throws {
        var run = try Self.run(kind: .standings, finished: nil, outcome: .accepted)
        run.standingRowsCreated = 400
        run.standingRowsUpdated = 16

        let closed = try run.closed(as: .succeeded, at: Date(timeIntervalSince1970: 90))

        #expect(closed.kind == .standings)
        #expect(closed.standingRowsCreated == 400)
        #expect(closed.standingRowsUpdated == 16)
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

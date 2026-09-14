import Application
import Domain
import Foundation
import Testing

@testable import App

/// Nivel 1 sobre el adaptador primario: **el freno del recorrido de clubes es
/// una regla pura**, así que se prueba sin Docker y sin `Application` — igual
/// que `IngestArgumentsTests`, y por el mismo motivo de §8.1 (*"si un componente
/// no hace I/O, se prueba sin él, esté donde esté"*).
///
/// # Por qué existe esta suite (F6-ter, `A-7`/H-45)
///
/// `D-86` enmendada tiene **dos** frenos y hasta A-7 solo uno estaba probado. El
/// de dentro de un club —entre competiciones— lo guarda
/// `aDatabaseOutageStopsTheTraversal`, que A-3 mutó. El de **entre clubes** vivía
/// en catorce líneas de `IngestCommand.ingest` que **ningún test alcanzaba**: la
/// unidad de trabajo se construye ahí dentro desde `app.db(.control)` y no es
/// inyectable, y provocar el fallo de verdad exigiría parar Postgres a mitad de
/// un test. Mutar el `break` del `catch` no tumbaba nada.
///
/// Lo que la fase hizo es lo que el fichero ya sabía hacer catorce líneas más
/// abajo: `incomplete(outcomes)` está separado de `run` *"porque es la regla —no
/// el `print`— y probarla no puede exigir montar una consola"*. Aquí es lo mismo
/// con una consola cambiada por un Postgres.
///
/// **Las cuatro aserciones son dos pares, y los dos lados importan.** `D-86` es
/// una decisión con dos mitades inseparables —*"se continúa y se apunta"*, y
/// *"se para cuando no se puede apuntar"*—, así que probar solo que se para
/// dejaría pasar un freno que frena siempre: un `break` incondicional convierte
/// la resiliencia de `D-86` en lo que había antes de ella.
@Suite("IngestCommand · el freno del recorrido de clubes (D-86)")
struct IngestTraversalStopTests {

    static let slug = try! Slug("atleti")

    static func report(
        aborted: Bool = false, failures: Bool = false
    ) -> ClubIngestionReport {
        var report = ClubIngestionReport(clubSlug: slug, federation: .rffm)
        if failures {
            report.entries.append(
                ClubIngestionReport.Entry(
                    competitionID: CompetitionID(raw: UUID()),
                    outcome: .failed("la federación no contestó")))
        }
        report.abortedByInfrastructure = aborted
        return report
    }

    // ── Freno 1 · el club que se paró a sí mismo ─────────────────────────────

    @Test("un club que abortó por infraestructura para el recorrido (D-86, H-23)")
    func anInfrastructureAbortStopsTheTraversal() {
        // `abortedByInfrastructure` significa que la base dejó de responder
        // **dentro** del club, y el *pool*, la conexión y el Postgres son uno
        // solo (§6.4): probar con el siguiente club no es resiliencia, son N
        // recorridos que tampoco van a poder dejar constancia (`D-85`).
        #expect(IngestCommand.stopsTraversal(.success(Self.report(aborted: true))))
    }

    @Test("un club con competiciones fallidas no para el recorrido (D-86)")
    func failedCompetitionsDoNotStopTheTraversal() {
        // Es la mitad *"se continúa"* de `D-86`, y es la que hace falta que no
        // se rompa al escribir la otra: una competición fallida **sí** dejó su
        // fila en `ingestion_runs`, así que el club siguiente tiene todo lo que
        // necesita para intentarlo.
        #expect(IngestCommand.stopsTraversal(.success(Self.report(failures: true))) == false)
        #expect(IngestCommand.stopsTraversal(.success(Self.report())) == false)
    }

    // ── Freno 2 · el club que ni llegó a recorrerse ──────────────────────────

    @Test("`databaseUnavailable` para el recorrido (D-86 enmendada, H-45)")
    func aDatabaseOutageStopsTheTraversal() {
        // El ámbito 1 —el plan— es el primero que puede enterarse de que la base
        // no está, y lo dice con su nombre en vez de dejar salir un error de
        // conexión en crudo (`IngestClubCalendars`). Este es el otro extremo de
        // ese par: hasta F6-ter, que los dos *targets* estuvieran de acuerdo no
        // lo comprobaba nada.
        #expect(IngestCommand.stopsTraversal(.failure(ApplicationError.databaseUnavailable)))
    }

    @Test("cualquier otro fallo de un club no para el recorrido (D-86, D-17)")
    func anyOtherFailureDoesNotStopTheTraversal() {
        // Un club sin adaptador (`D-17`, la FCF hasta F9) o con el *schema* sin
        // aprovisionar es un fallo **de ese club**. Frenar aquí sería dejar sin
        // sincronizar a todos los que van detrás por orden alfabético, que es
        // exactamente lo que `D-86` existe para evitar.
        #expect(
            IngestCommand.stopsTraversal(
                .failure(ApplicationError.federationAdapterMissing(federation: "fcf"))) == false)
        #expect(
            IngestCommand.stopsTraversal(
                .failure(ApplicationError.tenantNotProvisioned(slug: "atleti"))) == false)
        // Y un error que no es ni de la Aplicación: lo que llega de Fluent o de
        // la red cuando el club falla por su cuenta.
        #expect(IngestCommand.stopsTraversal(.failure(SomeoneElsesProblem())) == false)
    }

    struct SomeoneElsesProblem: Error {}
}

import Application
import Domain
import Foundation
import Testing

@testable import App

/// Nivel 1 sobre el adaptador primario: **el recorrido vacío**, sin Docker, por
/// el mismo motivo que `IngestTraversalStopTests`: es una regla pura sobre el
/// informe, y probarla no puede exigir una consola ni un Postgres.
///
/// # Por qué existe esta suite (Plan launchd `DL-2`, A-11·H-59)
///
/// Con la base de trabajo sin temporada vigente, `ingest` decía *"0
/// competición(es) sincronizada(s), 0 con fallo"* y salía con `0`: **un verde que
/// no acumula un solo dato**, cada semana, sin nadie mirando. Pero esa misma línea
/// la da también el disparo de más que encontró todo reciente, que es legítimo
/// (`D-87`). Lo que los separa es `skippedByDebounce`, y lo que convierte el
/// primero en un código de salida es `--fail-if-empty`.
///
/// **El *flag* es opcional a propósito**: quien lanza `ingest` a mano sobre un
/// club recién dado de alta, sin temporada, no ha hecho nada mal. Es el disparo
/// desatendido —`launchd`— el que no tiene a nadie delante para notarlo.
@Suite("IngestCommand · el recorrido vacío (Plan launchd DL-2, H-59)")
struct IngestEmptyTraversalTests {

    static let slug = try! Slug("atleti")

    static func outcome(
        _ slug: String = "atleti",
        skipped: Int = 0, failures: Bool = false, aborted: Bool = false
    ) -> TenantIngestion {
        var report = ClubIngestionReport(clubSlug: Self.slug, federation: .rffm)
        if failures {
            report.entries.append(
                ClubIngestionReport.Entry(
                    competitionID: CompetitionID(raw: UUID()),
                    outcome: .failed("la federación no contestó")))
        }
        report.skippedByDebounce = skipped
        report.abortedByInfrastructure = aborted
        return TenantIngestion(slug: slug, report: report, error: nil)
    }

    @Test("sin nada recorrido ni saltado, el club está vacío (DL-2, H-59)")
    func nothingTraversedNorSkippedIsEmpty() {
        #expect(Self.outcome().isEmpty)
    }

    @Test("lo saltado por el antirrebote, lo fallido y lo abortado no son vacío (DL-2, D-87)")
    func skippedFailedOrAbortedIsNotEmpty() {
        // El disparo de más: lo encontró todo reciente y no pidió nada. Es lo
        // que `D-87` hace inofensivo, y dar rojo por él convertiría cada
        // segundo disparo en una alarma.
        #expect(Self.outcome(skipped: 2).isEmpty == false)
        // Lo fallido ya es rojo por su cuenta (`D-86`); llamarlo además vacío
        // daría dos motivos para un solo fallo.
        #expect(Self.outcome(failures: true).isEmpty == false)
        // Lo abortado no llegó a mirar: no sabe si había algo que recorrer.
        #expect(Self.outcome(aborted: true).isEmpty == false)
        // Y el club que ni se recorrió ya es un fallo con su motivo.
        #expect(TenantIngestion(slug: "atleti", report: nil, error: "sin schema").isEmpty == false)
    }

    @Test("con `--fail-if-empty`, el club vacío cuenta como incompleto (DL-2)")
    func failIfEmptyMakesTheEmptyClubIncomplete() {
        let outcomes = [Self.outcome("otro", skipped: 3), Self.outcome("vacio")]
        #expect(IngestCommand.incomplete(outcomes, failIfEmpty: true) == ["vacio"])
    }

    @Test("sin `--fail-if-empty`, el club vacío sigue siendo verde (DL-2)")
    func withoutTheFlagTheEmptyClubIsStillASuccess() {
        // Es la mitad que protege a quien lo lanza a mano: un club recién
        // provisionado, sin temporada, no ha hecho nada mal.
        #expect(IngestCommand.incomplete([Self.outcome("vacio")]).isEmpty)
    }

    @Test("el resumen dice cuántas saltó el antirrebote (DL-2)")
    func theSummarySaysHowManyWereSkipped() {
        guard case .done(let line) = Self.outcome(skipped: 3).summary() else {
            Issue.record("un disparo de más no es un fallo")
            return
        }
        // Es lo que se lee en el log de `launchd` tres días después: sin la
        // cifra, *"0 sincronizadas"* no dice si fue un disparo de más o nada.
        #expect(line.contains("3 saltada(s) por el antirrebote"))
    }

    @Test("el resumen del club vacío lo dice, y es rojo solo con el flag (DL-2)")
    func theSummaryOfAnEmptyClubNamesIt() {
        guard case .failed(let red) = Self.outcome().summary(failIfEmpty: true) else {
            Issue.record("con el flag, el vacío tiene que salir como fallo")
            return
        }
        #expect(red.contains("nada que recorrer"))

        guard case .skipped(let warning) = Self.outcome().summary(failIfEmpty: false) else {
            Issue.record("sin el flag, el vacío es un aviso, no un éxito ni un fallo")
            return
        }
        #expect(warning.contains("nada que recorrer"))
    }
}

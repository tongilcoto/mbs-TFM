import Foundation
import Testing
@testable import Domain

/// Nivel 1 (§8.1): el estado de la ingesta de una competición (`D-89` con su
/// enmienda; Plan R1, decisión 2). **Un test por caso del orden**, con horas
/// distintas entre sí, para que cruzar dos fechas no pase por bueno.
@Suite("IngestionHealth · D-89 · el estado de la sincronización")
struct IngestionHealthTests {

    static let now = try! Date("2026-10-18T22:00:00Z", strategy: .iso8601)
    static let competition = CompetitionID(raw: UUID())

    static func minutesAgo(_ minutes: Double) -> Date {
        now.addingTimeInterval(-minutes * 60)
    }

    /// Una pasada. `finished` en minutos antes de ahora; `nil` ⇒ `accepted`.
    static func run(
        _ kind: IngestionKind, _ outcome: IngestionOutcome,
        started: Double, finished: Double?
    ) -> IngestionRun {
        try! IngestionRun(
            id: IngestionRunID(raw: UUID()), competitionID: competition, kind: kind,
            roundID: kind == .standings ? RoundID(raw: UUID()) : nil,
            startedAt: minutesAgo(started), finishedAt: finished.map(minutesAgo),
            outcome: outcome, error: outcome == .failed ? "FederationError" : nil)
    }

    static func assess(
        _ runs: [IngestionRun], lastSyncedAt: Date? = minutesAgo(60),
        clubLastFinishedAt: Date? = minutesAgo(50)
    ) -> IngestionHealthAssessment {
        IngestionHealth.assess(
            recentRuns: runs, lastSyncedAt: lastSyncedAt,
            clubLastFinishedAt: clubLastFinishedAt, now: now)
    }

    /// Una pasada de las tres clases, todas bien, hace una hora.
    static let allGood = [
        run(.calendar, .succeeded, started: 62, finished: 61),
        run(.standings, .succeeded, started: 61, finished: 60.5),
        run(.scorers, .succeeded, started: 60.5, finished: 60),
    ]

    // ── 6 · ok ──────────────────────────────────────────────────────────────

    @Test("6 · las tres clases bien y el éxito de hace una hora: al día")
    func everythingFineIsOk() {
        #expect(Self.assess(Self.allGood) == IngestionHealthAssessment(health: .ok))
    }

    @Test("una clase que la federación no publica no cuenta")
    func aMissingKindDoesNotCount() {
        let noScorers = Array(Self.allGood.prefix(2))
        #expect(Self.assess(noScorers).health == .ok)
    }

    // ── 3 · failing, la última fila de alguna clase ─────────────────────────

    /// El Alevín del 17/10: calendario y clasificación bien, goleadores mal (el
    /// `null` pasajero de la RFFM, H-61). Si solo contara el calendario, saldría
    /// al día.
    @Test("3 · el calendario bien y los goleadores mal: con fallos (el Alevín)")
    func aFailedKindMakesItFailing() {
        let runs = [
            Self.run(.calendar, .succeeded, started: 62, finished: 61),
            Self.run(.standings, .succeeded, started: 61, finished: 60.5),
            Self.run(.scorers, .failed, started: 60.5, finished: 60),
        ]
        #expect(Self.assess(runs) == IngestionHealthAssessment(health: .failing))
    }

    @Test("un fallo viejo que la pasada siguiente de su clase arregló ya no cuenta")
    func anOlderFailureFixedLaterDoesNotCount() {
        let runs = Self.allGood + [Self.run(.scorers, .failed, started: 300, finished: 299)]
        #expect(Self.assess(runs).health == .ok)
    }

    /// Se ordena por cuándo **empezó**: la de las 10:00 falló y acabó tarde; la de
    /// las 10:01 salió bien y acabó antes. La última es la de las 10:01.
    @Test("la última de cada clase es la que empezó más tarde, no la que acabó más tarde")
    func latestIsByStartNotByFinish() {
        let runs = [
            Self.run(.calendar, .succeeded, started: 62, finished: 61),
            Self.run(.standings, .failed, started: 40, finished: 30),
            Self.run(.standings, .succeeded, started: 39, finished: 38),
        ]
        #expect(Self.assess(runs).health == .ok)
    }

    // ── 4 · never ───────────────────────────────────────────────────────────

    @Test("4 · sin ningún éxito ni ningún fallo: sin datos todavía")
    func noSuccessYetIsNever() {
        #expect(Self.assess([], lastSyncedAt: nil) == IngestionHealthAssessment(health: .never))
    }

    @Test("3 antes que 4 · el calendario falló y nunca hubo éxito: con fallos, no «sin datos»")
    func failingComesBeforeNever() {
        let runs = [Self.run(.calendar, .failed, started: 30, finished: 29)]
        #expect(Self.assess(runs, lastSyncedAt: nil).health == .failing)
    }

    // ── 5 · stale ───────────────────────────────────────────────────────────

    @Test("5 · el último éxito, de hace ocho días: desactualizada")
    func anOldSuccessIsStale() {
        let eightDays: Double = 8 * 24 * 60
        let runs = [Self.run(.calendar, .succeeded, started: eightDays + 1, finished: eightDays)]
        #expect(Self.assess(runs, lastSyncedAt: Self.minutesAgo(eightDays)).health == .stale)
    }

    @Test("una semana justa todavía no es desactualizada: tiene que ser MÁS de una semana")
    func exactlyAWeekIsNotStaleYet() {
        let week: Double = 7 * 24 * 60
        let runs = [Self.run(.calendar, .succeeded, started: week + 1, finished: week)]
        #expect(Self.assess(runs, lastSyncedAt: Self.minutesAgo(week)).health == .ok)
    }

    // ── 2 · pending, y lo que había antes ───────────────────────────────────

    /// El reloj vuelve a cero con cualquier pasada del club que acabe: se pidió
    /// hace 40 minutos, pero otra pasada del club acabó hace 5. La cola avanza.
    @Test("2 · una pasada pedida hace 40 min con la cola avanzando: en marcha, y lo de antes iba bien")
    func anAcceptedRunWithAMovingQueueIsPending() {
        let runs = Self.allGood + [Self.run(.calendar, .accepted, started: 40, finished: nil)]
        #expect(Self.assess(runs, clubLastFinishedAt: Self.minutesAgo(5))
                == IngestionHealthAssessment(health: .pending, previous: .ok))
    }

    @Test("2 · en marcha, y la anterior tuvo fallos (decisión 2)")
    func pendingKeepsThePreviousFailure() {
        let runs = [
            Self.run(.calendar, .succeeded, started: 62, finished: 61),
            Self.run(.scorers, .failed, started: 60.5, finished: 60),
            Self.run(.calendar, .accepted, started: 3, finished: nil),
        ]
        #expect(Self.assess(runs, clubLastFinishedAt: Self.minutesAgo(50))
                == IngestionHealthAssessment(health: .pending, previous: .failing))
    }

    /// Lo de antes se calcula **sin** la pasada en marcha: con ella fuera, la
    /// última de calendario es la que falló.
    @Test("2 · lo de antes sale de la pasada anterior de la misma clase")
    func previousComesFromTheRunBeforeTheAcceptedOne() {
        let runs = [
            Self.run(.calendar, .failed, started: 62, finished: 61),
            Self.run(.calendar, .accepted, started: 3, finished: nil),
        ]
        #expect(Self.assess(runs, clubLastFinishedAt: Self.minutesAgo(50)).previous == .failing)
    }

    /// Una huérfana de hace dos horas (`H-27`, `H-57`) que el calendario de hace
    /// una hora dejó atrás: ya no es la última de su clase, y no dice nada.
    @Test("una pasada pedida vieja que otra posterior de su clase dejó atrás ya no cuenta")
    func anOldAcceptedRunLeftBehindDoesNotCount() {
        let runs = Self.allGood + [Self.run(.calendar, .accepted, started: 120, finished: nil)]
        #expect(Self.assess(runs, clubLastFinishedAt: Self.minutesAgo(60))
                == IngestionHealthAssessment(health: .ok))
    }

    // ── 1 · failing, la cola parada ─────────────────────────────────────────

    /// Se pidió hace 20 minutos y la última pasada del club acabó hace 30: lleva
    /// 20 minutos sin acabar nada.
    @Test("1 · una pasada pedida y 20 min sin acabar ninguna del club: con fallos, sin «lo de antes»")
    func anAcceptedRunWithAStoppedQueueIsFailing() {
        let runs = Self.allGood + [Self.run(.calendar, .accepted, started: 20, finished: nil)]
        #expect(Self.assess(runs, clubLastFinishedAt: Self.minutesAgo(30))
                == IngestionHealthAssessment(health: .failing))
    }

    /// El reloj cuenta desde lo más reciente de las dos: la hora a la que se pidió
    /// (hace 10) o la última que acabó (hace 30). Diez minutos: todavía en marcha.
    @Test("1 · el reloj cuenta desde la hora en que se pidió si es más reciente que la última que acabó")
    func theClockStartsWhenTheRunWasRequested() {
        let runs = Self.allGood + [Self.run(.calendar, .accepted, started: 10, finished: nil)]
        #expect(Self.assess(runs, clubLastFinishedAt: Self.minutesAgo(30)).health == .pending)
    }

    @Test("1 · el borde: a los 14:59 sigue en marcha, a los 15:00 ya es con fallos")
    func theFifteenMinuteEdge() {
        let justUnder = Self.allGood + [Self.run(.calendar, .accepted, started: 14 + 59.0 / 60, finished: nil)]
        let exactly = Self.allGood + [Self.run(.calendar, .accepted, started: 15, finished: nil)]
        #expect(Self.assess(justUnder, clubLastFinishedAt: Self.minutesAgo(30)).health == .pending)
        #expect(Self.assess(exactly, clubLastFinishedAt: Self.minutesAgo(30)).health == .failing)
    }

    @Test("1 · sin ninguna pasada del club acabada nunca, el reloj cuenta desde que se pidió")
    func withNoFinishedRunTheClockStartsAtTheRequest() {
        let runs = [Self.run(.calendar, .accepted, started: 16, finished: nil)]
        #expect(Self.assess(runs, lastSyncedAt: nil, clubLastFinishedAt: nil).health == .failing)
    }
}

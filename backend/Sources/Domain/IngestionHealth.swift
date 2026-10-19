public import struct Foundation.Date
public import typealias Foundation.TimeInterval

/// Cómo está la sincronización de una competición (`D-89`, con su enmienda del
/// 2026-10-18). **Derivado en lectura**: no hay columna detrás.
///
/// Los valores son los del catálogo (`IngestionHealth`), y en pantalla se leen
/// «Al día», «Con fallos», «Desactualizada», «Sin datos todavía» y «En marcha».
public enum IngestionHealth: String, CaseIterable, Equatable, Sendable {
    case ok
    case failing
    case stale
    case never
    case pending
}

/// El estado de una competición y, **solo cuando está `pending`**, el que tendría
/// sin la pasada en marcha (`previousIngestionHealth`).
public struct IngestionHealthAssessment: Equatable, Sendable {
    public let health: IngestionHealth
    public let previous: IngestionHealth?

    public init(health: IngestionHealth, previous: IngestionHealth? = nil) {
        self.health = health
        self.previous = previous
    }
}

extension IngestionHealth {
    /// Sin que acabe **ninguna** pasada del club durante este rato, una pasada
    /// pedida que no ha acabado se da por perdida y cuenta como `failing`
    /// (enmienda de `D-89`). Desde 15 minutos justos.
    public static let stuckAfter: TimeInterval = 15 * 60

    /// Un último éxito de hace **más** de una semana es `stale`: §5.6 dice que no
    /// debe pasar.
    public static let staleAfter: TimeInterval = 7 * 24 * 60 * 60

    /// La regla entera de la enmienda de `D-89`, en el orden en que se evalúa:
    ///
    /// | Orden | Valor | Cuándo |
    /// |---|---|---|
    /// | 1 | `failing` | hay una pasada `accepted`, y lleva 15 minutos sin acabar ninguna pasada del club |
    /// | 2 | `pending` | hay una pasada `accepted`, y la cola avanza |
    /// | 3 | `failing` | la última fila de alguna clase falló |
    /// | 4 | `never` | nunca hubo una pasada con éxito |
    /// | 5 | `stale` | el último éxito es de hace más de una semana |
    /// | 6 | `ok` | el resto |
    ///
    /// - Parameters:
    ///   - recentRuns: las pasadas recientes de la competición, **las dos últimas
    ///     de cada clase** por `startedAt`: la última decide, y la anterior hace
    ///     falta para saber qué había antes de una pasada en marcha.
    ///   - lastSyncedAt: el último éxito del calendario (`Competition`).
    ///   - clubLastFinishedAt: cuándo acabó la última pasada **del club**, de
    ///     cualquier competición, bien o mal. Es lo que pone a cero el reloj.
    ///   - now: la hora de ahora.
    public static func assess(
        recentRuns: [IngestionRun],
        lastSyncedAt: Date?,
        clubLastFinishedAt: Date?,
        now: Date
    ) -> IngestionHealthAssessment {
        // 1 y 2 · Una pasada pedida que no ha acabado. Solo cuenta si es la
        // última de su clase: una vieja que otra pasada de su clase dejó atrás ya
        // no dice nada.
        if let open = latestByKind(recentRuns).first(where: { $0.outcome == .accepted }) {
            // El reloj cuenta desde lo más reciente de las dos: la hora a la que se
            // pidió o la última pasada del club que acabó, bien o mal.
            let reference = max(open.startedAt, clubLastFinishedAt ?? open.startedAt)
            if now.timeIntervalSince(reference) >= stuckAfter {
                return IngestionHealthAssessment(health: .failing)
            }
            let previous = settled(
                recentRuns.filter { $0.id != open.id }, lastSyncedAt: lastSyncedAt, now: now)
            return IngestionHealthAssessment(health: .pending, previous: previous)
        }
        return IngestionHealthAssessment(
            health: settled(recentRuns, lastSyncedAt: lastSyncedAt, now: now))
    }

    /// Los casos 3 a 6: el estado **sin** una pasada en marcha. Nunca da
    /// `pending`, así que vale también para `previousIngestionHealth`.
    private static func settled(
        _ runs: [IngestionRun], lastSyncedAt: Date?, now: Date
    ) -> IngestionHealth {
        if latestByKind(runs).contains(where: { $0.outcome == .failed }) { return .failing }
        guard let lastSyncedAt else { return .never }
        if now.timeIntervalSince(lastSyncedAt) > staleAfter { return .stale }
        return .ok
    }

    /// La última pasada de cada clase, **por cuándo empezó** (H-58, pregunta 3):
    /// por cuándo acabó, una pasada sin acabar no tiene sitio en el orden.
    private static func latestByKind(_ runs: [IngestionRun]) -> [IngestionRun] {
        Dictionary(grouping: runs, by: \.kind).values.compactMap { sameKind in
            sameKind.max { $0.startedAt < $1.startedAt }
        }
    }
}

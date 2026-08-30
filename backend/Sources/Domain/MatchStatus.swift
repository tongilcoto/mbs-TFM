/// El estado del partido (§3.3).
///
/// **Lo escribe la ingesta por dos vías** (`D-57`): del **acta** en los partidos
/// de equipos propios —donde los cuatro valores son alcanzables— y **derivado
/// del marcador** en los ajenos, donde solo lo son los dos primeros. F5 solo
/// tiene la segunda: el acta es otra fase y sus códigos siguen sin observarse.
public enum MatchStatus: String, CaseIterable, Sendable {
    case programado
    case finalizado
    /// Solo del acta (`D-57`). La ingesta del calendario **no puede producirlo**:
    /// un partido aplazado desaparece del calendario o cambia de fecha, y las dos
    /// cosas son indistinguibles de un partido normal desde aquí.
    case aplazado
    /// Solo del acta (`D-57`).
    case suspendido
}

extension MatchStatus {
    /// El estado **derivado del marcador**, que es la única vía que F5 tiene
    /// (`D-57`).
    ///
    /// # El marcador que decide es el fusionado
    ///
    /// El mismo cuidado que `Kickoff.merging` (`D-56`): si se derivara del
    /// marcador **de la pasada**, una pasada que callara devolvería a
    /// `programado` un partido ya jugado. `MatchResult` es "los dos goles o
    /// ninguno" precisamente para que esta pregunta tenga una sola respuesta.
    public static func derived(from result: MatchResult?) -> MatchStatus {
        result == nil ? .programado : .finalizado
    }
}

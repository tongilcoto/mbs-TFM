/// Una hora de reloj de pared: `18:05`. **Sin fecha y sin huso.**
///
/// Existe porque `D-30` separa `match_date` de `kickoff_time` en **dos columnas**,
/// y la razón por la que las separa es que la RFFM publica el calendario en dos
/// tiempos: primero todos los partidos al sábado por defecto y **sin hora**, y el
/// domingo anterior fija la franja ([Anexo RFFM §F.5]). Un `timestamptz` único no
/// sabe decir *"sábado, hora por decidir"*.
///
/// Consecuencia directa: **esto no es un instante**, así que no lleva huso. El
/// aviso de [Anexo RFFM §F.11] —*"sin huso horario en ningún payload, fijar
/// `Europe/Madrid`"*— se aplica cuando alguien componga fecha + hora para
/// mostrarlas, no aquí: convertir a instante en la ingesta obligaría a decidir qué
/// pasa en los cambios de hora con un dato que la fuente ni siquiera afirma.
public struct WallClockTime: Hashable, Sendable {
    public let hour: Int
    public let minute: Int

    /// - Returns: `nil` si la hora no existe en un reloj de 24 h.
    public init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }
}

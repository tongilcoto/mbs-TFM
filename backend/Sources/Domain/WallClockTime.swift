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
///
/// **Vive en el Dominio, y no siempre estuvo aquí.** Nació en Aplicación con el
/// puerto de F2, que fue quien primero necesitó nombrar una hora suelta. Es un
/// *Value Object* con invariante —el reloj de 24 h— y §4.1 los pone en el
/// Dominio; lo que forzó la mudanza es `Kickoff`, que **es** dominio (`D-30`) y
/// lo lleva dentro. Un segundo tipo idéntico en la otra capa habría sido la
/// alternativa, y es peor.
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

extension WallClockTime {
    /// `"18:05"`, con el cero delante. Es la forma en que se persiste (§4.4) y
    /// la que la RFFM publica ([Anexo RFFM §F.15]).
    ///
    /// **Se guarda como texto y no como `time` de Postgres**, y conviene decir
    /// por qué: el driver decodifica `time` a un `Date`, que es un instante — y
    /// volver a meter este valor en un instante es exactamente lo que este tipo
    /// existe para no hacer. El texto `HH:mm` además **ordena
    /// lexicográficamente igual que cronológicamente**, así que un `ORDER BY`
    /// sobre la columna sigue funcionando.
    public var text: String {
        let hh = hour < 10 ? "0\(hour)" : "\(hour)"
        let mm = minute < 10 ? "0\(minute)" : "\(minute)"
        return "\(hh):\(mm)"
    }

    /// El inverso de `text`. `nil` si el texto no es una hora de reloj.
    public init?(text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              parts[0].count == 2, parts[1].count == 2
        else { return nil }
        self.init(hour: hour, minute: minute)
    }
}

public import struct Foundation.Date

/// La jornada de una competición (§3.2). Único(competición, número) (§3.5).
public struct Round: Identifiable, Equatable, Sendable {
    public let id: RoundID
    public let competitionID: CompetitionID
    public let number: Int
    public let startDate: Date
    public let endDate: Date
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: RoundID,
        competitionID: CompetitionID,
        number: Int,
        startDate: Date,
        endDate: Date,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        guard number >= 1 else {
            throw DomainError.invalidValue(
                field: "number", reason: "la jornada se numera desde 1"
            )
        }
        guard endDate >= startDate else {
            throw DomainError.invalidValue(
                field: "endDate", reason: "la jornada no puede acabar antes de empezar"
            )
        }

        self.id = id
        self.competitionID = competitionID
        self.number = number
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Round {
    /// El rango de la jornada, **derivado de las fechas de sus partidos** (`D-81`).
    ///
    /// # Por qué se deriva y no se lee
    ///
    /// §3.2 exige `start_date` y `end_date`, y **la federación no publica
    /// ninguno de los dos**. Lo que publica es un rótulo —`"1 (27-09-2025)"`— y
    /// la fecha de cada partido. El rótulo tienta, pero es **un** día: sirve
    /// para el sábado y pierde el domingo, que es donde cae un tercio de los
    /// partidos de una jornada real.
    ///
    /// Mínimo y máximo, en cambio, salen del dato que sí existe y no inventan
    /// nada. Contra los dos volcados: en la temporada jugada dan **sábado →
    /// domingo** en 26 de las 30 jornadas y recogen los 4 partidos que se
    /// jugaron entre semana; en la que no ha arrancado **colapsan en un solo
    /// día**, porque eso es literalmente todo lo que la fuente ha dicho.
    ///
    /// # `nil` no es "la jornada está vacía"
    ///
    /// Es **"no hay ninguna fecha con la que calcular el rango"**, y quien lo
    /// recibe decide. Un partido cuya fecha la fuente no publica no se puede
    /// insertar —`match_date` es `NOT NULL` (§3.2)—, así que no llega hasta
    /// aquí: la ingesta lo deja fuera y lo reporta.
    ///
    /// Devuelve un `ClosedRange` y no dos fechas sueltas por lo mismo que el
    /// `init` de arriba tiene guarda: el tipo ya no deja construir un rango al
    /// revés, así que la única forma de equivocarse se queda dentro de esta
    /// función.
    public static func span(ofMatchDates dates: [Date]) -> ClosedRange<Date>? {
        guard let start = dates.min(), let end = dates.max() else { return nil }
        return start...end
    }
}

extension Round {
    /// El *upsert* de la jornada (§3.7): **el rango es volátil**.
    ///
    /// Es propiedad de la federación por la misma razón que la fecha de los
    /// partidos de los que se deriva (`D-30`, `D-81`): un aplazamiento estira la
    /// jornada y la pasada siguiente tiene que reflejarlo.
    ///
    /// **No lanza**, y eso también es de diseño: recibe un `ClosedRange` ya
    /// construido, que por su propio tipo no puede estar del revés. La invariante
    /// del `init` no se puede violar desde aquí.
    ///
    /// El `number` no entra: es identidad —(competición, número) es la clave
    /// única de §3.5—, así que no se fusiona, se empareja por él.
    public func merging(span: ClosedRange<Date>?) -> Round {
        // `try!` no es una concesión: los dos valores salen del mismo
        // `ClosedRange`, así que `end >= start` está garantizado por su tipo y
        // la única guarda del `init` no puede fallar. El día que `Round` gane
        // otra invariante, esta línea deja de compilar en silencio — y por eso
        // el `init` sigue siendo el sitio donde viven, no este método.
        try! Round(
            id: id,
            competitionID: competitionID,
            number: number,
            startDate: UpsertPolicy.volatile(existing: startDate, incoming: span?.lowerBound)!,
            endDate: UpsertPolicy.volatile(existing: endDate, incoming: span?.upperBound)!,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

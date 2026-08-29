public import struct Foundation.Date

/// El horario de un partido: **fecha siempre, hora a veces** (`D-30`).
///
/// Existe porque un calendario federado **no se publica cerrado**. Al arrancar
/// la temporada la federación reparte todos los partidos con una fecha por
/// defecto —el sábado— y **sin hora**; la franja real se fija el domingo
/// anterior, y al fijarla la fecha puede desplazarse ([Anexo RFFM §F.5]). Un
/// `timestamptz` único solo puede guardar una de dos mentiras: un `00:00` de
/// relleno indistinguible de la medianoche real, o un `NULL` que se lleva por
/// delante también la fecha, que sí se conoce y sí hay que pintar.
public struct Kickoff: Equatable, Sendable {
    /// **Obligatoria** (§3.2): un partido siempre tiene fecha nominal, aunque sea
    /// la conjetura del propio proveedor.
    public let date: Date

    /// `nil` mientras la federación no haya publicado franja.
    public let time: WallClockTime?

    public init(date: Date, time: WallClockTime? = nil) {
        self.date = date
        self.time = time
    }

    /// **Derivado, no almacenado** (`D-30`): una bandera guardada podría
    /// contradecir al dato que describe, que es la deriva que `D-18` evita en
    /// integración.
    ///
    /// Se llama `isConfirmed` y **no** `isFinal`, y la diferencia no es
    /// cosmética: significa *"la federación ya publicó franja"*, no *"esto ya no
    /// se mueve"*. Una suspensión lo devuelve a `nil`.
    public var isConfirmed: Bool { time != nil }
}

extension Kickoff {
    /// El *upsert* del horario: **volátil, pero con la salvedad de `D-56`**.
    ///
    /// Los dos campos son volátiles (§3.7) —se pisan **también los ya
    /// confirmados**, porque una suspensión mueve el partido (`D-30`)— y la
    /// salvedad es que *vacío* significa **dos cosas distintas** según el
    /// partido se haya jugado o no. Está aquí, en un método del VO, y no
    /// repartida por la ingesta, por lo mismo que `isConfirmed`: para que la
    /// regla viva en un sitio.
    ///
    /// El marcador se pasa **en sus dos versiones y sin fusionar** a propósito.
    /// Quien decide si el partido se ha jugado es el marcador **ya fusionado**
    /// —el que quedará en la fila—, no el que traiga esta pasada; si la firma
    /// pidiera uno solo, el orden de las dos operaciones sería un detalle que se
    /// puede hacer mal desde fuera, y equivocarlo borra horarios.
    public func merging(
        date: Date?,
        time: WallClockTime?,
        existingResult: MatchResult?,
        incomingResult: MatchResult?
    ) -> Kickoff {
        // El marcador **fusionado**, con la misma regla que cualquier otro campo
        // volátil: el silencio de esta pasada no devuelve el partido a «sin jugar».
        let result = UpsertPolicy.volatile(existing: existingResult, incoming: incomingResult)

        return Kickoff(
            // `volatile` de §3.7 sobre una columna `NOT NULL`: la fuente gana
            // cuando dice algo y su silencio deja lo que había. No hay tercera
            // rama, porque «vacío» no es un valor válido para `match_date`.
            date: date ?? self.date,
            // Las dos filas de la tabla de `D-56`, y la única línea de toda la
            // fase donde escribir `nil` es lo correcto:
            //   · sin marcador → «horario aún sin confirmar», es el dato real;
            //   · con marcador → la fuente dejó de publicarlo, se conserva.
            time: result == nil ? time : (time ?? self.time)
        )
    }
}

public import struct Application.FederationScorerTable
import struct Application.FederationScorerRow
import enum Application.FederationError
import struct Foundation.Data
import class Foundation.JSONDecoder

/// De la respuesta de `/api/scorers` a lo que el puerto promete
/// ([Anexo RFFM §F.19]).
///
/// **Función pura**: entra texto, sale un `FederationScorerTable`. Ni red, ni
/// reloj, ni base de datos — la misma frontera que sus dos hermanos, y por el
/// mismo motivo (Plan §7.3): *"la frontera «cliente HTTP» y la frontera «parser»
/// son **dos** responsabilidades"*.
///
/// # En qué SÍ se parece al de la clasificación, y hay que copiarlo
///
/// En cómo detecta que la coordenada no designa nada: **el documento entero es
/// `null`**, cuatro bytes, así que se decodifica a `Payload?` y un `nil` es
/// `coordinateNotFound`. Escrito por analogía con el **calendario** —que sí manda
/// la página entera con un campo a nulo— eso se caería por el `catch` del
/// decodificador y saldría como `malformedResponse`: el canario gritando *"¡han
/// cambiado la forma!"* cada vez que alguien se equivoque de número, que es
/// exactamente la falsa alarma que `D-84` existe para evitar.
///
/// Y aquí ese `null` tiene **tres** causas y no una, medidas: par inexistente,
/// competición que no casa con el grupo, y competición ausente. Esta ruta exige
/// los dos códigos y **valida que sean pareja** — es la única ruta medida de la
/// RFFM donde una coordenada mal tecleada no puede servir los datos de otra.
///
/// # En qué NO se parece, y es lo que hay que resistirse a copiar
///
/// **Aquí una fila rara no tira la tabla.** El de la clasificación exige los ocho
/// contadores y falla con `malformedResponse` diciendo cuál faltaba, porque una
/// clasificación es un **bloque**: una fila sin posición deja un hueco en una
/// numeración que el *spec* declara imposible. Un ranking de goleadores **no
/// tiene numeración** —ninguna de las dos federaciones publica puesto (§F.13,
/// §F.19, [Anexo FCF §C.10.7])— así que sus filas son independientes: 217 de 218
/// sigue siendo un ranking utilizable, y tirar la pasada entera por una fila rara
/// sería el error caro de `D-75`.
///
/// De ahí que lo que no se entiende salga como `nil` y **lo descarte el caso de
/// uso**, que es quien tiene dónde apuntarlo (`unidentifiedScorer`). Un parser que
/// filtrara aquí escondería la fila sin dejar rastro, que es peor que descartarla.
///
/// > **Y el atajo que no funciona, igual que en la clasificación:** el sobre trae
/// > `estado: "1"`, lo que invita a usar un `"0"` como señal de error. Con
/// > coordenada mala **no llega sobre ninguno**, así que no hay `estado` que mirar.
public enum RFFMScorersParser {

    public static func parse(_ body: String) throws -> FederationScorerTable {
        let payload: Payload?
        do {
            let decoder = JSONDecoder()
            // `codigo_jugador` → `codigoJugador` sin un `CodingKeys` que mantener
            // a mano. Mismo criterio que los otros dos parsers.
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            payload = try decoder.decode(Payload?.self, from: Data(body.utf8))
        } catch {
            throw FederationError.malformedResponse(
                field: "(cuerpo)",
                reason: "no es el JSON de /api/scorers: \(error)")
        }

        // **El `null` de raíz es la coordenada, no el formato** (§F.19).
        guard let payload else {
            throw FederationError.coordinateNotFound(
                detail: "la respuesta llegó a `null`: ese par idGroup+idCompetition no existe")
        }

        return FederationScorerTable(
            competitionName: nonEmpty(payload.competicion),
            rows: payload.goles.map(Self.row))
    }

    private static func row(_ raw: Payload.Row) -> FederationScorerRow {
        FederationScorerRow(
            federationPlayerID: nonEmpty(raw.codigoJugador),
            // **Sin normalizar y sin partir.** `NormalizedName` existe para
            // *emparejar* y aquí no se empareja nada (`D-09`); y la letra viene
            // pegada al nombre del equipo, sin las comillas simples con las que la
            // RFFM la escribe en el calendario ([Anexo RFFM §F.5], §F.13), así que
            // partirla sería trabajo con riesgo y sin lector.
            fullName: raw.jugador ?? "",
            teamLabel: raw.nombreEquipo ?? "",
            // `nil` ⇒ la fuente no dijo nada, que **no es `0`** (`D-56`). Un cero
            // aquí afirmaría "este jugador no ha marcado", que es un dato.
            goals: raw.goles.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) },
            // **No se sintetiza desde el índice**, que es la tentación del
            // endpoint: la lista viene ordenada por goles, así que `índice + 1`
            // parece gratis. El *spec* se comprometió a respetar el puesto **del
            // proveedor** porque los criterios de desempate son suyos; numerar los
            // empates aquí sería inventárselos y servirlos con cara de dato ajeno.
            rank: nil)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }

    /// Espejo del JSON, **con solo lo que alguien lee**.
    ///
    /// La respuesta trae cuatro claves de sobre y diez por fila ([Anexo RFFM
    /// §F.19]); aquí hay una y cuatro. Es la regla que F6-bis cobró con
    /// `FederationRound.label` —un campo que llevaba desde F2 sin más aparición
    /// que su propia asignación—, y en este sobre hay que aplicarla **más** fuerte
    /// que en los otros dos, porque el equivalente catalán es **un array pelado**
    /// ([Anexo FCF §C.10.7]).
    ///
    /// Lo que queda fuera, y dónde está descrito por si algún día hace falta:
    /// `estado` y `sesion_ok` (no sirven de guarda: con coordenada mala no hay
    /// sobre), `grupo` (ya lo trae el calendario), `codigo_equipo` (mide 16/16 con
    /// el del calendario, y precisamente por eso **no** se transporta: `D-09` no
    /// liga esta fila con `Team`), `escudo_equipo`, `foto` —vacía en 426/426
    /// filas—, `partidos_jugados`, `goles_penalti` y `goles_por_partidos`.
    ///
    /// Todo `String?` por §F.11 —*"todo llega como cadena, sin excepción"*—, que
    /// en la RFFM se cumple también aquí: las diez claves de las 218 filas.
    /// **En la FCF no**: allí `goles` y `penalti` son números JSON, y su parser
    /// tendrá que tiparlo por su volcado ([Anexo FCF §C.10.7]).
    struct Payload: Decodable {
        /// El único campo del sobre con lector: la guarda de `D-84`
        /// (`Competition.requireSameSource`). **No es eco** —lo que se envían son
        /// números y lo que vuelve es texto— pero sí es **ciego a la temporada**,
        /// porque §F.17 midió que el nombre es idéntico entre temporadas.
        let competicion: String?

        /// Las filas. La clave del array se llama igual que el campo de goles de
        /// cada fila, y no colisiona porque son dos niveles distintos del
        /// documento — pero conviene saberlo antes de leer el `Row` de abajo.
        let goles: [Row]

        struct Row: Decodable {
            let codigoJugador: String?
            let jugador: String?
            let nombreEquipo: String?
            let goles: String?
        }
    }
}

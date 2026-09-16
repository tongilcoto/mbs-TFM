public import struct Application.FederationStanding
import struct Application.FederationStandingRow
import struct Application.FederationTeamRef
import enum Application.FederationError
import struct Foundation.Data
import class Foundation.JSONDecoder

/// De la respuesta de `/api/standings` a lo que el puerto promete
/// ([Anexo RFFM §F.18]).
///
/// **Función pura**: entra texto, sale un `FederationStanding`. Ni red, ni reloj,
/// ni base de datos — la misma frontera que `RFFMCalendarParser`, y por el mismo
/// motivo (Plan §7.3): *"la frontera «cliente HTTP» y la frontera «parser» son
/// **dos** responsabilidades"*.
///
/// # En qué NO se parece al parser del calendario, que es lo que hay que saber
///
/// Los dos tienen que distinguir *"esa coordenada no designa nada"* de *"la fuente
/// ha cambiado de forma"* —`D-84`, punto 2—, y **la señal no es la misma**:
///
/// | | Qué llega con una coordenada inexistente | Cómo se detecta |
/// |---|---|---|
/// | Calendario | la **página entera**, props completas, y `pageProps.calendar` a nulo | mirando ese campo |
/// | Clasificación | **el documento entero es `null`** — cuatro bytes | decodificando a **opcional** |
///
/// Por eso aquí se decodifica a `Payload?` y no a `Payload`. Escrito por analogía
/// con el calendario, ese `null` se caería por el `catch` del decodificador y
/// saldría como `malformedResponse`: **el canario gritando "¡han cambiado la
/// forma!" cada vez que alguien se equivoque de número**, que es exactamente la
/// falsa alarma que `D-84` existe para evitar. Medido el 2026-09-15; hasta
/// entonces de esta ruta no se sabía nada y se dio por hecho que haría lo que el
/// calendario — es la lección de `D-74` dentro de la misma federación.
///
/// > **Y el atajo que no funciona:** el sobre trae `estado: "1"`, lo que invita a
/// > usar un `"0"` como señal de error. Con coordenada mala **no llega sobre
/// > ninguno**, así que no hay `estado` que mirar.
public enum RFFMStandingsParser {

    public static func parse(_ body: String) throws -> FederationStanding {
        let payload: Payload?
        do {
            let decoder = JSONDecoder()
            // `codigo_competicion` → `codigoCompeticion` sin un `CodingKeys` de
            // treinta líneas que mantener a mano. Mismo criterio que el parser
            // del calendario.
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            payload = try decoder.decode(Payload?.self, from: Data(body.utf8))
        } catch {
            throw FederationError.malformedResponse(
                field: "(cuerpo)",
                reason: "no es el JSON de /api/standings: \(error)")
        }

        // **El `null` de raíz es la coordenada, no el formato** (§F.18).
        guard let payload else {
            throw FederationError.coordinateNotFound(
                detail: "la respuesta llegó a `null`: ese idGroup no existe")
        }

        return FederationStanding(
            federationCompetitionID: nonEmpty(payload.codigoCompeticion),
            competitionName: nonEmpty(payload.competicion),
            rows: try payload.clasificacion.enumerated().map { index, row in
                try Self.row(row, at: index, host: payload.host ?? "")
            })
    }

    private static func row(
        _ raw: Payload.Row, at index: Int, host: String
    ) throws -> FederationStandingRow {
        /// Los ocho contadores son **obligatorios**, al revés que en el calendario.
        ///
        /// Allí un campo vacío significa *"la fuente no dijo nada"* y `D-56`
        /// construye encima la política de *upsert*. Aquí no: una clasificación es
        /// un **bloque**, y una fila sin posición o sin puntos deja un hueco en la
        /// numeración que el *spec* declara imposible (`position`, `minimum: 1`).
        /// Así que se exige, y el error dice **qué campo y de qué fila**: con 16
        /// filas casi idénticas, *"un número no es un número"* manda a mirarlas
        /// todas.
        func number(_ value: String?, _ field: String) throws -> Int {
            guard let value, let parsed = Int(value.trimmingCharacters(in: .whitespaces))
            else {
                throw FederationError.malformedResponse(
                    field: "clasificacion[\(index)].\(field)",
                    reason: #"no es un entero: "\#(value ?? "(ausente)")""#)
            }
            return parsed
        }

        let split = RFFMValue.teamName(raw.nombre ?? "")
        return FederationStandingRow(
            team: FederationTeamRef(
                federationTeamID: nonEmpty(raw.codequipo),
                name: split.name,
                letter: split.letter,
                federationClubID: RFFMValue.federationClubID(fromCrestPath: raw.urlImg),
                crestURL: raw.urlImg.flatMap {
                    $0.isEmpty || host.isEmpty ? nil : host + $0
                }),
            position: try number(raw.posicion, "posicion"),
            played: try number(raw.jugados, "jugados"),
            // **Por nombre y nunca por posición** ([Anexo RFFM §F.8]): el orden en
            // el JSON es `ganados, perdidos, empatados`, así que leerlos por
            // índice cruzaría empates con derrotas sin que nada chille.
            won: try number(raw.ganados, "ganados"),
            drawn: try number(raw.empatados, "empatados"),
            lost: try number(raw.perdidos, "perdidos"),
            goalsFor: try number(raw.golesAFavor, "goles_a_favor"),
            goalsAgainst: try number(raw.golesEnContra, "goles_en_contra"),
            points: try number(raw.puntos, "puntos"))
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return value
    }

    /// Espejo del JSON, **con solo lo que alguien lee**.
    ///
    /// La respuesta trae 29 claves por fila ([Anexo RFFM §F.18]) y aquí hay diez.
    /// No es un espejo incompleto por descuido: es la regla que F6-bis cobró con
    /// `FederationRound.label` —un campo que llevaba desde F2 sin más aparición
    /// que su propia asignación—. Lo que queda fuera está descrito en el anexo y
    /// entra cuando exista el lector: desglose casa/fuera, `puntos_local`,
    /// `puntos_sancion`, `coeficiente`, `color`, `promociones[]` y
    /// `racha_partidos[]`.
    ///
    /// Todo `String?` por §F.11 —*"todo llega como cadena, sin excepción"*—; la
    /// exigencia de que estén se hace arriba, con el nombre del campo delante.
    struct Payload: Decodable {
        /// **Evidencia que no puede ser eco** (§F.18): solo se envían `idGroup` y
        /// `round`, así que este código lo pone la fuente.
        let codigoCompeticion: String?
        let competicion: String?
        /// `"https://appweb.rffm.es/"`, para componer la ruta del escudo (§F.4).
        let host: String?
        let clasificacion: [Row]

        struct Row: Decodable {
            let posicion: String?
            let codequipo: String?
            let nombre: String?
            let urlImg: String?
            let jugados: String?
            let ganados: String?
            let empatados: String?
            let perdidos: String?
            let golesAFavor: String?
            let golesEnContra: String?
            let puntos: String?
        }
    }
}

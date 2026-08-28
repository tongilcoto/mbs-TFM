/// Espejo literal del JSON del calendario ([Anexo RFFM §F.15]).
///
/// **Todo es `String?`, y no es pereza.** §F.11: *"todo llega como cadena, sin
/// excepción — nunca hay números ni booleanos, y las banderas son `"0"`/`"1"`"*.
/// Tipar aquí un `Int` haría que un `""` —que la fuente usa constantemente para
/// decir "no lo sé"— reventase la decodificación del calendario **entero** por un
/// partido sin marcador. La conversión, con sus reglas, vive en `RFFMValue`.
///
/// Y opcional aunque el volcado lo traiga siempre: la muestra 2 de §F.2 **no trae
/// `hora` en absoluto** —campo ausente, no vacío—, así que el *decoder* tolera la
/// ausencia por diseño, no por si acaso.
///
/// Los nombres van en `camelCase` y el *decoder* aplica `.convertFromSnakeCase`,
/// así que `codigo_equipo_local` entra como `codigoEquipoLocal` sin escribir un
/// `CodingKeys` de treinta líneas que habría que mantener a mano.
struct RFFMCalendarPayload: Decodable {
    let props: Props

    struct Props: Decodable {
        let pageProps: PageProps
    }

    struct PageProps: Decodable {
        let calendar: Calendar
        /// La jornada en curso ([Anexo RFFM §F.7]).
        let currentRound: String?
    }

    struct Calendar: Decodable {
        /// El **nombre** de la competición, no su código (§F.15).
        let competicion: String?
        let grupo: String?
        /// `"2026-2027"` — se reformatea en `RFFMSeasonLabel` (`D-71`).
        let temporada: String
        /// `"https://appweb.rffm.es/"`. **Lo publica la fuente** (§F.15).
        let host: String?
        let rounds: [Round]
    }

    struct Round: Decodable {
        /// El número de jornada de verdad.
        let codjornada: String
        /// El **rótulo**: `"1 (13-09-2026)"`. No es un número (§F.15).
        let jornada: String
        /// **Son los partidos, no los equipos.** Nombre engañoso del proveedor,
        /// anotado en §F.11.
        let equipos: [Match]
    }

    struct Match: Decodable {
        let codacta: String?
        let codigoEquipoLocal: String?
        let equipoLocal: String?
        let escudoEquipoLocal: String?
        let golesCasa: String?
        let codigoEquipoVisitante: String?
        let equipoVisitante: String?
        let escudoEquipoVisitante: String?
        let golesVisitante: String?
        let codigoCampo: String?
        let campo: String?
        let fecha: String?
        let hora: String?
    }
}

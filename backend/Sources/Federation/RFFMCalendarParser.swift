import Foundation
public import struct Application.FederationCalendar
import struct Application.FederationRound
import struct Application.FederationMatch
import struct Application.FederationTeamRef
import enum Application.FederationError

/// De la página del calendario de la RFFM a lo que el puerto promete.
///
/// **Función pura**: entra texto, sale un `FederationCalendar`. Ni red, ni reloj,
/// ni base de datos — por eso F2 es nivel 1 de la pirámide (§8.1) y corre en
/// milisegundos sin Docker.
///
/// La frontera está puesta a conciencia (Plan §7.3): *"la frontera «cliente HTTP»
/// y la frontera «parser» son **dos** responsabilidades"*. Quien trae los bytes es
/// `RFFMFederationClient`; interpretarlos es esto, y se prueba contra el volcado
/// real sin levantar nada.
public enum RFFMCalendarParser {

    /// - Parameter html: la página tal cual, con su `__NEXT_DATA__` dentro.
    public static func parse(_ html: String) throws -> FederationCalendar {
        let json = try NextDataExtractor.json(from: html)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let payload: RFFMCalendarPayload
        do {
            payload = try decoder.decode(RFFMCalendarPayload.self, from: Data(json.utf8))
        } catch {
            // Se traduce a `FederationError` en vez de dejar salir el
            // `DecodingError`: quien llama es un caso de uso, y lo que necesita
            // saber es "la fuente no tiene la forma documentada", no la ruta de
            // claves de Foundation. El detalle va dentro, para poder depurarlo.
            throw FederationError.malformedResponse(
                field: "props.pageProps.calendar",
                reason: "la respuesta no tiene la forma del Anexo RFFM §F.15: \(error)"
            )
        }

        let calendar = payload.props.pageProps.calendar
        let host = (calendar.host ?? "").hasSuffix("/")
            ? String(calendar.host!.dropLast())
            : (calendar.host ?? "")

        return FederationCalendar(
            seasonLabel: try RFFMSeasonLabel.parse(calendar.temporada),
            competitionName: calendar.competicion,
            groupLabel: calendar.grupo,
            currentRound: payload.props.pageProps.currentRound.flatMap { Int($0) },
            rounds: try calendar.rounds.map { try round($0, host: host) }
        )
    }

    private static func round(_ raw: RFFMCalendarPayload.Round, host: String) throws -> FederationRound {
        // **Del `codjornada`, no del `jornada`.** §F.11 decía lo contrario y se
        // equivocaba: `jornada` es `"1 (13-09-2026)"`, un rótulo con la fecha
        // nominal dentro. Corregido en §F.15 con el volcado delante.
        //
        // Y tampoco del índice del array, que es lo que hacía la app heredada: un
        // hueco en la numeración desplazaría todas las jornadas siguientes en
        // silencio.
        guard let number = Int(raw.codjornada) else {
            throw FederationError.malformedResponse(
                field: "calendar.rounds[].codjornada",
                reason: #"se esperaba un entero, llegó "\#(raw.codjornada)""#
            )
        }
        return FederationRound(
            number: number,
            label: raw.jornada,
            matches: try raw.equipos.map { try match($0, host: host) }
        )
    }

    private static func match(_ raw: RFFMCalendarPayload.Match, host: String) throws -> FederationMatch {
        FederationMatch(
            federationMatchID: raw.codacta.flatMap { $0.isEmpty ? nil : $0 },
            home: team(
                id: raw.codigoEquipoLocal, name: raw.equipoLocal,
                crestPath: raw.escudoEquipoLocal, host: host
            ),
            away: team(
                id: raw.codigoEquipoVisitante, name: raw.equipoVisitante,
                crestPath: raw.escudoEquipoVisitante, host: host
            ),
            homeScore: try RFFMValue.score(raw.golesCasa),
            awayScore: try RFFMValue.score(raw.golesVisitante),
            date: try RFFMValue.matchDate(raw.fecha),
            kickoff: try RFFMValue.kickoff(raw.hora),
            venue: RFFMValue.venue(raw.campo),
            venueCode: raw.codigoCampo.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private static func team(
        id: String?, name: String?, crestPath: String?, host: String
    ) -> FederationTeamRef {
        let split = RFFMValue.teamName(name ?? "")
        return FederationTeamRef(
            federationTeamID: id.flatMap { $0.isEmpty ? nil : $0 },
            name: split.name,
            letter: split.letter,
            federationClubID: RFFMValue.federationClubID(fromCrestPath: crestPath),
            // El host **lo publica la respuesta** (§F.15); las rutas del escudo son
            // relativas a él (§F.4).
            crestURL: crestPath.flatMap { $0.isEmpty || host.isEmpty ? nil : host + $0 }
        )
    }
}

public import protocol Application.FederationClient
public import struct Application.FederationCalendar
public import struct Application.FederationCoordinate

/// El adaptador de la RFFM: implementa el puerto `FederationClient` (§4.3).
///
/// Son cuatro líneas, y esa es la señal de que las fronteras están bien puestas:
/// **traer** es del transporte, **interpretar** es del parser, y esto solo dice
/// *qué* se pide y *en qué orden* — que es lo único específico de la federación
/// que queda una vez separadas las otras dos.
///
/// # Sin estado, por diseño
///
/// Un `struct` con una sola dependencia inmutable. La implementación previa de la
/// app iOS guardaba entre llamadas la temporada y la categoría de la anterior
/// (Plan §7.2): en un backend multi-tenant, donde el mismo cliente sirve a clubes
/// distintos a la vez, eso es una fuga esperando a ocurrir. Aquí no hay nada que
/// filtrar porque no hay nada que recordar.
public struct RFFMFederationClient: FederationClient {
    private let transport: any FederationTransport

    public init(transport: any FederationTransport) {
        self.transport = transport
    }

    /// Una petición, el calendario entero (§5.6, [Anexo RFFM §F.1]).
    ///
    /// **No persiste ni empareja nada**: eso es F3 y F4. Lo que sale de aquí es lo
    /// que la fuente dijo, con sus huecos intactos — que es la materia prima sobre
    /// la que `D-56` decide qué se escribe y qué no.
    public func fetchCalendar(_ coordinate: FederationCoordinate) async throws -> FederationCalendar {
        let page = try await transport.get(RFFMEndpoints.calendar(for: coordinate))
        return try RFFMCalendarParser.parse(page)
    }
}

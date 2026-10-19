public import Domain

/// Caso de uso: las temporadas del club, con la que está en curso (`GET /v1/seasons`).
///
/// **`isCurrent` se deriva en lectura** (§3.2): no hay columna detrás, y la regla
/// vive en el Dominio (`current(on:)`). Aquí solo se le da el reloj.
public struct ListSeasons: Sendable {
    private let seasons: any SeasonRepository
    private let clock: any Clock

    public init(seasons: any SeasonRepository, clock: any Clock) {
        self.seasons = seasons
        self.clock = clock
    }

    /// Las temporadas, en el orden del repositorio (la más reciente primero), y
    /// cuál está en curso. Viajan juntas porque `isCurrent` no es de una
    /// temporada sola: depende del día y de que no esté archivada.
    public struct Listing: Equatable, Sendable {
        public let seasons: [Season]
        public let currentID: SeasonID?
    }

    public func execute(includingArchived: Bool) async throws -> Listing {
        let list = try await seasons.list(includingArchived: includingArchived)
        return Listing(seasons: list, currentID: list.current(on: clock.now())?.id)
    }
}

public import Domain
import Foundation

/// Caso de uso: dar de alta una temporada (`POST /v1/seasons`).
///
/// **Nace sin código de la federación** si no se le da (`D-106`): el club la crea
/// en julio, desde el formulario de alta de equipo, cuando la federación todavía
/// no ha publicado nada, y el primer enganche se lo pone. El código se sigue
/// aceptando para semillas, *scripts* y pruebas.
///
/// **«Ya existe» se comprueba antes de escribir**, no esperando al `23505` de
/// Postgres (la lección de `FEDERATION_TEAM_ID_TAKEN` en F10): la etiqueta, **también
/// contra las archivadas** —`listSeasons` no las enseña, pero su etiqueta sigue
/// ocupada—, y el código, si viene.
public struct CreateSeason: Sendable {
    private let seasons: any SeasonRepository
    private let clock: any Clock
    private let ids: any UUIDProvider

    public init(seasons: any SeasonRepository, clock: any Clock, ids: any UUIDProvider) {
        self.seasons = seasons
        self.clock = clock
        self.ids = ids
    }

    /// Lo que el caso de uso acepta. **No es el DTO** (§2.2).
    public struct Command: Sendable {
        public let label: String
        public let federationSeasonID: String?

        public init(label: String, federationSeasonID: String?) {
            self.label = label
            self.federationSeasonID = federationSeasonID
        }
    }

    public func execute(_ command: Command) async throws -> Season {
        // La etiqueta pasa por el Dominio **antes** que nada: «2026/28» es un
        // valor que no vale (422), no una temporada que choque con otra.
        let label = try SeasonLabel(command.label)
        let now = clock.now()
        let season = try Season(
            id: SeasonID(raw: ids.next()), label: label,
            federationSeasonID: command.federationSeasonID,
            createdAt: now, updatedAt: now)

        // **Con las archivadas**: no se enseñan, pero su etiqueta sigue ocupada.
        let existing = try await seasons.list(includingArchived: true)
        if existing.contains(where: { $0.label == label }) {
            throw ApplicationError.seasonAlreadyExists(field: "label", value: label.value)
        }
        if let code = command.federationSeasonID,
           try await seasons.findByFederationID(code) != nil {
            throw ApplicationError.seasonAlreadyExists(field: "federationSeasonId", value: code)
        }

        try await seasons.save(season)
        // Se relee para devolver las marcas de tiempo que puso la base, no las
        // del reloj de aquí.
        return try await seasons.find(season.id) ?? season
    }
}

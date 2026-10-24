public import Domain
import Foundation

/// Caso de uso: dar de alta un equipo del club (`POST /v1/teams`).
///
/// **El equipo es del club, no de la federación** (`D-66`): nace sin ningún dato
/// de la federación, propio, e inscrito en la temporada que se indica (`D-68`).
///
/// **Y si ya existe, lo inscribe** (`D-107`). El equipo propio no lleva temporada:
/// el «Alevín A» de 2026/27 y el de 2027/28 son el mismo equipo, y lo que cambia
/// cada año es su inscripción. «El mismo» es uno **propio** con la misma
/// categoría, letra, género y modalidad, la clave de §3.5. Solo es conflicto si
/// ya estaba inscrito en esa temporada. Todo se comprueba **antes de escribir**.
public struct CreateTeam: Sendable {
    private let clubs: any ClubRepository
    private let seasons: any SeasonRepository
    private let teams: any TeamRepository
    private let registrations: any TeamRegistrationRepository
    private let clock: any Clock
    private let ids: any UUIDProvider

    public init(
        clubs: any ClubRepository, seasons: any SeasonRepository,
        teams: any TeamRepository, registrations: any TeamRegistrationRepository,
        clock: any Clock, ids: any UUIDProvider
    ) {
        self.clubs = clubs
        self.seasons = seasons
        self.teams = teams
        self.registrations = registrations
        self.clock = clock
        self.ids = ids
    }

    /// Lo que el caso de uso acepta. **No es el DTO** (§2.2).
    public struct Command: Sendable {
        public let category: TeamCategory
        public let letter: String?
        public let gender: Gender
        public let modality: Modality
        public let seasonID: SeasonID

        public init(
            category: TeamCategory, letter: String?, gender: Gender, modality: Modality,
            seasonID: SeasonID
        ) {
            self.category = category
            self.letter = letter
            self.gender = gender
            self.modality = modality
            self.seasonID = seasonID
        }
    }

    /// El equipo, el club —para componer su nombre en la respuesta— y **si se ha
    /// creado** o ya existía: es lo que separa el 201 del 200.
    public struct Result: Sendable {
        public let team: Team
        public let club: Club
        public let created: Bool
    }

    public func execute(_ command: Command, actor: ActorContext) async throws -> Result {
        guard let club = try await clubs.current() else {
            throw ApplicationError.tenantNotProvisioned(slug: actor.clubSlug.value)
        }
        // El id lo puso quien llama: si no es de ninguna temporada, 404, no el
        // *schema* roto de `seasonNotFound`.
        guard try await seasons.find(command.seasonID) != nil else {
            throw ApplicationError.unknownSeason(id: "\(command.seasonID)")
        }
        let now = clock.now()

        // **El mismo equipo**: propio y con las cuatro de la clave. Un rival con la
        // misma identidad es de otro club y de una temporada (`D-104`).
        let existing = try await teams.list().first {
            $0.isOwn && $0.category == command.category && $0.letter == command.letter
                && $0.gender == command.gender && $0.modality == command.modality
        }

        if let existing {
            guard try await registrations.list(teamID: existing.id, seasonID: command.seasonID).isEmpty
            else {
                throw ApplicationError.teamAlreadyRegistered(
                    team: "\(existing.id)", season: "\(command.seasonID)")
            }
            try await registrations.save(try TeamRegistration(
                id: TeamRegistrationID(raw: ids.next()), team: existing,
                seasonID: command.seasonID, createdAt: now, updatedAt: now))
            return Result(team: existing, club: club, created: false)
        }

        let team = try Team(
            id: TeamID(raw: ids.next()), category: command.category, letter: command.letter,
            gender: command.gender, modality: command.modality, createdAt: now, updatedAt: now)
        try await teams.save(team)
        try await registrations.save(try TeamRegistration(
            id: TeamRegistrationID(raw: ids.next()), team: team,
            seasonID: command.seasonID, createdAt: now, updatedAt: now))
        // Se relee para devolver las marcas de tiempo que puso la base.
        return Result(team: try await teams.find(team.id) ?? team, club: club, created: true)
    }
}

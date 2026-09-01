import Application
import Domain
import Federation
import Fluent
import Persistence
import Tenancy
public import Vapor

/// `seed-competition` — da de alta la **entrada** de la ingesta a mano.
///
/// # Es una herramienta, no contrato, y la diferencia importa
///
/// `POST /v1/competitions` existe en el *spec* y **no es esto**: aquél es el
/// camino del administrador, en dos pasos y con su `preview` (`D-22`), y el que
/// de verdad se quiere es el enganche desde la ficha del equipo (`D-67`, F10).
/// Esto es el andamiaje para operar mientras tanto — el sitio de
/// `provision-tenant`, no el de un caso de uso.
///
/// # Lo que sí hereda del diseño, porque hacerlo por SQL lo perdía
///
/// - **Se pega la URL entera** (`D-22`). Copiar de la barra de direcciones no
///   admite errata, y un dígito cambiado **no da error**: sincroniza otro
///   calendario (`D-84`).
/// - **Los rótulos los dice la federación**, no el que teclea: se le pide el
///   calendario y de ahí salen la etiqueta de temporada (`D-71`), el nombre
///   literal de la competición (`D-72`) y el del grupo. Un `INSERT` a mano los
///   inventaba.
/// - **Todo pasa por el Dominio**, así que las fechas de la temporada se derivan
///   de su etiqueta (§3.2) y las invariantes se comprueban. Por SQL se saltaban
///   las dos cosas.
/// - **Y valida antes de escribir**: si la coordenada devuelve otra competición,
///   te enteras aquí y no tres días después mirando `ingestion_runs`.
public struct SeedCompetitionCommand: AsyncCommand {
    public struct Signature: CommandSignature {
        @Option(name: "tenant", short: "t", help: "Slug del club.")
        public var tenant: String?

        @Option(name: "url", short: "u",
                help: "URL del calendario, pegada entera de la barra de direcciones.")
        public var url: String?

        @Option(name: "category", short: "c",
                help: "Categoría de edad: \(TeamCategory.allCases.map(\.rawValue).joined(separator: ", ")).")
        public var category: String?

        @Option(name: "gender", short: "g",
                help: "Género: \(Gender.allCases.map(\.rawValue).joined(separator: ", ")).")
        public var gender: String?

        @Option(name: "division",
                help: "Rótulo de división. Por defecto, el nombre que dé la federación.")
        public var division: String?

        public init() {}
    }

    public var help: String {
        "Da de alta una competición desde la URL de su calendario (herramienta, no contrato)."
    }

    public init() {}

    public func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application

        guard let slug = signature.tenant else { throw SeedError.missing("--tenant") }
        guard let url = signature.url else { throw SeedError.missing("--url") }
        guard let rawCategory = signature.category else { throw SeedError.missing("--category") }
        guard let category = TeamCategory(rawValue: rawCategory) else {
            throw SeedError.unknown("--category", rawCategory,
                                    TeamCategory.allCases.map(\.rawValue))
        }
        // **El género no tiene defecto honesto** (`D-58`): entra en la clave única
        // de cada `Team` que la ingesta cree, así que equivocarlo no da un rótulo
        // feo — da un 409 de unicidad tres días después. La federación no lo
        // publica por competición; va dentro del nombre, y esa inferencia es del
        // `/preview` de F10, no de una herramienta.
        guard let rawGender = signature.gender else { throw SeedError.missing("--gender") }
        guard let gender = Gender(rawValue: rawGender) else {
            throw SeedError.unknown("--gender", rawGender, Gender.allCases.map(\.rawValue))
        }

        let coordinate = try RFFMEndpoints.coordinate(fromCalendarURL: url)

        // ── Se pregunta a la federación ANTES de escribir ────────────────────
        context.console.info("→ consultando la federación…")
        let calendar = try await RFFMFederationClient(transport: HTTPFederationTransport())
            .fetchCalendar(coordinate)

        context.console.info("""
              temporada:   \(calendar.seasonLabel.value)  (temporada=\(coordinate.federationSeasonID))
              competición: \(calendar.competitionName ?? "«sin nombre»")
              grupo:       \(calendar.groupLabel ?? "«sin rótulo»")
              jornadas:    \(calendar.rounds.count)
            """)

        let actor = ActorContext(clubSlug: try Slug(slug), isSystem: true)
        let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
        let now = Date()

        let competitionID = try await unitOfWork.withRepositories(actor: actor) { repositories in
            // **Reutiliza, no duplica** — igual que la cascada de `D-67`: dos
            // equipos del club pueden caer en el mismo grupo.
            let season: Season
            if let existing = try await repositories.seasons
                .findByFederationID(coordinate.federationSeasonID)
            {
                season = existing
            } else {
                season = try Season(
                    id: SeasonID(raw: UUID()),
                    label: calendar.seasonLabel,
                    federationSeasonID: coordinate.federationSeasonID,
                    createdAt: now, updatedAt: now)
                try await repositories.seasons.save(season)
            }

            if let existing = try await repositories.competitions.findByFederationGroup(
                seasonID: season.id, federationGroupID: coordinate.federationGroupID)
            {
                return existing.id
            }

            let competition = try Competition(
                id: CompetitionID(raw: UUID()),
                seasonID: season.id,
                modality: coordinate.modality,
                gender: gender,
                federationCompetitionID: coordinate.federationCompetitionID,
                federationGroupID: coordinate.federationGroupID,
                ageCategory: category,
                divisionLabel: signature.division ?? calendar.competitionName ?? "Sin división",
                groupLabel: calendar.groupLabel ?? "Grupo Único",
                // **La evidencia se guarda ya** (`D-72`), y con ella la guarda de
                // `D-84` queda armada desde el principio: sin este valor, la
                // primera pasada no tiene con qué comparar y una coordenada
                // equivocada solo la para el `UNIQUE`, con un error feo.
                federationName: calendar.competitionName,
                createdAt: now, updatedAt: now)
            try await repositories.competitions.save(competition)
            return competition.id
        }

        let id = competitionID.raw.uuidString.lowercased()
        context.console.success("""
            Competición lista: \(id)

              swift run Run ingest -t \(slug) -c \(id)

              curl -s -X POST http://\(slug).localhost:8080/v1/ingestion-runs \\
                -H 'Content-Type: application/json' \\
                -d '{"competitionIds":["\(id)"]}' | jq
            """)
    }

    enum SeedError: Error, CustomStringConvertible {
        case missing(String)
        case unknown(String, String, [String])

        var description: String {
            switch self {
            case .missing(let option):
                "Falta \(option)."
            case .unknown(let option, let value, let valid):
                "\(option) no admite '\(value)'. Valores: \(valid.joined(separator: ", "))."
            }
        }
    }
}

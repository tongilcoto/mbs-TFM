import Application
import Domain
import Fluent
import Persistence
import Tenancy
public import Vapor

/// `seed-team` — da de alta un equipo **del club** a mano.
///
/// # Es una herramienta, no contrato — el mismo estatuto que `seed-competition`
///
/// `POST /v1/teams` existe en el *spec* y **no es esto**: aquél es del bloque del
/// backoffice, que no tiene fase (Plan F10 §1.3). Esto es el andamiaje para
/// operar mientras tanto, y existe por una razón concreta: **sin él la base de
/// trabajo no puede tener un equipo propio**, y sin un equipo propio no hay nada
/// que enganchar con los dos endpoints de `D-67`. La batería no lo nota —siembra
/// por repositorio— y por eso es justo lo que la batería no ve.
///
/// # El equipo nace en el único estado desde el que se puede enganchar
///
/// - **`opponentClubID` nulo ⇒ equipo propio** (§3.6, `D-03`): no hay columna
///   `is_own`, se deriva.
/// - **`federationTeamID` nulo ⇒ sin emparejar**, que es la mitad de `D-66` sin
///   la cual el enganche no se sostiene: una fila con la clave nula **no tiene
///   segundo escritor**, así que el club puede crearla y borrarla. En cuanto se
///   engancha, deja de ser suya del todo.
///
/// Y **no lleva ningún dato de federación**, exactamente como `CreateTeamRequest`:
/// el equipo se forma, se inscribe, y **solo entonces** la federación publica
/// calendario. Ése es el orden que `D-66` protege.
///
/// # Las tres que son identidad se piden, y ninguna tiene defecto honesto
///
/// `category`, `gender` y `modality` forman la clave única junto con la letra
/// (§3.5) y quedan **congeladas** tras el alta (`D-58`). Equivocar una no da un
/// rótulo feo: da un **409 de unicidad** el día que la ingesta cree el equipo que
/// éste tenía que haber sido. `seed-competition` puede derivar la modalidad de la
/// URL; aquí no hay URL de la que derivarla, así que se teclea.
///
/// # Lo que NO hace todavía, y conviene saberlo antes de mirar una pantalla
///
/// **No escribe `TeamRegistration`**, y desde el Bloque D de F10 ya no es porque
/// la tabla no exista: existe (`C-D.2`/`C-D.3`). Es porque **quien la escribe es
/// la cascada del enganche** (`C-C.10`, [D-67]), que es la que sabe en qué
/// competición queda inscrito el equipo. Esta herramienta deja el equipo en el
/// único estado desde el que [D-67] engancha: propio, sin enganchar y **sin
/// inscribir**.
///
/// El *spec* sí exige `seasonId` en el alta de `POST /v1/teams`, y por un motivo
/// que aquí se hereda entero: sin inscripción existe el estado *"equipo creado,
/// inscrito en ninguna parte"*, **invisible en todas las pantallas** que filtran
/// por temporada. Ese alta es del backoffice y **no tiene fase**; mientras tanto
/// el equipo existe y se puede enganchar, que es para lo que esto está.
public struct SeedTeamCommand: AsyncCommand {
    public struct Signature: CommandSignature {
        @Option(name: "tenant", short: "t", help: "Slug del club.")
        public var tenant: String?

        @Option(name: "category", short: "c",
                help: "Categoría de edad: \(TeamCategory.allCases.map(\.rawValue).joined(separator: ", ")).")
        public var category: String?

        @Option(name: "gender", short: "g",
                help: "Género: \(Gender.allCases.map(\.rawValue).joined(separator: ", ")).")
        public var gender: String?

        @Option(name: "modality", short: "m",
                help: "Modalidad: \(Modality.allCases.map(\.rawValue).joined(separator: ", ")).")
        public var modality: String?

        @Option(name: "letter", short: "l",
                help: "Letra que distingue equipos de la misma categoría (\"A\", \"B\"…). Opcional.")
        public var letter: String?

        public init() {}
    }

    public var help: String {
        "Da de alta un equipo propio, sin enganchar (herramienta, no contrato)."
    }

    public init() {}

    public func run(using context: CommandContext, signature: Signature) async throws {
        let app = context.application

        guard let slug = signature.tenant else { throw SeedTeamError.missing("--tenant") }
        guard let rawCategory = signature.category else { throw SeedTeamError.missing("--category") }
        guard let category = TeamCategory(rawValue: rawCategory) else {
            throw SeedTeamError.unknown("--category", rawCategory,
                                        TeamCategory.allCases.map(\.rawValue))
        }
        guard let rawGender = signature.gender else { throw SeedTeamError.missing("--gender") }
        guard let gender = Gender(rawValue: rawGender) else {
            throw SeedTeamError.unknown("--gender", rawGender, Gender.allCases.map(\.rawValue))
        }
        guard let rawModality = signature.modality else { throw SeedTeamError.missing("--modality") }
        guard let modality = Modality(rawValue: rawModality) else {
            throw SeedTeamError.unknown("--modality", rawModality,
                                        Modality.allCases.map(\.rawValue))
        }

        let actor = ActorContext(clubSlug: try Slug(slug), isSystem: true)
        let unitOfWork = FluentTenantUnitOfWork(controlDatabase: app.db(.control))
        let now = Date()

        let teamID = try await unitOfWork.withRepositories(actor: actor) { repositories in
            // **Valida antes de escribir**, como `seed-competition`. La clave
            // única de §3.5 la haría cumplir Postgres igual, pero un `23505` en
            // crudo no dice cuál de las cinco columnas repetiste — y una
            // violación de restricción aborta el ámbito entero (`25P02`), así que
            // el error que llegaría arriba sería el equivocado.
            let existing = try await repositories.teams.list().first {
                $0.isOwn && $0.category == category && $0.letter == signature.letter
                    && $0.gender == gender && $0.modality == modality
            }
            if let existing {
                throw SeedTeamError.duplicate(
                    id: existing.id.raw.uuidString.lowercased(),
                    linked: existing.federationTeamID)
            }

            let team = try Team(
                id: TeamID(raw: UUID()),
                // Nulo: **equipo propio** (`D-03`). No es un olvido, es el dato.
                opponentClubID: nil,
                category: category,
                letter: signature.letter,
                gender: gender,
                modality: modality,
                // Nulo: **sin enganchar**, que es el estado desde el que `D-67`
                // engancha y el único en el que esta fila no tiene dos escritores.
                federationTeamID: nil,
                createdAt: now, updatedAt: now)
            try await repositories.teams.save(team)
            return team.id
        }

        let id = teamID.raw.uuidString.lowercased()
        context.console.success("""
            Equipo listo: \(id)
              \(category.rawValue) \(signature.letter ?? "—") · \(gender.rawValue) · \(modality.rawValue)
              propio, SIN enganchar y SIN inscribir (la inscribe la cascada de D-67)

              curl -s -X POST http://\(slug).localhost:8080/v1/teams/\(id)/federation-link/preview \\
                -H 'Content-Type: application/json' \\
                -d '{"calendarUrl":"<URL del calendario>"}' | jq
            """)
    }

    enum SeedTeamError: Error, CustomStringConvertible {
        case missing(String)
        case unknown(String, String, [String])
        case duplicate(id: String, linked: String?)

        var description: String {
            switch self {
            case .missing(let option):
                "Falta \(option)."
            case .unknown(let option, let value, let valid):
                "\(option) no admite '\(value)'. Valores: \(valid.joined(separator: ", "))."
            case .duplicate(let id, let linked):
                """
                Ya existe un equipo propio con esa identidad: \(id) \
                (\(linked.map { "enganchado a '\($0)'" } ?? "sin enganchar")). \
                La clave única de §3.5 son categoría + letra + género + modalidad, \
                y la letra nula ES un valor —«el único equipo»—, no un comodín.
                """
            }
        }
    }
}

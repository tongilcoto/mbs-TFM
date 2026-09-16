public import APIContract
public import Application
import Domain
import Foundation
import Logging

/// `GET /v1/ingestion-runs` y `POST /v1/ingestion-runs` (§5.6, `D-85`, `D-87`).
///
/// **Los dos primeros endpoints desde F0**, y no es casualidad que sean éstos:
/// el módulo de ingesta no expone superficie HTTP propia (§5.6), así que lo
/// único que asoma de él es *lo que la ingesta dejó dicho* y *el botón de volver
/// a pasar*.
///
/// # El disparador no es una segunda puerta de escritura
///
/// Un `POST` sobre un recurso que escribe la ingesta parecería romper la
/// frontera de propiedad de §5.1 —*"el BFF corrige lo que la ingesta trae; no
/// crea ni borra filas emparejadas"*— y no la rompe: **este `POST` no crea la
/// fila**. Pide que el job pase, y la fila la escribe él con la misma política
/// de §3.7. El cuerpo de la petición no lleva ni un solo dato de la pasada.
///
/// # Lo que el contrato declara se **devuelve**; el resto se lanza
///
/// Igual que en `updateClub`, y con su misma corrección de `A-6`/H-40: aquí
/// decía que el transporte convertía en 500 lo que se lanzara antes de que
/// `ProblemMiddleware` lo viese, y **es falso** — lo propaga envuelto en un
/// `ServerError` y el middleware lo traduce. Lo que sí es cierto y es el motivo
/// de los `catch` de abajo: **solo se puede devolver un código que el *spec*
/// declare**, porque los casos del `Output` generado son esos códigos. Se
/// atrapa, entonces, lo que se quiera servir como respuesta **del contrato**
/// —los dos 404, el 501, el 502— y se deja volar lo demás.
extension APIHandler {

    public func listIngestionRuns(_ input: Operations.listIngestionRuns.Input) async throws
        -> Operations.listIngestionRuns.Output
    {
        let actor: ActorContext
        do { actor = try Self.currentActor() } catch {
            return .badRequest(.init(body: .application_problem_plus_json(
                Self.problem(status: 400, code: "TENANT_NOT_RESOLVED",
                             title: "La petición no identifica ningún club"))))
        }

        guard let competitionID = UUID(uuidString: input.query.competitionId) else {
            return .badRequest(.init(body: .application_problem_plus_json(
                Self.problem(status: 400, code: "INVALID_UUID",
                             title: "`competitionId` no es un UUID",
                             detail: input.query.competitionId))))
        }

        // **El rango del `limit` lo comprueba aquí el adaptador**, porque el
        // generador ignora `minimum`/`maximum`/`default` (`D-65`, tabla de
        // reparto de §5.5). Un `limit=0` no es un error de tipo: es un valor
        // fuera de contrato.
        let limit = input.query.limit ?? Self.defaultRunLimit
        guard (1...Self.maxRunLimit).contains(limit) else {
            return .badRequest(.init(body: .application_problem_plus_json(
                Self.problem(status: 400, code: "INVALID_LIMIT",
                             title: "`limit` fuera de rango",
                             detail: "1..\(Self.maxRunLimit), recibido \(limit)"))))
        }

        do {
            let runs = try await unitOfWork.withRepositories(actor: actor) { repositories in
                // **El 404 es del ámbito**, no de la lista: una competición sin
                // pasadas devuelve 200 con array vacío, que es distinto de una
                // competición que no existe. Sin esta comprobación, pedir la de
                // otro club daría un 200 mintiendo.
                guard try await repositories.competitions.find(CompetitionID(raw: competitionID))
                    != nil
                else {
                    throw ApplicationError.competitionNotFound(id: "\(competitionID)")
                }
                return try await repositories.ingestionRuns.list(
                    competitionID: CompetitionID(raw: competitionID), limit: limit)
            }
            return .ok(.init(body: .json(runs.map { $0.toResponse() })))
        } catch ApplicationError.competitionNotFound(let id) {
            return .notFound(.init(body: .application_problem_plus_json(
                Self.problem(status: 404, code: "COMPETITION_NOT_FOUND",
                             title: "Competición desconocida", detail: id))))
        }
    }

    public func triggerIngestion(_ input: Operations.triggerIngestion.Input) async throws
        -> Operations.triggerIngestion.Output
    {
        let actor: ActorContext
        do { actor = try Self.currentActor() } catch {
            return .badRequest(.init(body: .application_problem_plus_json(
                Self.problem(status: 400, code: "TENANT_NOT_RESOLVED",
                             title: "La petición no identifica ningún club"))))
        }

        var seasonID: SeasonID?
        var competitionIDs: [CompetitionID]?
        if case .json(let payload) = input.body {
            do {
                seasonID = try payload.seasonId.map {
                    SeasonID(raw: try Self.uuid($0, field: "seasonId"))
                }
                competitionIDs = try payload.competitionIds.map { list in
                    try list.map { CompetitionID(raw: try Self.uuid($0, field: "competitionIds")) }
                }
            } catch let error as InvalidUUID {
                return .badRequest(.init(body: .application_problem_plus_json(
                    Self.problem(status: 400, code: "INVALID_UUID",
                                 title: "`\(error.field)` no es un UUID",
                                 detail: error.value))))
            }
        }

        // **`minItems: 1` lo comprueba aquí el adaptador**, porque el generador
        // lo ignora (`D-65`). Una lista vacía **no significa "todas"**: significa
        // que el cliente no ha decidido, y adivinar por él sería lanzar el
        // recorrido entero de un club por una casilla sin marcar.
        if let competitionIDs, competitionIDs.isEmpty {
            return .badRequest(.init(body: .application_problem_plus_json(
                Self.problem(status: 400, code: "EMPTY_SELECTION",
                             title: "`competitionIds` no puede venir vacío",
                             detail: "minItems: 1. Para la temporada vigente entera, omítelo."))))
        }

        // **Sin antirrebote** (§5.6): quien pulsa el botón lo pulsa porque quiere
        // ahora, y una guarda silenciosa le diría que ya está sincronizado sin
        // haber ido a mirar.
        let scope = IngestionScope(
            seasonID: seasonID, competitionIDs: competitionIDs, minInterval: nil)

        let useCase = IngestClubCalendars(
            unitOfWork: unitOfWork, federationClients: federationClients,
            clock: clock, ids: ids)

        do {
            // ── Una sola competición: se hace aquí y se devuelve (§2.3-c) ────
            //
            // **Lo decide la petición, no los datos.** Con `{}` sobre un club que
            // solo tiene una competición la respuesta sigue siendo 202: que un
            // cliente reciba 200 o 202 según cuántos equipos tenga el club sería
            // una forma de respuesta imposible de programar.
            if competitionIDs?.count == 1 {
                let report = try await useCase.execute(scope: scope, actor: actor)
                switch report.entries.first?.outcome {
                case .synced(let run):
                    return .ok(.init(body: .json(run.toResponse())))
                case .failed(let reason):
                    // **502**: el fallo es del tercero, no del cliente. Mismo
                    // criterio que `D-84` en `ProblemMiddleware` — un 4xx
                    // invitaría a reintentar con otro cuerpo, y eso aquí no
                    // arregla nada. La constancia ya está en `ingestion_runs`.
                    return .badGateway(.init(body: .application_problem_plus_json(
                        Self.problem(status: 502, code: "INGESTION_FAILED",
                                     title: "La pasada no terminó",
                                     detail: reason))))
                case nil:
                    // Inalcanzable por construcción —el plan de una competición
                    // encontrada tiene exactamente un elemento—, pero el tipo de
                    // retorno exige un valor y un `fatalError` aquí tumbaría el
                    // servidor por una rama que no debería existir.
                    return .badGateway(.init(body: .application_problem_plus_json(
                        Self.problem(status: 502, code: "INGESTION_FAILED",
                                     title: "La pasada no llegó a ejecutarse"))))
                }
            }

            // ── Una temporada entera: se acepta y se hace después (D-67) ─────
            //
            // El plan se calcula **antes** de responder, y no solo para poder
            // decir qué entra: es lo que hace que una `seasonId` inexistente dé
            // 404 aquí y no un `202` seguido de un fallo que nadie ve.
            let planned = try await useCase.plannedCompetitions(scope: scope, actor: actor)
            await background.enqueue {
                await self.runAccepted(
                    useCase, scope: scope, actor: actor, planned: planned)
            }
            return .accepted(.init(body: .json(.init(
                competitionIds: planned.map { $0.raw.uuidString.lowercased() }))))

        } catch ApplicationError.competitionNotFound(let id) {
            return .notFound(.init(body: .application_problem_plus_json(
                Self.problem(status: 404, code: "COMPETITION_NOT_FOUND",
                             title: "Competición desconocida", detail: id))))
        } catch ApplicationError.unknownSeason(let id) {
            return .notFound(.init(body: .application_problem_plus_json(
                Self.problem(status: 404, code: "SEASON_NOT_FOUND",
                             title: "Temporada desconocida", detail: id))))
        } catch ApplicationError.federationAdapterMissing(let federation) {
            // **501, no 500**: no se ha roto nada. La federación está en el
            // catálogo y su adaptador todavía no se ha escrito (F9).
            return .notImplemented(.init(body: .application_problem_plus_json(
                Self.problem(status: 501, code: "FEDERATION_ADAPTER_MISSING",
                             title: "Federación todavía sin adaptador",
                             detail: "No hay adaptador de ingesta para '\(federation)'."))))
        }
    }

    /// El trabajo que el `202` prometió, con la **única salida que le queda**
    /// (H-27).
    ///
    /// # Por qué esto no puede ser `_ = try? await …`
    ///
    /// Así estaba, y así el `202` aceptaba dos competiciones, no hacía ninguna y
    /// **nadie se enteraba jamás**. Las tres formas de enterarse se caen a la vez
    /// en este camino: la **respuesta** ya salió; la fila de `ingestion_runs`
    /// (`D-85`) se escribe *en la base*, que es justo lo que falla en el caso malo
    /// (H-23); y el **código de salida** de `D-86` es del comando `ingest`, no de
    /// un servidor, que no termina. Queda el log.
    ///
    /// # Qué se registra y qué no
    ///
    /// - **El recorrido abortado** y **el error que sale del caso de uso** son
    ///   `error`: de esos dos no queda constancia en ningún otro sitio.
    /// - **Las competiciones que fallaron** con la base viva son `warning`, y a
    ///   propósito más flojo: cada una **ya tiene su fila** con su motivo
    ///   (`D-85`), así que esto es una miga para el que lee el log, no la fuente.
    ///
    /// **Y lo que esto no arregla, para que nadie lo confunda con la solución:**
    /// un log lo lee el operador, no el backoffice. Que la pantalla se entere
    /// —sin *push*, que es como es— necesita que quede **fila** desde el instante
    /// en que se acepta; hoy `IngestionOutcome` solo tiene `succeeded` y `failed`,
    /// así que el `202` no deja ni un hueco donde mirar y `ingestionHealth`
    /// (`D-89`) sigue diciendo `ok`. Eso es modelo, contrato y una enmienda a
    /// `D-88` —que hoy dice *"el `POST` no crea la fila"*—: va a **F10**, con el
    /// `202` de `D-67`.
    func runAccepted(
        _ useCase: IngestClubCalendars,
        scope: IngestionScope,
        actor: ActorContext,
        planned: [CompetitionID]
    ) async {
        let ids: @Sendable ([CompetitionID]) -> String = { list in
            list.map { $0.raw.uuidString.lowercased() }.joined(separator: ", ")
        }
        do {
            let report = try await useCase.execute(scope: scope, actor: actor)
            let attempted = Set(report.entries.map(\.competitionID))
            let untouched = planned.filter { !attempted.contains($0) }

            if report.abortedByInfrastructure {
                // El mensaje **no** afirma que quedara algo detrás: cuando la que
                // se cae es la última, no queda nada, y decirlo igual sería el
                // tipo de imprecisión que hace desconfiar de un log.
                logger.error(
                    "El recorrido aceptado con 202 se paró: la base dejó de responder",
                    metadata: [
                        "club": .string(actor.clubSlug.value),
                        "intentadas": .string("\(report.entries.count)"),
                        "sin-intentar": .string(
                            untouched.isEmpty ? "ninguna" : ids(untouched)),
                    ])
            } else if report.hasFailures {
                logger.warning(
                    "Alguna competición del recorrido aceptado con 202 falló",
                    metadata: [
                        "club": .string(actor.clubSlug.value),
                        "detalle": .string("en ingestion_runs"),
                    ])
            }
        } catch {
            logger.error(
                "El trabajo aceptado con 202 no se hizo",
                metadata: [
                    "club": .string(actor.clubSlug.value),
                    "aceptadas": .string(ids(planned)),
                    "motivo": .string(diagnosticText(for: error)),
                ])
        }
    }

    /// Veinte: una competición hace ~2 pasadas por semana (§5.6), así que la cola
    /// reciente por defecto cubre un par de meses — que es el horizonte de la
    /// pregunta *«¿desde cuándo falta este partido?»*.
    static let defaultRunLimit = 20
    static let maxRunLimit = 100

    struct InvalidUUID: Error { let field: String; let value: String }

    static func uuid(_ raw: String, field: String) throws -> UUID {
        guard let value = UUID(uuidString: raw) else {
            throw InvalidUUID(field: field, value: raw)
        }
        return value
    }
}

extension Domain.IngestionRun {
    /// Mapeo `Entidad → DTO` (§2.2).
    ///
    /// Los ocho contadores viajan **anidados** aunque en la tabla sean ocho
    /// columnas planas: la forma del DTO no es la de la fila (§5.2), y ocho
    /// claves sueltas en la raíz de la respuesta esconderían los cuatro campos
    /// que de verdad se leen.
    func toResponse() -> Components.Schemas.IngestionRunResponse {
        .init(
            id: id.raw.uuidString.lowercased(),
            competitionId: competitionID.raw.uuidString.lowercased(),
            kind: kind.toContract(),
            startedAt: startedAt,
            finishedAt: finishedAt,
            outcome: outcome.toContract(),
            error: error,
            counters: .init(
                opponentClubsCreated: opponentClubsCreated,
                opponentClubsUpdated: opponentClubsUpdated,
                teamsCreated: teamsCreated,
                teamsUpdated: teamsUpdated,
                roundsCreated: roundsCreated,
                roundsUpdated: roundsUpdated,
                matchesCreated: matchesCreated,
                matchesUpdated: matchesUpdated,
                standingRowsCreated: standingRowsCreated,
                standingRowsUpdated: standingRowsUpdated),
            skipped: skipped.map {
                .init(reason: $0.reason.toContract(), detail: $0.detail)
            })
    }
}

extension Domain.IngestionKind {
    /// `switch` exhaustivo, como sus hermanos y por lo mismo (`D-61`): es lo que
    /// hace que añadir `scorers` en F8 **no compile** hasta que el caso exista
    /// también en el *spec*, que es la fuente de verdad del contrato (`D-25`).
    func toContract() -> Components.Schemas.IngestionKind {
        switch self {
        case .calendar: .calendar
        case .standings: .standings
        }
    }
}

extension Domain.IngestionOutcome {
    func toContract() -> Components.Schemas.IngestionOutcome {
        switch self {
        case .succeeded: .succeeded
        case .failed: .failed
        }
    }
}

extension Domain.IngestionSkip.Reason {
    /// `switch` exhaustivo, igual que `FederationCode.toContract()` y por lo
    /// mismo (`D-61`): son dos enumerados distintos que pueden divergir.
    ///
    /// **Y aquí la traducción no es cosmética.** Los valores del Dominio se
    /// serializan tal cual dentro del `jsonb` de `skipped` desde F5, así que ya
    /// hay datos escritos con ellos; el contrato, en cambio, usa `snake_case`
    /// como el resto de sus enumerados (§5.2). Cambiar cualquiera de los dos
    /// lados para que coincidan rompería una cosa u otra: esto es lo que permite
    /// que las dos convenciones convivan sin que nadie tenga que acordarse.
    func toContract() -> Components.Schemas.IngestionSkipReason {
        switch self {
        case .ambiguousOpponentClub: .ambiguous_opponent_club
        case .ambiguousTeam: .ambiguous_team
        case .ambiguousMatch: .ambiguous_match
        case .unresolvedTeam: .unresolved_team
        case .missingMatchDate: .missing_match_date
        case .unsluggableClubName: .unsluggable_club_name
        case .duplicateClubName: .duplicate_club_name
        case .unknownStandingTeam: .unknown_standing_team
        }
    }
}

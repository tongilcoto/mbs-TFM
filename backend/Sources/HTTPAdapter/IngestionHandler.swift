public import APIContract
public import Application
import Domain
import Foundation

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
/// # Los errores se **devuelven**, no se lanzan
///
/// Igual que en `updateClub`, y por lo mismo: el transporte generado atrapa lo
/// que se lance y lo convierte en **500** antes de que `ProblemMiddleware` lo
/// vea. La consecuencia buena es que **un código que el *spec* no declara no se
/// puede devolver**, porque no existe como caso del `Output`.
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
                _ = try? await useCase.execute(scope: scope, actor: actor)
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
                matchesUpdated: matchesUpdated),
            skipped: skipped.map {
                .init(reason: $0.reason.toContract(), detail: $0.detail)
            })
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
        }
    }
}

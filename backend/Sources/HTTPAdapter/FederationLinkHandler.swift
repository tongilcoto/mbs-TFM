public import APIContract
// `internal` y no `public`: los dos `public func` de abajo solo exponen tipos de
// `APIContract`, así que nada de `Application` ni de `Domain` cruza la firma. Es
// el mismo trato que `IngestionHandler`, y lo pide `UnusedImportAccess`.
import Application
import Domain
// `uuidString` lo define Foundation, y `MemberImportVisibility` (SE-0444) exige
// declarar el módulo que define el miembro aunque el tipo venga de otro. Es la
// misma bandera que `ProblemMiddleware` cobra con `HTTPTypes`.
import Foundation

/// `POST /v1/teams/{id}/federation-link/preview` y `POST /v1/teams/{id}/federation-link`
/// — los dos endpoints del enganche (`D-67`, F10).
///
/// # Los dos nacieron como ESQUELETO en el Bloque 0, y el porqué sigue valiendo
///
/// `C-0.1` añadió las dos operaciones al `filter` de
/// `openapi-generator-config.yaml`, que es el trinquete del alcance (`D-69`):
/// desde ese momento `APIProtocol` declara sus dos métodos y `APIHandler` **no
/// compila** hasta que existen. Sin el esqueleto, el *build* habría quedado rojo
/// desde `C-0.1` hasta este bloque, y en esa ventana A, B, C y D **no habrían
/// podido correr la batería** — que es justo lo que el método exige en cada
/// ciclo.
///
/// `C-E.3` y `C-E.4` son los ciclos que los sustituyen por los de verdad.
///
/// # Lo que se devuelve y lo que se deja volar
///
/// Igual que en `IngestionHandler`, y por el mismo motivo: **solo se puede
/// devolver un código que el *spec* declare**, porque los casos del `Output`
/// generado son esos códigos. Lo que se quiera servir como respuesta **del
/// contrato** se atrapa; lo demás vuela hasta `ProblemMiddleware`, que lo
/// traduce (`A-6`/H-40).
extension APIHandler {

    /// **El primer paso del enganche** (`D-67`, §2.3-c): 200 con lo que hay en
    /// la coordenada, y **sin persistir nada** (`C-E.3`).
    ///
    /// Es la única ruta síncrona con latencia de terceros: llama a la federación
    /// **dentro de la petición**, que es su motivo de existir. Por eso es también
    /// la que estrena la traducción de `FederationError` (`C-E.1`) — hasta aquí
    /// el `202` respondía antes de llamar.
    public func previewFederationLink(_ input: Operations.previewFederationLink.Input) async throws
        -> Operations.previewFederationLink.Output
    {
        let actor = try actors.currentActor()

        // **400 y no 404**, con el mismo criterio que `listIngestionRuns`: lo que
        // no es un UUID no es un equipo que falte, es un valor que no se pudo
        // decodificar. El 404 del equipo inexistente es otra cosa y va en
        // `C-E.6`.
        let teamID: TeamID
        do {
            teamID = TeamID(raw: try Self.uuid(input.path.teamId, field: "teamId"))
        } catch let error as InvalidUUID {
            return .badRequest(.init(body: .application_problem_plus_json(
                Self.problem(status: 400, code: "INVALID_UUID",
                             title: "`\(error.field)` no es un UUID",
                             detail: error.value))))
        }

        let payload: Components.Schemas.FederationLinkPreviewRequest
        switch input.body {
        case .json(let json): payload = json
        }

        let preview = try await PreviewFederationLink(
            unitOfWork: unitOfWork, federationClients: federationClients
        ).execute(
            teamID: teamID, calendarURL: payload.federationCalendarUrl, actor: actor)

        return .ok(.init(body: .json(preview.toResponse())))
    }

    /// **El segundo paso, y el único camino que lleva a sincronizar** (`D-67`):
    /// 202 con `IngestJobResponse` (`C-E.4`).
    ///
    /// `202` y no `201` porque la primera ingesta no cabe en una respuesta:
    /// detrás del calendario vienen ~240 partidos y un escudo por club que
    /// descargar (`D-19`). Lo que el cuerpo trae no es el resultado, es **con
    /// qué seguirlo** — el `jobId` es la fila `accepted` que la cascada escribe
    /// **antes** de responder (`D-96`, `C-C.11`).
    public func linkTeamToFederation(_ input: Operations.linkTeamToFederation.Input) async throws
        -> Operations.linkTeamToFederation.Output
    {
        let actor = try actors.currentActor()

        let teamID: TeamID
        do {
            teamID = TeamID(raw: try Self.uuid(input.path.teamId, field: "teamId"))
        } catch let error as InvalidUUID {
            return .badRequest(.init(body: .application_problem_plus_json(
                Self.problem(status: 400, code: "INVALID_UUID",
                             title: "`\(error.field)` no es un UUID",
                             detail: error.value))))
        }

        let payload: Components.Schemas.FederationLinkRequest
        switch input.body {
        case .json(let json): payload = json
        }

        // **La etiqueta se valida aquí y su rechazo es un 400, no un 422.** Por
        // el criterio de `ProblemMiddleware` esto sería 422 —el cuerpo se
        // decodificó y dice algo que la regla no admite—, pero **esta ruta no
        // declara 422** (`C-0.5`), y solo se puede devolver lo que el contrato
        // admite: un código sin declarar no lo sabe leer un cliente generado.
        // Es el mismo razonamiento con el que `C-B.2` puso en 400 la URL
        // ilegible.
        let seasonLabel: SeasonLabel?
        do {
            seasonLabel = try payload.seasonLabel.map { try SeasonLabel($0) }
        } catch let error as DomainError {
            return .badRequest(.init(body: .application_problem_plus_json(
                Self.problem(status: 400, code: "INVALID_VALUE",
                             title: "Valor no válido",
                             detail: "seasonLabel: \(error)"))))
        }

        let result = try await LinkTeamToFederation(
            unitOfWork: unitOfWork, federationClients: federationClients,
            clock: clock, ids: ids
        ).execute(
            FederationLinkRequest(
                teamID: teamID,
                calendarURL: payload.federationCalendarUrl,
                ownTeamFederationID: payload.ownTeamFederationId,
                gender: payload.gender.value1.toDomain(),
                seasonLabel: seasonLabel),
            actor: actor)

        // ── Y la primera ingesta, que es lo que el `202` promete ─────────────
        //
        // Sin esto el enganche dejaría una fila `accepted` que **jamás cierra**:
        // exactamente el *"202 mudo"* que `C-C.12` existe para evitar un paso
        // antes. La pasada adopta esa fila —no escribe una segunda— porque
        // `IngestCalendar` la busca antes de abrir la suya (F10-bis), que es lo
        // que hace que **las dos puertas del 202 la abran igual**.
        //
        // **Sin antirrebote** (`minInterval: nil`), como el otro disparador: la
        // competición acaba de nacer y nunca se sincronizó, así que la excepción
        // de `D-87` la dejaría entrar de todos modos — pedirlo explícitamente es
        // decir la verdad sobre lo que esta ruta quiere.
        //
        // **Y va por `runAccepted` y no por un `try?`** (`H-27`): detrás de un
        // `202` no hay respuesta, ni `ingestion_runs` cuando la que falla es la
        // base, ni código de salida. Queda el log, y éste es el **segundo** `202`
        // del sistema — la segunda copia de aquel silencio.
        let scope = IngestionScope(
            seasonID: nil, competitionIDs: [result.competitionID], minInterval: nil)
        let useCase = IngestClubCalendars(
            unitOfWork: unitOfWork, federationClients: federationClients,
            clock: clock, ids: ids)
        await background.enqueue {
            await self.runAccepted(
                useCase, scope: scope, actor: actor, planned: [result.competitionID])
        }

        return .accepted(.init(body: .json(.init(
            jobId: "\(result.jobID)",
            // **`encolado` es el único valor honesto aquí**: la respuesta sale
            // antes de que el trabajo empiece. Los otros tres los cuenta el
            // registro de `D-85`, que es lo que se consulta con el `jobId`.
            status: .encolado,
            teamId: "\(result.teamID)",
            competitionId: "\(result.competitionID)",
            seasonId: "\(result.seasonID)")))
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mapeo `Caso de uso → DTO`, trabajo del adaptador primario (§2.2).
// ─────────────────────────────────────────────────────────────────────────────

extension FederationLinkPreview {
    /// Lo que hay en la coordenada, **tal y como lo declara el contrato**.
    ///
    /// La mezcla de la que sale no es caprichosa y está razonada en el caso de
    /// uso: los **rótulos** son de la fuente, para que el administrador
    /// reconozca su grupo como lo ve en la web de la federación (`D-16`), y la
    /// **identidad** es de la fila que la cascada va a reutilizar o crear,
    /// porque es la que decide si esto va a dar un 409.
    func toResponse() -> Components.Schemas.FederationLinkPreviewResponse {
        .init(
            season: .init(
                federationSeasonId: season.federationSeasonID,
                label: season.label,
                exists: season.exists),
            competition: .init(
                modality: competition.modality.toContract(),
                gender: .init(value1: competition.gender.toContract()),
                ageCategory: competition.ageCategory.toContract(),
                divisionLabel: competition.divisionLabel,
                groupLabel: competition.groupLabel,
                federationCompetitionId: competition.federationCompetitionID,
                federationGroupId: competition.federationGroupID,
                roundCount: competition.roundCount,
                teams: competition.teams.map {
                    .init(
                        // **Anulable, y viaja igual** (`C-C.5`): el equipo que la
                        // fuente publica sin código no desaparece de la lista, que
                        // es donde un humano reconoce su club. Filtrarlo aquí
                        // escondería el caso justo en esa pantalla.
                        federationTeamId: $0.federationTeamID,
                        rawName: $0.rawName,
                        crestUrl: $0.crestURL)
                },
                alreadyRegistered: competition.alreadyRegistered),
            identityMatches: identityMatches)
    }
}

extension Domain.Modality {
    /// `switch` exhaustivo a propósito, por lo mismo que `FederationCode` y sus
    /// tres hermanos (`D-61`): son **dos tipos distintos que pueden divergir**,
    /// así que añadir una modalidad al Dominio **no compila** hasta que también
    /// se declare en el contrato.
    ///
    /// El compilador obliga a escribir la línea, **no a escribirla bien**. Lo
    /// que exige que los valores sean distintos entre sí es `C-E.9`.
    func toContract() -> Components.Schemas.Modality {
        switch self {
        case .futbol11: .futbol_11
        case .futbol7: .futbol_7
        case .futbol5: .futbol_5
        case .futbolSala: .futbol_sala
        case .futbolPlaya: .futbol_playa
        }
    }
}

extension Domain.Gender {
    func toContract() -> Components.Schemas.Gender {
        switch self {
        case .masculino: .masculino
        case .femenino: .femenino
        case .mixto: .mixto
        }
    }
}

extension Domain.TeamCategory {
    func toContract() -> Components.Schemas.TeamCategory {
        switch self {
        case .prebenjamin: .prebenjamin
        case .benjamin: .benjamin
        case .alevin: .alevin
        case .infantil: .infantil
        case .cadete: .cadete
        case .juvenil: .juvenil
        case .senior: .senior
        }
    }
}

extension Components.Schemas.Gender {
    /// **La traducción de vuelta**, del contrato al Dominio, y es la primera del
    /// proyecto en ese sentido: hasta F10 nada que el cliente eligiera de un
    /// enumerado entraba en una escritura.
    ///
    /// `switch` exhaustivo por lo mismo que sus hermanas (`D-61`), y aquí el
    /// argumento muerde más: `gender` entra en la clave única de `Team` (§3.5),
    /// así que un valor traducido mal **no da un rótulo feo, da un 409** — o
    /// peor, engancha al equipo a una competición que no es la suya (`D-58`).
    func toDomain() -> Domain.Gender {
        switch self {
        case .masculino: .masculino
        case .femenino: .femenino
        case .mixto: .mixto
        }
    }
}

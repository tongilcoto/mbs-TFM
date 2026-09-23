import Fluent
import Foundation
public import Application
public import Domain

// ─────────────────────────────────────────────────────────────────────────────
// Los cuatro adaptadores secundarios de la salida de la ingesta (§4.3, §4.4).
//
// **Todos con la misma forma**: `list` carga lo que la pasada necesita para
// emparejar y `save` hace *upsert* por `id`. Ninguno tiene `delete`, y no es un
// olvido: la ingesta no borra —lo que la fuente deja de publicar no se destruye
// (`D-75`)— y el BFF no tiene `DELETE` sobre estas entidades (§5.1).
//
// **El `save` es por `id` y no por clave natural**, que es lo que permite que el
// caso de uso ponga el UUID antes de guardar y meta la fila recién creada en los
// candidatos de la misma pasada sin releerla.
// ─────────────────────────────────────────────────────────────────────────────

public struct FluentOpponentClubRepository: OpponentClubRepository {
    private let database: any Database
    public init(database: any Database) { self.database = database }

    public func list() async throws -> [OpponentClub] {
        try await OpponentClubRecord.query(on: database).sort(\.$name).all()
            .map { try $0.toDomain() }
    }

    public func save(_ club: OpponentClub) async throws {
        if let existing = try await OpponentClubRecord.find(club.id.raw, on: database) {
            existing.apply(club)
            try await existing.update(on: database)
        } else {
            let record = OpponentClubRecord()
            record.id = club.id.raw
            record.apply(club)
            try await record.create(on: database)
        }
    }
}

public struct FluentTeamRepository: TeamRepository {
    private let database: any Database
    public init(database: any Database) { self.database = database }

    public func list() async throws -> [Team] {
        try await TeamRecord.query(on: database).sort(\.$category).sort(\.$letter).all()
            .map { try $0.toDomain() }
    }

    /// **ESQUELETO del Bloque C, y está mal a propósito.** `C-D.1` lo escribe.
    ///
    /// Devuelve *"no está"* siempre: un valor **válido y equivocado**, que es lo
    /// que el método pide (Plan §5.1). Nace aquí y no en el Bloque D porque el
    /// puerto lo estrena el Bloque C —el caso de uso del enganche llega al equipo
    /// **por su id**— y sin esta línea el *build* se queda rojo hasta `C-D.1`,
    /// que es justo lo que el esqueleto de `C-0.1` compró para los bloques A–D.
    public func find(_ id: TeamID) async throws -> Team? { nil }

    public func save(_ team: Team) async throws {
        if let existing = try await TeamRecord.find(team.id.raw, on: database) {
            existing.apply(team)
            try await existing.update(on: database)
        } else {
            let record = TeamRecord()
            record.id = team.id.raw
            record.apply(team)
            try await record.create(on: database)
        }
    }
}

public struct FluentRoundRepository: RoundRepository {
    private let database: any Database
    public init(database: any Database) { self.database = database }

    public func list(competitionID: CompetitionID) async throws -> [Round] {
        try await RoundRecord.query(on: database)
            .filter(\.$competition.$id == competitionID.raw)
            .sort(\.$number)
            .all()
            .map { try $0.toDomain() }
    }

    public func save(_ round: Round) async throws {
        if let existing = try await RoundRecord.find(round.id.raw, on: database) {
            existing.apply(round)
            try await existing.update(on: database)
        } else {
            let record = RoundRecord()
            record.id = round.id.raw
            record.apply(round)
            try await record.create(on: database)
        }
    }
}

public struct FluentMatchRepository: MatchRepository {
    private let database: any Database
    public init(database: any Database) { self.database = database }

    public func list(competitionID: CompetitionID) async throws -> [Match] {
        try await MatchRecord.query(on: database)
            .filter(\.$competition.$id == competitionID.raw)
            .sort(\.$matchDate)
            .all()
            .map { try $0.toDomain() }
    }

    public func save(_ match: Match) async throws {
        if let existing = try await MatchRecord.find(match.id.raw, on: database) {
            existing.apply(match)
            try await existing.update(on: database)
        } else {
            let record = MatchRecord()
            record.id = match.id.raw
            record.apply(match)
            try await record.create(on: database)
        }
    }
}

// ── Mapeo Record ↔ Entidad (§4.4) ────────────────────────────────────────────

extension OpponentClubRecord {
    func apply(_ club: OpponentClub) {
        name = club.name
        shortName = club.shortName
        slug = club.slug.value
        federationClubID = club.federationClubID
        crestKey = club.crestKey
    }

    func toDomain() throws -> OpponentClub {
        guard let createdAt, let updatedAt else {
            throw PersistenceError.missingTimestamp(
                table: Self.schema, id: try requireID().uuidString)
        }
        return try OpponentClub(
            id: OpponentClubID(raw: try requireID()),
            name: name,
            shortName: shortName,
            // Que el slug guardado no valide es corrupción por la misma vía que
            // un enumerado fuera de rango: no hay `CHECK` que lo sostenga, así
            // que el `pattern` lo hace cumplir el VO al entrar y al salir.
            slug: try Slug(slug),
            federationClubID: federationClubID,
            crestKey: crestKey,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension TeamRecord {
    func apply(_ team: Team) {
        $opponentClub.id = team.opponentClubID?.raw
        category = team.category.rawValue
        letter = team.letter
        gender = team.gender.rawValue
        modality = team.modality.rawValue
        federationTeamID = team.federationTeamID
    }

    func toDomain() throws -> Team {
        guard let category = TeamCategory(rawValue: category) else {
            throw PersistenceError.corruptEnumeration(
                table: Self.schema, column: "category", value: self.category)
        }
        guard let gender = Gender(rawValue: gender) else {
            throw PersistenceError.corruptEnumeration(
                table: Self.schema, column: "gender", value: self.gender)
        }
        guard let modality = Modality(rawValue: modality) else {
            throw PersistenceError.corruptEnumeration(
                table: Self.schema, column: "modality", value: self.modality)
        }
        guard let createdAt, let updatedAt else {
            throw PersistenceError.missingTimestamp(
                table: Self.schema, id: try requireID().uuidString)
        }
        return try Team(
            id: TeamID(raw: try requireID()),
            opponentClubID: $opponentClub.id.map { OpponentClubID(raw: $0) },
            category: category,
            letter: letter,
            gender: gender,
            modality: modality,
            federationTeamID: federationTeamID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension RoundRecord {
    func apply(_ round: Round) {
        $competition.id = round.competitionID.raw
        number = round.number
        startDate = round.startDate
        endDate = round.endDate
    }

    func toDomain() throws -> Round {
        guard let createdAt, let updatedAt else {
            throw PersistenceError.missingTimestamp(
                table: Self.schema, id: try requireID().uuidString)
        }
        return try Round(
            id: RoundID(raw: try requireID()),
            competitionID: CompetitionID(raw: $competition.id),
            number: number,
            startDate: startDate,
            endDate: endDate,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension MatchRecord {
    func apply(_ match: Match) {
        $competition.id = match.competitionID.raw
        $round.id = match.roundID.raw
        matchDate = match.kickoff.date
        kickoffTime = match.kickoff.time?.text
        $homeTeam.id = match.homeTeamID.raw
        $awayTeam.id = match.awayTeamID.raw
        homeScore = match.result?.homeScore
        awayScore = match.result?.awayScore
        status = match.status.rawValue
        venue = match.venue
        federationMatchID = match.federationMatchID
    }

    func toDomain() throws -> Match {
        guard let status = MatchStatus(rawValue: status) else {
            throw PersistenceError.corruptEnumeration(
                table: Self.schema, column: "status", value: self.status)
        }
        guard let createdAt, let updatedAt else {
            throw PersistenceError.missingTimestamp(
                table: Self.schema, id: try requireID().uuidString)
        }

        // El par de `MatchResult`, reconstruido. Media fila es corrupción: el
        // esquema no puede expresar "los dos o ninguno" y este es el sitio donde
        // esa invariante vuelve a existir.
        let result: MatchResult?
        switch (homeScore, awayScore) {
        case (nil, nil):
            result = nil
        case (let home?, let away?):
            result = try MatchResult(homeScore: home, awayScore: away)
        default:
            throw PersistenceError.corruptPair(
                table: Self.schema, columns: "home_score/away_score",
                id: try requireID().uuidString)
        }

        // Un `kickoff_time` que no parsea es corrupción por la misma vía: la
        // columna es texto libre para Postgres, así que el formato lo sostiene
        // el VO y no un `CHECK`.
        let time: WallClockTime?
        if let kickoffTime {
            guard let parsed = WallClockTime(text: kickoffTime) else {
                throw PersistenceError.corruptEnumeration(
                    table: Self.schema, column: "kickoff_time", value: kickoffTime)
            }
            time = parsed
        } else {
            time = nil
        }

        return try Match(
            id: MatchID(raw: try requireID()),
            competitionID: CompetitionID(raw: $competition.id),
            roundID: RoundID(raw: $round.id),
            kickoff: Kickoff(date: matchDate, time: time),
            homeTeamID: TeamID(raw: $homeTeam.id),
            awayTeamID: TeamID(raw: $awayTeam.id),
            result: result,
            status: status,
            venue: venue,
            federationMatchID: federationMatchID,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public struct FluentIngestionRunRepository: IngestionRunRepository {
    private let database: any Database
    public init(database: any Database) { self.database = database }

    /// *Upsert* por `id`, **y eso es F10-bis enmendando su propia
    /// documentación** ([D-96]).
    ///
    /// Era `create` a secas, con un argumento que era bueno mientras toda fila
    /// naciera acabada: *"una pasada ocurrió o no ocurrió, y reescribir la
    /// historia de una sincronización no significa nada"*. La fila `accepted`
    /// crea la excepción y la crea entera — dice *"todavía no ha ocurrido"*, así
    /// que cerrarla no reescribe ninguna historia: **la termina**. Insertar una
    /// fila nueva dejaría dos versiones de la misma pasada, una eternamente
    /// abierta, que es lo que `IngestionRun.closed(as:at:)` llama el peor
    /// desenlace posible.
    ///
    /// La identidad es el `id`, como en todos sus hermanos, y por lo mismo: lo
    /// pone el caso de uso, así que la fila recién escrita se puede volver a
    /// tocar en la misma pasada sin releerla.
    public func record(_ run: IngestionRun) async throws {
        if let existing = try await IngestionRunRecord.find(run.id.raw, on: database) {
            existing.apply(run)
            try await existing.update(on: database)
            return
        }
        let record = IngestionRunRecord()
        record.id = run.id.raw
        record.apply(run)
        try await record.create(on: database)
    }

    public func list(competitionID: CompetitionID, limit: Int) async throws -> [IngestionRun] {
        try await IngestionRunRecord.query(on: database)
            .filter(\.$competition.$id == competitionID.raw)
            .sort(\.$finishedAt, .descending)
            .limit(limit)
            .all()
            .map { try $0.toDomain() }
    }

    /// **Sin `limit` y ordenada por la más antigua**, y las dos cosas a
    /// propósito: la fila que esto busca es la que **se quedó abierta**, que es
    /// justo la que una consulta paginada por *"las últimas N"* no encuentra. Y
    /// si hubiera dos —dos peticiones para la misma competición antes de que
    /// pasara el *job*—, se cierra primero la que lleva más esperando.
    ///
    /// **El filtro de `outcome` no es decorativo, y lo demostró la mutación**:
    /// sin él, la pasada del cron encontraría la fila **ya cerrada** de la semana
    /// pasada e intentaría cerrarla otra vez — y el Dominio se niega con razón.
    /// La ingesta se caería en la segunda pasada de cada competición.
    public func findAccepted(
        competitionID: CompetitionID, kind: IngestionKind
    ) async throws -> IngestionRun? {
        try await IngestionRunRecord.query(on: database)
            .filter(\.$competition.$id == competitionID.raw)
            .filter(\.$kind == kind.rawValue)
            .filter(\.$outcome == IngestionOutcome.accepted.rawValue)
            .sort(\.$startedAt, .ascending)
            .first()?
            .toDomain()
    }
}

extension IngestionRunRecord {
    /// Vuelca la entidad sobre la fila. **Sin el `id`**, que es la identidad y no
    /// un campo: lo pone quien crea.
    fileprivate func apply(_ run: IngestionRun) {
        self.$competition.id = run.competitionID.raw
        self.startedAt = run.startedAt
        self.finishedAt = run.finishedAt
        self.outcome = run.outcome.rawValue
        self.error = run.error
        self.kind = run.kind.rawValue
        self.$round.id = run.roundID?.raw
        self.opponentClubsCreated = run.opponentClubsCreated
        self.opponentClubsUpdated = run.opponentClubsUpdated
        self.teamsCreated = run.teamsCreated
        self.teamsUpdated = run.teamsUpdated
        self.roundsCreated = run.roundsCreated
        self.roundsUpdated = run.roundsUpdated
        self.matchesCreated = run.matchesCreated
        self.matchesUpdated = run.matchesUpdated
        self.standingRowsCreated = run.standingRowsCreated
        self.standingRowsUpdated = run.standingRowsUpdated
        self.leagueScorersCreated = run.leagueScorersCreated
        self.leagueScorersUpdated = run.leagueScorersUpdated
        self.leagueScorersRetired = run.leagueScorersRetired
        self.skipped = .init(rows: run.skipped)
    }
}

extension IngestionRunRecord {
    func toDomain() throws -> IngestionRun {
        guard let outcome = IngestionOutcome(rawValue: outcome) else {
            throw PersistenceError.corruptEnumeration(
                table: Self.schema, column: "outcome", value: self.outcome)
        }
        // Mismo trato que `outcome`, y por el mismo motivo: un valor que el
        // enumerado no conoce es **esquema corrupto**, no un caso a ignorar. El
        // `CHECK` de la columna lo impide, así que llegar aquí significa que
        // alguien escribió por debajo de él.
        guard let kind = IngestionKind(rawValue: kind) else {
            throw PersistenceError.corruptEnumeration(
                table: Self.schema, column: "kind", value: self.kind)
        }
        var run = try IngestionRun(
            id: IngestionRunID(raw: try requireID()),
            competitionID: CompetitionID(raw: $competition.id), kind: kind,
            roundID: $round.id.map { RoundID(raw: $0) },
            startedAt: startedAt, finishedAt: finishedAt,
            outcome: outcome, error: error)
        run.standingRowsCreated = standingRowsCreated
        run.standingRowsUpdated = standingRowsUpdated
        run.leagueScorersCreated = leagueScorersCreated
        run.leagueScorersUpdated = leagueScorersUpdated
        run.leagueScorersRetired = leagueScorersRetired
        run.opponentClubsCreated = opponentClubsCreated
        run.opponentClubsUpdated = opponentClubsUpdated
        run.teamsCreated = teamsCreated
        run.teamsUpdated = teamsUpdated
        run.roundsCreated = roundsCreated
        run.roundsUpdated = roundsUpdated
        run.matchesCreated = matchesCreated
        run.matchesUpdated = matchesUpdated
        run.skipped = skipped.rows
        return run
    }
}

/// El repositorio de `StandingRow` (F7).
///
/// **La lectura es por jornada y ordenada por posición**, que no es cosmética:
/// la sirve la pantalla de clasificación tal cual, y la usa la ingesta para
/// resolver la columna PREV de la jornada siguiente (`D-33`). El índice que la
/// hace barata es el `UNIQUE(round_id, team_id)` de §3.5, así que no hace falta
/// uno aparte.
public struct FluentStandingRowRepository: StandingRowRepository {
    private let database: any Database
    public init(database: any Database) { self.database = database }

    public func list(roundID: RoundID) async throws -> [StandingRow] {
        try await StandingRowRecord.query(on: database)
            .filter(\.$round.$id == roundID.raw)
            .sort(\.$position)
            .all()
            .map { try $0.toDomain() }
    }

    public func save(_ row: StandingRow) async throws {
        if let existing = try await StandingRowRecord.find(row.id.raw, on: database) {
            existing.apply(row)
            try await existing.update(on: database)
        } else {
            let record = StandingRowRecord()
            record.id = row.id.raw
            record.apply(row)
            try await record.create(on: database)
        }
    }
}

extension StandingRowRecord {
    func apply(_ row: StandingRow) {
        $competition.id = row.competitionID.raw
        $round.id = row.roundID.raw
        $team.id = row.teamID.raw
        position = row.position
        previousPosition = row.previousPosition
        played = row.played
        won = row.won
        drawn = row.drawn
        lost = row.lost
        goalsFor = row.goalsFor
        goalsAgainst = row.goalsAgainst
        points = row.points
    }

    func toDomain() throws -> StandingRow {
        guard let createdAt, let updatedAt else {
            throw PersistenceError.missingTimestamp(
                table: Self.schema, id: try requireID().uuidString)
        }
        return try StandingRow(
            id: StandingRowID(raw: try requireID()),
            competitionID: CompetitionID(raw: $competition.id),
            roundID: RoundID(raw: $round.id),
            teamID: TeamID(raw: $team.id),
            position: position,
            previousPosition: previousPosition,
            played: played,
            won: won,
            drawn: drawn,
            lost: lost,
            goalsFor: goalsFor,
            goalsAgainst: goalsAgainst,
            points: points,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// ── LeagueScorer (F8) ───────────────────────────────────────────────────────

/// Adaptador de `LeagueScorerRepository` (§4.4).
public struct FluentLeagueScorerRepository: LeagueScorerRepository {
    private let database: any Database

    public init(database: any Database) {
        self.database = database
    }

    /// El ranking, **en el orden que `D-49` y §5.1 fijan**: puesto ascendente con
    /// los nulos al final, goles descendente, y el nombre como desempate estable.
    ///
    /// # Los tres criterios hacen falta aunque hoy solo se note el segundo
    ///
    /// - **`rank` primero**, porque el *spec* se comprometió a respetar el del
    ///   proveedor: los criterios de desempate son suyos. Hoy es nulo siempre
    ///   —ninguna de las dos federaciones lo publica—, así que este `sort` no
    ///   reordena nada; el día que una lo publique, la regla ya está aquí y no en
    ///   el llamante.
    /// - **`goals` descendente**, que es el criterio real de hoy.
    /// - **`fullName` de desempate**, y no es cosmético: es la misma lección que
    ///   `D-92` cobró en la clasificación. Sin un tercer criterio, dos goleadores
    ///   con los mismos goles salen en el orden que le apetezca a Postgres, y ese
    ///   orden **puede cambiar entre dos consultas idénticas**. El ranking es lo
    ///   que la pantalla pinta; que dos filas bailen entre recargas es un defecto,
    ///   no una indiferencia.
    ///
    /// > **`NULLS LAST` es explícito y no el valor por defecto.** En Postgres, con
    /// > orden ascendente los nulos van **al final** por defecto, así que aquí
    /// > coincide — pero coincidir no es lo mismo que decirlo, y el día que alguien
    /// > invierta el orden del puesto se lo llevaría por delante en silencio.
    public func list(competitionID: CompetitionID) async throws -> [LeagueScorer] {
        try await LeagueScorerRecord.query(on: database)
            .filter(\.$competition.$id == competitionID.raw)
            .sort(\.$rank, .ascending)
            .sort(\.$goals, .descending)
            .sort(\.$fullName, .ascending)
            .all()
            .map { try $0.toDomain() }
    }

    public func save(_ scorer: LeagueScorer) async throws {
        if let existing = try await LeagueScorerRecord.find(scorer.id.raw, on: database) {
            existing.apply(scorer)
            try await existing.update(on: database)
        } else {
            let record = LeagueScorerRecord()
            record.id = scorer.id.raw
            record.apply(scorer)
            try await record.create(on: database)
        }
    }

    /// La retirada de `D-94`, **con las dos mitades del filtro**.
    ///
    /// `competition_id` **y** la marca. Sin la primera esto vacía el club entero;
    /// sin la segunda, la competición.
    ///
    /// # `IS DISTINCT FROM`, expresado con un `OR`
    ///
    /// Lo que hay que retirar es *"lo que esta pasada no ha tocado"*, y en SQL eso
    /// es `synced_at IS DISTINCT FROM :mark`. Fluent no lo expresa, así que va
    /// como `!=` **más** el `IS NULL`: un `synced_at != :mark` a secas evalúa a
    /// `NULL` —no a `true`— en las filas sin marca, y ésas son justo las que
    /// ninguna pasada ha confirmado. Sin la segunda rama serían inmortales.
    ///
    /// Se cuenta **antes** de borrar y no se usa el número de filas afectadas,
    /// porque Fluent no lo expone de forma portable en `delete()`. Son dos
    /// consultas dentro de la misma transacción (`D-83`), así que entre ellas no
    /// se cuela nadie.
    @discardableResult
    public func retire(competitionID: CompetitionID, keepingMark: Date) async throws -> Int {
        func stale() -> QueryBuilder<LeagueScorerRecord> {
            LeagueScorerRecord.query(on: database)
                .filter(\.$competition.$id == competitionID.raw)
                .group(.or) { outdated in
                    outdated.filter(\.$syncedAt != keepingMark)
                    outdated.filter(\.$syncedAt == .null)
                }
        }
        let retired = try await stale().count()
        guard retired > 0 else { return 0 }
        try await stale().delete()
        return retired
    }
}

extension LeagueScorerRecord {
    func apply(_ scorer: LeagueScorer) {
        $competition.id = scorer.competitionID.raw
        federationPlayerID = scorer.federationPlayerID
        fullName = scorer.fullName
        teamLabel = scorer.teamLabel
        goals = scorer.goals
        rank = scorer.rank
        syncedAt = scorer.syncedAt
    }

    func toDomain() throws -> LeagueScorer {
        guard let createdAt, let updatedAt else {
            throw PersistenceError.missingTimestamp(
                table: Self.schema, id: try requireID().uuidString)
        }
        return try LeagueScorer(
            id: LeagueScorerID(raw: try requireID()),
            competitionID: CompetitionID(raw: $competition.id),
            federationPlayerID: federationPlayerID,
            fullName: fullName,
            teamLabel: teamLabel,
            goals: goals,
            rank: rank,
            syncedAt: syncedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}


// ── TeamRegistration · ESQUELETO del Bloque C (`D-68`) ───────────────────────

/// **No hay tabla todavía**: `C-D.2` escribe el `…Record` y `C-D.3` su
/// migración, con el `UNIQUE` de tres columnas (`NULLS NOT DISTINCT`) y la FK
/// compuesta a la temporada.
///
/// # Por qué este esqueleto **lanza** en vez de devolver un valor equivocado
///
/// El criterio de Plan §5.1 —*"un valor válido pero equivocado"*— supone que hay
/// un valor que devolver. Aquí no lo hay: `save` no tiene tipo de retorno, así
/// que el único *"valor equivocado"* posible sería **no hacer nada y decir que
/// sí**. Eso no es un esqueleto, es una escritura que se pierde en silencio —
/// exactamente el desenlace que `D-85` y `D-86` existen para evitar. Un `throw`
/// es ruidoso, recuperable y trae escrito el ciclo que lo sustituye; no es un
/// `fatalError()`, que trapearía y se llevaría el proceso entero.
///
/// Nada lo llama todavía: los *handlers* del enganche son `C-E.3`/`C-E.4` y
/// llegan **después** del Bloque D, que es el orden en que hay que dejarlo.
public struct FluentTeamRegistrationRepository: TeamRegistrationRepository {
    private let database: any Database
    public init(database: any Database) { self.database = database }

    public func list(teamID: TeamID, seasonID: SeasonID) async throws -> [TeamRegistration] {
        throw PersistenceError.notImplemented(
            port: "TeamRegistrationRepository.list", cycle: "C-D.2")
    }

    public func save(_ registration: TeamRegistration) async throws {
        throw PersistenceError.notImplemented(
            port: "TeamRegistrationRepository.save", cycle: "C-D.2")
    }
}

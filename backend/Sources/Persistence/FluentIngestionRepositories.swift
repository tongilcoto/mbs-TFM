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

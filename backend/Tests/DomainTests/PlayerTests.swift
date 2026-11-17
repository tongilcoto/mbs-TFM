import Foundation
import Testing
@testable import Domain

/// Nivel 1 (§8.1): el año, el dorsal, las reglas de la plantilla y lo que el
/// perfil recuerda de una fila (`D-118` a `D-122`), **cero I/O**.
@Suite("Player · D-118 a D-122 · el año, el dorsal y las reglas de la plantilla")
struct PlayerTests {

    // ── El año de nacimiento (D-119) ────────────────────────────────────────

    @Test("el año vale de 1900 al año en curso", arguments: [1900, 2010, 2026])
    func acceptsBirthYear(_ year: Int) throws {
        #expect(try BirthYear(year, notAfter: 2026).value == year)
    }

    @Test("un año posterior al año en curso, o anterior a 1900, no vale", arguments: [2027, 1899, 0])
    func rejectsBirthYear(_ year: Int) {
        #expect {
            try BirthYear(year, notAfter: 2026)
        } throws: { error in
            guard case DomainError.invalidValue(let field, _) = error else { return false }
            return field == "birthYear"
        }
    }

    // ── El dorsal (D-118) ───────────────────────────────────────────────────

    @Test("el dorsal vale del 1 al 99", arguments: [1, 9, 99])
    func acceptsShirtNumber(_ number: Int) throws {
        #expect(try ShirtNumber(number).value == number)
    }

    @Test("el 0, el 100 o uno negativo no valen", arguments: [0, 100, -1])
    func rejectsShirtNumber(_ number: Int) {
        #expect {
            try ShirtNumber(number)
        } throws: { error in
            guard case DomainError.invalidValue(let field, _) = error else { return false }
            return field == "shirtNumber"
        }
    }

    // ── Las reglas de la plantilla (§3.7, §5.1) ─────────────────────────────

    static func team(own: Bool) throws -> Team {
        try Team(
            id: TeamID(raw: UUID()),
            opponentClubID: own ? nil : OpponentClubID(raw: UUID()),
            seasonID: own ? nil : SeasonID(raw: UUID()),
            category: .cadete, letter: "A", gender: .masculino, modality: .futbol11,
            createdAt: Date(), updatedAt: Date())
    }

    static func season(archived: Bool) throws -> Season {
        try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"), federationSeasonID: nil,
            archivedAt: archived ? Date() : nil, createdAt: Date(), updatedAt: Date())
    }

    @Test("un equipo propio en una temporada sin archivar admite el alta")
    func ownTeamInOpenSeason() throws {
        try RosterRules.requireCanAdd(to: Self.team(own: true), in: Self.season(archived: false))
    }

    /// Un rival no tiene plantilla: no hay de dónde sacarla (§3.7).
    @Test("un equipo rival no tiene plantilla")
    func opponentTeamHasNoRoster() throws {
        let rival = try Self.team(own: false)
        #expect(throws: DomainError.teamNotOwn(team: rival.id.description)) {
            try RosterRules.requireCanAdd(to: rival, in: Self.season(archived: false))
        }
    }

    /// La temporada archivada es de solo lectura entera (R6.3): ni el alta ni
    /// nada más.
    @Test("en una temporada archivada no se da de alta a nadie")
    func archivedSeasonRejectsAdding() throws {
        #expect(throws: DomainError.seasonArchived(label: "2025/26")) {
            try RosterRules.requireCanAdd(to: Self.team(own: true), in: Self.season(archived: true))
        }
    }

    @Test("y tampoco se corrige, se da de baja ni se cambia la foto")
    func archivedSeasonRejectsEditing() throws {
        try RosterRules.requireEditable(in: Self.season(archived: false))
        #expect(throws: DomainError.seasonArchived(label: "2025/26")) {
            try RosterRules.requireEditable(in: Self.season(archived: true))
        }
    }

    // ── Lo que el perfil recuerda de una fila (D-122) ───────────────────────

    static func profile() throws -> PlayerProfile {
        PlayerProfile(
            id: PlayerProfileID(raw: UUID()), fullName: try PlayerName("Juan García"),
            birthYear: try BirthYear(2010, notAfter: 2026),
            lastShirtNumber: try ShirtNumber(7), lastPosition: .defensa, lastPhotoKey: "club/vieja.jpg",
            createdAt: Date(), updatedAt: Date())
    }

    static func row(of profile: PlayerProfile, shirt: ShirtNumber?, position: PlayerPosition?,
                    photo: String?) -> Player {
        Player(
            id: PlayerID(raw: UUID()), profileID: profile.id,
            teamID: TeamID(raw: UUID()), seasonID: SeasonID(raw: UUID()),
            shirtNumber: shirt, position: position, photoKey: photo,
            createdAt: Date(), updatedAt: Date())
    }

    @Test("guardar una fila copia su dorsal, su demarcación y su foto al perfil")
    func profileRemembersTheRow() throws {
        let profile = try Self.profile()
        let row = Self.row(of: profile, shirt: try ShirtNumber(9), position: .delantero,
                           photo: "club/nueva.jpg")

        let remembered = profile.remembering(row)

        #expect(remembered.lastShirtNumber == (try ShirtNumber(9)))
        #expect(remembered.lastPosition == .delantero)
        #expect(remembered.lastPhotoKey == "club/nueva.jpg")
        #expect(remembered.fullName == profile.fullName, "el nombre no es de la fila")
        #expect(remembered.birthYear == profile.birthYear, "el año tampoco")
    }

    /// «Lo vacío también se copia» (D-122): el perfil no guarda lo de antes si
    /// la fila lo ha quitado.
    @Test("lo vacío también se copia")
    func emptyIsCopiedToo() throws {
        let profile = try Self.profile()
        let remembered = profile.remembering(Self.row(of: profile, shirt: nil, position: nil, photo: nil))

        #expect(remembered.lastShirtNumber == nil)
        #expect(remembered.lastPosition == nil)
        #expect(remembered.lastPhotoKey == nil)
    }

    /// `D-120`, R6.14: «federado» y la última vez listado son de la sincronización; cambiar la foto no los toca.
    @Test("cambiar la foto conserva federado y la última vez listado (D-120)")
    func photoKeepsFederated() {
        let listed = Date(timeIntervalSince1970: 1_800_000_000)
        let row = Player(id: PlayerID(raw: UUID()), profileID: PlayerProfileID(raw: UUID()), teamID: TeamID(raw: UUID()),
                         seasonID: SeasonID(raw: UUID()), federated: true, lastListedAt: listed,
                         createdAt: listed, updatedAt: listed)

        let changed = row.with(photoKey: "club/nueva.jpg", updatedAt: listed)

        #expect(changed.federated == true && changed.lastListedAt == listed && changed.photoKey == "club/nueva.jpg")
    }
}

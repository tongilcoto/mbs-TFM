import Foundation
import Testing
@testable import Domain

/// Nivel 1 (§8.1): la guarda de `D-91`, **cero I/O**.
///
/// Lo que defiende: que un calendario de la temporada pasada no entre en la
/// temporada nueva. La otra guarda —`requireSameSource`, `D-84`— no puede
/// hacerlo, porque el nombre de la competición **es el mismo todos los años**
/// ([Anexo RFFM §F.17]).
@Suite("Season · D-91 · la temporada de un calendario la prueban sus fechas")
struct SeasonCalendarGuardTests {

    static func season(_ label: String) throws -> Season {
        try Season(
            id: SeasonID(raw: UUID()),
            label: try SeasonLabel(label),
            federationSeasonID: "22",
            archivedAt: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// `yyyy-MM-dd` en UTC, que es como viven las fechas de partido (`D-30`).
    static func date(_ iso: String) -> Date {
        let parts = iso.split(separator: "-").map { Int($0)! }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    /// Las fechas reales de PRIMERA CADETE Grupo 4, una jornada por mes
    /// ([Anexo RFFM §F.17]): la 25-26 va de septiembre de 2025 a mayo de 2026.
    static let calendario2526 = [
        "2025-09-27", "2025-10-25", "2025-11-22", "2025-12-20",
        "2026-01-24", "2026-02-21", "2026-03-21", "2026-04-18", "2026-05-24",
    ].map(date)

    /// Y la 26-27, un año más tarde: septiembre de 2026 a mayo de 2027.
    static let calendario2627 = [
        "2026-09-26", "2026-10-24", "2026-11-21", "2026-12-19",
        "2027-01-23", "2027-02-20", "2027-03-20", "2027-04-17", "2027-05-22",
    ].map(date)

    /// El camino bueno. Va primero porque es el que una guarda pasada de celosa
    /// rompería, y eso dejaría a **todos** los clubes sin sincronizar.
    @Test("el calendario de la temporada pasa (D-91)")
    func theRightCalendarPasses() throws {
        let season = try Self.season("2025/26")
        #expect(throws: Never.self) {
            try season.requireOwnsCalendar(matchDates: Self.calendario2526)
        }
    }

    /// El caso que existe: se da de alta la temporada 26-27 y se pegan los
    /// códigos del año anterior. La fuente responde `200`, el nombre coincide y
    /// el calendario es de 25-26.
    @Test("el calendario del año pasado se rechaza, aunque el nombre coincida (D-91)")
    func lastSeasonsCalendarIsRejected() throws {
        let season = try Self.season("2026/27")

        let error = #expect(throws: DomainError.self) {
            try season.requireOwnsCalendar(matchDates: Self.calendario2526)
        }

        guard case .federationSeasonMismatch(let label, let median) = error else {
            Issue.record("el motivo no dice qué temporada ni qué fecha: \(String(describing: error))")
            return
        }
        #expect(label == "2026/27")
        #expect(median == Self.date("2026-01-24"), "la mediana no es la fecha central del calendario")
    }

    /// Y la simétrica: sincronizar la temporada vieja con los códigos nuevos.
    /// Es el mismo error visto desde el otro lado, y también hay que pararlo.
    @Test("el calendario del año siguiente también se rechaza (D-91)")
    func nextSeasonsCalendarIsRejectedToo() throws {
        let season = try Self.season("2025/26")
        #expect(throws: DomainError.self) {
            try season.requireOwnsCalendar(matchDates: Self.calendario2627)
        }
    }

    /// **La razón de que la regla sea la mediana y no *"todas dentro"***. Un
    /// partido aplazado a julio se sale de la ventana y es un caso real: con la
    /// regla estricta, esa competición no volvería a sincronizarse nunca.
    @Test("un partido aplazado fuera de la ventana no tumba la pasada (D-91)")
    func aPostponedMatchDoesNotBreakThePass() throws {
        let season = try Self.season("2025/26")
        let conAplazado = Self.calendario2526 + [Self.date("2026-07-05")]

        #expect(throws: Never.self) {
            try season.requireOwnsCalendar(matchDates: conAplazado)
        }
    }

    /// **La razón de que no sea *"que los rangos solapen"***. Ese criterio
    /// depende de un solo valor: el mínimo de este calendario cae antes del fin
    /// de la 26-27 y su máximo después de su inicio, así que solaparía — y la
    /// mediana, que está en enero de 2026, no.
    @Test("con un solo aplazado, «que solapen» dejaría pasar el año equivocado (D-91)")
    func overlapWouldNotHaveCaughtIt() throws {
        let season = try Self.season("2026/27")
        let de2526ConAplazado = Self.calendario2526 + [Self.date("2026-07-05")]

        #expect(de2526ConAplazado.min()! <= season.endDate)
        #expect(de2526ConAplazado.max()! >= season.startDate,
                "si esto falla, el criterio de solape habría bastado y este test sobra")

        #expect(throws: DomainError.self) {
            try season.requireOwnsCalendar(matchDates: de2526ConAplazado)
        }
    }

    /// Una competición recién publicada no tiene fechas. Eso no es evidencia de
    /// nada, y pararla sería tratar un silencio como un dato (`D-56`).
    @Test("un calendario sin fechas no opina (D-91, D-56)")
    func anEmptyCalendarDoesNotOpine() throws {
        let season = try Self.season("2026/27")
        #expect(throws: Never.self) {
            try season.requireOwnsCalendar(matchDates: [])
        }
    }

    /// Los bordes de la ventana **entran**: la temporada va del 1 de julio al 30
    /// de junio (§3.2), y un partido en cualquiera de esos dos días es de ella.
    @Test("los extremos de la ventana cuentan como dentro (§3.2)")
    func windowBoundsAreInclusive() throws {
        let season = try Self.season("2026/27")

        #expect(throws: Never.self) {
            try season.requireOwnsCalendar(matchDates: [Self.date("2026-07-01")])
        }
        #expect(throws: Never.self) {
            try season.requireOwnsCalendar(matchDates: [Self.date("2027-06-30")])
        }
    }
}

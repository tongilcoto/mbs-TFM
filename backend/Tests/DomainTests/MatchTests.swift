import Foundation
import Testing

@testable import Domain

/// Nivel 1 (§8.1): el partido, y las cuatro clases de campo de §3.7 aplicadas a
/// la entidad donde equivocarse **destruye datos que no vuelven** (`D-75`).
@Suite("Match · §3.7 · la política de upsert sobre la entidad sin PATCH")
struct MatchTests {

    static let home = TeamID(raw: UUID())
    static let away = TeamID(raw: UUID())

    static func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "Europe/Madrid")
        f.dateFormat = "dd-MM-yyyy"
        return f.date(from: iso)!
    }

    static func match(
        roundID: RoundID = RoundID(raw: UUID()),
        kickoff: Kickoff = Kickoff(date: date("27-09-2025")),
        homeTeamID: TeamID = home,
        awayTeamID: TeamID = away,
        result: MatchResult? = nil,
        status: MatchStatus = .programado,
        venue: String? = nil,
        federationMatchID: String? = nil
    ) throws -> Match {
        try Match(
            id: MatchID(raw: UUID()),
            competitionID: CompetitionID(raw: UUID()),
            roundID: roundID,
            kickoff: kickoff,
            homeTeamID: homeTeamID,
            awayTeamID: awayTeamID,
            result: result,
            status: status,
            venue: venue,
            federationMatchID: federationMatchID,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// §3.5: la clave única del partido es (`round_id`, `home_team_id`,
    /// `away_team_id`), y con los dos equipos iguales esa clave deja de
    /// identificar nada. El `UNIQUE` **no lo impide** —una fila así es única— así
    /// que lo impide el tipo.
    @Test("un equipo no juega contra sí mismo (§3.5)")
    func rejectsATeamPlayingItself() throws {
        let team = TeamID(raw: UUID())

        #expect(throws: DomainError.self) {
            try Self.match(homeTeamID: team, awayTeamID: team)
        }
    }

    // ── El estado, derivado del marcador (D-57) ──────────────────────────────

    /// `D-57`: en los partidos ajenos —la inmensa mayoría de una liga— el estado
    /// **no llega de ningún campo**, se deriva. El volcado de temporada jugada
    /// trae 240 partidos con marcador; el de temporada sin arrancar, 306 sin él.
    /// Son literalmente los dos casos.
    @Test("con marcador el partido está finalizado (D-57)", arguments: [
        (0, 0), (3, 3), (1, 0),
    ])
    func scoredMatchIsFinished(_ home: Int, _ away: Int) throws {
        let result = try MatchResult(homeScore: home, awayScore: away)

        #expect(MatchStatus.derived(from: result) == .finalizado)
    }

    /// La otra mitad, y **llega en verde** contra el esqueleto: se escribe porque
    /// es la mitad que un "siempre finalizado" tumbaría, y sin ella la
    /// comprobación de mutación no distinguiría las dos ramas.
    ///
    /// El `0-0` de arriba es el que hace que esto no se pueda implementar
    /// mirando si los goles suman cero.
    @Test("sin marcador el partido está programado (D-57)")
    func unscoredMatchIsScheduled() throws {
        #expect(MatchStatus.derived(from: nil) == .programado)
    }

    // ── Volátil: la fuente gana cuando dice algo (D-56) ─────────────────────

    /// `D-56` sobre el campo donde más duele. El caso real: la RFFM publica el
    /// marcador el domingo, y una pasada posterior que devuelva `""` —campo
    /// vacío, ausente o inservible, las tres formas de callar de §5.6— **no
    /// puede borrar un 3-3 ya ingerido**. `Match` no tiene `PATCH`: eso no se
    /// recupera a mano.
    @Test("una pasada muda no borra el marcador que había (D-56)")
    func scoreSurvivesASilentPass() throws {
        let played = try Self.match(result: try MatchResult(homeScore: 3, awayScore: 3))

        let merged = try played.merging(
            roundID: nil, date: nil, time: nil,
            result: nil, venue: nil, federationMatchID: nil)

        #expect(merged.result == (try MatchResult(homeScore: 3, awayScore: 3)))
    }

    /// Mismo `D-56`, otro campo, y hace falta su propio test: §3.7 lista `venue`
    /// como volátil aparte del marcador. La fuente lo publica con ruido
    /// —`"GALAPAGAR - EL CHOPO (HA)(HA)"`— y el administrador lo limpia; que
    /// **no** sea descriptivo es lo que permite que un cambio de campo real se
    /// refleje.
    @Test("una pasada muda no borra el campo de juego (D-56)")
    func venueSurvivesASilentPass() throws {
        let stored = try Self.match(venue: "Canal Isabel II")

        let merged = try stored.merging(
            roundID: nil, date: nil, time: nil,
            result: nil, venue: nil, federationMatchID: nil)

        #expect(merged.venue == "Canal Isabel II")
    }

    /// `D-31`: el partido **reubicado** se reconoce por su `codacta` y cambia de
    /// jornada. Es lo que hace que `roundID` sea volátil y no identidad, pese a
    /// estar en la clave única de §3.5 — si fuese inmutable, la única salida
    /// sería duplicarlo.
    ///
    /// **Llega en verde**: el esqueleto ya acertaba en este campo. Se escribe
    /// porque es la regla que un "la jornada no se toca" tumbaría.
    @Test("el partido reubicado cambia de jornada, no se duplica (D-31)")
    func roundIsVolatile() throws {
        let stored = try Self.match()
        let newRound = RoundID(raw: UUID())

        let merged = try stored.merging(
            roundID: newRound, date: nil, time: nil,
            result: nil, venue: nil, federationMatchID: nil)

        #expect(merged.roundID == newRound)
    }

    // ── El horario: delegado en Kickoff, con el marcador FUSIONADO (D-56) ────

    /// La regla la escribió F3 dentro de `Kickoff.merging` y **aquí no se
    /// vuelve a probar** (Plan §5: cada regla en el nivel más barato donde
    /// vive). Lo que se prueba aquí es lo que es de `Match`: **qué marcadores le
    /// pasa**.
    ///
    /// Y es el sitio exacto donde `D-56` avisa de que el orden de dos
    /// operaciones se puede hacer mal desde fuera. Un partido ya jugado con hora
    /// confirmada, y una pasada que calla en los dos campos: si `Match` pasara
    /// el marcador **de la pasada** —`nil`— en vez del fusionado, `Kickoff`
    /// leería "sin marcador" y **vaciaría la hora de un partido ya jugado**.
    @Test("con marcador fusionado, la hora que desaparece se ignora (D-56)")
    func kickoffUsesTheMergedResult() throws {
        let played = try Self.match(
            kickoff: Kickoff(date: Self.date("27-09-2025"),
                             time: WallClockTime(hour: 10, minute: 45)),
            result: try MatchResult(homeScore: 3, awayScore: 3))

        let merged = try played.merging(
            roundID: nil, date: nil, time: nil,
            result: nil, venue: nil, federationMatchID: nil)

        #expect(merged.kickoff.time == WallClockTime(hour: 10, minute: 45))
        #expect(merged.isKickoffConfirmed)
    }

    /// La otra mitad del par (`D-30`), y **llega en verde** contra el esqueleto:
    /// sin marcador, una hora que desaparece **sí** devuelve el horario a
    /// provisional, porque una suspensión hace exactamente eso. Es la línea
    /// gemela de la de arriba, y son las dos que `D-56` señala como "casi
    /// idénticas".
    @Test("sin marcador, la hora que desaparece devuelve el horario a provisional (D-30)")
    func kickoffFallsBackToProvisional() throws {
        let scheduled = try Self.match(
            kickoff: Kickoff(date: Self.date("27-09-2025"),
                             time: WallClockTime(hour: 10, minute: 45)))

        let merged = try scheduled.merging(
            roundID: nil, date: nil, time: nil,
            result: nil, venue: nil, federationMatchID: nil)

        #expect(merged.kickoff.time == nil)
        #expect(!merged.isKickoffConfirmed)
    }

    // ── El estado, también del marcador fusionado (D-57) ────────────────────

    /// Exactamente el mismo error que el anterior, en el otro campo que depende
    /// de "¿se ha jugado?". Un partido finalizado y una pasada que calla: si el
    /// estado se derivara del marcador **de la pasada**, el partido volvería a
    /// `programado` — y el marcador se quedaría ahí, contradiciéndolo.
    ///
    /// Es la deriva que `D-18` evita no guardando banderas, aplicada a un campo
    /// que **sí** se guarda: por eso tiene que salir del mismo sitio que el
    /// marcador que lo justifica.
    @Test("el estado sale del marcador fusionado, no del de la pasada (D-57)")
    func statusUsesTheMergedResult() throws {
        let played = try Self.match(
            result: try MatchResult(homeScore: 3, awayScore: 3), status: .finalizado)

        let merged = try played.merging(
            roundID: nil, date: nil, time: nil,
            result: nil, venue: nil, federationMatchID: nil)

        #expect(merged.status == .finalizado)
        #expect(merged.result != nil)
    }

    // ── De emparejamiento (§3.7, D-31) ──────────────────────────────────────

    /// Tercera clave, misma regla, y la que `D-31` señala: *"una clave distinta
    /// solo puede significar que la federación reemplazó el acta"*. Reemplazar
    /// el `codacta` con el que la fila se venía reconociendo la dejaría sin el
    /// escalón exacto de la cadena.
    @Test("un codacta distinto no reescribe el que ya emparejaba (D-31)")
    func federationMatchKeyIsNotOverwritten() throws {
        let matched = try Self.match(federationMatchID: "5374968")

        let merged = try matched.merging(
            roundID: nil, date: nil, time: nil,
            result: nil, venue: nil, federationMatchID: "5589120")

        #expect(merged.federationMatchID == "5374968")
    }

    /// `D-76` en la tercera clave. El caso que lo produce es el proveedor sin
    /// identificador de partido —la FCF (`D-31`)—: si algún día lo publicara, las
    /// filas que nacieron emparejándose por coordenadas lo recogerían.
    @Test("un partido sin codacta lo recibe cuando la fuente lo publica (D-76)")
    func federationMatchKeyFillsTheGap() throws {
        let byCoordinates = try Self.match(federationMatchID: nil)

        let merged = try byCoordinates.merging(
            roundID: nil, date: nil, time: nil,
            result: nil, venue: nil, federationMatchID: "5374968")

        #expect(merged.federationMatchID == "5374968")
    }
}

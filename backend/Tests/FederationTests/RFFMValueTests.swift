import Foundation
import Testing
import Application
@testable import Federation

/// Nivel 1 (§8.1). Cada `@Test` cita la observación del anexo que lo exige: es
/// lo que permite revisar la fase leyendo los tests (Plan §9).
///
/// Todo lo de aquí sale de [Anexo RFFM §F.5], §F.11 y §F.15, y **de los volcados
/// reales**, no de suponer cómo debería venir un campo.
@Suite("RFFM · coerción de valores · Anexo RFFM §F.5, §F.11, §F.15")
struct RFFMValueTests {

    // ── Marcador ─────────────────────────────────────────────────────────────

    /// §F.5: `goles_casa`/`goles_visitante` llegan como **cadena vacía**, no
    /// `null`, si el partido no se ha jugado. Y §F.11: `""` y `"0"` **no son
    /// intercambiables** — el mismo objeto usa los dos con significados distintos.
    @Test("el marcador ausente es nil, y el cero es cero (§F.5, §F.11)")
    func scoreDistinguishesEmptyFromZero() throws {
        #expect(try RFFMValue.score("") == nil)
        #expect(try RFFMValue.score("0") == 0)
        #expect(try RFFMValue.score("3") == 3)
    }

    /// §F.11: el parser de la app heredada **filtra todo lo que no sea dígito**,
    /// así que un `-3` se convertiría en `3`. El anexo lo marca como corrupción a
    /// evitar: **preservar el signo**.
    @Test("preserva el signo, que el parser heredado se comía (§F.11)")
    func scorePreservesSign() throws {
        #expect(try RFFMValue.score("-3") == -3)
    }

    /// §F.11: se han visto `&nbsp;` y espacios duros **dentro de campos
    /// numéricos**. Sanear antes de convertir.
    @Test("sanea espacios duros y &nbsp; antes de convertir (§F.11)", arguments: [
        "&nbsp;", "\u{00A0}", " ", "  3  ", "\u{00A0}3",
    ])
    func scoreSanitises(_ raw: String) throws {
        let expected: Int? = raw.contains("3") ? 3 : nil
        #expect(try RFFMValue.score(raw) == expected)
    }

    // ── Fecha y hora ─────────────────────────────────────────────────────────

    /// §F.5: las fechas vienen `DD-MM-AAAA`, **no es ISO**. §F.11 avisa además de
    /// que el mismo proveedor usa `yyyy-MM-dd` en los catálogos: parseo **según el
    /// campo**, nunca uno genérico.
    @Test("parsea dd-MM-yyyy, que no es ISO (§F.5, §F.11)")
    func parsesMatchDate() throws {
        let date = try #require(try RFFMValue.matchDate("13-09-2026"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        #expect(parts.year == 2026)
        #expect(parts.month == 9)
        #expect(parts.day == 13)
    }

    /// La trampa que este test existe para cazar: si la fecha se construyese en
    /// `Europe/Madrid`, la medianoche local cae el día **anterior** en UTC y el
    /// 13 de septiembre se guardaría como el 12. Es el mismo razonamiento que
    /// `SeasonLabel` documenta para sus fechas derivadas.
    @Test("una fecha de calendario no lleva huso: se construye en UTC")
    func matchDateHasNoTimeZoneDrift() throws {
        let date = try #require(try RFFMValue.matchDate("01-01-2027"))
        #expect(date.timeIntervalSince1970.truncatingRemainder(dividingBy: 86_400) == 0)
    }

    /// §F.5: `hora` puede venir **vacía** aun conociéndose la fecha, y la muestra
    /// 2 **no la trae en absoluto**. Ninguna de las dos es un error: es el
    /// calendario publicándose en dos tiempos.
    @Test("la hora ausente o vacía es nil, no un fallo (§F.5)")
    func kickoffIsOptional() throws {
        #expect(try RFFMValue.kickoff("") == nil)
        #expect(try RFFMValue.kickoff(nil) == nil)
    }

    /// `D-30`: hora y fecha van a **dos columnas**, así que la hora es un reloj de
    /// pared sin huso — no un instante.
    @Test("la hora es hora de pared, no un instante (D-30)")
    func parsesKickoff() throws {
        let time = try #require(try RFFMValue.kickoff("12:00"))
        #expect(time.hour == 12)
        #expect(time.minute == 0)
        let evening = try #require(try RFFMValue.kickoff("18:05"))
        #expect(evening.hour == 18)
        #expect(evening.minute == 5)
    }

    // ── Campo de juego ───────────────────────────────────────────────────────

    /// §F.11 y §F.15. La regex que el anexo proponía —solo `HA`, y como sufijo—
    /// **no basta**: el volcado trae `(HB)` y trae `(HA)` **en medio** del nombre.
    @Test("limpia la marca (HA)/(HB) en todas sus formas y posiciones (§F.11, §F.15)", arguments: [
        ("GALAPAGAR - EL CHOPO (HA)(HA)", "GALAPAGAR - EL CHOPO"),
        ("CANAL ISABEL II (HA) (HA)", "CANAL ISABEL II"),
        ("TRES CANTOS - JAIME MATA (H.A.)(HA)", "TRES CANTOS - JAIME MATA"),
        ("C.D.M. SANTA ANA - MARTIN TEMIÑO (HB)(HB)", "C.D.M. SANTA ANA - MARTIN TEMIÑO"),
        ("S.S. REYES - GABRIEL PEDREGAL 2 (HA) ANT. DEHESA VIEJA",
         "S.S. REYES - GABRIEL PEDREGAL 2 ANT. DEHESA VIEJA"),
        ("VALDEYEROS", "VALDEYEROS"),
    ])
    func cleansVenue(_ raw: String, _ expected: String) {
        #expect(RFFMValue.venue(raw) == expected)
    }

    @Test("un campo vacío es nil, no una cadena vacía")
    func emptyVenueIsNil() {
        #expect(RFFMValue.venue("") == nil)
        #expect(RFFMValue.venue("   ") == nil)
    }

    // ── Identificador de club, desde la ruta del escudo ───────────────────────

    /// §F.4: no hay campo de club en el objeto de partido; la clave es el
    /// **segmento numérico de la ruta del escudo**, con formato
    /// `{00100}_{id_club}_{etiqueta}.{ext}`.
    @Test("extrae el id de club del nombre del fichero del escudo (§F.4)", arguments: [
        ("/pnfg/pimg/Clubes/00100_0010940034_ESC_CELTIC_CASTILLA.png", "0010940034"),
        ("/pnfg/pimg/Clubes/00100_0011702833_escudo_CD_Escorial.png", "0011702833"),
        ("/pnfg/pimg/Clubes/00100_0000101074_AD_CALASANZ_POZUELO.jpg", "0000101074"),
    ])
    func extractsClubID(_ path: String, _ expected: String) {
        #expect(RFFMValue.federationClubID(fromCrestPath: path) == expected)
    }

    /// §F.15: en el volcado hay una extensión **en mayúsculas** (`.JPG`). Y §F.11:
    /// `?nova=1` aparece de forma inconsistente y hay que quitarlo si la ruta se
    /// usa como clave.
    @Test("tolera la extensión en mayúsculas y el ?nova=1 (§F.11, §F.15)", arguments: [
        "/pnfg/pimg/Clubes/00100_0010943406_ac326b74-7769-4ae0.JPG",
        "/pnfg/pimg/Clubes/00100_0010943406_ac326b74-7769-4ae0.png?nova=1",
    ])
    func extractsClubIDDespiteNoise(_ path: String) {
        #expect(RFFMValue.federationClubID(fromCrestPath: path) == "0010943406")
    }

    /// §F.4 lo dice con todas las letras: esto es **parsear el nombre de un
    /// fichero**, no leer un campo. La ingesta debe **tolerar el fallo y
    /// degradar** (§3.7), no reventar.
    @Test("si la ruta no tiene la forma esperada, degrada a nil (§F.4, §3.7)", arguments: [
        "", "/pnfg/pimg/Clubes/escutbase.png", "/otra/cosa.png", "00100_soloedos.png",
    ])
    func clubIDDegradesToNil(_ path: String) {
        #expect(RFFMValue.federationClubID(fromCrestPath: path) == nil)
    }

    // ── Nombre de equipo y letra ─────────────────────────────────────────────

    /// §F.5: el nombre trae **la letra embebida entre comillas simples**. La
    /// ingesta separa club + `letter`, y `letter` sigue siendo opcional porque hay
    /// clubes sin filial.
    @Test("separa la letra del nombre del club (§F.5)", arguments: [
        ("C.D. FUTBOL TRES CANTOS 'A'", "C.D. FUTBOL TRES CANTOS", "A"),
        ("CELTIC CASTILLA C.F. 'A'", "CELTIC CASTILLA C.F.", "A"),
        ("A.D. CALA POZUELO 'B'", "A.D. CALA POZUELO", "B"),
    ])
    func splitsLetter(_ raw: String, _ name: String, _ letter: String) {
        let parsed = RFFMValue.teamName(raw)
        #expect(parsed.name == name)
        #expect(parsed.letter == letter)
    }

    @Test("sin letra, no se inventa una (§F.5)", arguments: [
        "C.D. EL ESCORIAL", "C.D.E. F.P.A. LAS ROZAS", "DEPORTIVO A.V. SANTA ANA",
    ])
    func noLetterStaysNil(_ raw: String) {
        let parsed = RFFMValue.teamName(raw)
        #expect(parsed.name == raw)
        #expect(parsed.letter == nil)
    }

    /// §F.11: `"(No asignado)"` aparece como **nombre real** de equipo. Tolerarlo.
    @Test("tolera el \"(No asignado)\" que la fuente usa como nombre (§F.11)")
    func toleratesPlaceholderName() {
        let parsed = RFFMValue.teamName("(No asignado)")
        #expect(parsed.name == "(No asignado)")
        #expect(parsed.letter == nil)
    }
}

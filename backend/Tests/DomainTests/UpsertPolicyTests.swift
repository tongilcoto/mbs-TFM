import Foundation
import Testing
@testable import Domain

/// Nivel 1 (§8.1), **cero I/O y en milisegundos**: es el dividendo de `D-01`
/// —separar el Dominio de Fluent— aplicado a la regla más delicada del diseño.
///
/// Cada `@Test` cita la fila de §3.7 o la decisión que lo exige. Aquí es donde
/// equivocarse **destruye datos que no vuelven** (Plan §4.1), así que las
/// aserciones se leen de dos en dos: *"vacío no sobrescribe"* y *"vacío
/// sobrescribe"* son dos líneas casi idénticas con consecuencias opuestas.
@Suite("Política de upsert · §3.7 · D-18")
struct UpsertPolicyTests {

    // ── Descriptivo ──────────────────────────────────────────────────────────

    /// §3.7: *"se escribe **solo en el INSERT**. En el UPDATE **no se toca**: el
    /// valor bueno es el del administrador"*.
    ///
    /// El caso real: la RFFM publica `"C.D. FUTBOL TRES CANTOS"` en mayúsculas y
    /// sin acentos ([Anexo RFFM §F.5]); el administrador lo corrige. La pasada
    /// siguiente **no** puede devolverlo a como estaba, o el `PATCH` de `D-21`
    /// duraría hasta el lunes.
    @Test("el nombre corregido por el administrador sobrevive a la pasada (§3.7)")
    func descriptiveKeepsTheAdministratorsValue() {
        let corregido = "C.D. Fútbol Tres Cantos"
        let queDiceLaFuente = "C.D. FUTBOL TRES CANTOS"

        let merged = UpsertPolicy.descriptive(existing: corregido, incoming: queDiceLaFuente)

        #expect(merged == corregido)
    }

    // ── Volátil ──────────────────────────────────────────────────────────────

    /// §3.7 y `D-30`: el horario y el marcador son **de la federación**, y se
    /// pisan **también los ya confirmados** — una suspensión mueve el partido.
    ///
    /// Tratar un campo volátil como descriptivo —escribir solo en el INSERT—
    /// congelaría el calendario en su versión provisional, *"que es el peor
    /// resultado posible"* (`D-30`). Este test es esa mitad de la regla; la otra
    /// es el test de abajo, y las dos juntas son `D-56`.
    @Test("lo que la federación publica pisa lo que había (§3.7, D-30)")
    func volatileLetsTheSourceWin() {
        let merged = UpsertPolicy.volatile(existing: 0, incoming: 3)

        #expect(merged == 3)
    }

    /// **`D-56`, y es la regla más cara de equivocar de toda la fase.** «Volátil»
    /// no es «pisar siempre»: un campo **ausente o vacío no es un valor**, es
    /// ausencia de información, y nunca sobrescribe lo que ya hay.
    ///
    /// La ingesta no puede escribirse como un `UPDATE` ciego. El adaptador ya
    /// deja `nil` donde la fuente calla —`RFFMValue.score("")`, un campo que ni
    /// siquiera viene ([Anexo RFFM §F.5], muestra 2), un `federation_club_id` que
    /// no se pudo inferir del escudo (§F.4)—, y `nil` significa **"no dijo
    /// nada"**. Escribirlo sería borrar el dato bueno.
    @Test("lo que la fuente no dice no borra lo que hay (D-56)")
    func volatileNeverOverwritesWithSilence() {
        let merged = UpsertPolicy.volatile(existing: 3, incoming: nil)

        #expect(merged == 3)
    }

    // ── De propiedad ─────────────────────────────────────────────────────────

    /// §3.7: *"**nunca** lo toca la ingesta en un UPDATE. Es del BFF"*.
    ///
    /// El caso concreto que `D-18` cita: si la ingesta pudiera reasignarlo, **la
    /// primera sincronización tras reclamar un equipo lo devolvería a rival**.
    @Test("la ingesta no reasigna el club de un equipo (§3.7, D-18)")
    func ownedIsNeverTouchedByIngestion() {
        let reclamadoComoPropio: String? = nil
        let loQueCreeLaIngesta: String? = "opponent-club-celtic"

        let merged = UpsertPolicy.owned(
            existing: reclamadoComoPropio, incoming: loQueCreeLaIngesta
        )

        #expect(merged == nil)
    }

    // ── De emparejamiento ────────────────────────────────────────────────────

    /// §3.7: las claves de salida son **inmutables**. Que la fuente publique otro
    /// código no es una corrección: es o un error suyo o un renumerado, y en los
    /// dos casos la respuesta es la **fusión** (§9), no pisar la clave con la que
    /// esta fila se venía reconociendo.
    @Test("un codacta distinto no reescribe el que ya emparejaba (§3.7, D-31)")
    func matchingNeverOverwritesAKeyThatWorks() {
        let merged = UpsertPolicy.matching(existing: "5594142", incoming: "9999999")

        #expect(merged == "5594142")
    }

    /// **`D-76`, y es el matiz que §3.7 no tenía.** La tabla decía *"solo la
    /// ingesta, y solo al insertar"*, y eso deja tiradas las filas que nacieron
    /// **sin** clave: §3.7 admite que la ingesta *"puede no lograr extraerlas"*
    /// —en la RFFM el `federation_club_id` se infiere del nombre del fichero del
    /// escudo y puede fallar ([Anexo RFFM §F.4])— y esas filas se quedarían para
    /// siempre en el paso 2 de la cadena, el del nombre normalizado, que es el
    /// **inexacto**.
    ///
    /// Rellenar un hueco no es sobrescribir: no hay dato que destruir. Es la
    /// asimetría exacta que separa esta clase de `owned`, donde el `nil` **sí**
    /// es un valor —léanse los dos tests seguidos, que es como se ve.
    @Test("una fila que nació sin clave la recibe cuando la fuente la publica (D-76)")
    func matchingFillsTheHoleButOnlyTheHole() {
        let sinClave: String? = nil

        let merged = UpsertPolicy.matching(existing: sinClave, incoming: "0010940034")

        #expect(merged == "0010940034")
    }
}

/// Nivel 1 (§8.1). **El sitio donde equivocarse destruye datos que no vuelven**
/// (Plan §4.1, §5.1): `Match` no tiene `PATCH` (`D-21`), así que lo que la
/// ingesta borre aquí no lo puede recuperar nadie a mano.
@Suite("Horario · D-56 · «vacío» significa dos cosas según el marcador")
struct KickoffMergeTests {

    static let sabado = Date(timeIntervalSince1970: 1_789_171_200)   // sábado 2026-09-12
    static let domingo = Date(timeIntervalSince1970: 1_789_257_600)  // domingo 2026-09-13
    static let mediodia = WallClockTime(hour: 12, minute: 0)

    /// §3.7 y `D-30`: `match_date` es volátil —la federación reparte los
    /// partidos al sábado por defecto y al fijar la franja puede desplazarlos a
    /// domingo ([Anexo RFFM §F.5])— y a la vez es `NOT NULL` (§3.2), así que
    /// **vacío nunca es un valor válido para ella**. Las dos mitades, juntas:
    /// la fuente la mueve, su silencio no la borra.
    @Test("la fecha se mueve con la fuente, pero su silencio no la vacía (§3.7, D-30)")
    func dateIsVolatileButNeverErased() {
        let provisional = Kickoff(date: Self.sabado, time: nil)

        let movido = provisional.merging(
            date: Self.domingo, time: nil, existingResult: nil, incomingResult: nil
        )
        let callado = provisional.merging(
            date: nil, time: nil, existingResult: nil, incomingResult: nil
        )

        #expect(movido.date == Self.domingo)
        #expect(callado.date == Self.sabado)
    }

    /// **Primera fila de la tabla de `D-56`.** Sin marcador, una hora vacía es
    /// *"horario aún sin confirmar"* — **es el dato real** y se escribe.
    ///
    /// El caso que lo obliga: el partido tenía franja publicada y se **suspende**
    /// (campo inutilizable, causa mayor). `D-30` es explícito en que confirmado
    /// **no** es inmutable: *"una suspensión lo devuelve a provisional"*. Y como
    /// `Match` no tiene `PATCH` (`D-21`), si la ingesta no puede devolverlo a
    /// `nil` **no puede nadie**, y la app enseñaría un horario que ya no existe.
    @Test("sin marcador, la hora que desaparece devuelve el horario a provisional (D-30)")
    func emptyTimeIsWrittenWhileTheMatchIsUnplayed() {
        let confirmado = Kickoff(date: Self.sabado, time: Self.mediodia)

        let suspendido = confirmado.merging(
            date: nil, time: nil, existingResult: nil, incomingResult: nil
        )

        #expect(suspendido.time == nil)
        #expect(suspendido.isConfirmed == false)
    }

    /// **Segunda fila de la tabla de `D-56`, y la línea gemela de la de arriba.**
    /// Con marcador, una hora vacía ya no es *"sin confirmar"*: es que **la
    /// fuente dejó de publicarla**, y escribirla borraría la hora a la que se
    /// jugó el partido — para siempre, porque `Match` no tiene `PATCH` (`D-21`).
    ///
    /// **La justificación que traía `D-56` para esto ha caducado** y conviene
    /// decirlo: su ejemplo estrella era que *"la FCF borra fecha y hora al
    /// jugarse el partido"*, y la reobservación del 2026-08-28 lo desmiente —una
    /// temporada entera ya jugada las conserva en **240 de 240**
    /// ([Anexo FCF §C.10.4], `D-74`). La regla se mantiene por otro argumento,
    /// que es el de `D-75` y está escrito allí: **el coste de las dos
    /// equivocaciones no es simétrico**. Ignorar un vacío que era real cuesta
    /// enseñar una hora vieja hasta la pasada siguiente; escribirlo cuando no lo
    /// era cuesta el dato entero y sin vuelta atrás.
    @Test("con marcador, la hora que desaparece se ignora: es pérdida de dato (D-56)")
    func emptyTimeIsIgnoredOnceTheMatchHasAScore() throws {
        let jugado = Kickoff(date: Self.sabado, time: Self.mediodia)
        let marcador = try MatchResult(homeScore: 3, awayScore: 0)

        let siguientePasada = jugado.merging(
            date: nil, time: nil, existingResult: nil, incomingResult: marcador
        )

        #expect(siguientePasada.time == Self.mediodia)
    }

    /// **Quién desambigua es el marcador que quedará en la fila, no el que trae
    /// esta pasada.** Es la trampa de orden que la firma de `merging` existe para
    /// cerrar: el partido se jugó hace tres semanas y su 3-0 ya está guardado;
    /// que la fuente hoy no repita el marcador **no lo devuelve a "sin jugar"**
    /// —eso es `D-56` otra vez, aplicado al propio marcador— y por tanto tampoco
    /// abre la puerta a borrarle la hora.
    ///
    /// Sin esta regla, una respuesta parcial de la federación —que las hay,
    /// `D-31` cuenta con ellas— vaciaría el horario de todos los partidos ya
    /// jugados de golpe.
    @Test("el marcador que decide es el fusionado, no el de la pasada (D-56)")
    func theScoreThatDisambiguatesIsTheMergedOne() throws {
        let jugado = Kickoff(date: Self.sabado, time: Self.mediodia)
        let yaGuardado = try MatchResult(homeScore: 3, awayScore: 0)

        let pasadaMuda = jugado.merging(
            date: nil, time: nil, existingResult: yaGuardado, incomingResult: nil
        )

        #expect(pasadaMuda.time == Self.mediodia)
    }
}

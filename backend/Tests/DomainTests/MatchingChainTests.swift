import Foundation
import Testing
@testable import Domain

/// Nivel 1 (§8.1), **cero I/O**: la otra mitad de §3.7. `UpsertPolicy` (F3) dice
/// **qué se escribe** cuando ya se sabe que la fila es la misma; esto dice **cómo
/// se sabe**.
///
/// Los candidatos son tipos propios y no las entidades de F5, y es deliberado:
/// llevan **solo** las claves de emparejamiento, así que una regla de §3.7 como
/// *"ni la fecha ni la hora entran nunca en la cadena"* deja de ser disciplina y
/// pasa a ser estructural — el dato no está ahí para escribir el fallo.
@Suite("Cadena de emparejamiento · §3.7 · D-31")
struct MatchingChainTests {

    // ── Clubes: paso 1 ───────────────────────────────────────────────────────

    /// §3.7, paso 1: *"`federation_team_id` / `federation_club_id`, si vienen"*.
    ///
    /// La clave del club es el segmento numérico de la ruta del escudo
    /// ([Anexo RFFM §F.4]) y es **estable entre temporadas y categorías** (§F.3):
    /// `0010940034` es Celtic Castilla en las cuatro muestras. Es el escalón
    /// exacto, y el nombre no se mira.
    @Test("el club se reconoce por su clave de federación (§3.7, paso 1)")
    func opponentClubMatchesByFederationKey() {
        let celtic = OpponentClubCandidate(
            id: OpponentClubID(raw: UUID()),
            federationClubID: "0010940034",
            name: NormalizedName("Celtic Castilla C.F.")
        )
        let escorial = OpponentClubCandidate(
            id: OpponentClubID(raw: UUID()),
            federationClubID: "0011702833",
            name: NormalizedName("C.D. El Escorial")
        )

        let outcome = MatchingChain.opponentClub(
            IncomingOpponentClub(
                federationClubID: "0010940034",
                name: NormalizedName("CELTIC CASTILLA C.F.")
            ),
            among: [escorial, celtic]
        )

        #expect(outcome == .matched(celtic.id, by: .federationKey))
    }

    /// §3.7 dice de estas claves que *"la ingesta puede no lograr extraerlas"*, y
    /// por eso hay paso 2. Lo que **no** puede pasar es que la ausencia de clave
    /// sea ella misma una clave.
    ///
    /// El caso es real y frecuente: el `federation_club_id` se infiere del nombre
    /// del fichero del escudo ([Anexo RFFM §F.4]) y un club **sin escudo** no lo
    /// tiene. Si dos clubes sin escudo cayeran en el mismo grupo, comparar los
    /// dos opcionales con `==` los declararía el mismo club — y a partir de ahí
    /// `D-76` le estamparía a uno la clave del otro.
    @Test("no tener clave no es tener la misma clave (§3.7, §F.4)")
    func opponentClubDoesNotMatchOnAbsentKey() {
        let sinEscudo = OpponentClubCandidate(
            id: OpponentClubID(raw: UUID()),
            federationClubID: nil,
            name: NormalizedName("C.D. El Escorial")
        )

        let outcome = MatchingChain.opponentClub(
            IncomingOpponentClub(
                federationClubID: nil,
                name: NormalizedName("C.F. Pozuelo de Alarcón")
            ),
            among: [sinEscudo]
        )

        #expect(outcome == .unmatched)
    }

    // ── Clubes: paso 2 ───────────────────────────────────────────────────────

    /// §3.7, paso 2: *"si no, **nombre normalizado**"*.
    ///
    /// El caso que lo obliga: un club **sin escudo** no tiene clave, porque la
    /// clave se infiere de la ruta del escudo ([Anexo RFFM §F.4]). Sin este
    /// escalón, cada pasada semanal le daría de alta una fila nueva.
    ///
    /// Y empareja **contra la grafía corregida**: el nombre es campo descriptivo
    /// y el valor almacenado es el del administrador (§3.7, `UpsertPolicy`
    /// `descriptive`), mientras la fuente sigue publicando mayúsculas sin acentos
    /// ([Anexo RFFM §F.5]). Los dos lados se comparan ya normalizados.
    @Test("sin clave, el club se reconoce por el nombre normalizado (§3.7, paso 2)")
    func opponentClubDegradesToNormalizedName() {
        let tresCantos = OpponentClubCandidate(
            id: OpponentClubID(raw: UUID()),
            federationClubID: nil,
            name: NormalizedName("C.D. Fútbol Tres Cantos")
        )

        let outcome = MatchingChain.opponentClub(
            IncomingOpponentClub(
                federationClubID: nil,
                name: NormalizedName("C.D. FUTBOL TRES CANTOS")
            ),
            among: [tresCantos]
        )

        #expect(outcome == .matched(tresCantos.id, by: .normalizedName))
    }

    /// **El escalón sin el cual `D-76` no llega a ocurrir nunca.**
    ///
    /// §3.7 encadena los pasos con un *"si no"* que, leído literal, significa
    /// *"si no **viene** la clave"*. Con esa lectura, una fila que nació sin
    /// clave —el club sin escudo del test anterior— **jamás la recibiría**: en
    /// cuanto la fuente publicase el escudo, el club entrante traería clave, el
    /// paso 1 no encontraría a nadie (la fila almacenada la tiene nula) y el paso
    /// 2 estaría cerrado. Alta nueva, duplicado, y `D-76` —*"sí rellena el hueco
    /// de una fila que nació sin ella"*— sin un solo caso en el que aplicarse.
    ///
    /// Así que el *"si no"* es **"si el paso anterior no resolvió"**, no *"si el
    /// dato no viene"*.
    @Test("la clave que no encuentra a nadie cae al paso 2, y por eso D-76 existe")
    func opponentClubFallsThroughWhenTheKeyFindsNobody() {
        let nacidoSinClave = OpponentClubCandidate(
            id: OpponentClubID(raw: UUID()),
            federationClubID: nil,
            name: NormalizedName("C.D. Fútbol Tres Cantos")
        )

        let outcome = MatchingChain.opponentClub(
            IncomingOpponentClub(
                federationClubID: "0012158828",
                name: NormalizedName("C.D. FUTBOL TRES CANTOS")
            ),
            among: [nacidoSinClave]
        )

        #expect(outcome == .matched(nacidoSinClave.id, by: .normalizedName))
    }

    /// **El reverso del test anterior, y el que evita que abrir el paso 2 sea un
    /// agujero.**
    ///
    /// Que el paso 2 se alcance con clave en la mano no puede significar que el
    /// nombre **contradiga** a la clave. Si la fila almacenada ya tiene una clave
    /// y es **otra**, la fuente está diciendo que son dos clubes distintos —dos
    /// clubes homónimos, o un renumerado—, y emparejarlos los fusionaría en
    /// silencio. §3.7 declara estas claves **inmutables** justo para no tener que
    /// adivinar cuál de las dos cosas es: *"se degradaría el emparejamiento, no
    /// la integridad"*, y el arreglo es la fusión (§9).
    ///
    /// Así que el paso 2 solo mira a quien **no tiene nada que contradecir**: los
    /// candidatos sin clave. Que es exactamente el conjunto que `D-76` quiere
    /// alcanzar.
    @Test("una clave distinta descarta al candidato aunque el nombre case (§3.7)")
    func opponentClubIgnoresACandidateWhoseKeyContradicts() {
        let otroClubDelMismoNombre = OpponentClubCandidate(
            id: OpponentClubID(raw: UUID()),
            federationClubID: "0010940034",
            name: NormalizedName("C.D. Fútbol Tres Cantos")
        )

        let outcome = MatchingChain.opponentClub(
            IncomingOpponentClub(
                federationClubID: "0012158828",
                name: NormalizedName("C.D. FUTBOL TRES CANTOS")
            ),
            among: [otroClubDelMismoNombre]
        )

        #expect(outcome == .unmatched)
    }

    /// El paso 2 es **inexacto por declaración propia** (§3.7), así que puede
    /// devolver más de uno — y el `UNIQUE(name)` de §3.5 **no lo impide**: es
    /// único sobre la grafía almacenada, no sobre la normalizada, y
    /// `"C.D. Fútbol Tres Cantos"` y `"CD Futbol Tres Cantos"` son dos filas
    /// legales que normalizan igual.
    ///
    /// Las tres salidas posibles y por qué se elige la tercera: **crear** produce
    /// justo el duplicado que la cadena existe para evitar; **quedarse con el
    /// primero** congela un emparejamiento posiblemente equivocado, que es el
    /// riesgo del que avisa `D-76` pero sin la excusa de que el candidato fuese
    /// único; **no decidir y reportar** deja el trabajo donde §9 ya lo tiene
    /// previsto, la operación de fusión.
    @Test("dos candidatos por nombre no se resuelven: se reportan (§3.7, §9)")
    func opponentClubReportsAmbiguityInsteadOfGuessing() {
        let primero = OpponentClubCandidate(
            id: OpponentClubID(raw: UUID()),
            federationClubID: nil,
            name: NormalizedName("C.D. Fútbol Tres Cantos")
        )
        let duplicado = OpponentClubCandidate(
            id: OpponentClubID(raw: UUID()),
            federationClubID: nil,
            name: NormalizedName("CD Futbol Tres Cantos")
        )

        let outcome = MatchingChain.opponentClub(
            IncomingOpponentClub(
                federationClubID: nil,
                name: NormalizedName("C.D. FUTBOL TRES CANTOS")
            ),
            among: [primero, duplicado]
        )

        #expect(outcome == .ambiguous([primero.id, duplicado.id]))
    }

    // ── Equipos: paso 1 ──────────────────────────────────────────────────────

    /// §3.7, paso 1, con `federation_team_id`.
    ///
    /// §F.3 mide por qué este escalón vale y el siguiente cuesta: el
    /// `codigo_equipo` identifica **al equipo**, es **estable entre temporadas**
    /// y **no depende de la competición** —el `821` del Celtic Castilla se repite
    /// aunque el equipo cambiara de división—. El nombre no hace ninguna de las
    /// tres cosas.
    @Test("el equipo se reconoce por su clave de federación (§3.7, §F.3)")
    func teamMatchesByFederationKey() {
        let celticA = TeamCandidate(
            id: TeamID(raw: UUID()),
            federationTeamID: "821",
            ownership: .opponent(clubName: NormalizedName("Celtic Castilla C.F.")),
            category: .infantil, letter: "A", gender: .masculino, modality: .futbol11
        )
        let celticB = TeamCandidate(
            id: TeamID(raw: UUID()),
            federationTeamID: "3349086",
            ownership: .opponent(clubName: NormalizedName("Celtic Castilla C.F.")),
            category: .infantil, letter: "B", gender: .masculino, modality: .futbol11
        )

        let outcome = MatchingChain.team(
            IncomingTeam(
                federationTeamID: "3349086",
                clubName: NormalizedName("CELTIC CASTILLA C.F."),
                letter: "B"
            ),
            in: CompetitionScope(ageCategory: .infantil, gender: .masculino, modality: .futbol11),
            among: [celticA, celticB]
        )

        #expect(outcome == .matched(celticB.id, by: .federationKey))
    }

    // ── Equipos: paso 2 ──────────────────────────────────────────────────────

    /// §3.7, paso 2: *"nombre normalizado (…) **más categoría**"*.
    ///
    /// La clave del equipo es el `codigo_equipo` y **puede faltar** en respuestas
    /// parciales (`D-31`), así que este escalón existe por lo mismo que el de
    /// clubes: sin él, cada pasada daría de alta un equipo nuevo.
    @Test("sin clave, el equipo se reconoce por club, categoría y letra (§3.7, paso 2)")
    func teamDegradesToNormalizedName() {
        let escorial = TeamCandidate(
            id: TeamID(raw: UUID()),
            federationTeamID: nil,
            ownership: .opponent(clubName: NormalizedName("C.D. El Escorial")),
            category: .cadete, letter: nil, gender: .masculino, modality: .futbol11
        )

        let outcome = MatchingChain.team(
            IncomingTeam(
                federationTeamID: nil,
                clubName: NormalizedName("C.D. EL ESCORIAL"),
                letter: nil
            ),
            in: CompetitionScope(ageCategory: .cadete, gender: .masculino, modality: .futbol11),
            among: [escorial]
        )

        #expect(outcome == .matched(escorial.id, by: .normalizedName))
    }

    /// **§F.3 mide este fallo y lo llama incorrecto, no frágil**: *"como el
    /// nombre es idéntico en ambas categorías, un emparejamiento por nombre
    /// habría **fusionado dos equipos distintos en uno**"*.
    ///
    /// Y la categoría no la publica la fuente por equipo —§F.3 lo comprueba: el
    /// `equipo_*` de las muestras 1 y 2 es **idéntico** siendo dos categorías—,
    /// así que sale del `scope`, heredada de la `Competition` (`D-58`).
    @Test("el mismo nombre en otra categoría no es el mismo equipo (§F.3)")
    func teamDoesNotMatchAcrossCategories() {
        let celticInfantil = TeamCandidate(
            id: TeamID(raw: UUID()),
            federationTeamID: nil,
            ownership: .opponent(clubName: NormalizedName("Celtic Castilla C.F.")),
            category: .infantil, letter: "A", gender: .masculino, modality: .futbol11
        )

        let outcome = MatchingChain.team(
            IncomingTeam(
                federationTeamID: nil,
                clubName: NormalizedName("CELTIC CASTILLA C.F."),
                letter: "A"
            ),
            in: CompetitionScope(ageCategory: .cadete, gender: .masculino, modality: .futbol11),
            among: [celticInfantil]
        )

        #expect(outcome == .unmatched)
    }

    /// **§3.7 dice *"nombre normalizado más categoría"*, y con eso no basta.**
    ///
    /// La clave única de `Team` es (`opponent_club_id`, `category`, `letter`,
    /// `gender`, `modality`) (§3.5). Un club con dos equipos en la **misma**
    /// categoría —el Celtic Castilla del §F.3 es exactamente ese caso, aunque
    /// allí las dos filas estén en categorías distintas— comparte nombre y
    /// comparte categoría: sin la letra, el paso 2 vería dos candidatos
    /// indistinguibles y devolvería `.ambiguous`, que en la práctica es dejar de
    /// ingerir esa mitad de la liga cada semana.
    ///
    /// La letra **la publica la fuente** —embebida entre comillas simples en el
    /// nombre— y **F2 ya la separa** (`RFFMValue.teamName`, §F.5). Es decir:
    /// arreglar §3.7 aquí no cuesta ni un dato nuevo.
    @Test("la letra distingue dos equipos del mismo club y categoría (§3.5)")
    func teamMatchesOnLetterWithinTheSameClubAndCategory() {
        let celticA = TeamCandidate(
            id: TeamID(raw: UUID()),
            federationTeamID: nil,
            ownership: .opponent(clubName: NormalizedName("Celtic Castilla C.F.")),
            category: .infantil, letter: "A", gender: .masculino, modality: .futbol11
        )
        let celticB = TeamCandidate(
            id: TeamID(raw: UUID()),
            federationTeamID: nil,
            ownership: .opponent(clubName: NormalizedName("Celtic Castilla C.F.")),
            category: .infantil, letter: "B", gender: .masculino, modality: .futbol11
        )

        let outcome = MatchingChain.team(
            IncomingTeam(
                federationTeamID: nil,
                clubName: NormalizedName("CELTIC CASTILLA C.F."),
                letter: "B"
            ),
            in: CompetitionScope(ageCategory: .infantil, gender: .masculino, modality: .futbol11),
            among: [celticA, celticB]
        )

        #expect(outcome == .matched(celticB.id, by: .normalizedName))
    }

    /// `D-58`: *"el 'Infantil A' masculino y el femenino del mismo club son
    /// equipos **distintos**"*. Y la fuente **no publica género por equipo** —lo
    /// embebe en el nombre de la competición ([Anexo RFFM §F.14])—, así que llega
    /// por el `scope`, confirmado por un humano en el alta.
    ///
    /// El coste de saltárselo lo dice §3.5 y no es un dato feo: *"como la clave
    /// es única, una inferencia equivocada no produce un dato feo: produce un
    /// **409**"*.
    @Test("el mismo equipo en el otro género no es el mismo equipo (D-58)")
    func teamDoesNotMatchAcrossGenders() {
        let celticFemenino = TeamCandidate(
            id: TeamID(raw: UUID()),
            federationTeamID: nil,
            ownership: .opponent(clubName: NormalizedName("Celtic Castilla C.F.")),
            category: .infantil, letter: "A", gender: .femenino, modality: .futbol11
        )

        let outcome = MatchingChain.team(
            IncomingTeam(
                federationTeamID: nil,
                clubName: NormalizedName("CELTIC CASTILLA C.F."),
                letter: "A"
            ),
            in: CompetitionScope(ageCategory: .infantil, gender: .masculino, modality: .futbol11),
            among: [celticFemenino]
        )

        #expect(outcome == .unmatched)
    }

    /// `D-07`: *"el 'Infantil A masculino' de fútbol-11 y el de fútbol-sala son
    /// equipos **distintos**"*. Es la cuarta y última pieza de la clave única de
    /// §3.5, y como el género, tampoco la publica la fuente por equipo: es el
    /// `tipojuego` con el que se **llama**, no un campo que venga (§3.7).
    @Test("el mismo equipo en otra modalidad no es el mismo equipo (D-07)")
    func teamDoesNotMatchAcrossModalities() {
        let celticSala = TeamCandidate(
            id: TeamID(raw: UUID()),
            federationTeamID: nil,
            ownership: .opponent(clubName: NormalizedName("Celtic Castilla C.F.")),
            category: .infantil, letter: "A", gender: .masculino, modality: .futbolSala
        )

        let outcome = MatchingChain.team(
            IncomingTeam(
                federationTeamID: nil,
                clubName: NormalizedName("CELTIC CASTILLA C.F."),
                letter: "A"
            ),
            in: CompetitionScope(ageCategory: .infantil, gender: .masculino, modality: .futbol11),
            among: [celticSala]
        )

        #expect(outcome == .unmatched)
    }

    // ── Equipos: la frontera de D-66 / D-67 ──────────────────────────────────

    /// **El límite que `D-76` le deja escrito a esta fase**, y que dice de quién
    /// es la responsabilidad: *"que el paso 2 no vaya a buscar entre los equipos
    /// propios sin emparejar es responsabilidad **de la cadena**"*.
    ///
    /// El escenario: el club creó su "Infantil A" en junio (`D-66`) y no lo ha
    /// enganchado. En septiembre la ingesta lo ve en el calendario. Si el paso 2
    /// lo reconociera por el nombre del club, `D-76` le estamparía acto seguido
    /// el `federation_team_id` — y eso es **el enganche**, que `D-67` hace un
    /// acto deliberado del administrador con su `/preview` y su confirmación de
    /// género.
    ///
    /// **Aquí no hace falta una guarda porque no hay dato que guardar.** Un
    /// equipo propio no tiene nombre de club rival contra el que comparar —su
    /// nombre está en `Club`, no en un `OpponentClub`—, y `TeamOwnership` lo dice
    /// como un `enum`: el caso `.own` no lleva `clubName`. Este test fija esa
    /// decisión de modelado; el día que alguien la convierta en `isOwn: Bool` más
    /// un `clubName` opcional, es lo que se pone rojo.
    @Test("un equipo propio sin enganchar no lo engancha la ingesta (D-66, D-67, D-76)")
    func step2NeverReachesAnUnlinkedOwnTeam() {
        let miInfantilA = TeamCandidate(
            id: TeamID(raw: UUID()),
            federationTeamID: nil,
            ownership: .own,
            category: .infantil, letter: "A", gender: .masculino, modality: .futbol11
        )

        let outcome = MatchingChain.team(
            IncomingTeam(
                federationTeamID: nil,
                clubName: NormalizedName("A.D. Mi Club"),
                letter: "A"
            ),
            in: CompetitionScope(ageCategory: .infantil, gender: .masculino, modality: .futbol11),
            among: [miInfantilA]
        )

        #expect(outcome == .unmatched)
    }

    /// **La otra mitad, y sin ella lo de arriba sería una sobrecorrección.**
    ///
    /// Un equipo propio **ya enganchado** (`D-67`) sí tiene que reconocerse, y
    /// por el paso 1: si la cadena excluyera a los propios en bloque, cada pasada
    /// daría de alta tu propio equipo **como rival** y haría falta `/ownership`
    /// más una fusión (§9.5) — que es justo el desenlace que `D-66` describe para
    /// el club que **no** enganchó.
    ///
    /// Es decir: la ingesta no crea equipos propios, pero sí **actualiza** el que
    /// alguien enganchó a mano.
    @Test("el equipo propio ya enganchado sí se reconoce, por el paso 1 (D-67)")
    func step1StillFindsALinkedOwnTeam() {
        let miInfantilAEnganchado = TeamCandidate(
            id: TeamID(raw: UUID()),
            federationTeamID: "821",
            ownership: .own,
            category: .infantil, letter: "A", gender: .masculino, modality: .futbol11
        )

        let outcome = MatchingChain.team(
            IncomingTeam(
                federationTeamID: "821",
                clubName: NormalizedName("A.D. MI CLUB"),
                letter: "A"
            ),
            in: CompetitionScope(ageCategory: .infantil, gender: .masculino, modality: .futbol11),
            among: [miInfantilAEnganchado]
        )

        #expect(outcome == .matched(miInfantilAEnganchado.id, by: .federationKey))
    }

    // ── Partidos: paso 1 ─────────────────────────────────────────────────────

    /// §3.7, paso 1 de la cadena de partidos: *"`federation_match_id`, si el
    /// proveedor lo publica"*. En la RFFM es el `codacta` ([Anexo RFFM §F.5]).
    @Test("el partido se reconoce por su codacta (§3.7, D-31)")
    func matchMatchesByFederationKey() {
        let jornada1 = RoundID(raw: UUID())
        let celtic = TeamID(raw: UUID())
        let escorial = TeamID(raw: UUID())

        let almacenado = MatchCandidate(
            id: MatchID(raw: UUID()),
            federationMatchID: "1234567",
            roundID: jornada1, homeTeamID: celtic, awayTeamID: escorial
        )

        let outcome = MatchingChain.match(
            IncomingMatch(
                federationMatchID: "1234567",
                roundID: jornada1, homeTeamID: celtic, awayTeamID: escorial
            ),
            among: [almacenado]
        )

        #expect(outcome == .matched(almacenado.id, by: .federationKey))
    }

    // ── Partidos: paso 2 ─────────────────────────────────────────────────────

    /// §3.7, paso 2: *"las **coordenadas** (`round_id`, `home_team_id`,
    /// `away_team_id`), que son índice único"*.
    ///
    /// **No es un apaño, y ésa es la diferencia con la cadena de equipos**
    /// (`D-31`): son FK internas ya resueltas —los equipos están emparejados
    /// cuando se llega al partido—, así que el escalón **siempre existe y siempre
    /// es exacto**. Por eso no hay tercero.
    ///
    /// Y no es un camino hipotético: la FCF **no publica identificador de partido
    /// en absoluto** ([Anexo FCF §C.3]), así que en Cataluña éste es el único
    /// escalón que hay.
    @Test("sin identificador de partido, emparejan las coordenadas (§3.7, D-31)")
    func matchDegradesToCoordinates() {
        let jornada1 = RoundID(raw: UUID())
        let celtic = TeamID(raw: UUID())
        let escorial = TeamID(raw: UUID())

        let almacenado = MatchCandidate(
            id: MatchID(raw: UUID()),
            federationMatchID: nil,
            roundID: jornada1, homeTeamID: celtic, awayTeamID: escorial
        )

        let outcome = MatchingChain.match(
            IncomingMatch(
                federationMatchID: nil,
                roundID: jornada1, homeTeamID: celtic, awayTeamID: escorial
            ),
            among: [almacenado]
        )

        #expect(outcome == .matched(almacenado.id, by: .coordinates))
    }

    /// **El caso concreto por el que `D-31` existe**, y su alternativa descartada
    /// dicha con nombre: *"no modelarlo y emparejar solo por coordenadas (…)
    /// funcionaría el 99 % de las veces, pero deja el sistema sin defensa ante el
    /// caso que sí ocurre —la federación **reubica un partido en otra
    /// jornada**—, que crearía un duplicado sin forma de detectarlo"*.
    ///
    /// Con el acta en la mano da igual dónde lo hayan puesto: es el mismo
    /// partido. Es también por qué el orden de los dos escalones no es
    /// intercambiable.
    @Test("el partido reubicado en otra jornada no se duplica (D-31)")
    func federationKeyBeatsCoordinatesWhenTheRoundChanges() {
        let celtic = TeamID(raw: UUID())
        let escorial = TeamID(raw: UUID())

        let jugadoEnLaJornada1 = MatchCandidate(
            id: MatchID(raw: UUID()),
            federationMatchID: "1234567",
            roundID: RoundID(raw: UUID()), homeTeamID: celtic, awayTeamID: escorial
        )

        let outcome = MatchingChain.match(
            IncomingMatch(
                federationMatchID: "1234567",
                roundID: RoundID(raw: UUID()),   // la federación lo movió de jornada
                homeTeamID: celtic, awayTeamID: escorial
            ),
            among: [jugadoEnLaJornada1]
        )

        #expect(outcome == .matched(jugadoEnLaJornada1.id, by: .federationKey))
    }

    /// **La asimetría con la cadena de clubes, y no es un descuido.**
    ///
    /// En clubes, una clave almacenada distinta **descarta** al candidato, porque
    /// allí el paso 2 es el nombre —inexacto— y la clave es prueba en contra.
    /// Aquí el paso 2 son FK internas más el `UNIQUE(round_id, home_team_id,
    /// away_team_id)` de §3.5: es **exacto**, así que un `codacta` distinto solo
    /// puede querer decir que la federación reemplazó el acta. Descartar al
    /// candidato daría de alta un partido que ese mismo `UNIQUE` rechazaría — un
    /// fallo de ingesta en vez de un emparejamiento.
    ///
    /// Lo que **no** pasa es que la clave nueva pise a la vieja: eso lo impide
    /// `UpsertPolicy.matching`, que solo rellena huecos (`D-76`).
    @Test("las coordenadas emparejan aunque el codacta almacenado sea otro (§3.5, D-31)")
    func coordinatesMatchEvenWhenTheStoredKeyDiffers() {
        let jornada1 = RoundID(raw: UUID())
        let celtic = TeamID(raw: UUID())
        let escorial = TeamID(raw: UUID())

        let actaAntigua = MatchCandidate(
            id: MatchID(raw: UUID()),
            federationMatchID: "1234567",
            roundID: jornada1, homeTeamID: celtic, awayTeamID: escorial
        )

        let outcome = MatchingChain.match(
            IncomingMatch(
                federationMatchID: "7654321",   // acta reemplazada
                roundID: jornada1, homeTeamID: celtic, awayTeamID: escorial
            ),
            among: [actaAntigua]
        )

        #expect(outcome == .matched(actaAntigua.id, by: .coordinates))
    }

    /// §3.7: *"**ni la fecha ni la hora entran nunca en la cadena**: son el dato
    /// que cambia cada semana (`D-30`), así que casar por fecha duplicaría el
    /// partido en cuanto se moviese"*.
    ///
    /// **Este test no puede fallar, y ése es el resultado.** `IncomingMatch` y
    /// `MatchCandidate` no tienen fecha ni hora, así que la regla no la sostiene
    /// una guarda que alguien pueda quitar: la sostiene el tipo. Lo que fija este
    /// test es la **decisión de modelado** — el día que alguien le añada
    /// `matchDate` a un candidato "para desempatar", esto es lo que hay que leer
    /// antes.
    ///
    /// El escenario, que es el normal y no el raro ([Anexo RFFM §F.5]): el
    /// calendario nace con todos los partidos un sábado y sin hora, y el domingo
    /// anterior la federación fija la franja y puede mover la fecha a domingo.
    /// Con la fecha en la cadena, **cada partido de la liga se duplicaría una vez
    /// por temporada**.
    @Test("la fecha no está en la cadena porque no está en el tipo (§3.7, D-30)")
    func neitherDateNorKickoffCanEnterTheChain() {
        let jornada1 = RoundID(raw: UUID())
        let celtic = TeamID(raw: UUID())
        let escorial = TeamID(raw: UUID())

        let sabadoSinHora = MatchCandidate(
            id: MatchID(raw: UUID()),
            federationMatchID: nil,
            roundID: jornada1, homeTeamID: celtic, awayTeamID: escorial
        )

        // Lo que la fuente publica el lunes siguiente: domingo, 12:00. La única
        // forma de expresar ese cambio aquí es no expresarlo.
        let outcome = MatchingChain.match(
            IncomingMatch(
                federationMatchID: nil,
                roundID: jornada1, homeTeamID: celtic, awayTeamID: escorial
            ),
            among: [sabadoSinHora]
        )

        #expect(outcome == .matched(sabadoSinHora.id, by: .coordinates))
    }

    /// **La jornada es parte de la coordenada, y hay un caso donde se nota**:
    /// `D-12` resuelve las eliminatorias a doble vuelta sin entidades nuevas —
    /// *"una eliminatoria a doble vuelta son **dos jornadas**"*—, y ahí los dos
    /// partidos tienen los mismos equipos con el mismo local.
    ///
    /// §3.5 lo dice al revés y con la asunción a la vista: *"no hay repeticiones
    /// de partido dentro de la misma jornada"*. Es decir, lo que hace única a la
    /// terna es que la jornada esté dentro.
    @Test("los dos partidos de una eliminatoria no son el mismo (§3.5, D-12)")
    func coordinatesIncludeTheRound() {
        let celtic = TeamID(raw: UUID())
        let escorial = TeamID(raw: UUID())
        let vuelta = RoundID(raw: UUID())

        let ida = MatchCandidate(
            id: MatchID(raw: UUID()), federationMatchID: nil,
            roundID: RoundID(raw: UUID()), homeTeamID: celtic, awayTeamID: escorial
        )
        let partidoDeVuelta = MatchCandidate(
            id: MatchID(raw: UUID()), federationMatchID: nil,
            roundID: vuelta, homeTeamID: celtic, awayTeamID: escorial
        )

        let outcome = MatchingChain.match(
            IncomingMatch(
                federationMatchID: nil,
                roundID: vuelta, homeTeamID: celtic, awayTeamID: escorial
            ),
            among: [ida, partidoDeVuelta]
        )

        #expect(outcome == .matched(partidoDeVuelta.id, by: .coordinates))
    }

    /// **La terna de §3.5 está ordenada**: es (`round_id`, `home_team_id`,
    /// `away_team_id`), no un conjunto de dos equipos y una jornada.
    ///
    /// Y aquí no vale el argumento de que en una liga cada equipo juega una vez
    /// por jornada: si los dos lados se compararan cruzados, un partido en casa
    /// emparejaría con el mismo enfrentamiento a domicilio. La consecuencia no es
    /// un duplicado sino algo peor — el marcador entraría **del revés**, y
    /// `Match` no tiene `PATCH` (`D-21`).
    @Test("el local y el visitante no son intercambiables (§3.5)")
    func coordinatesAreOrdered() {
        let jornada1 = RoundID(raw: UUID())
        let celtic = TeamID(raw: UUID())
        let escorial = TeamID(raw: UUID())

        let celticEnCasa = MatchCandidate(
            id: MatchID(raw: UUID()), federationMatchID: nil,
            roundID: jornada1, homeTeamID: celtic, awayTeamID: escorial
        )

        let outcome = MatchingChain.match(
            IncomingMatch(
                federationMatchID: nil,
                roundID: jornada1, homeTeamID: escorial, awayTeamID: celtic
            ),
            among: [celticEnCasa]
        )

        #expect(outcome == .unmatched)
    }
}

import Domain
import Foundation
import Testing

@testable import Application

/// Nivel 2 (§8.1): **el primer paso del enganche** (`D-67`), con los puertos
/// falseados y cero I/O.
///
/// El `/preview` es la única ruta síncrona con latencia de terceros junto a su
/// gemela de competiciones: recibe **la URL pegada del navegador**, la lee *por
/// el puerto* ([D-97], `C-B.1`), pregunta a la federación y enseña lo que hay
/// **sin escribir una sola fila**. Es verificación, no descubrimiento: de esos
/// cuatro números cuelga todo el árbol y un dígito mal **no da error** (`D-84`),
/// así que un humano tiene que reconocer su club antes de confirmar (`D-16`).
@Suite("PreviewFederationLink · D-67 · lo que hay en la coordenada, sin persistir")
struct FederationLinkPreviewTests {

    static let now = instant("2026-03-02")

    static func instant(_ yyyyMMdd: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: yyyyMMdd)!
    }

    // ── Fixtures ─────────────────────────────────────────────────────────────

    static let url =
        "https://www.rffm.es/competicion/calendario"
        + "?temporada=21&tipojuego=1&competicion=24037548&grupo=24037549"

    static let coordinate = FederationCoordinate(
        federationSeasonID: "21",
        federationCompetitionID: "24037548",
        federationGroupID: "24037549",
        modality: .futbol11)

    static func club(federation: FederationCode = .rffm) throws -> Club {
        try Club(
            id: ClubID(raw: UUID()), name: "C.D. Ejemplo", shortName: "Ejemplo",
            slug: try Slug("ejemplo"), federation: federation,
            createdAt: now, updatedAt: now)
    }

    /// El equipo propio **sin enganchar**: las dos claves nulas, que es el único
    /// estado desde el que [D-66] permite enganchar — la fila sin segundo
    /// escritor. Es lo que siembra `seed-team` (`C-F.1`).
    static func team(
        category: TeamCategory = .cadete,
        gender: Gender = .masculino,
        modality: Modality = .futbol11,
        federationTeamID: String? = nil
    ) throws -> Team {
        try Team(
            id: TeamID(raw: UUID()), opponentClubID: nil,
            category: category, letter: "A", gender: gender, modality: modality,
            federationTeamID: federationTeamID, createdAt: now, updatedAt: now)
    }

    static func season(
        _ label: String = "2025/26", federationSeasonID: String = "21"
    ) throws -> Season {
        try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel(label),
            federationSeasonID: federationSeasonID, createdAt: now, updatedAt: now)
    }

    static func competition(
        seasonID: SeasonID,
        ageCategory: TeamCategory = .cadete,
        gender: Gender = .masculino,
        modality: Modality = .futbol11,
        federationGroupID: String = "24037549",
        federationName: String? = nil
    ) throws -> Competition {
        try Competition(
            id: CompetitionID(raw: UUID()), seasonID: seasonID,
            modality: modality, gender: gender,
            federationCompetitionID: "24037548",
            federationGroupID: federationGroupID,
            ageCategory: ageCategory, divisionLabel: "Primera División Autonómica",
            groupLabel: "Grupo 1", federationName: federationName,
            createdAt: now, updatedAt: now)
    }

    static func teamRef(_ id: String?, _ name: String) -> FederationTeamRef {
        FederationTeamRef(
            federationTeamID: id, name: name, letter: nil,
            federationClubID: nil, crestURL: nil)
    }

    /// Un calendario de una jornada con un partido, que es lo mínimo con lo que
    /// `teams[]` dice algo.
    static func calendar(
        seasonLabel: String? = "2025/26",
        competitionName: String? = "PRIMERA CADETE",
        rounds: [FederationRound]? = nil
    ) -> FederationCalendar {
        FederationCalendar(
            seasonLabel: seasonLabel.map { try! SeasonLabel($0) },
            competitionName: competitionName,
            groupLabel: "Grupo 4",
            currentRound: 1,
            rounds: rounds ?? [
                FederationRound(number: 1, matches: [
                    FederationMatch(
                        federationMatchID: "1", home: teamRef("3349086", "C.D. EJEMPLO 'A'"),
                        away: teamRef("3349087", "C.D. GALAPAGAR 'B'"),
                        homeScore: nil, awayScore: nil,
                        date: instant("2025-09-13"), kickoff: nil,
                        venue: nil, venueCode: nil)
                ])
            ])
    }

    static func useCase(
        store: IngestionStore, federation: any FederationClient,
        code: FederationCode = .rffm
    ) -> PreviewFederationLink {
        PreviewFederationLink(
            unitOfWork: FakeUnitOfWork(store: store),
            federationClients: FakeFederationClientProvider([code: federation]))
    }

    static let actor = ActorContext(clubSlug: try! Slug("ejemplo"), isSystem: false)

    // ── C-C.1 · el preview no persiste nada ──────────────────────────────────

    /// **`D-67` y el *spec*, literales: *"200 — lo que hay en la coordenada, sin
    /// persistir nada"*.**
    ///
    /// No es una obviedad que se pueda dar por hecha: el `/preview` tiene en la
    /// mano exactamente lo que la cascada necesita —la temporada que falta, la
    /// competición que no existe— y adelantarlo *"para no volver a pedirlo"* es
    /// el atajo natural. Lo que lo hace inaceptable es quién decide: entre el
    /// `/preview` y el enganche hay **un humano** que todavía no ha reconocido su
    /// club en `teams[]`, y que puede cerrar la pestaña. Una `Season` creada aquí
    /// quedaría dada de alta por una URL que nadie confirmó.
    ///
    /// Se afirma contando **todas** las escrituras del almacén y no las filas de
    /// cada tabla: así la tabla que añada la fase siguiente entra en la
    /// afirmación sin que nadie tenga que acordarse.
    @Test("el preview no escribe ni una fila, tenga o no que crearse la cascada (D-67)")
    func thePreviewPersistsNothing() async throws {
        let store = IngestionStore()
        await store.seed(club: try Self.club())
        let team = try Self.team()
        await store.seed(teams: [team])
        let federation = SpyFederationClient(
            returning: Self.calendar(), readingURLAs: Self.coordinate)

        _ = try await Self.useCase(store: store, federation: federation)
            .execute(teamID: team.id, calendarURL: Self.url, actor: Self.actor)

        // Cero, y la temporada de la coordenada **no existe** en el almacén: es
        // el caso en el que la cascada sí tendría trabajo que hacer.
        #expect(await store.writes == 0)
    }

    // ── C-C.2 · `exists` dice si la temporada ya está ────────────────────────

    /// **`exists = false` ⇒ al confirmar se creará en cascada** (`D-67`), y es
    /// lo que hace aceptable que una URL pegada dé de alta una `Season`: el
    /// administrador lo ve **antes**.
    ///
    /// La pregunta se hace por `federationSeasonID` y no por la etiqueta, que es
    /// lo mismo que hace `seed-competition` y por el mismo motivo: la etiqueta
    /// es un rótulo —y en la RFFM, **el eco de nuestro propio parámetro**
    /// ([Anexo RFFM §F.16])—, mientras que el código es la coordenada.
    ///
    /// **Las dos mitades en el mismo test**, que es la lección de `M6` en el
    /// Bloque B: una guarda que solo se prueba por el lado que rechaza pasa
    /// igual de verde cuando rechaza **todo**.
    @Test("`exists` distingue la temporada que ya está de la que habrá que crear (D-67)")
    func theSeasonSaysWhetherItAlreadyExists() async throws {
        let team = try Self.team()

        // La que no está: el club es nuevo en esa temporada.
        let fresh = IngestionStore()
        await fresh.seed(club: try Self.club())
        await fresh.seed(teams: [team])
        let onFresh = try await Self.useCase(
            store: fresh,
            federation: SpyFederationClient(
                returning: Self.calendar(), readingURLAs: Self.coordinate))
            .execute(teamID: team.id, calendarURL: Self.url, actor: Self.actor)

        #expect(onFresh.season.exists == false)
        #expect(onFresh.season.federationSeasonID == "21")

        // La que sí: mismo `federationSeasonID` de la coordenada.
        let seeded = IngestionStore()
        await seeded.seed(club: try Self.club())
        await seeded.seed(seasons: [try Self.season(federationSeasonID: "21")], teams: [team])
        // Y la fuente, con esa misma coordenada, rotula **otra cosa**: no es un
        // caso rebuscado, es lo que [Anexo RFFM §F.16] midió — `temporada` es el
        // eco del parámetro que enviamos, así que su etiqueta no es dato suyo.
        let onSeeded = try await Self.useCase(
            store: seeded,
            federation: SpyFederationClient(
                returning: Self.calendar(seasonLabel: "2026/27"),
                readingURLAs: Self.coordinate))
            .execute(teamID: team.id, calendarURL: Self.url, actor: Self.actor)

        #expect(onSeeded.season.exists)
        // La etiqueta que se enseña es **la del club**, no la que diga la
        // fuente: la temporada ya existe y su rótulo es dato nuestro.
        #expect(onSeeded.season.label == "2025/26")
    }

    // ── C-C.3 · `alreadyRegistered` ──────────────────────────────────────────

    /// **`true` si ese grupo ya está dado de alta en esa temporada** (§3.5): es
    /// la unicidad del modelo —`Competition` se identifica por `season_id` **+**
    /// `federation_group_id`— enseñada **antes** de que llegue a ser un 409.
    ///
    /// No es un aviso de error: el segundo enganche sobre un grupo ya dado de
    /// alta es el caso **normal** —el Infantil A y el Infantil B del mismo club
    /// caen en el mismo grupo (`D-67`, `C-C.7`)—. Lo que dice este campo es *"la
    /// competición no se va a crear, se va a reutilizar"*.
    ///
    /// **Y se pregunta por el grupo, no por la competición**: los dos códigos
    /// viajan en la coordenada, pero el que identifica la fila es el del grupo
    /// (§3.5). Preguntar por el de competición daría `true` para el Grupo 5 de
    /// la misma liga, que es otra fila.
    @Test("`alreadyRegistered` dice si ese grupo ya está en esa temporada (§3.5, D-67)")
    func theCompetitionSaysWhetherTheGroupIsAlreadyRegistered() async throws {
        let team = try Self.team()
        let season = try Self.season(federationSeasonID: "21")

        // La temporada está, pero el grupo no: es el alta de una competición
        // nueva dentro de una temporada que el club ya tenía.
        let withoutGroup = IngestionStore()
        await withoutGroup.seed(club: try Self.club())
        await withoutGroup.seed(
            seasons: [season],
            competitions: [try Self.competition(
                seasonID: season.id, federationGroupID: "99999999")],
            teams: [team])
        let onFresh = try await Self.useCase(
            store: withoutGroup,
            federation: SpyFederationClient(
                returning: Self.calendar(), readingURLAs: Self.coordinate))
            .execute(teamID: team.id, calendarURL: Self.url, actor: Self.actor)

        #expect(onFresh.competition.alreadyRegistered == false)

        // El mismo grupo de la coordenada, ya dado de alta.
        let withGroup = IngestionStore()
        await withGroup.seed(club: try Self.club())
        await withGroup.seed(
            seasons: [season],
            competitions: [try Self.competition(
                seasonID: season.id, federationGroupID: "24037549")],
            teams: [team])
        let onSeeded = try await Self.useCase(
            store: withGroup,
            federation: SpyFederationClient(
                returning: Self.calendar(), readingURLAs: Self.coordinate))
            .execute(teamID: team.id, calendarURL: Self.url, actor: Self.actor)

        #expect(onSeeded.competition.alreadyRegistered)
    }

    // ── C-C.4 · `identityMatches` viaja en el preview (C-A.3 conectada) ──────

    /// **El veredicto de `C-A.3`, enseñado antes de chocar** (`D-66`, `D-58`,
    /// §3.2). `Team.identityMatches` compara **las tres** piezas que la
    /// competición presta —`ageCategory`, `gender` y `modality`— contra las que
    /// el equipo tiene congeladas desde su alta. Lo que este ciclo añade no es
    /// la regla: es que **cruce la puerta**, porque en `false` confirmar
    /// devuelve 409 y el administrador puede enganchar otro equipo en vez de
    /// estrellarse.
    ///
    /// **De dónde salen los tres valores, que es la decisión de este ciclo.**
    /// Si la competición **ya existe** —`alreadyRegistered`—, son los suyos: es
    /// la fila que la cascada va a reutilizar (`C-C.7`) y por tanto la que
    /// decide el 409. Si **no existe**, la cascada la va a crear, y entonces
    /// `ageCategory` sale del propio equipo —es el único sitio de donde puede
    /// salir: la federación no la publica y el cuerpo del enganche no la lleva—,
    /// `modality` de la coordenada (`tipojuego`) y `gender` de la inferencia
    /// sobre el nombre (`C-A.7`). En ese caso la edad cuadra por construcción y
    /// las que de verdad se comprueban son las otras dos.
    ///
    /// Éste es el caso que `D-58` llama *"no degrada, colisiona"*: el Cadete A
    /// enganchado a una competición **juvenil** pasaría, y la ingesta heredaría
    /// `juvenil` a cada equipo que creara desde ella (`D-07`) — con `category`
    /// en la clave única (§3.5), el choque llega después y en otro sitio.
    @Test("la identidad que no cuadra se ve en el preview, no en el 409 (C-A.3, D-58)")
    func theIdentityVerdictTravelsInThePreview() async throws {
        let cadete = try Self.team(category: .cadete)
        let season = try Self.season(federationSeasonID: "21")

        // La competición ya existe y es **juvenil**: la fila que se reutilizaría.
        let mismatched = IngestionStore()
        await mismatched.seed(club: try Self.club())
        await mismatched.seed(
            seasons: [season],
            competitions: [try Self.competition(seasonID: season.id, ageCategory: .juvenil)],
            teams: [cadete])
        let onMismatch = try await Self.useCase(
            store: mismatched,
            federation: SpyFederationClient(
                returning: Self.calendar(), readingURLAs: Self.coordinate))
            .execute(teamID: cadete.id, calendarURL: Self.url, actor: Self.actor)

        #expect(onMismatch.identityMatches == false)
        // **No hace falta un campo que diga cuál falla**: los tres valores
        // propuestos viajan en `competition`, así que la pantalla puede decir
        // *"tu equipo es cadete y esta competición es juvenil"* sin preguntar
        // otra vez. Esto es el veredicto, no el diagnóstico.
        #expect(onMismatch.competition.ageCategory == .juvenil)

        // Y la otra mitad, que es lo que impide que un `false` fijo pase por
        // guarda: la misma competición en cadete sí cuadra.
        let matched = IngestionStore()
        await matched.seed(club: try Self.club())
        await matched.seed(
            seasons: [season],
            competitions: [try Self.competition(seasonID: season.id, ageCategory: .cadete)],
            teams: [cadete])
        let onMatch = try await Self.useCase(
            store: matched,
            federation: SpyFederationClient(
                returning: Self.calendar(), readingURLAs: Self.coordinate))
            .execute(teamID: cadete.id, calendarURL: Self.url, actor: Self.actor)

        #expect(onMatch.identityMatches)
    }

    // ── C-C.5 · el equipo sin código no desaparece de `teams[]` ──────────────

    /// **`teams[]` es la razón de ser de este endpoint** (`D-16`): el
    /// administrador tiene que **reconocer su club ahí** antes de confirmar, y
    /// de esa lista sale el `ownTeamFederationId` del enganche.
    ///
    /// **La fuente publica equipos sin `codigo_equipo`** —medido, y es lo que
    /// F9-bis dejó anotado en la pasada como `unidentified_team`—. Ese equipo
    /// **viaja con el campo nulo** en vez de desaparecer: filtrarlo sería
    /// esconder el caso justo en la pantalla donde un humano tiene que
    /// reconocer su club, y le dejaría un hueco que nadie puede explicar. La web
    /// lo enseña y ofrece entrada manual; elegirlo como propio **sí** está
    /// prohibido, porque `ownTeamFederationId` es obligatorio al confirmar
    /// (`D-67`) — pero eso es una regla de la otra puerta, no de ésta.
    ///
    /// **Y la lista es de equipos, no de menciones**: el mismo equipo aparece en
    /// tantos partidos como jornadas tiene el calendario. Se desduplica por el
    /// código cuando lo hay y por el nombre cuando no, que es lo único que queda.
    @Test("el equipo sin código viaja con el campo nulo y no se filtra (F9-bis, D-16)")
    func theTeamWithoutACodeStillTravels() async throws {
        let team = try Self.team()
        let store = IngestionStore()
        await store.seed(club: try Self.club())
        await store.seed(teams: [team])

        // Dos jornadas, cuatro menciones, **tres** equipos — y uno de ellos sin
        // código, como la fuente los publica.
        let calendar = Self.calendar(rounds: [
            FederationRound(number: 1, matches: [
                FederationMatch(
                    federationMatchID: "1",
                    home: Self.teamRef("3349086", "C.D. EJEMPLO 'A'"),
                    away: Self.teamRef(nil, "C.D. EL ESCORIAL"),
                    homeScore: nil, awayScore: nil,
                    date: Self.instant("2025-09-13"), kickoff: nil,
                    venue: nil, venueCode: nil)
            ]),
            FederationRound(number: 2, matches: [
                FederationMatch(
                    federationMatchID: "2",
                    home: Self.teamRef("3349087", "C.D. GALAPAGAR 'B'"),
                    away: Self.teamRef("3349086", "C.D. EJEMPLO 'A'"),
                    homeScore: nil, awayScore: nil,
                    date: Self.instant("2025-09-20"), kickoff: nil,
                    venue: nil, venueCode: nil)
            ])
        ])

        let preview = try await Self.useCase(
            store: store,
            federation: SpyFederationClient(
                returning: calendar, readingURLAs: Self.coordinate))
            .execute(teamID: team.id, calendarURL: Self.url, actor: Self.actor)

        #expect(preview.competition.teams.count == 3)
        let unidentified = preview.competition.teams.filter { $0.federationTeamID == nil }
        #expect(unidentified.count == 1)
        // **Y llega reconocible**: el nombre en crudo es lo único que le queda a
        // la pantalla para enseñarlo.
        #expect(unidentified.first?.rawName == "C.D. EL ESCORIAL")
    }

    // ── C-C.8 · la misma regla en la primera puerta ──────────────────────────

    /// **La otra mitad de `C-C.8`: el `/preview` tampoco se inventa la
    /// etiqueta.**
    ///
    /// Aquí no hay cuerpo que la traiga —el `/preview` recibe solo la URL—, así
    /// que sin etiqueta en la fuente y con temporada nueva no hay nada honesto
    /// que enseñar: el contrato declara `label` **obligatoria y no anulable**, y
    /// rellenarla con una cadena vacía sería *"una fila que miente"* — el mismo
    /// defecto que `D-96` corrigió en `finishedAt`.
    ///
    /// La consecuencia es deliberada y conviene verla escrita: en una federación
    /// que no publique etiqueta, **la temporada hay que darla de alta antes**
    /// (`POST /v1/seasons`) y entonces las dos puertas funcionan. Es exactamente
    /// lo que `seed-competition` ya dice en su mensaje de error.
    @Test("el preview tampoco inventa la etiqueta de una temporada nueva (D-91, H-08)")
    func thePreviewDoesNotInventASeasonLabel() async throws {
        let team = try Self.team()
        let store = IngestionStore()
        await store.seed(club: try Self.club())
        await store.seed(teams: [team])

        await #expect(throws: ApplicationError.seasonLabelUnavailable(
            federationSeasonID: "21")) {
            try await Self.useCase(
                store: store,
                federation: SpyFederationClient(
                    returning: Self.calendar(seasonLabel: nil),
                    readingURLAs: Self.coordinate))
                .execute(teamID: team.id, calendarURL: Self.url, actor: Self.actor)
        }
    }
}

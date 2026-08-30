import Domain
import Foundation
import Testing

@testable import Application

/// Nivel 2 (§8.1): la orquestación de la pasada, con los puertos falseados y
/// **cero I/O**.
///
/// Lo que **no** se prueba aquí: la política de §3.7 y la cadena de §3.7, que
/// son de nivel 1 y ya están cubiertas (F3, F4, y las cuatro entidades de esta
/// misma fase). Lo que sí: qué se carga, en qué orden, qué se hace con cada
/// desenlace de la cadena y qué se deja escrito.
@Suite("IngestCalendar · §2.3-b · la pasada del calendario, con puertos falseados")
struct IngestCalendarTests {

    static let syncInstant = Date(timeIntervalSince1970: 1_790_000_000)

    static func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "dd-MM-yyyy"
        return f.date(from: iso)!
    }

    static func season() throws -> Season {
        try Season(
            id: SeasonID(raw: UUID()), label: try SeasonLabel("2025/26"),
            federationSeasonID: "21", createdAt: Date(), updatedAt: Date())
    }

    static func competition(
        seasonID: SeasonID,
        gender: Gender = .masculino,
        modality: Modality = .futbol11,
        ageCategory: TeamCategory = .cadete,
        federationName: String? = nil,
        lastSyncedAt: Date? = nil
    ) throws -> Competition {
        try Competition(
            id: CompetitionID(raw: UUID()), seasonID: seasonID,
            modality: modality, gender: gender,
            federationCompetitionID: "24037548", federationGroupID: "24037549",
            ageCategory: ageCategory, divisionLabel: "Primera División Autonómica",
            groupLabel: "Grupo 1", federationName: federationName,
            lastSyncedAt: lastSyncedAt, createdAt: Date(), updatedAt: Date())
    }

    /// Un calendario de una jornada y un partido, con los dos equipos del
    /// volcado real de temporada jugada.
    static func calendar(
        competitionName: String? = "PRIMERA DIVISION AUTONOMICA CADETE",
        matches: [FederationMatch]? = nil
    ) throws -> FederationCalendar {
        FederationCalendar(
            seasonLabel: try SeasonLabel("2025/26"),
            competitionName: competitionName,
            groupLabel: "Grupo 1",
            currentRound: 1,
            rounds: [
                FederationRound(
                    number: 1, label: "1 (27-09-2025)",
                    matches: matches ?? [Self.match()])
            ])
    }

    static func match(
        federationMatchID: String? = "5374968",
        home: FederationTeamRef = teamRef(
            id: "821", name: "CELTIC CASTILLA C.F.", letter: "A", club: "0010940034"),
        away: FederationTeamRef = teamRef(
            id: "304468", name: "C.D. GALAPAGAR", letter: "B", club: "0011078749"),
        homeScore: Int? = nil,
        awayScore: Int? = nil,
        date: Date? = IngestCalendarTests.date("27-09-2025"),
        kickoff: WallClockTime? = nil,
        venue: String? = "CANAL ISABEL II"
    ) -> FederationMatch {
        FederationMatch(
            federationMatchID: federationMatchID, home: home, away: away,
            homeScore: homeScore, awayScore: awayScore, date: date,
            kickoff: kickoff, venue: venue, venueCode: "103")
    }

    static func teamRef(
        id: String?, name: String, letter: String?, club: String?
    ) -> FederationTeamRef {
        FederationTeamRef(
            federationTeamID: id, name: name, letter: letter,
            federationClubID: club, crestURL: nil)
    }

    /// Monta la pasada sobre un almacén sembrado con temporada y competición.
    static func pass(
        competition: Competition,
        season: Season,
        calendar: FederationCalendar,
        store: IngestionStore = IngestionStore()
    ) async -> (IngestCalendar, IngestionStore, SpyFederationClient) {
        await store.seed(seasons: [season], competitions: [competition])
        let spy = SpyFederationClient(returning: calendar)
        let useCase = IngestCalendar(
            unitOfWork: FakeUnitOfWork(store: store),
            federation: spy,
            clock: FixedClock(instant: syncInstant),
            ids: SequentialUUIDProvider())
        return (useCase, store, spy)
    }

    // ── La coordenada (§3.7) ────────────────────────────────────────────────

    /// §3.7: la coordenada son **tres códigos y una modalidad**, y ninguno lo
    /// inventa el caso de uso — `federation_season_id` es de `Season` y los otros
    /// dos de `Competition`, que es donde el administrador los tecleó.
    ///
    /// La modalidad **no es una columna de la coordenada**: es la contrapartida
    /// de dominio del `tipojuego` (`D-07`), y el adaptador la traduce al llamar.
    /// Que viaje aquí es lo que permite que el catálogo de federaciones no tenga
    /// que consultar la base.
    @Test("compone la coordenada con la temporada y la competición (§3.7)")
    func buildsTheCoordinateFromTheStoredEntities() async throws {
        let season = try Self.season()
        let competition = try Self.competition(seasonID: season.id, modality: .futbol11)
        let (useCase, _, spy) = await Self.pass(
            competition: competition, season: season, calendar: try Self.calendar())

        _ = try await useCase.execute(
            competitionID: competition.id,
            actor: .init(clubSlug: try Slug("atleti"), isSystem: true))

        #expect(spy.received == [FederationCoordinate(
            federationSeasonID: "21",
            federationCompetitionID: "24037548",
            federationGroupID: "24037549",
            modality: .futbol11)])
    }

    // ── Paso 3 de la cadena: alta nueva, que es rival por construcción ──────

    /// §3.7, paso 3: lo que la cadena no reconoce **se da de alta**, y es rival
    /// por construcción (`D-66`) — la ingesta no crea equipos propios, así que
    /// todo lo que encuentra y no reconoce es de un `OpponentClub`.
    ///
    /// Los dos clubes salen del primer partido del volcado de temporada jugada.
    /// El `slug` lo deriva `D-82` del nombre que publica la fuente.
    @Test("da de alta los clubes que la cadena no reconoce (§3.7, paso 3, D-66)")
    func createsUnknownOpponentClubs() async throws {
        let season = try Self.season()
        let competition = try Self.competition(seasonID: season.id)
        let (useCase, store, _) = await Self.pass(
            competition: competition, season: season, calendar: try Self.calendar())

        let report = try await useCase.execute(
            competitionID: competition.id,
            actor: .init(clubSlug: try Slug("atleti"), isSystem: true))

        let clubs = await store.opponentClubs.sorted { $0.name < $1.name }
        #expect(clubs.count == 2)
        #expect(clubs.map(\.name) == ["C.D. GALAPAGAR", "CELTIC CASTILLA C.F."])
        #expect(clubs.map(\.slug.value) == ["c-d-galapagar", "celtic-castilla-c-f"])
        #expect(clubs.map(\.federationClubID) == ["0011078749", "0010940034"])
        // El nombre corto nace igual que el nombre: lo acorta un humano (spec).
        #expect(clubs.map(\.shortName) == ["C.D. GALAPAGAR", "CELTIC CASTILLA C.F."])
        #expect(report.opponentClubsCreated == 2)
    }

    /// `D-07` y `D-58`: la federación **no publica** categoría, género ni
    /// modalidad por equipo —el género lo embebe en el nombre de la competición
    /// ([Anexo RFFM §F.14])—, así que las tres las presta la `Competition` que se
    /// está sincronizando. Y las tres entran en la clave única de §3.5, de modo
    /// que equivocarse no da un dato feo: da un 409.
    ///
    /// La competición de este test es **cadete femenino de fútbol sala**, que no
    /// se parece a nada de lo que trae el calendario: si el caso de uso dedujera
    /// cualquiera de las tres del texto de la fuente, el test lo cazaría.
    @Test("el equipo nuevo hereda categoría, género y modalidad de la competición (D-07, D-58)")
    func newTeamsInheritTheCompetitionIdentity() async throws {
        let season = try Self.season()
        let competition = try Self.competition(
            seasonID: season.id, gender: .femenino,
            modality: .futbolSala, ageCategory: .juvenil)
        let (useCase, store, _) = await Self.pass(
            competition: competition, season: season, calendar: try Self.calendar())

        let report = try await useCase.execute(
            competitionID: competition.id,
            actor: .init(clubSlug: try Slug("atleti"), isSystem: true))

        let teams = await store.teams.sorted { ($0.letter ?? "") < ($1.letter ?? "") }
        #expect(teams.count == 2)
        #expect(teams.allSatisfy { $0.category == .juvenil })
        #expect(teams.allSatisfy { $0.gender == .femenino })
        #expect(teams.allSatisfy { $0.modality == .futbolSala })
        // La letra sí la publica la fuente, embebida en el nombre; la separa el
        // adaptador (F2, `RFFMValue.teamName`).
        #expect(teams.map(\.letter) == ["A", "B"])
        #expect(teams.map(\.federationTeamID) == ["821", "304468"])
        // `D-66`: todo lo que la ingesta crea es rival. No hay equipos propios.
        #expect(teams.allSatisfy { !$0.isOwn })
        #expect(report.teamsCreated == 2)
    }

    // ── La jornada y su rango (D-81) ────────────────────────────────────────

    /// `D-81` con el reparto real: la jornada 1 del volcado de temporada jugada
    /// tiene seis partidos el sábado 27 y dos el domingo 28. El rango sale del
    /// mínimo y el máximo, y **el número sale del `codjornada`**, no del índice
    /// del array ([Anexo RFFM §F.15]).
    @Test("crea la jornada con el rango de sus partidos (D-81)")
    func createsTheRoundSpanningItsMatches() async throws {
        let season = try Self.season()
        let competition = try Self.competition(seasonID: season.id)
        let calendar = try Self.calendar(matches: [
            Self.match(federationMatchID: "5374968"),
            Self.match(
                federationMatchID: "5374969",
                home: Self.teamRef(
                    id: "900", name: "E.F.M.O. BOADILLA", letter: "B", club: "0011111111"),
                away: Self.teamRef(
                    id: "901", name: "LAS ROZAS C.F.", letter: "C", club: "0012222222"),
                date: Self.date("28-09-2025")),
        ])
        let (useCase, store, _) = await Self.pass(
            competition: competition, season: season, calendar: calendar)

        let report = try await useCase.execute(
            competitionID: competition.id,
            actor: .init(clubSlug: try Slug("atleti"), isSystem: true))

        let rounds = await store.rounds
        #expect(rounds.count == 1)
        #expect(rounds.first?.number == 1)
        #expect(rounds.first?.competitionID == competition.id)
        #expect(rounds.first?.startDate == Self.date("27-09-2025"))
        #expect(rounds.first?.endDate == Self.date("28-09-2025"))
        #expect(report.roundsCreated == 1)
    }

    // ── El partido ──────────────────────────────────────────────────────────

    /// El primer partido del volcado de temporada jugada, entero: `codacta`
    /// 5374968, Celtic Castilla 'A' 3-3 C.D. Galapagar 'B', 27-09-2025 a las
    /// 10:45 en el Canal Isabel II.
    ///
    /// **El local y el visitante no son intercambiables**, y por eso la aserción
    /// los comprueba por separado contra los equipos que la pasada creó: cruzar
    /// los dos daría un partido que existe y es falso.
    @Test("crea el partido con su marcador, su hora y su estado (§3.7)")
    func createsThePlayedMatch() async throws {
        let season = try Self.season()
        let competition = try Self.competition(seasonID: season.id)
        let calendar = try Self.calendar(matches: [
            Self.match(homeScore: 3, awayScore: 3,
                       kickoff: WallClockTime(hour: 10, minute: 45))
        ])
        let (useCase, store, _) = await Self.pass(
            competition: competition, season: season, calendar: calendar)

        let report = try await useCase.execute(
            competitionID: competition.id,
            actor: .init(clubSlug: try Slug("atleti"), isSystem: true))

        let matches = await store.matches
        let teams = await store.teams
        let celtic = teams.first { $0.federationTeamID == "821" }
        let galapagar = teams.first { $0.federationTeamID == "304468" }
        let round = await store.rounds.first

        #expect(matches.count == 1)
        #expect(matches.first?.competitionID == competition.id)
        #expect(matches.first?.roundID == round?.id)
        #expect(matches.first?.homeTeamID == celtic?.id)
        #expect(matches.first?.awayTeamID == galapagar?.id)
        #expect(matches.first?.result == (try MatchResult(homeScore: 3, awayScore: 3)))
        #expect(matches.first?.status == .finalizado)
        #expect(matches.first?.kickoff.date == Self.date("27-09-2025"))
        #expect(matches.first?.kickoff.time == WallClockTime(hour: 10, minute: 45))
        #expect(matches.first?.venue == "CANAL ISABEL II")
        #expect(matches.first?.federationMatchID == "5374968")
        #expect(report.matchesCreated == 1)
    }

    /// Construye una pasada más sobre un almacén **ya sembrado**, que es como se
    /// prueba la segunda semana.
    static func again(
        on store: IngestionStore, calendar: FederationCalendar
    ) -> IngestCalendar {
        IngestCalendar(
            unitOfWork: FakeUnitOfWork(store: store),
            federation: SpyFederationClient(returning: calendar),
            clock: FixedClock(instant: syncInstant),
            ids: SequentialUUIDProvider())
    }

    // ── Idempotencia: la propiedad que hace segura la cadencia semanal ──────

    /// §5.6 fija **una pasada por semana como mínimo**, así que la misma
    /// competición se recorre decenas de veces por temporada. Si la segunda
    /// pasada duplicara algo, el modelo se degradaría solo.
    ///
    /// La prueba usa las dos muestras reales seguidas: primero el calendario tal
    /// como nace —sin marcador y sin hora, el volcado de temporada sin arrancar—
    /// y después el mismo partido ya jugado. **Nada se crea dos veces y el
    /// resultado entra**, que es literalmente lo que hace la ingesta cada lunes.
    @Test("la segunda pasada actualiza y no duplica (§5.6)")
    func secondPassUpdatesInsteadOfDuplicating() async throws {
        let season = try Self.season()
        let competition = try Self.competition(seasonID: season.id)
        let (first, store, _) = await Self.pass(
            competition: competition, season: season,
            calendar: try Self.calendar(matches: [Self.match()]))
        let actor = ActorContext(clubSlug: try Slug("atleti"), isSystem: true)

        _ = try await first.execute(competitionID: competition.id, actor: actor)

        let second = Self.again(on: store, calendar: try Self.calendar(matches: [
            Self.match(homeScore: 3, awayScore: 3,
                       kickoff: WallClockTime(hour: 10, minute: 45))
        ]))
        let report = try await second.execute(competitionID: competition.id, actor: actor)

        #expect(await store.opponentClubs.count == 2)
        #expect(await store.teams.count == 2)
        #expect(await store.rounds.count == 1)
        #expect(await store.matches.count == 1)

        let match = await store.matches.first
        #expect(match?.result == (try MatchResult(homeScore: 3, awayScore: 3)))
        #expect(match?.status == .finalizado)
        #expect(match?.kickoff.time == WallClockTime(hour: 10, minute: 45))

        #expect(report.matchesCreated == 0)
        #expect(report.matchesUpdated == 1)
        #expect(report.opponentClubsCreated == 0)
        #expect(report.teamsCreated == 0)
        #expect(report.roundsCreated == 0)
    }

    // ── La frontera de D-66 / D-67 dentro de la pasada ─────────────────────

    /// El caso que ocurre **en todas las jornadas de todas las semanas**: el
    /// calendario menciona a nuestro propio equipo, porque la federación no
    /// distingue propio de rival ni puede.
    ///
    /// Ese equipo lo creó el club (`D-66`) y lo enganchó el administrador
    /// (`D-67`), así que tiene `codigo_equipo` y el **paso 1** lo reconoce. Dos
    /// cosas tienen que pasar, y las dos son negativas:
    ///
    /// 1. **no se le toca `opponent_club_id`** (§3.7, campo de propiedad,
    ///    `D-20`) — si no, la primera sincronización tras reclamarlo lo
    ///    devolvería a rival;
    /// 2. **no se crea un `OpponentClub` con el nombre de nuestro club**, que es
    ///    lo que pasaría si la pasada resolviera el club antes que el equipo.
    ///
    /// El segundo no lo impide ningún tipo: lo impide el **orden**, y por eso
    /// hace falta este test y no basta con el de `Team.merging`.
    @Test("el equipo propio ya enganchado no vuelve a rival ni crea club (D-20, D-66)")
    func engagedOwnTeamStaysOwnAndCreatesNoClub() async throws {
        let season = try Self.season()
        let competition = try Self.competition(seasonID: season.id)
        let ownTeam = try Team(
            id: TeamID(raw: UUID()), opponentClubID: nil,
            category: .cadete, letter: "A", gender: .masculino, modality: .futbol11,
            federationTeamID: "821", createdAt: Date(), updatedAt: Date())

        let store = IngestionStore()
        await store.seed(teams: [ownTeam])
        let (useCase, _, _) = await Self.pass(
            competition: competition, season: season,
            calendar: try Self.calendar(), store: store)

        let report = try await useCase.execute(
            competitionID: competition.id,
            actor: .init(clubSlug: try Slug("atleti"), isSystem: true))

        let teams = await store.teams
        #expect(teams.count == 2)
        #expect(teams.first { $0.id == ownTeam.id }?.isOwn == true)
        #expect(teams.first { $0.id == ownTeam.id }?.opponentClubID == nil)

        // Solo el club del rival. El nuestro **no** aparece como OpponentClub.
        let clubs = await store.opponentClubs
        #expect(clubs.count == 1)
        #expect(clubs.first?.name == "C.D. GALAPAGAR")
        #expect(report.opponentClubsCreated == 1)
        #expect(report.teamsCreated == 1)
    }

    // ── D-79: dos candidatos no se resuelven, se reportan ──────────────────

    /// `D-79`. El caso es real y lo produce la propia corrección manual: el
    /// nombre es campo **descriptivo**, así que el administrador lo arregla, y
    /// dos filas distintas —`"C.D. GALAPAGAR"` y `"CD GALAPAGAR"`— **normalizan
    /// igual** (`D-80`). El `UNIQUE(name)` de §3.5 no las impide: son dos
    /// nombres distintos.
    ///
    /// Con la clave de federación ausente ([Anexo RFFM §F.4] — es una inferencia
    /// sobre un nombre de fichero), el paso 1 no resuelve y el paso 2 encuentra
    /// dos. Entonces **ni se elige ni se crea**: elegir congelaría un
    /// emparejamiento posiblemente equivocado y crear haría el duplicado que la
    /// cadena existe para evitar.
    ///
    /// Y hay una segunda mitad, que es de la pasada y no de la cadena: **el
    /// partido se cae con el equipo**, porque un `Match` necesita sus dos FK.
    /// Se reporta como `unresolvedTeam` y no como otra ambigüedad, para que el
    /// informe no cuente dos incidencias donde hay una.
    @Test("dos clubes que normalizan igual no se resuelven: se reportan (D-79)")
    func ambiguousClubIsReportedAndDragsItsMatch() async throws {
        let season = try Self.season()
        let competition = try Self.competition(seasonID: season.id)
        let store = IngestionStore()
        await store.seed(opponentClubs: [
            try OpponentClub(
                id: OpponentClubID(raw: UUID()), name: "C.D. GALAPAGAR",
                shortName: "Galapagar", slug: try Slug("c-d-galapagar"),
                createdAt: Date(), updatedAt: Date()),
            try OpponentClub(
                id: OpponentClubID(raw: UUID()), name: "CD GALAPAGAR",
                shortName: "Galapagar", slug: try Slug("cd-galapagar"),
                createdAt: Date(), updatedAt: Date()),
        ])

        // El equipo visitante llega **sin** federationClubID: la inferencia
        // sobre la ruta del escudo falló (§F.4), que es el supuesto de toda la
        // degradación de §3.7.
        let calendar = try Self.calendar(matches: [
            Self.match(away: Self.teamRef(
                id: "304468", name: "C.D. GALAPAGAR", letter: "B", club: nil))
        ])
        let (useCase, _, _) = await Self.pass(
            competition: competition, season: season, calendar: calendar, store: store)

        let report = try await useCase.execute(
            competitionID: competition.id,
            actor: .init(clubSlug: try Slug("atleti"), isSystem: true))

        // Ni se eligió uno de los dos Galapagar ni se creó un tercero. El único
        // club que la pasada da de alta es el del **local**, que no es ambiguo.
        let galapagar = await store.opponentClubs.filter {
            $0.matchingName == NormalizedName("C.D. GALAPAGAR")
        }
        #expect(galapagar.count == 2)
        #expect(galapagar.allSatisfy { $0.federationClubID == nil })
        #expect(await store.opponentClubs.count == 3)
        #expect(report.opponentClubsCreated == 1)
        // El equipo del rival no se crea; el del local, sí.
        #expect(await store.teams.count == 1)
        #expect(await store.teams.first?.federationTeamID == "821")
        // Y el partido se cae con él.
        #expect(await store.matches.isEmpty)

        #expect(report.skipped == [
            IngestionSkip(reason: .ambiguousOpponentClub, detail: "C.D. GALAPAGAR"),
            IngestionSkip(
                reason: .unresolvedTeam,
                detail: "[5374968] CELTIC CASTILLA C.F. - C.D. GALAPAGAR"),
        ])
    }

    // ── Lo que la pasada deja escrito en la competición ────────────────────

    /// Dos cosas, y las dos de §3.2.
    ///
    /// `last_synced_at` = *"última sincronización **con éxito**"*, y es la
    /// condición bajo la cual las coordenadas y el género dejan de ser editables
    /// (`D-22`). Sale del puerto `Clock`, no de un `Date()`: con un `Date()` la
    /// única aserción posible sería *"no es nulo"*, que pasaría igual si se
    /// escribiera la fecha equivocada.
    ///
    /// `federation_name` = **evidencia, no rótulo** (`D-72`). Nace nulo —el alta
    /// por ids no pasa por la federación— y lo rellena la primera pasada. Es lo
    /// que hay que poder mirar cuando un alta reviente con 409 porque la
    /// inferencia de `gender` falló.
    @Test("deja fecha de sincronización y el nombre literal de la fuente (§3.2, D-72)")
    func recordsTheSyncInstantAndTheSourceName() async throws {
        let season = try Self.season()
        let competition = try Self.competition(seasonID: season.id, federationName: nil)
        let (useCase, store, _) = await Self.pass(
            competition: competition, season: season, calendar: try Self.calendar())

        let report = try await useCase.execute(
            competitionID: competition.id,
            actor: .init(clubSlug: try Slug("atleti"), isSystem: true))

        let stored = await store.competitions.first
        #expect(stored?.lastSyncedAt == Self.syncInstant)
        #expect(stored?.isSynced == true)
        #expect(stored?.federationName == "PRIMERA DIVISION AUTONOMICA CADETE")
        #expect(report.syncedAt == Self.syncInstant)
    }

    // ── La guarda que exigió el hallazgo de los dos volcados ───────────────

    /// **Capturando los volcados de esta fase se descubrió que la RFFM reutiliza
    /// los códigos de competición y grupo entre temporadas.** La misma URL con
    /// `temporada=22` da PREFERENTE AFICIONADO y con `temporada=21` da PRIMERA
    /// DIVISION AUTONOMICA CADETE.
    ///
    /// Eso rompe el supuesto de Plan §4.4 —*"un 404 tiene que decir una cosa y un
    /// parseo fallido otra"*—: una coordenada caducada **no da 404**, devuelve un
    /// calendario perfectamente parseable **de otra competición**. Sin guarda, la
    /// pasada escribiría un calendario cadete dentro de una competición senior y
    /// nada chillaría: los equipos heredarían la categoría equivocada de la
    /// competición (`D-07`) y los partidos colgarían de ella.
    ///
    /// La evidencia con la que detectarlo ya existía: `federation_name`, que
    /// `D-72` guarda como procedencia. Aquí es donde se cobra.
    ///
    /// **Se para y no se escribe nada**, que es lo que pidió el desarrollador: la
    /// transacción se deshace y queda lo que hubiera.
    @Test("una coordenada que apunta a otra competición para la pasada (D-72, D-84)")
    func abortsWhenTheSourceNamesAnotherCompetition() async throws {
        let season = try Self.season()
        let competition = try Self.competition(
            seasonID: season.id, federationName: "PREFERENTE AFICIONADO")
        let (useCase, store, _) = await Self.pass(
            competition: competition, season: season,
            calendar: try Self.calendar(
                competitionName: "PRIMERA DIVISION AUTONOMICA CADETE"))

        await #expect(throws: DomainError.self) {
            try await useCase.execute(
                competitionID: competition.id,
                actor: .init(clubSlug: try Slug("atleti"), isSystem: true))
        }

        #expect(await store.opponentClubs.isEmpty)
        #expect(await store.teams.isEmpty)
        #expect(await store.rounds.isEmpty)
        #expect(await store.matches.isEmpty)
        #expect(await store.competitions.first?.lastSyncedAt == nil)
    }

    /// El reverso, y **llega en verde**: el mismo nombre no es una discrepancia.
    /// Se escribe porque una guarda que parase siempre pasaría el test de
    /// arriba igual de bien.
    @Test("el mismo nombre no para nada (D-84)")
    func doesNotAbortWhenTheNameMatches() async throws {
        let season = try Self.season()
        let competition = try Self.competition(
            seasonID: season.id, federationName: "PRIMERA DIVISION AUTONOMICA CADETE")
        let (useCase, store, _) = await Self.pass(
            competition: competition, season: season, calendar: try Self.calendar())

        _ = try await useCase.execute(
            competitionID: competition.id,
            actor: .init(clubSlug: try Slug("atleti"), isSystem: true))

        #expect(await store.matches.count == 1)
    }

    /// Y la otra mitad: **la primera pasada no tiene con qué comparar**. El alta
    /// por ids no pasa por la federación, así que `federation_name` nace nulo
    /// (`D-72`) y la guarda no puede exigir nada. Si parase aquí, ninguna
    /// competición se podría sincronizar nunca por primera vez.
    @Test("sin evidencia guardada, la primera pasada no se para (D-72, D-84)")
    func doesNotAbortOnTheFirstPass() async throws {
        let season = try Self.season()
        let competition = try Self.competition(seasonID: season.id, federationName: nil)
        let (useCase, store, _) = await Self.pass(
            competition: competition, season: season, calendar: try Self.calendar())

        _ = try await useCase.execute(
            competitionID: competition.id,
            actor: .init(clubSlug: try Slug("atleti"), isSystem: true))

        #expect(await store.matches.count == 1)
        #expect(await store.competitions.first?.federationName
                == "PRIMERA DIVISION AUTONOMICA CADETE")
    }

    // ── Lo que la pasada deja fuera, y sigue ───────────────────────────────

    /// `match_date` es `NOT NULL` (§3.2) y la jornada tiene fecha nominal en su
    /// rótulo, así que la tentación es rellenar con ella. **No se hace**: sería
    /// inventarle a un partido concreto el dato de otro, y `D-75` dice que
    /// ignorar de más se corrige en la pasada siguiente y escribir de más no se
    /// corrige nunca.
    ///
    /// Lo que sí pasa: **el resto de la jornada entra**, y los equipos del
    /// partido descartado también — ya estaban emparejados cuando se llegó al
    /// partido (§3.7), y una fila de equipo buena no se pierde porque su partido
    /// venga incompleto.
    @Test("el partido sin fecha se queda fuera y se reporta, y la jornada sigue (D-75)")
    func matchWithoutDateIsSkipped() async throws {
        let season = try Self.season()
        let competition = try Self.competition(seasonID: season.id)
        let calendar = try Self.calendar(matches: [
            Self.match(federationMatchID: "5374968"),
            Self.match(
                federationMatchID: "5374969",
                home: Self.teamRef(
                    id: "900", name: "E.F.M.O. BOADILLA", letter: "B", club: "0011111111"),
                away: Self.teamRef(
                    id: "901", name: "LAS ROZAS C.F.", letter: "C", club: "0012222222"),
                date: nil),
        ])
        let (useCase, store, _) = await Self.pass(
            competition: competition, season: season, calendar: calendar)

        let report = try await useCase.execute(
            competitionID: competition.id,
            actor: .init(clubSlug: try Slug("atleti"), isSystem: true))

        #expect(await store.matches.count == 1)
        #expect(await store.matches.first?.federationMatchID == "5374968")
        #expect(await store.teams.count == 4)
        #expect(report.skipped == [IngestionSkip(
            reason: .missingMatchDate,
            detail: "[5374969] E.F.M.O. BOADILLA - LAS ROZAS C.F.")])
    }

    // ── D-82: dos clubes distintos con el mismo nombre ─────────────────────

    /// El caso lo produce la propia cadena: un club ya guardado con
    /// `federation_club_id` **contradice** a uno entrante con otro, así que el
    /// paso 2 lo descarta (§3.7) — la fuente está diciendo que son dos clubes
    /// distintos— y se crea uno nuevo.
    ///
    /// **Los dos nombres son distintos** —`"C D GALAPAGAR"` y
    /// `"C.D. GALAPAGAR"`—, que es lo que hace el caso posible: `UNIQUE(name)`
    /// (§3.5) no deja repetir nombre. Pero el slug se deriva del nombre
    /// (`D-82`) tratando toda la puntuación como una frontera, así que los dos
    /// dan `c-d-galapagar` y el `UNIQUE(slug)` rechazaría la fila.
    ///
    /// Como el slug es **inmutable** y acaba en claves de Storage (`D-19`), no se
    /// puede "arreglar después": se desempata al crear, con sufijo. Y el
    /// desempate vive en la pasada y no en el VO porque exige saber qué hay ya
    /// guardado, que es justo lo que un *Value Object* no puede saber.
    @Test("dos clubes distintos con el mismo nombre no colisionan de slug (D-82)")
    func collidingSlugsAreDisambiguated() async throws {
        let season = try Self.season()
        let competition = try Self.competition(seasonID: season.id)
        let store = IngestionStore()
        await store.seed(opponentClubs: [try OpponentClub(
            id: OpponentClubID(raw: UUID()), name: "C D GALAPAGAR",
            shortName: "Galapagar", slug: try Slug("c-d-galapagar"),
            federationClubID: "0011078749", createdAt: Date(), updatedAt: Date())])

        // Otra grafía del mismo nombre —así que normaliza igual y el slug
        // colisiona— con **otro** federation_club_id: la fuente dice que es otro
        // club, y el paso 2 descarta al que contradice.
        let calendar = try Self.calendar(matches: [
            Self.match(away: Self.teamRef(
                id: "304468", name: "C.D. GALAPAGAR", letter: "B", club: "0099999999"))
        ])
        let (useCase, _, _) = await Self.pass(
            competition: competition, season: season, calendar: calendar, store: store)

        _ = try await useCase.execute(
            competitionID: competition.id,
            actor: .init(clubSlug: try Slug("atleti"), isSystem: true))

        let galapagar = await store.opponentClubs.sorted { $0.slug.value < $1.slug.value }
        #expect(galapagar.count == 3)  // los dos Galapagar y el Celtic del local
        let slugs = galapagar.filter { $0.slug.value.hasPrefix("c-d-galapagar") }
        #expect(slugs.map(\.slug.value) == ["c-d-galapagar", "c-d-galapagar-2"])
        #expect(slugs.map(\.name) == ["C D GALAPAGAR", "C.D. GALAPAGAR"])
        #expect(slugs.map(\.federationClubID) == ["0011078749", "0099999999"])
    }

    // ── D-83: dónde están las fronteras transaccionales ────────────────────

    /// `D-83`: la pasada abre **dos** ámbitos —leer la coordenada y escribir el
    /// resultado— y la llamada a la federación queda **fuera de los dos**. Con
    /// uno solo, una caída del proveedor dejaría una transacción abierta
    /// esperando, que es como se agota el *pool* de §6.4.
    ///
    /// Y todo lo que se escribe va en **el segundo**, entero: o la competición
    /// queda sincronizada o no queda tocada, coherente con que `last_synced_at`
    /// signifique *"última sincronización con éxito"*.
    @Test("la pasada abre dos ámbitos y la red queda fuera de los dos (D-83)")
    func opensExactlyTwoScopes() async throws {
        let season = try Self.season()
        let competition = try Self.competition(seasonID: season.id)
        let (useCase, store, _) = await Self.pass(
            competition: competition, season: season, calendar: try Self.calendar())

        _ = try await useCase.execute(
            competitionID: competition.id,
            actor: .init(clubSlug: try Slug("atleti"), isSystem: true))

        #expect(await store.scopesOpened == 2)
    }

    /// Y el caso que el nivel 2 **no puede** cazar solo, porque estos dobles no
    /// tienen restricciones: §3.5 declara `OpponentClub(name)` **único**, así que
    /// dos clubes con el mismo nombre literal no caben en la tabla.
    ///
    /// La cadena sí produce ese intento —descarta al candidato cuya clave
    /// contradice (§3.7) y cae al paso 3—, y sin guarda la fila reventaría el
    /// `UNIQUE` y con él **la transacción entera**: una coincidencia de nombre se
    /// llevaría por delante la pasada de toda la competición.
    ///
    /// Así que se trata como lo que es: dos filas que dicen ser el mismo club y
    /// la fuente dice que no. Ni se elige ni se crea, se reporta — el mismo
    /// desenlace que `D-79`, por un camino distinto.
    @Test("dos clubes con el mismo nombre literal se reportan, no revientan la pasada (§3.5)")
    func duplicateClubNameIsReportedInsteadOfBreakingThePass() async throws {
        let season = try Self.season()
        let competition = try Self.competition(seasonID: season.id)
        let store = IngestionStore()
        await store.seed(opponentClubs: [try OpponentClub(
            id: OpponentClubID(raw: UUID()), name: "C.D. GALAPAGAR",
            shortName: "Galapagar", slug: try Slug("c-d-galapagar"),
            federationClubID: "0011078749", createdAt: Date(), updatedAt: Date())])

        let calendar = try Self.calendar(matches: [
            Self.match(away: Self.teamRef(
                id: "304468", name: "C.D. GALAPAGAR", letter: "B", club: "0099999999"))
        ])
        let (useCase, _, _) = await Self.pass(
            competition: competition, season: season, calendar: calendar, store: store)

        let report = try await useCase.execute(
            competitionID: competition.id,
            actor: .init(clubSlug: try Slug("atleti"), isSystem: true))

        // Solo el club del local se da de alta. El Galapagar entrante se reporta.
        #expect(await store.opponentClubs.count == 2)
        #expect(report.skipped.map(\.reason) == [.duplicateClubName, .unresolvedTeam])
        #expect(await store.matches.isEmpty)
    }
}

import Foundation
import Domain

/// El recorrido de **una** pasada de ingesta sobre **una** competición.
///
/// Vive aparte de `IngestCalendar` porque tiene lo que un caso de uso no debe
/// tener: **estado**. Las listas de candidatos se cargan una vez y se van
/// actualizando según la pasada crea filas, de modo que dos partidos de la misma
/// jornada que mencionen al mismo club nuevo lo creen **una** vez — sin volver a
/// consultar y sin duplicar.
///
/// Ese estado es lo que obliga a que el ciclo de vida sea el de la pasada: se
/// construye dentro del ámbito de tenant, se recorre y se tira. No es
/// `Sendable`, y es correcto que no lo sea.
///
/// # Qué hay aquí y qué no
///
/// Aquí: el **orden** y qué se hace con cada desenlace. Las dos reglas de §3.7
/// —a qué fila corresponde lo que llega, y qué se le escribe— están en el
/// Dominio, en `MatchingChain` y en el `merging` de cada entidad. Si alguna
/// vuelve a aparecer escrita aquí, está duplicada.
final class CalendarPass {
    private let competition: Competition
    private let repositories: any Repositories
    private let ids: any UUIDProvider
    private let now: Date

    /// Los candidatos de la cadena, en memoria y **al día**: lo que la pasada
    /// crea entra aquí, no en la siguiente consulta.
    private var clubs: [OpponentClub]
    private var teams: [Team]
    private var rounds: [Round]
    private var matches: [Match]

    private(set) var report: IngestionRun

    init(
        competition: Competition,
        repositories: any Repositories,
        ids: any UUIDProvider,
        now: Date
    ) async throws {
        self.competition = competition
        self.repositories = repositories
        self.ids = ids
        self.now = now
        self.clubs = try await repositories.opponentClubs.list()
        self.teams = try await repositories.teams.list()
        self.rounds = try await repositories.rounds.list(competitionID: competition.id)
        self.matches = try await repositories.matches.list(competitionID: competition.id)
        self.report = try IngestionRun(
            id: IngestionRunID(raw: ids.next()),
            competitionID: competition.id,
            startedAt: now, finishedAt: now)
    }

    func run(_ calendar: FederationCalendar) async throws {
        // **Lo primero de todo** (`D-84`): antes de escribir una sola fila, que
        // la coordenada siga apuntando a esta competición. La RFFM **ignora el
        // parámetro `temporada`** y sus códigos son densos ([Anexo RFFM §F.16],
        // que enmendó la causa que `D-84` daba), así que una coordenada
        // equivocada o caducada no falla — devuelve el calendario de otra
        // competición, y se parecen lo suficiente como para que la pasada entera
        // lo escriba sin enterarse.
        try competition.requireSameSource(as: calendar.competitionName)

        for federationRound in calendar.rounds {
            // La jornada primero: los partidos cuelgan de ella por FK, y su
            // rango se calcula del conjunto, no partido a partido (`D-81`).
            let roundID = try await resolveRound(federationRound)

            for match in federationRound.matches {
                // Los equipos **siempre**, aunque el partido acabe descartándose:
                // §3.7 dice que los equipos ya están emparejados cuando se llega
                // al partido, y una fila de equipo válida no se pierde porque su
                // partido venga sin fecha.
                let home = try await resolveTeam(match.home)
                let away = try await resolveTeam(match.away)

                guard let roundID else {
                    report.skipped.append(IngestionSkip(
                        reason: .missingMatchDate, detail: describe(match)))
                    continue
                }
                try await resolveMatch(match, roundID: roundID, home: home, away: away)
            }
        }

        // Lo último, y dentro del mismo ámbito: si algo de lo anterior revienta,
        // la transacción se deshace y **la marca de sincronizado no se escribe**
        // — que es lo que hace que `last_synced_at` signifique lo que §3.2 dice.
        try await repositories.competitions.save(
            try competition.synced(at: now, federationName: calendar.competitionName))
    }

    // ── Partidos: la cadena de §3.7, dos pasos y sin tercero ────────────────

    private func resolveMatch(
        _ federationMatch: FederationMatch, roundID: RoundID,
        home: TeamID?, away: TeamID?
    ) async throws {
        // Un equipo que se quedó fuera arrastra a su partido. No es un problema
        // del partido: es el escalón anterior, y se reporta como tal para que en
        // el informe no parezca que hay dos incidencias distintas.
        guard let home, let away else {
            report.skipped.append(IngestionSkip(
                reason: .unresolvedTeam, detail: describe(federationMatch)))
            return
        }

        // `match_date` es `NOT NULL` (§3.2). La jornada tiene fecha nominal en su
        // rótulo y sería tentador usarla, pero eso es **inventar el dato de un
        // partido concreto** a partir del de otro — justo lo que `D-75` dice que
        // no se corrige nunca.
        guard let date = federationMatch.date else {
            report.skipped.append(IngestionSkip(
                reason: .missingMatchDate, detail: describe(federationMatch)))
            return
        }

        let result = try incomingResult(federationMatch)
        let incoming = IncomingMatch(
            federationMatchID: federationMatch.federationMatchID,
            roundID: roundID, homeTeamID: home, awayTeamID: away)

        switch MatchingChain.match(incoming, among: matches.map(\.candidate)) {
        case .matched(let id, _):
            guard let existing = matches.first(where: { $0.id == id }) else { return }
            let merged = try existing.merging(
                roundID: roundID, date: date, time: federationMatch.kickoff,
                result: result, venue: federationMatch.venue,
                federationMatchID: federationMatch.federationMatchID)
            if merged != existing {
                try await repositories.matches.save(merged)
                if let index = matches.firstIndex(where: { $0.id == merged.id }) {
                    matches[index] = merged
                }
                report.matchesUpdated += 1
            }

        case .ambiguous:
            // Solo alcanzable si el `UNIQUE` de coordenadas de §3.5 no estuviera.
            // Aquí es señal de esquema roto más que de datos ambiguos.
            report.skipped.append(IngestionSkip(
                reason: .ambiguousMatch, detail: describe(federationMatch)))

        case .unmatched:
            let match = try Match(
                id: MatchID(raw: ids.next()),
                competitionID: competition.id,
                roundID: roundID,
                kickoff: Kickoff(date: date, time: federationMatch.kickoff),
                homeTeamID: home, awayTeamID: away,
                result: result,
                // `D-57`: en el alta el marcador entrante **es** el fusionado,
                // porque no hay nada que preservar.
                status: MatchStatus.derived(from: result),
                venue: federationMatch.venue,
                federationMatchID: federationMatch.federationMatchID,
                createdAt: now, updatedAt: now)

            try await repositories.matches.save(match)
            matches.append(match)
            report.matchesCreated += 1
        }
    }

    /// El marcador de la fuente, o `nil`.
    ///
    /// **Medio marcador no es medio partido**: `MatchResult` es los dos goles o
    /// ninguno, así que un solo campo informado se trata como silencio. Traducir
    /// las tres formas de callar de cada federación —`""`, campo ausente, `"0"`
    /// en la FCF— ya lo hizo el adaptador (§3.7); aquí solo queda el par.
    private func incomingResult(_ match: FederationMatch) throws -> MatchResult? {
        guard let home = match.homeScore, let away = match.awayScore else { return nil }
        return try MatchResult(homeScore: home, awayScore: away)
    }

    /// Con qué encontrar la fila en la fuente cuando se reporta. Texto para un
    /// humano, no una clave.
    private func describe(_ match: FederationMatch) -> String {
        let acta = match.federationMatchID.map { "[\($0)] " } ?? ""
        return "\(acta)\(match.home.name) - \(match.away.name)"
    }

    // ── Jornadas: sin cadena, porque su clave es exacta (§3.5) ──────────────

    /// **No pasa por `MatchingChain`**, y no es una omisión: la jornada se
    /// identifica por (competición, número), que es un `UNIQUE` de §3.5 sobre dos
    /// columnas `NOT NULL`. No hay clave que pueda faltar, así que no hay nada
    /// que degradar — la cadena existe para las claves anulables.
    ///
    /// - Returns: `nil` si la jornada no tiene **ninguna** fecha con la que
    ///   calcular su rango. Sus partidos se caen con ella, y cada uno se reporta
    ///   por su cuenta.
    private func resolveRound(_ federationRound: FederationRound) async throws -> RoundID? {
        let span = Round.span(ofMatchDates: federationRound.matches.compactMap(\.date))

        if let existing = rounds.first(where: { $0.number == federationRound.number }) {
            let merged = existing.merging(span: span)
            if merged != existing {
                try await repositories.rounds.save(merged)
                if let index = rounds.firstIndex(where: { $0.id == merged.id }) {
                    rounds[index] = merged
                }
                report.roundsUpdated += 1
            }
            return existing.id
        }

        // Sin rango no se puede crear: las dos columnas son `NOT NULL` (§3.2) e
        // inventar un fin de semana sería exactamente lo que `D-75` prohíbe.
        guard let span else { return nil }

        let round = try Round(
            id: RoundID(raw: ids.next()),
            competitionID: competition.id,
            // Del `codjornada`, que es lo que trae `FederationRound.number`
            // ([Anexo RFFM §F.15]).
            number: federationRound.number,
            startDate: span.lowerBound,
            endDate: span.upperBound,
            createdAt: now, updatedAt: now)

        try await repositories.rounds.save(round)
        rounds.append(round)
        report.roundsCreated += 1
        return round.id
    }

    // ── Equipos: la cadena de §3.7, y el orden importa ──────────────────────

    /// **El equipo se resuelve antes que su club**, y no al revés.
    ///
    /// La razón es `D-66`: el paso 1 de la cadena de equipos alcanza también a
    /// los **propios ya enganchados** (`D-67`), y ésos no tienen `OpponentClub`
    /// ni deben tenerlo. Resolver primero el club crearía una fila de club rival
    /// con el nombre de nuestro propio club en cuanto la pasada se cruzara con
    /// nuestro equipo — que es lo que hace en todas las jornadas.
    ///
    /// El paso 2 tampoco lo necesita: compara el nombre del club **que publica
    /// la fuente**, no el de la fila que tengamos. El club solo hace falta para
    /// **crear** el equipo, que es el paso 3.
    private func resolveTeam(_ ref: FederationTeamRef) async throws -> TeamID? {
        let incoming = IncomingTeam(
            federationTeamID: ref.federationTeamID,
            clubName: NormalizedName(ref.name),
            letter: ref.letter)
        let scope = CompetitionScope(
            ageCategory: competition.ageCategory,
            gender: competition.gender,
            modality: competition.modality)

        switch MatchingChain.team(incoming, in: scope, among: try candidates()) {
        case .matched(let id, _):
            guard let existing = teams.first(where: { $0.id == id }) else { return id }

            // Si es rival, su club también recibe la pasada: es por donde una
            // fila que nació sin `federation_club_id` lo recibe (`D-76`).
            if existing.opponentClubID != nil { _ = try await resolveClub(ref) }

            // `opponentClubID: nil` no es "quítaselo": `UpsertPolicy.owned`
            // devuelve lo que hay pase lo que pase, y pasarlo es cómo se lee que
            // **la ingesta no tiene nada que decir** de ese campo (`D-20`).
            let merged = try existing.merging(
                opponentClubID: nil, federationTeamID: ref.federationTeamID)
            if merged != existing {
                try await repositories.teams.save(merged)
                replace(merged)
                report.teamsUpdated += 1
            }
            return id

        case .ambiguous:
            report.skipped.append(IngestionSkip(reason: .ambiguousTeam, detail: ref.name))
            return nil

        case .unmatched:
            guard let clubID = try await resolveClub(ref) else { return nil }
            return try await createTeam(ref, clubID: clubID)
        }
    }

    private func createTeam(
        _ ref: FederationTeamRef, clubID: OpponentClubID
    ) async throws -> TeamID {
        let team = try Team(
            id: TeamID(raw: ids.next()),
            // `D-66`: todo lo que la ingesta crea es **rival**. No hay rama que
            // produzca un equipo propio, y ésa es la mitad de la regla sin la
            // cual la otra —que `Team` tenga `POST`— no se sostiene.
            opponentClubID: clubID,
            // Las tres que la fuente no publica, prestadas por la competición
            // (`D-07`, `D-58`). Las tres entran en la clave única de §3.5.
            category: competition.ageCategory,
            letter: ref.letter,
            gender: competition.gender,
            modality: competition.modality,
            federationTeamID: ref.federationTeamID,
            createdAt: now, updatedAt: now)

        try await repositories.teams.save(team)
        teams.append(team)
        report.teamsCreated += 1
        return team.id
    }

    /// Proyecta los equipos a candidatos, que es donde hace falta el nombre de
    /// su club (Plan §4.6).
    private func candidates() throws -> [TeamCandidate] {
        let names = Dictionary(
            uniqueKeysWithValues: clubs.map { ($0.id, $0.matchingName) })
        return try teams.map { try $0.candidate(opponentClubName: $0.opponentClubID.flatMap { names[$0] }) }
    }

    private func replace(_ team: Team) {
        if let index = teams.firstIndex(where: { $0.id == team.id }) { teams[index] = team }
    }

    // ── Clubes: la cadena de §3.7 en sus tres pasos ─────────────────────────

    /// - Returns: `nil` si la fila **se queda fuera de la pasada** (`D-79`), que
    ///   no es un error: la pasada sigue y el informe lo recoge.
    private func resolveClub(_ ref: FederationTeamRef) async throws -> OpponentClubID? {
        let incoming = IncomingOpponentClub(
            federationClubID: ref.federationClubID, name: NormalizedName(ref.name))

        switch MatchingChain.opponentClub(incoming, among: clubs.map(\.candidate)) {
        case .matched(let id, _):
            guard let existing = clubs.first(where: { $0.id == id }) else { return id }
            let merged = try existing.merging(
                name: ref.name, shortName: ref.name,
                crestKey: nil, federationClubID: ref.federationClubID)
            if merged != existing {
                try await repositories.opponentClubs.save(merged)
                replace(merged)
                report.opponentClubsUpdated += 1
            }
            return id

        case .ambiguous:
            // `D-79`: ni se elige uno ni se da de alta. Se reporta, y es material
            // para la fusión de §9.
            report.skipped.append(
                IngestionSkip(reason: .ambiguousOpponentClub, detail: ref.name))
            return nil

        case .unmatched:
            return try await createClub(ref)
        }
    }

    private func createClub(_ ref: FederationTeamRef) async throws -> OpponentClubID? {
        // §3.5: `UNIQUE(name)`. La cadena llega aquí habiendo **descartado** a
        // un candidato que se llama igual —porque su clave de federación
        // contradice a la entrante (§3.7)—, así que este choque es alcanzable, y
        // sin la guarda reventaría el `UNIQUE` y con él la transacción de la
        // pasada entera: una coincidencia de nombre se llevaría por delante toda
        // la competición. Ni se elige ni se crea, se reporta — el desenlace de
        // `D-79` por otro camino.
        guard !clubs.contains(where: { $0.name == ref.name }) else {
            report.skipped.append(
                IngestionSkip(reason: .duplicateClubName, detail: ref.name))
            return nil
        }

        guard let slug = freeSlug(from: ref.name) else {
            // `D-82`: del nombre no queda nada de lo que derivar un slug, y un
            // relleno inventado acabaría en una clave de Storage (`D-19`).
            report.skipped.append(
                IngestionSkip(reason: .unsluggableClubName, detail: ref.name))
            return nil
        }

        let club = try OpponentClub(
            id: OpponentClubID(raw: ids.next()),
            name: ref.name,
            // El *spec*: si no se aporta, se inicializa desde `name`. La ingesta
            // nunca lo aporta — no tiene forma de saber cómo se abrevia un club.
            shortName: ref.name,
            slug: slug,
            federationClubID: ref.federationClubID,
            createdAt: now, updatedAt: now)

        try await repositories.opponentClubs.save(club)
        clubs.append(club)
        report.opponentClubsCreated += 1
        return club.id
    }

    /// El slug de `D-82`, desempatado contra lo que ya hay.
    ///
    /// # Por qué hace falta desempatar
    ///
    /// Dos clubes con el mismo nombre **son un caso real**, y lo produce la
    /// propia cadena: un candidato cuya `federation_club_id` contradice a la
    /// entrante queda descartado (§3.7) porque la fuente dice que son dos clubes
    /// distintos. El nombre sigue siendo el mismo, así que el slug derivado
    /// también — y `UNIQUE(slug)` (§3.5) rechazaría la fila.
    ///
    /// # Y por qué el desempate está aquí y no en el VO
    ///
    /// Porque exige saber **qué hay guardado**, que es lo que un *Value Object*
    /// no puede saber. `Slug(derivedFrom:)` deriva; elegir uno libre es de quien
    /// tiene la lista delante.
    ///
    /// El sufijo empieza en `-2` y no en `-1`: el primero no lleva ninguno, así
    /// que `-1` daría a entender que hay un cero.
    private func freeSlug(from name: String) -> Slug? {
        guard let base = try? Slug(derivedFrom: name) else { return nil }
        guard clubs.contains(where: { $0.slug == base }) else { return base }

        // El bucle termina: cada vuelta prueba un sufijo distinto y la lista es
        // finita. Y no se recalcula nunca —el slug es inmutable (§3.2)—, así que
        // una corrección posterior del nombre no deja *assets* huérfanos: el
        // fichero conserva su nombre original, algo desfasado pero estable.
        for suffix in 2... {
            guard let candidate = try? Slug("\(base.value)-\(suffix)") else { return nil }
            if !clubs.contains(where: { $0.slug == candidate }) { return candidate }
        }
        return nil
    }

    private func replace(_ club: OpponentClub) {
        if let index = clubs.firstIndex(where: { $0.id == club.id }) { clubs[index] = club }
    }
}

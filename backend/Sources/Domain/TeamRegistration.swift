public import struct Foundation.Date

/// **La inscripción de un equipo propio en una temporada** (`D-68`), y desde la
/// enmienda de esa misma decisión, también en su competición.
///
/// # Por qué es una tabla y no una derivación
///
/// `GET /v1/teams?seasonId=` contestaba derivando de `Match` (`D-27`): equipos
/// con algún partido en alguna competición de esa temporada. **En junio no hay
/// partidos.** El club forma sus equipos antes de que la federación publique
/// calendario, así que entre junio y septiembre el equipo existe y no pertenece
/// a ninguna temporada — invisible justo en la pantalla que se abre para cargar
/// la plantilla del año nuevo.
///
/// Lo que justifica la tabla **no es que tenga atributos: es que no es
/// derivable.** Es información que el club afirma y que no está en ningún otro
/// sitio del esquema. Por eso no es la resurrección del pivote vacío que `D-27`
/// eliminó: aquél era un índice de `Match` mantenido a mano, y éste contiene lo
/// que `Match` todavía no puede implicar.
///
/// # Y por qué la competición es anulable
///
/// Porque la terna se completa en dos momentos distintos:
///
/// | Momento | Fila |
/// |---|---|
/// | Junio, el club inscribe | `(equipo, temporada, nil)` |
/// | El enganche de `D-67` | esa fila **se completa** con la competición |
/// | La copa, enganchada aparte (`D-12`) | **segunda** fila con su competición |
///
/// La invariante *"a lo sumo una fila con competición nula por equipo y
/// temporada, y desaparece en cuanto hay una con competición"* **no vive aquí**:
/// es de la colección, no de la fila, y la sostiene el `UNIQUE` de tres columnas
/// de `C-D.3`. Igual que la coherencia entre competición y temporada, que es una
/// **FK compuesta** y no una guarda que alguien tenga que recordar (`D-61`).
///
/// # `Team` no se toca
///
/// Ni `season_id` ni `competition_id` dentro (`D-28`): `federation_team_id` es
/// estable entre temporadas, así que duplicar la fila del equipo por temporada
/// rompería la clave de emparejamiento de la ingesta. La temporada se afirma
/// **sobre** el equipo, no **dentro** de él.
public struct TeamRegistration: Identifiable, Equatable, Sendable {
    public let id: TeamRegistrationID
    public let teamID: TeamID
    public let seasonID: SeasonID
    public let competitionID: CompetitionID?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: TeamRegistrationID,
        team: Team,
        seasonID: SeasonID,
        competitionID: CompetitionID? = nil,
        createdAt: Date,
        updatedAt: Date
    ) throws {
        // **El alcance de `D-68`, literal**: solo equipos propios. Un rival no se
        // inscribe en tu sistema — aparece porque juega, derivado de `Match`
        // (`D-27`). Los dos conjuntos de `?seasonId=` son disjuntos **por
        // construcción**, y un rival inscrito los solaparía: el mismo equipo dos
        // veces en la portada, que es el duplicado que la enmienda evita.
        //
        // **Por eso el `init` pide el `Team` y no su `TeamID`.** Ser propio se
        // *deriva* de `opponentClubID` (`D-03`: no hay columna `is_own`), así que
        // con solo el id esta regla no se podría comprobar aquí y acabaría en el
        // caso de uso, donde nada obliga a acordarse. Mismo movimiento que
        // `Team.candidate(opponentClubName:)`.
        guard team.isOwn else {
            throw DomainError.invalidValue(
                field: "teamId",
                reason: "un equipo rival no se inscribe: aparece porque juega"
            )
        }

        self.id = id
        self.teamID = team.id
        self.seasonID = seasonID
        self.competitionID = competitionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

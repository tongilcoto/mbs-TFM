public import Domain

/// **Qué jornadas entran en una pasada de clasificación y de dónde sale cada
/// una** (`D-15`, `D-55`).
///
/// # Son dos decisiones y no una, y conviene que se rompan por separado
///
/// `D-15` dice que la fila **existe siempre**: si no se puede ingerir, se
/// calcula desde `Match`. `D-55` dice solo **de dónde viene**, y corrigió el
/// disparador: no es *"la federación no publica clasificación"* —se midió y las
/// dos publican— sino **"esta jornada es anterior a nuestra primera
/// sincronización"**, porque lo que separa a las dos fuentes es si pueden servir
/// una jornada **pasada**.
///
/// Así que aquí hay dos reglas encadenadas: primero **qué jornadas**, y luego,
/// sobre ésas, **de dónde**. La capacidad de la federación no toca la primera.
///
/// # Por qué es una función pura y no está dentro del caso de uso
///
/// Por el mismo motivo que `IngestCommand.stopsTraversal` (F6-ter) y que el
/// `due()` de `IngestClubCalendars`: es **la regla**, y probarla no puede exigir
/// una federación y un Postgres. Equivocarla no da un error, da una pasada que
/// pide treinta veces lo mismo o que no pide nada.
public enum StandingsSyncPlan {

    /// Una jornada, reducida a lo que este plan necesita: **su número para
    /// ordenar y cortar, y su id para escribir**.
    public struct RoundRef: Equatable, Sendable {
        public let id: RoundID
        public let number: Int
        public init(id: RoundID, number: Int) {
            self.id = id
            self.number = number
        }
    }

    /// De dónde sale la tabla de esa jornada.
    public enum Source: Equatable, Sendable {
        /// Se le pide a la federación. Es **mejor dato**: lleva las sanciones
        /// administrativas y el desempate por enfrentamiento directo, que es
        /// justo lo que el cálculo no puede dar (`D-92`).
        case fetch
        /// Se calcula desde `Match` (`D-15`). Peor dato, y el único posible para
        /// el histórico anterior al alta cuando la fuente no lo sirve.
        case compute
    }

    public struct Step: Equatable, Sendable {
        public let round: RoundRef
        public let source: Source
        public init(round: RoundRef, source: Source) {
            self.round = round
            self.source = source
        }
    }

    /// El plan, **en orden ascendente de jornada**.
    ///
    /// # Qué jornadas
    ///
    /// - **Solo las que tienen algún partido jugado.** Una jornada del calendario
    ///   que aún no se ha disputado no tiene clasificación: pedirla sería pedir
    ///   una tabla que no existe, y calcularla daría dieciséis filas a cero con
    ///   cara de dato. `result == nil` es *"no se ha jugado"* (`D-56`).
    /// - De ésas, **las que no tienen ya su *snapshot*** — la foto de una jornada
    ///   pasada no cambia, y volver a pedirla cada semana serían treinta
    ///   peticiones por competición y por pasada para reescribir lo mismo.
    /// - **Más la última jugada, siempre.** Es la excepción que hace que el
    ///   sistema se corrija solo: el resultado de un partido de la jornada en
    ///   curso cambia —un acta que se cierra tarde, una alegación— y con él toda
    ///   la tabla. Sin esto, la clasificación se congelaría en la primera versión
    ///   que llegara a guardarse.
    ///
    /// # Por qué ascendente
    ///
    /// **No es cosmético**: la columna PREV de la jornada N se calcula contra la
    /// tabla de la N−1 (`D-33`), así que una pasada que recompusiera el histórico
    /// al revés tendría que resolver cada PREV contra una tabla que todavía no ha
    /// construido.
    ///
    /// # De dónde
    ///
    /// Con una fuente que **sirve jornadas pasadas** (`providesRoundStandings`,
    /// la RFFM), todas se piden: el histórico entra oficial en vez de calculado.
    /// Con una que **solo sirve la vigente** (la FCF), se pide **una sola vez** y
    /// para la **última** —que es la que esa tabla realmente representa— y lo
    /// anterior se calcula. Pedírsela una vez por jornada serían N peticiones
    /// para escribir N veces lo mismo, y además sería **falso**: la tabla vigente
    /// no es la foto de la jornada 3.
    public static func steps(
        rounds: [RoundRef],
        fixtures: [StandingTable.Fixture],
        alreadyStored: Set<RoundID>,
        providesRoundStandings: Bool
    ) -> [Step] {
        let playedNumbers = Set(
            fixtures.filter { $0.result != nil }.map(\.roundNumber))

        let played = rounds
            .filter { playedNumbers.contains($0.number) }
            .sorted { $0.number < $1.number }

        guard let latest = played.last else { return [] }

        let due = played.filter { !alreadyStored.contains($0.id) || $0.id == latest.id }

        return due.map { round in
            let source: Source =
                providesRoundStandings || round.id == latest.id ? .fetch : .compute
            return Step(round: round, source: source)
        }
    }
}

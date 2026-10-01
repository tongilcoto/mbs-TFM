import Domain

/// **Las competiciones que este proceso tiene sincronizando ahora mismo**, por
/// club (A-11·H-55).
///
/// Existe por el doble clic. `accept` deduplica la **fila** —si ya hay una
/// `accepted`, no escribe otra—, pero el `202` encolaba el **trabajo** igual, así
/// que dos pulsaciones eran dos pasadas sobre la misma competición a la vez. Con
/// esto, la segunda responde su `202` —lo pedido está aceptado— sin lanzar nada.
///
/// # Por qué en memoria y no mirando la fila abierta
///
/// Porque una fila `accepted` **no dice si hay alguien trabajando en ella**:
/// puede ser la de un proceso que murió (H-57). Si el botón se negara a encolar
/// cuando hay fila abierta, una huérfana no se podría reintentar nunca desde la
/// pantalla. Lo que sí sabe el proceso es qué ha lanzado **él**, y tras un
/// reinicio no ha lanzado nada: el botón vuelve a funcionar, y la pasada adopta
/// la huérfana y la cierra.
///
/// # Lo que no cubre, y por qué no importa
///
/// Otro proceso —el `ingest` del cron, una segunda instancia— no está aquí
/// dentro. No hace falta: que dos pasadas coincidan es **inofensivo** desde que la
/// escritura se hace con la competición bloqueada y el registro no pisa lo que
/// otra cerró. Esto no es lo que hace correcto el sistema; es lo que evita hacer
/// el trabajo dos veces en el caso de todos los días.
actor IngestionsInFlight {
    private var running: Set<Key> = []

    private struct Key: Hashable {
        let club: String
        let competition: CompetitionID
    }

    /// Marca como en curso las que no lo estaban, y **devuelve solo ésas**: son
    /// las que le toca lanzar a quien llama.
    func reserve(_ competitions: [CompetitionID], club: Slug) -> [CompetitionID] {
        competitions.filter { running.insert(Key(club: club.value, competition: $0)).inserted }
    }

    /// El trabajo terminó —bien o mal—: la siguiente pulsación vuelve a lanzar.
    func release(_ competitions: [CompetitionID], club: Slug) {
        for competition in competitions {
            running.remove(Key(club: club.value, competition: competition))
        }
    }
}

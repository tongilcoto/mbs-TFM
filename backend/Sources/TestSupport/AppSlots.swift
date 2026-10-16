/// **Cuántas `Application` de prueba pueden estar abiertas a la vez.**
///
/// Cada una abre su propio *pool* contra `tfm_test`, y las suites corren en
/// paralelo. Sin límite, la batería llegaba a ~90 conexiones; con las que el
/// desarrollador tiene abiertas (su servidor, TablePlus) pasaba de las 100 que
/// admite Postgres y algunas suites fallaban al arrancar con *"too many clients
/// already"* — unas veces sí y otras no (medido el 2026-10-16, en `R0.10`).
///
/// Se limita aquí y no subiendo `max_connections` porque así la batería no
/// depende de cuántas conexiones tenga abiertas cada uno, ni obliga a reiniciar
/// su Postgres. Quien llega con las plazas ocupadas espera su turno.
actor AppSlots {
    static let shared = AppSlots(limit: 4)

    private let limit: Int
    private var inUse = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        if inUse < limit {
            inUse += 1
            return
        }
        // La plaza la pasa directamente quien la suelta (abajo), así que al
        // despertar ya es nuestra.
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty {
            inUse -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}

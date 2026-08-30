public import struct Foundation.Date
public import struct Foundation.UUID

/// El reloj, como **puerto** (§4.3).
///
/// Existe por lo que Plan §5 pide del nivel 2: *"orquestación con los puertos
/// falseados: `FederationClient` en memoria, `Clock` y `UUIDProvider` **fijos**"*.
/// Un `Date()` dentro del caso de uso convierte `last_synced_at` en un valor que
/// ningún test puede afirmar, y entonces la única aserción posible es *"no es
/// nulo"* — que pasaría igual si se escribiera la fecha equivocada.
public protocol Clock: Sendable {
    func now() -> Date
}

/// El reloj de verdad. Es la única implementación que va en producción.
public struct SystemClock: Clock {
    public init() {}
    public func now() -> Date { Date() }
}

/// La fábrica de identificadores, como **puerto** (§4.3).
///
/// Mismo argumento que `Clock`, y con una consecuencia más fuerte: las entidades
/// que la ingesta crea nacen con un UUID nuevo, así que sin este puerto un test
/// no puede afirmar **qué** fila se creó, solo cuántas.
///
/// Y no es solo comodidad de test: es lo que permite que el caso de uso construya
/// la entidad **antes** de guardarla, en vez de dejar que la base de datos ponga
/// el id y tener que releerla. Con id propio, la fila recién creada se puede
/// añadir a la lista de candidatos de la misma pasada — que es justo lo que hace
/// falta cuando dos partidos de la misma jornada mencionan al mismo club nuevo.
public protocol UUIDProvider: Sendable {
    func next() -> UUID
}

/// La de verdad.
public struct SystemUUIDProvider: UUIDProvider {
    public init() {}
    public func next() -> UUID { UUID() }
}

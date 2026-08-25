public import Domain

/// Puerto de salida (§4.3): lo declara la Aplicación y lo implementa el
/// adaptador Fluent, así que la dependencia queda **invertida** (DIP).
///
/// Un repositorio **por raíz de agregado** (§4.2). `Club` es *singleton* del
/// tenant, así que no lleva `find(_ id:)`: dentro de un *schema* hay exactamente
/// una fila y el `search_path` ya eligió cuál (§6.2).
public protocol ClubRepository: Sendable {
    /// El club del tenant activo. `nil` solo si el *schema* está sin aprovisionar
    /// —que es un fallo de provisión (§6.3), no un caso de negocio—.
    func current() async throws -> Club?

    /// Persiste el club. *Upsert* del agregado (§4.3): `Club` es *singleton* del
    /// tenant, así que en la práctica es siempre una actualización — el alta es
    /// provisión (§6.3), no una operación de esta API.
    func save(_ club: Club) async throws
}

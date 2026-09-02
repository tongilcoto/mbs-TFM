import Application
import Domain
import Federation

/// El catálogo de adaptadores de `D-17`, resuelto en la **raíz de composición**.
///
/// Implementa `FederationClientProvider` (§4.3) y es el único sitio del backend
/// donde una `FederationCode` se convierte en un adaptador concreto — que es lo
/// que permite que el caso de uso hable de *"la federación del club"* sin
/// conocer a ninguna.
///
/// # El `switch` es exhaustivo, y ése es el mecanismo
///
/// `FederationCode` documenta que *"un caso nuevo no compila hasta declarar sus
/// capacidades"*. Aquí pasa lo mismo con el adaptador: añadir una federación al
/// enumerado del Dominio **rompe este fichero** hasta que alguien diga con qué
/// se sincroniza — o diga explícitamente que todavía con nada, que es lo que hoy
/// dice la FCF.
public struct CatalogFederationClientProvider: FederationClientProvider {
    private let rffm: any FederationClient

    /// - Parameter rffm: se inyecta para que los tests puedan poner un doble en
    ///   su sitio **sin red**. En producción es el adaptador de verdad sobre el
    ///   transporte HTTP con su *timeout* corto (§2.3-c).
    public init(rffm: any FederationClient = RFFMFederationClient(transport: HTTPFederationTransport())) {
        self.rffm = rffm
    }

    public func client(for code: FederationCode) -> (any FederationClient)? {
        switch code {
        case .rffm:
            rffm
        case .fcf:
            // **F9.** El `nil` no es un olvido: la FCF está en el catálogo del
            // Dominio desde F0 —`Club.federation` la acepta y sus capacidades
            // están declaradas contra el anexo— y su adaptador todavía no se ha
            // escrito. Quien decide qué hacer con este hueco es el recorrido:
            // salta el club y **no le deja pasadas fallidas** (`D-85`).
            nil
        }
    }
}

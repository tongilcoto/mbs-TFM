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
            // **Fuera del alcance, y decidido: `D-95`.** El `nil` no es un
            // olvido ni un "todavía no me ha dado tiempo": F9 abrió, revalidó la
            // fuente como manda `D-74` y **se paró con lo medido delante** — su
            // clasificación publica cuatro contadores concatenados que su propia
            // web pinta en crudo, dice que no con un contenedor vacío
            // indistinguible de "no hay datos", y cambió de forma en 23 días
            // ([Anexo FCF §C.12]).
            //
            // La FCF sigue en el catálogo del Dominio —`Club.federation` la
            // acepta y sus capacidades están declaradas contra el anexo—, y esa
            // asimetría es justo lo que este `switch` exhaustivo existe para
            // hacer visible: **el Dominio sabe qué sabe hacer esa federación; la
            // raíz de composición sabe que nadie se lo pregunta.**
            //
            // Quien decide qué hacer con el hueco es el recorrido: salta el club
            // y **no le deja pasadas fallidas** (`D-85`) — no hay fallo que
            // registrar, hay federación sin adaptador. Por HTTP sale como **501**
            // por las dos puertas de `POST /v1/ingestion-runs` (`H-28`).
            nil
        }
    }
}

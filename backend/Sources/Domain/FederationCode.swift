/// Federación del club. **Catálogo en código, no tabla** (§3.6, D-17): soportar
/// una nueva exige escribir un adaptador, así que darla de alta como dato no la
/// haría funcionar.
///
/// Es propiedad **del tenant**: hay una por *schema* (`Club.federation`).
public enum FederationCode: String, CaseIterable, Sendable {
    /// Real Federación de Fútbol de Madrid.
    case rffm
    /// Federació Catalana de Futbol.
    case fcf
}

/// Lo que cada proveedor **sabe hacer**, no solo dónde está (D-17, D-55).
///
/// Vive en el Dominio y no en el adaptador porque de ella salen dos campos
/// derivados del contrato (`ClubResponse`), y porque decidir si una clasificación
/// se ingiere o se calcula (D-15) es una regla de negocio, no un detalle HTTP.
public struct FederationCapabilities: Equatable, Sendable {
    /// `true` si se puede pedir la clasificación de una **jornada pasada**.
    ///
    /// **No condiciona que haya clasificación** —la hay siempre—: es un dato de
    /// *procedencia*. Con `false`, las jornadas anteriores al alta se calculan
    /// desde `Match` (D-15, D-29).
    public let providesRoundStandings: Bool

    /// `true` si la federación publica ranking de goleadores.
    ///
    /// Al contrario que su hermano, **este sí condiciona que haya dato** (D-48):
    /// no hay *fallback* posible, porque calcularlo exigiría la plantilla de los
    /// rivales, que no se modela (D-09).
    public let providesScorers: Bool
}

extension FederationCode {
    /// El catálogo. Cada entrada se justifica en el anexo de su federación; no
    /// se deduce de memoria (AGENTS.md).
    public var capabilities: FederationCapabilities {
        switch self {
        case .rffm:
            // Clasificación por cualquier jornada (Anexo RFFM §F.8) y goleadores
            // con endpoint JSON propio (Anexo RFFM §F.13).
            FederationCapabilities(providesRoundStandings: true, providesScorers: true)
        case .fcf:
            // Solo la clasificación vigente (D-55). Goleadores **no observados**
            // (Anexo FCF §C.9): se declara `false` hasta tener evidencia, porque
            // prometer una pantalla vacía es peor que ocultarla (D-48).
            FederationCapabilities(providesRoundStandings: false, providesScorers: false)
        }
    }
}

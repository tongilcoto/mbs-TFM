/// Federación del club. **Catálogo en código, no tabla** (§3.6, D-17): soportar
/// una nueva exige escribir un adaptador, así que darla de alta como dato no la
/// haría funcionar.
///
/// Es propiedad **del tenant**: hay una por *schema* (`Club.federation`).
///
/// # Éste es el sitio donde se añade una federación
///
/// **Ningún literal `"rffm"` / `"fcf"` debe existir en el proyecto fuera de este
/// fichero.** Todo lo demás se deriva:
///
/// | Qué | Cómo se mantiene al día |
/// |---|---|
/// | `capabilities` | `switch` **exhaustivo** → un caso nuevo no compila hasta declararlas |
/// | `CHECK` de la tabla `clubs` (§4.6) | se genera de `sqlValueList`, no se teclea |
/// | Enum del contrato (`Components.Schemas.FederationCode`) | `toContract()` es un `switch` **exhaustivo** |
/// | *Fixtures* de test | tipadas con este `enum`, nunca con `String` |
///
/// ## Los dos pasos que sí hay que dar a mano
///
/// 1. **Añadir el caso aquí**, con sus `capabilities` — y **citando la evidencia
///    de su anexo**, nunca de memoria (AGENTS.md).
/// 2. **Añadir el valor al `enum` de `FederationCode` en el *spec* OpenAPI.**
///    Esto **no puede** derivarse de Swift: el *spec* es la fuente de verdad del
///    contrato ([D-25], [D-65]) y la generación va en esa dirección, no al revés.
///
/// El paso 2 **no depende de que nadie se acuerde**: `toContract()` no compila
/// hasta que el caso exista también en el contrato. Es el criterio de [D-61] —
/// la integridad en el sistema de tipos, no en la disciplina.
///
/// Y después, el trabajo de verdad: **el adaptador** de su API (D-17), sin el
/// cual el caso nuevo es un rótulo sin ingesta detrás.
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
            // Clasificación **solo vigente** (D-55), reverificado el 2026-08-28
            // contra la web nueva: `classificacio?grupId=…` devuelve el mismo
            // cuerpo con `jornada`, `round` o `jornadaId`, así que sigue sin
            // haber histórico y las jornadas anteriores al alta se calculan (D-15).
            //
            // Goleadores **sí**, desde el 2026-08-28. El `false` anterior citaba
            // el §C.9 del anexo —"ni endpoint, ni parser"—, que describía el sitio
            // *antiguo*; el nuevo publica `/api/competition/goleadores`. Corregido
            // con el volcado, no de memoria (AGENTS.md).
            FederationCapabilities(providesRoundStandings: false, providesScorers: true)
        }
    }
}

// El `sqlValueList` que este enumerado usaba en su `CHECK` (§4.6) ya no vive
// aquí: se generalizó a `CaseIterable where RawValue == String`
// (`Enumerations.swift`), para que los enumerados de §3.3 lo hereden sin copiarlo.

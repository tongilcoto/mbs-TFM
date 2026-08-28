/// Enumerados de dominio (§3.3).
///
/// **Son de dominio, no de integración**: significan lo mismo en cualquier
/// federación. Su codificación externa —el `tipojuego` de la RFFM, por ejemplo—
/// **no se almacena**: vive en el catálogo de federaciones, en código (§3.6).
///
/// Se guardan como `text` + `CHECK`, **no como `ENUM` nativo de Postgres**
/// (`D-02`): un tipo `ENUM` vive dentro de un *schema*, así que añadir un valor
/// obligaría a alterarlo en **cada** *schema* de tenant. El `CHECK` se deriva de
/// `sqlValueList`, nunca se teclea.

/// Género de la competición y, por herencia, del equipo (`D-58`).
///
/// **Compartido entre `Competition` y `Team`**, igual que `Modality`, y parte de
/// la **clave única de `Team`** (§3.5): el "Infantil A" masculino y el femenino
/// del mismo club son equipos **distintos**.
///
/// La federación **no lo publica como campo**: lo embebe en el nombre de la
/// competición ([Anexo RFFM §F.14]), así que el `/preview` lo infiere y lo
/// **propone**, y el administrador lo **confirma**. `mixto` no es expresable en
/// la fuente — solo lo puede poner un humano.
public enum Gender: String, CaseIterable, Sendable {
    case masculino
    case femenino
    case mixto
}

/// Modalidad de juego (§3.3, `D-07`).
///
/// Parte de la **identidad** del equipo y de su clave única (§3.5): el "Infantil
/// A masculino" de fútbol-11 y el de fútbol-sala son equipos **distintos**. Sin
/// este campo, un club con equipos en dos modalidades no se podría representar.
public enum Modality: String, CaseIterable, Sendable {
    case futbol11 = "futbol_11"
    case futbol7 = "futbol_7"
    case futbol5 = "futbol_5"
    case futbolSala = "futbol_sala"
    case futbolPlaya = "futbol_playa"
}

/// Categoría de edad (§3.3).
///
/// La usan `Team.category` y `Competition.ageCategory` —el mismo enumerado—, que
/// es lo que permite **validar** que un equipo solo participe en una competición
/// de su edad. `senior` cubre tanto el "Primer Equipo" como los filiales; se
/// distinguen por `letter` (`D-13`).
public enum TeamCategory: String, CaseIterable, Sendable {
    case prebenjamin
    case benjamin
    case alevin
    case infantil
    case cadete
    case juvenil
    case senior
}

extension TeamCategory {
    /// Rótulo legible, con los acentos que el *raw value* no lleva.
    ///
    /// Vive en el Dominio porque de él se compone `Competition.displayName`
    /// (§5.2), que es un campo derivado del contrato. El *raw value* se queda sin
    /// acentos: es lo que viaja al `enum` del *spec* y a la columna.
    public var displayLabel: String {
        switch self {
        case .prebenjamin: "Prebenjamín"
        case .benjamin: "Benjamín"
        case .alevin: "Alevín"
        case .infantil: "Infantil"
        case .cadete: "Cadete"
        case .juvenil: "Juvenil"
        case .senior: "Senior"
        }
    }
}

extension CaseIterable where Self: RawRepresentable, Self.RawValue == String {
    /// Los valores del enumerado listados para un `IN (…)` de SQL.
    ///
    /// **El `CHECK` de la migración se deriva de aquí, no se teclea** (§4.6). Una
    /// lista escrita a mano en la migración es una segunda fuente de verdad que
    /// nadie recuerda actualizar, y su forma de fallar es fea: añadir un valor al
    /// `enum` compilaría, y el `INSERT` reventaría en producción contra un
    /// `CHECK` que se quedó atrás.
    ///
    /// Interpolar es seguro por construcción: los valores salen de un `enum` de
    /// Swift, no de entrada de usuario.
    ///
    /// Está en el Dominio, y genérica sobre `CaseIterable`, porque la lista de
    /// valores **es** el `enum`: cada enumerado nuevo la hereda sin escribir nada.
    public static var sqlValueList: String {
        allCases.map { "'\($0.rawValue)'" }.joined(separator: ", ")
    }
}

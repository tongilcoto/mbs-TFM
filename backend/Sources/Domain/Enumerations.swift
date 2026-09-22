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

extension Gender {
    /// **El género que el nombre de la competición propone** (`D-58`,
    /// [Anexo RFFM §F.14]).
    ///
    /// # Por qué hace falta inferir, y por qué solo se propone
    ///
    /// La RFFM **no publica el género en ninguna entidad**: ni en el partido, ni
    /// en el equipo, ni en la clasificación. Lo lleva embebido en el **nombre de
    /// la competición** —`"TERCERA FEDERACION DE FÚTBOL FEMENINO"`—, como rótulo
    /// y no como campo. Era una columna sin origen, y esto es lo que la alimenta.
    ///
    /// Lo que devuelve es una **propuesta que el administrador confirma** en el
    /// `/preview`, nunca un hecho, y las tres razones son del anexo:
    ///
    /// 1. **`mixto` es inalcanzable desde la fuente.** El enumerado tiene tres
    ///    valores y la RFFM sabe expresar dos. En fútbol base los equipos mixtos
    ///    existen aunque la federación los inscriba como masculinos: el único que
    ///    puede poner ese valor es el club.
    /// 2. **El truncado puede comerse el marcador.** §F.11 observó
    ///    `"PRIMERA DIVISION AUTONOMICA FEMENINO CAD"` —40 caracteres exactos, con
    ///    `FEMENINO` salvado por los pelos—. En `/api/competitions` no se ha
    ///    observado truncado (el rótulo más largo, 44 caracteres, llega entero),
    ///    pero basta la posibilidad para no confiar el valor a un `contains`.
    /// 3. **Un error aquí no da un dato feo, da un 409.** `gender` entra en la
    ///    clave única de `Team` (§3.5), así que una inferencia equivocada
    ///    **colisiona** con el equipo que ya existe en vez de degradarse.
    ///
    /// # `contains`, nunca sufijo — y está medido
    ///
    /// Del volcado de las **30 competiciones** (2026-08-28), **2 de las 6
    /// femeninas** llevan el marcador **en medio**: `PRIMERA DIVISIÓN AUTONÓMICA
    /// FEMENINO JUVENIL` y `PREFERENTE FEMENINO JUVENIL`. La regla de sufijo que
    /// el diseño suponía habría dado masculinas a las dos.
    ///
    /// Y la ausencia de marcador **es** el masculino, también medido: en las 30
    /// no aparece `MASCULINO` explícito ni una vez.
    ///
    /// # El plegado se reutiliza, no se reescribe
    ///
    /// `NormalizedName` ya pliega diacríticos y caja con *locale* fijo, que es
    /// exactamente lo que aquí hace falta. Escribir un segundo plegado sería la
    /// tercera implementación divergente de la misma regla — lo que `UpsertPolicy`
    /// documenta como forma de acabar mal, y lo que `A-7`·H-48 manda buscar antes
    /// de aceptar que algo falta.
    ///
    /// Ese plegado **también quita los espacios**, así que en teoría dos palabras
    /// contiguas podrían componer el marcador sin que esté. No se corrige: el
    /// único desenlace es proponer `femenino` en una pantalla donde un humano
    /// confirma, y el error contrario —no ver el marcador que sí está— es el que
    /// cuesta un 409.
    public static func proposed(fromFederationName name: String) -> Gender {
        let folded = NormalizedName(name).value
        // Las dos formas que la tabla de §F.14 declara. `FEMENINA` no apareció ni
        // una vez en las 30 medidas —las seis dicen `FEMENINO`—, y se comprueba
        // igual: que la fuente la estrene mañana no puede costar un 409.
        if folded.contains("femenino") || folded.contains("femenina") {
            return .femenino
        }
        return .masculino
    }
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

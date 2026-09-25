import APIContract
import Domain
import Foundation
import Testing

@testable import HTTPAdapter

/// **Las traducciones de enumerado espejo, bajo arnés** (`C-E.9`, hallazgo de
/// F9-bis · `A-7`·H-46).
///
/// # El defecto que este fichero existe para cazar
///
/// El Dominio y el contrato son **dos enumerados distintos que pueden divergir**
/// ([D-61]), y por eso la traducción es un `switch` exhaustivo a mano: añadir un
/// caso al Dominio **no compila** hasta que alguien escriba su línea. Eso es lo
/// que el compilador compra, y es la mitad del problema.
///
/// La otra mitad no la compra nadie: **obliga a escribir la línea, no a
/// escribirla bien**. Mapear un motivo al valor del vecino compila igual y llega
/// al backoffice como otra cosa — un `unresolved_team` que dice
/// `missing_match_date`, o una pasada `accepted` que se anuncia `succeeded`. El
/// reparto de arnés medido el 2026-09-21 era: `FederationCode` 2/2,
/// `IngestionOutcome` 2/2, `IngestionKind` **0/3**, `IngestionSkipReason`
/// **1/10**.
///
/// # Y son SIETE traducciones, no cuatro
///
/// El plan contaba las cuatro que existían al abrir la fase. `C-E.3` añadió tres
/// al escribir el `/preview` —`Modality`, `Gender` y `TeamCategory`, que hasta
/// F10 no cruzaban la frontera porque ningún endpoint servía una competición— y
/// `C-E.4` añadió la primera **de vuelta**, del contrato al Dominio. Esa última
/// es la que más muerde: `gender` entra en la clave única de `Team` (§3.5), así
/// que traducirla mal no da un rótulo feo — **engancha el equipo a la
/// competición equivocada** ([D-58]).
///
/// # Por qué la aserción es ésta y no una tabla
///
/// Escribir el mapeo esperado caso a caso sería **repetir el `switch` en el
/// test**: dos copias de lo mismo que se equivocan juntas el día que alguien
/// copie y pegue. Lo que se afirma en su lugar es la **invariante de forma** que
/// las siete cumplen: el valor del contrato es el del Dominio en `snake_case`.
/// Quitar los `_` y bajar la caja deja los dos lados comparables sin
/// reimplementar ninguna conversión, y **eso caza la permutación** —que es el
/// fallo de verdad—, no solo el duplicado.
///
/// `IngestionSkipReason` es la que obliga a plegar: sus valores de Dominio se
/// serializan **tal cual** dentro del `jsonb` de `skipped` desde F5 —hay datos
/// escritos con ellos— y el contrato usa `snake_case`. Las otras seis coinciden
/// literalmente.
@Suite("Frontera · D-61 · las traducciones de enumerado espejo")
struct ContractEnumTests {

    /// Plegado que hace comparables los dos lados sin reimplementar la
    /// conversión: `ambiguousTeam` y `ambiguous_team` colapsan al mismo texto.
    static func folded(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: "").lowercased()
    }

    /// El cuerpo de las siete comprobaciones: **cada caso va a su gemelo, y dos
    /// casos no van al mismo sitio**.
    ///
    /// La segunda mitad no es redundante con la primera: un mapeo que colapsara
    /// dos casos en uno perdería información sin que ningún nombre lo delatara.
    static func check<Source, Target>(
        _ cases: [Source], _ translate: (Source) -> Target, _ label: String
    ) where Source: RawRepresentable, Source.RawValue == String,
            Target: RawRepresentable & Hashable, Target.RawValue == String
    {
        var seen: Set<Target> = []
        for value in cases {
            let translated = translate(value)
            #expect(
                folded(value.rawValue) == folded(translated.rawValue),
                "\(label): `\(value.rawValue)` se traduce a `\(translated.rawValue)`")
            #expect(seen.insert(translated).inserted,
                    "\(label): `\(translated.rawValue)` ya lo usaba otro caso")
        }
        #expect(seen.count == cases.count, "\(label)")
    }

    @Test("FederationCode → contrato (D-61)")
    func federationCode() {
        Self.check(FederationCode.allCases, { $0.toContract() }, "FederationCode")
    }

    /// **Los tres, y el tercero lo estrena F10.** `accepted` era el caso que
    /// [D-96] añadió: el compilador paró en `toContract()` hasta escribir su
    /// línea, y mapearlo a `.succeeded` habría compilado igual — dando por
    /// terminada una pasada que no ha empezado.
    @Test("IngestionOutcome → contrato, con el `accepted` de D-96 (C-E.9)")
    func ingestionOutcome() {
        #expect(IngestionOutcome.allCases.count == 3)
        Self.check(IngestionOutcome.allCases, { $0.toContract() }, "IngestionOutcome")
    }

    /// Estaba **0/3** hasta este ciclo, y es la de mapeo más fácil de
    /// intercambiar: tres palabras sueltas sin nada que las distinga en la línea
    /// de al lado.
    @Test("IngestionKind → contrato (C-E.9)")
    func ingestionKind() {
        Self.check(IngestionKind.allCases, { $0.toContract() }, "IngestionKind")
    }

    /// La más larga y la que estaba **1/10** — el único afirmado lo escribió
    /// F9-bis con el motivo que ella misma añadió.
    ///
    /// **Son diez, no once.** El plan y la descripción del *spec* dicen *"los
    /// once"*; contados el 2026-09-24 sobre `IngestionRun.swift` y sobre el
    /// `enum` del contrato, son **diez** en los dos lados. El recuento estaba mal
    /// escrito, no el código.
    @Test("IngestionSkipReason → contrato, los diez (C-E.9)")
    func ingestionSkipReason() {
        #expect(IngestionSkip.Reason.allCases.count == 10)
        Self.check(
            IngestionSkip.Reason.allCases, { $0.toContract() }, "IngestionSkipReason")
    }

    // ── Las tres que F10 estrena con el `/preview` (`C-E.3`) ─────────────────

    @Test("Modality → contrato (C-E.3 · C-E.9)")
    func modality() {
        Self.check(Modality.allCases, { $0.toContract() }, "Modality")
    }

    @Test("Gender → contrato (C-E.3 · C-E.9)")
    func gender() {
        Self.check(Gender.allCases, { $0.toContract() }, "Gender")
    }

    @Test("TeamCategory → contrato (C-E.3 · C-E.9)")
    func teamCategory() {
        Self.check(TeamCategory.allCases, { $0.toContract() }, "TeamCategory")
    }

    /// **Y la de vuelta**, que es la única que escribe en la base lo que el
    /// cliente eligió: el `gender` del enganche acaba en `Competition` y decide
    /// si el equipo cuadra con ella ([D-58], `C-C.15`).
    ///
    /// Se afirma además el **viaje redondo**, que es lo que de verdad importa de
    /// un par de traducciones opuestas: lo que sale por una puerta y entra por la
    /// otra tiene que ser lo mismo.
    @Test("Gender ← contrato, y el viaje redondo (C-E.4 · C-E.9)")
    func genderBack() {
        Self.check(
            Components.Schemas.Gender.allCases, { $0.toDomain() }, "Gender (de vuelta)")

        for value in Gender.allCases {
            #expect(value.toContract().toDomain() == value)
        }
    }
}

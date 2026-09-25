import Foundation
import Testing

@testable import Domain

/// Nivel 1 (§8.1): **cómo se escribe un identificador**, que hasta `F10-ter` no
/// lo decidía nadie (§4.1).
///
/// # Qué defecto fija esto
///
/// Un `UUID` admite mayúsculas y minúsculas sin cambiar de valor, así que la
/// forma **hay que elegirla**; RFC 4122 §3 elige **minúscula** y es la que viaja
/// en todo cuerpo del contrato. Foundation entrega mayúsculas, de modo que la
/// conversión hacía falta en cada punto de salida y **se repetía a mano**:
/// medido el 2026-09-25, **14 sitios se acordaban y 14 no**.
///
/// Los que no se acordaban eran los que meten el id en el texto de un error, con
/// la consecuencia de que un cliente que comparase el `detail` de un problema
/// contra el id que había enviado **no casaba**. Ahora la forma la decide el
/// tipo, y esto es lo que lo sujeta.
@Suite("Identificadores · §4.1 · cómo se escriben")
struct IdentifierTextTests {

    /// **Un UUID con letras a propósito, y es la mitad que hace falta leer.**
    ///
    /// Con uno de solo dígitos —`00000000-0000-…`— mayúsculas y minúsculas son
    /// el **mismo texto**, así que el test pasaría igual sin el arreglo y no
    /// estaría comprobando nada. Es la misma familia que el test vacío que la
    /// mutación `M14` del Bloque D destapó: un verde que no distingue.
    static let raw = UUID(uuidString: "1E136180-7ACC-41CC-BD00-FDEEFCA03A08")!

    /// El cuerpo de las once comprobaciones. Genérico sobre el protocolo, que es
    /// lo que permite escribir la regla **una vez** en lugar de diez.
    static func check<ID: TypedIdentifier>(_ type: ID.Type, _ label: String) {
        let id = ID(raw: raw)

        // La forma canónica: minúscula.
        #expect("\(id)" == raw.uuidString.lowercased(), "\(label)")

        // Y que **no** sea la que Foundation da por defecto, que es de donde
        // venía el defecto. Sin esta mitad, `description` podría devolver la
        // cadena en mayúsculas y la aserción de arriba seguiría siendo la única
        // que habla — y compara contra sí misma en cuanto el UUID no lleve
        // letras.
        #expect("\(id)" != raw.uuidString, "\(label)")

        // Y `raw` sigue estando, intacto: quien necesite el `UUID` de verdad
        // —un repositorio, una columna— no pasa por el texto.
        #expect(id.raw == raw, "\(label)")
    }

    /// **Los once se enumeran a mano, y hay que saber por qué.**
    ///
    /// Swift no permite recorrer los tipos que cumplen un protocolo, así que
    /// esta lista no se deriva: **un identificador nuevo no entra solo**. Lo que
    /// sí le pasa al que venga es que el compilador le exija conformar
    /// `TypedIdentifier` en cuanto alguien lo interpole, porque lo demás no
    /// compila — y entonces hereda la regla aunque su renglón falte aquí.
    @Test("los once identificadores se escriben en minúscula (RFC 4122 §3, F10-ter)")
    func everyIdentifierWritesItselfInLowercase() {
        Self.check(ClubID.self, "ClubID")
        Self.check(SeasonID.self, "SeasonID")
        Self.check(CompetitionID.self, "CompetitionID")
        Self.check(OpponentClubID.self, "OpponentClubID")
        Self.check(TeamID.self, "TeamID")
        Self.check(TeamRegistrationID.self, "TeamRegistrationID")
        Self.check(RoundID.self, "RoundID")
        Self.check(MatchID.self, "MatchID")
        Self.check(StandingRowID.self, "StandingRowID")
        Self.check(LeagueScorerID.self, "LeagueScorerID")

        // **El once, y el que enseña por qué esta lista se escribe a mano.**
        // `IngestionRunID` vive en `IngestionRun.swift`, no en
        // `Identifiers.swift`, así que al conformar «los diez» se quedó fuera y
        // el `jobId` del `202` salió como `IngestionRunID(raw: …)`. Lo cazó un
        // test de nivel 4 en el acto — pero a un identificador que nadie
        // interpole no lo caza nadie, y por eso su renglón va aquí.
        Self.check(IngestionRunID.self, "IngestionRunID")
    }
}

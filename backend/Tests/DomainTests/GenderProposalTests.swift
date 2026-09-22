import Foundation
import Testing

@testable import Domain

/// Nivel 1 (§8.1): la inferencia de género desde el nombre de la competición
/// (`D-58`, [Anexo RFFM §F.14]).
@Suite("Gender · D-58 · lo que propone la máquina y confirma el humano")
struct GenderProposalTests {

    /// El caso del anexo, literal: la RFFM **no tiene campo de género** en
    /// ninguna entidad y lo publica solo como texto dentro del rótulo.
    @Test("el marcador en el nombre propone femenino (D-58, §F.14)")
    func theMarkerProposesFemenino() {
        #expect(Gender.proposed(fromFederationName: "TERCERA FEDERACION DE FÚTBOL FEMENINO")
                == .femenino)
    }

    /// **El `contains` no es un sufijo, y está medido**: del volcado de las 30
    /// competiciones (2026-08-28), **2 de las 6 femeninas** llevan el marcador
    /// **en medio** del rótulo. Una regla de sufijo las habría dado por
    /// masculinas — y como `gender` entra en la clave única de `Team` (§3.5),
    /// eso no es un rótulo feo: es un 409 el día del alta.
    @Test("el marcador en medio del rótulo también cuenta (§F.14, medido)")
    func theMarkerIsNotASuffix() {
        #expect(Gender.proposed(
            fromFederationName: "PRIMERA DIVISIÓN AUTONÓMICA FEMENINO JUVENIL") == .femenino)
        #expect(Gender.proposed(fromFederationName: "PREFERENTE FEMENINO JUVENIL") == .femenino)
    }

    /// La tabla del anexo lista las dos formas. **`FEMENINA` no apareció ni una
    /// vez en las 30 medidas** —las seis dicen `FEMENINO`—, así que esto cubre lo
    /// que la regla declara y la muestra no vio: que aparezca mañana no puede
    /// costar un 409.
    @Test("«femenina» también es marcador, aunque la muestra no lo trajera (§F.14)")
    func theFeminineFormCountsToo() {
        #expect(Gender.proposed(fromFederationName: "LIGA FEMENINA CADETE") == .femenino)
    }

    /// **Sin marcador es masculino, y es el valor por defecto de la fuente, no
    /// nuestro**: las 30 medidas confirman que `MASCULINO` no aparece nunca
    /// explícito, así que la ausencia **es** el masculino.
    @Test("sin marcador se propone masculino (D-58, §F.14)")
    func noMarkerProposesMasculino() {
        #expect(Gender.proposed(fromFederationName: "PRIMERA CADETE") == .masculino)
    }

    /// El plegado, que es lo que evita una segunda regla de acentos: el rótulo
    /// llega en mayúsculas y sin acentos desde la fuente ([Anexo RFFM §F.5]),
    /// pero nadie garantiza que siga así.
    @Test("acentos y caja no cambian la propuesta (§F.11, §F.14)")
    func foldingIsApplied() {
        #expect(Gender.proposed(fromFederationName: "liga femeníno infantil") == .femenino)
    }

    /// **`mixto` es inalcanzable desde la fuente, y por eso esto solo propone.**
    /// El enumerado tiene tres valores y la RFFM sabe expresar dos. En fútbol
    /// base los equipos mixtos existen aunque la federación los inscriba como
    /// masculinos: el único que puede poner ese valor es el club, confirmando.
    @Test("la propuesta nunca puede ser mixto: no es expresable en la fuente (§F.14)")
    func mixtoIsUnreachable() {
        let proposals = [
            "PRIMERA CADETE", "TERCERA FEDERACION DE FÚTBOL FEMENINO",
            "COPA MIXTA ALEVIN", "",
        ].map { Gender.proposed(fromFederationName: $0) }

        #expect(!proposals.contains(.mixto))
    }
}

import Testing

@testable import Domain

/// Nivel 1 (§8.1): la edad que propone el nombre de la competición
/// (A-12·H-75, `D-58`, [Anexo RFFM §F.14]).
///
/// Es el hermano de `GenderProposalTests`, con una diferencia que es el diseño:
/// el género **siempre** tiene propuesta —sin marcador es masculino, que es el
/// valor por defecto de la fuente—, y la edad **no**. Un nombre que no la dice
/// devuelve `nil`, y entonces el enganche la toma del equipo y el `/preview`
/// avisa de que no se ha podido comprobar.
@Suite("TeamCategory · H-75 · la edad que dice el nombre, o nada")
struct AgeCategoryProposalTests {

    /// **Las 30 competiciones del volcado de `/api/competitions`**
    /// (`docs/Federation APIs examples/RFFM-competition.txt`, §F.14), cada una con
    /// lo que su nombre dice. 24 dicen la edad; las 6 que no, se quedan sin
    /// propuesta. No es una muestra elegida: es el array entero.
    static let measured: [(name: String, age: TeamCategory?)] = [
        ("COPA RFEF FASE AUTONÓMICA", nil),
        ("DIVISIÓN DE HONOR ALEVÍN", .alevin),
        ("DIVISIÓN DE HONOR CADETE", .cadete),
        ("DIVISIÓN DE HONOR INFANTIL", .infantil),
        ("NACIONAL JUVENIL", .juvenil),
        ("PREFERENTE AFICIONADO", .senior),
        ("PREFERENTE ALEVÍN", .alevin),
        ("PREFERENTE CADETE", .cadete),
        ("PREFERENTE FEMENINO JUVENIL", .juvenil),
        ("PREFERENTE FÚTBOL FEMENINO", nil),
        ("PREFERENTE INFANTIL", .infantil),
        ("PREFERENTE JUVENIL", .juvenil),
        ("PRIMERA AFICIONADO", .senior),
        ("PRIMERA CADETE", .cadete),
        ("PRIMERA DIVISIÓN AUTONÓMICA AFICIONADO", .senior),
        ("PRIMERA DIVISIÓN AUTONÓMICA ALEVÍN", .alevin),
        ("PRIMERA DIVISIÓN AUTONÓMICA CADETE", .cadete),
        ("PRIMERA DIVISIÓN AUTONÓMICA FEMENINO JUVENIL", .juvenil),
        ("PRIMERA DIVISIÓN AUTONÓMICA FEMENINO", nil),
        ("PRIMERA DIVISIÓN AUTONÓMICA INFANTIL", .infantil),
        ("PRIMERA DIVISIÓN AUTONÓMICA JUVENIL", .juvenil),
        ("PRIMERA FÚTBOL FEMENINO", nil),
        ("PRIMERA INFANTIL", .infantil),
        ("PRIMERA JUVENIL", .juvenil),
        ("SEGUNDA AFICIONADO", .senior),
        ("SUPERLIGA ALEVÍN", .alevin),
        ("SUPERLIGA CADETE", .cadete),
        ("SUPERLIGA INFANTIL", .infantil),
        ("TERCERA FEDERACIÓN DE FÚTBOL FEMENINO", nil),
        ("TERCERA FEDERACIÓN RFEF", nil),
    ]

    @Test("las 30 competiciones medidas: la edad que dice cada nombre (§F.14)",
          arguments: measured)
    func theMeasuredNames(_ entry: (name: String, age: TeamCategory?)) {
        #expect(TeamCategory.proposed(fromFederationName: entry.name) == entry.age)
    }

    /// **`PREBENJAMÍN` contiene `BENJAMÍN`**, y el nombre se compara plegado y
    /// sin espacios (`NormalizedName`): sin cuidar el orden, un prebenjamín se
    /// propondría benjamín. La muestra no trae ninguno —es fútbol-11—, y por eso
    /// se escribe aparte.
    @Test("prebenjamín no se confunde con benjamín")
    func prebenjaminIsNotBenjamin() {
        #expect(TeamCategory.proposed(fromFederationName: "PRIMERA PREBENJAMÍN") == .prebenjamin)
        #expect(TeamCategory.proposed(fromFederationName: "PRIMERA BENJAMÍN") == .benjamin)
    }

    /// **Dos edades en el mismo nombre no proponen ninguna**: adivinar una de las
    /// dos sería afirmar algo que la fuente no ha dicho, y aquí equivocarse no da
    /// un rótulo feo, da un 409 (o lo deja pasar).
    @Test("dos edades en el mismo nombre no proponen ninguna")
    func twoAgesProposeNothing() {
        #expect(TeamCategory.proposed(fromFederationName: "COPA CADETE JUVENIL") == nil)
    }
}

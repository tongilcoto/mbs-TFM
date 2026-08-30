public import Domain

/// Puerto de salida: **qué adaptador atiende a cada federación** (§4.3, `D-17`).
///
/// # Por qué es un puerto y no un `switch` en el adaptador primario
///
/// `D-17` dice que la federación es un **catálogo en código**: soportar una
/// nueva exige escribir un adaptador. Lo que ese catálogo no dice —y hasta F6 no
/// hacía falta que dijera— es **cuál de ellos se usa en esta pasada**, y la
/// respuesta sale de un dato del tenant: `Club.federation` (§3.6).
///
/// Esa resolución es una regla del recorrido, no del cableado. Si viviera en el
/// `AsyncCommand`, el nivel 2 no podría afirmar que *"un club de la FCF no se
/// sincroniza con el adaptador de la RFFM"*, que es exactamente la clase de fallo
/// silencioso que `D-84` enseñó a temer: escribir el calendario equivocado no da
/// error, da datos.
///
/// # Devuelve un opcional, y es deliberado
///
/// Hoy hay **dos** federaciones en el catálogo del Dominio y **un** adaptador: la
/// FCF es F9. Un `nil` aquí es la constatación honesta de ese hueco, y quien
/// decide qué hacer con él es el caso de uso —no este puerto—: un club así no se
/// recorre y **no deja pasadas fallidas** en el registro, porque no es una pasada
/// que falla sino un club que todavía no se puede sincronizar.
public protocol FederationClientProvider: Sendable {
    /// El adaptador de esa federación, o `nil` si aún no se ha escrito.
    func client(for code: FederationCode) -> (any FederationClient)?
}

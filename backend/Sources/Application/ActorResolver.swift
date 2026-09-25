/// De dónde sale **quién** hace la petición (§7.4, `A-6`/H-42).
///
/// # Por qué es un puerto y no una función
///
/// §6.1 dice que el *claim* `club_id` del JWT es **autoritativo** y el subdominio
/// solo enrutado, y que una discrepancia entre los dos **se rechaza**. Esa
/// comparación existe —`FluentTenantUnitOfWork.resolveTenant` lanza
/// `TenancyError.tenantMismatch`— y hasta `C-E.2` **no podía dispararse nunca**:
/// el adaptador construía el actor *desde el propio ambiente*, así que comparaba
/// un valor consigo mismo. Una guarda tautológica no es una guarda; es un trozo
/// de código que aprueba.
///
/// Con el actor detrás de un puerto, la comparación deja de ser tautológica
/// **por construcción**: quien resuelve al actor y quien fija el ambiente son
/// dos piezas distintas, y un test puede hacerlas discrepar sin esperar a JWKS.
///
/// # Lo que esto NO es
///
/// **No es la autenticación** (§7), que sigue siendo la deuda declarada de F0.
/// La implementación de hoy deriva el actor del tenant ambiental, así que en
/// producción los dos siguen coincidiendo siempre. Lo que cambia es dónde está
/// escrito: cuando llegue la validación JWKS, el actor sale del *claim*
/// cambiando **el adaptador**, no el middleware ni los *handlers*, y el 403 que
/// hoy solo ve un test pasa a poder ocurrir de verdad.
///
/// Hoy `ActorContext` solo lleva el club. Cuando §7 aterrice, es el adaptador de
/// este puerto quien carga además el `StaffMember` y sus asignaciones vigentes
/// — y la firma de los casos de uso **no cambia**, que es justo lo que esa
/// decisión persigue.
public protocol ActorResolver: Sendable {
    /// El actor de la petición en curso, o el error de tenancy que impide
    /// construirlo.
    func currentActor() throws -> ActorContext
}

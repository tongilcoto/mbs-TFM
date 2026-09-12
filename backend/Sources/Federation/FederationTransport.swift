/// Traer bytes de la red. Nada más.
///
/// Existe porque el Plan §7.3 corrige un atajo del propio diseño: *"la frontera
/// «cliente HTTP» y la frontera «parser» son **dos** responsabilidades en ambos
/// proveedores, no una en uno y dos en el otro"*. Separarlas es lo que hace que
/// **todo F2 sea nivel 1** (§8.1): el parser se prueba contra volcados reales, en
/// milisegundos y sin red.
///
/// Es un protocolo **interno del adaptador**, no un puerto de la capa Aplicación:
/// ningún caso de uso lo conoce. Lo que la Aplicación conoce es `FederationClient`.
///
/// # Aquí no hay implementación de verdad, y es a propósito
///
/// La que habla con la red llega en **F5**, que es donde hay integración que la
/// ejercite — y con ella el ***canario*** (Plan §4.4): una prueba **fuera de la
/// suite normal**, tras `FEDERATION_LIVE=1`, que pasa el parser por encima de la
/// respuesta **viva** y exige que no falle. No compara bytes: el calendario cambia
/// cada semana por diseño ([Anexo RFFM §F.5]), así que un `diff` daría alarma cada
/// lunes. Lo que afirma es que **el parser sigue tragando**, que es lo que avisa de
/// un rediseño como el que se llevó por delante medio anexo de la FCF (`D-74`).
///
/// Escribirla en F2 habría sido código sin un solo test que lo toque —exactamente
/// lo que el bucle de §5 del plan existe para evitar—, y además lo que tenía que
/// resolver eran cosas que F2 no sabía todavía: **validar el `2xx`
/// explícitamente**, que es el fallo que [Anexo RFFM §F.7] documenta en la app
/// heredada —*"imprime el código HTTP pero no lo valida"*, así que un 500 acaba
/// en el parser de JSON con un error engañoso—, el tope de cuerpo y el *timeout*.
///
/// **Y una cosa que ya no tiene que resolver:** el control de concurrencia y el
/// *backoff* que este comentario le encargaba citando [Anexo FCF §C.6] eran para
/// raspar ~34 páginas por grupo. Esa sección **está obsoleta**: la FCF publica API
/// JSON y su calendario entero cuesta **una** petición (`D-74`,
/// [Anexo FCF §C.10.4]), igual que la RFFM. Si alguna vez hace falta paralelismo
/// será por otra razón y con otra medida.
public protocol FederationTransport: Sendable {
    /// - Returns: el cuerpo de la respuesta como texto. La RFFM responde **UTF-8**
    ///   siempre y **sin cabeceras especiales** ([Anexo RFFM §F.7]).
    func get(_ url: String) async throws -> String
}

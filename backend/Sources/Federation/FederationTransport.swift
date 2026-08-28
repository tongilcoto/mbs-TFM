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
/// ejercite. Escribirla ahora sería código sin un solo test que lo toque —
/// exactamente lo que el bucle de §5 del plan existe para evitar—, y además lo
/// que tendría que resolver son cosas que F2 no sabe todavía: control de
/// concurrencia y *backoff* ([Anexo FCF §C.6]), y **validar el `2xx`
/// explícitamente**, que es el fallo que [Anexo RFFM §F.7] documenta en la app
/// heredada — *"imprime el código HTTP pero no lo valida"*, así que un 500 acaba
/// en el parser de JSON con un error engañoso.
public protocol FederationTransport: Sendable {
    /// - Returns: el cuerpo de la respuesta como texto. La RFFM responde **UTF-8**
    ///   siempre y **sin cabeceras especiales** ([Anexo RFFM §F.7]).
    func get(_ url: String) async throws -> String
}

/// Lo que puede salir mal al hablar con una federación (§4.3, §5.6).
///
/// Vive en la capa Aplicación, con el puerto, y no en el adaptador: **un caso de
/// uso tiene que poder distinguir "la fuente no contesta" de "la fuente contesta
/// algo que no entiendo"** sin saber si detrás hay HTML, JSON o un *scraper*.
///
/// No es `DomainError`, y la diferencia importa: un `DomainError` dice que un
/// **valor** viola una invariante nuestra; esto dice que la **fuente ajena** no
/// se comporta como esperábamos. La ingesta reacciona distinto a cada uno — ante
/// lo segundo degrada y reintenta (§3.7), ante lo primero no hay reintento que
/// valga.
public enum FederationError: Error, Equatable, Sendable {
    /// La respuesta llegó, pero no tiene la forma documentada en el anexo.
    ///
    /// `field` es la coordenada dentro del cuerpo (`"calendar.rounds[3].codjornada"`),
    /// no el nombre de una columna nuestra: lo que hay que mirar para arreglarlo
    /// es el volcado de la federación.
    case malformedResponse(field: String, reason: String)

    /// **La coordenada no designa nada.** Se distingue del resto porque
    /// significa otra cosa (Plan §4.4): `temporada` cambia cada año y
    /// `competicion`/`grupo` con ella ([Anexo RFFM §F.1]), así que esto es
    /// *"revisa la coordenada"* y no *"la fuente ha cambiado de forma"*. Un
    /// canario que no los separara daría la misma alarma para las dos cosas.
    ///
    /// **Lo levanta el adaptador tanto como el transporte, y eso es una
    /// corrección de F5.** El diseño daba por hecho que sería un 404; medido
    /// contra la RFFM, **nunca lo es**: una coordenada mala devuelve `200` con
    /// `calendar: null`, y una temporada inexistente devuelve `200` con el
    /// calendario de otra y `temporada` vacía. Por eso el detalle es texto y no
    /// una URL: quien lo levanta no siempre sabe a qué URL fue.
    case coordinateNotFound(detail: String)

    /// Cualquier otro código fuera de `2xx`.
    ///
    /// Existe porque [Anexo RFFM §F.7] documenta el fallo de la app heredada:
    /// *"imprime el código HTTP pero no lo valida"*, así que un 500 acaba en el
    /// parser de JSON y sale un error engañoso sobre el cuerpo. Validar el `2xx`
    /// explícitamente es lo que hace que un fallo del servidor **se llame** fallo
    /// del servidor.
    case unexpectedStatus(status: Int, url: String)

    /// No se pudo llegar a hablar con la fuente: DNS, conexión, *timeout*.
    ///
    /// Es la **tercera** cosa que un canario tiene que poder distinguir de las
    /// otras dos: aquí no hay nada que arreglar en nuestro código.
    case transportFailure(url: String, reason: String)
}

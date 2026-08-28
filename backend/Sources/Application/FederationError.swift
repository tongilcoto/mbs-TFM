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
}

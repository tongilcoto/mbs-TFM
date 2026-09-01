/// Cómo se cuenta un error en el registro de pasadas (`D-85`).
///
/// # Por qué esto no es `"\(error)"`
///
/// `D-85` guarda el motivo como **texto y no como código**, para poder
/// depurarlo. Pero el error más probable de la ingesta —una violación de
/// restricción de Postgres— **esconde su descripción**:
///
/// ```
/// PSQLError – Generic description to prevent accidental leakage of sensitive
/// data. For debugging details, use `String(reflecting: error)`.
/// ```
///
/// Con eso, la fila que existe para contestar *"¿por qué falta este partido?"*
/// no contestaba nada. Lo destaparon las pruebas manuales de F6, contra la base
/// de trabajo y con un `UNIQUE` reventando de verdad.
///
/// # Y el dato sensible aquí no lo es
///
/// La cautela de PostgresNIO es correcta en general: un error suyo puede llevar
/// trozos de la consulta, y los logs de producción se comparten. Pero esto **no
/// es un log**: es una fila dentro del *schema* del club, que solo alcanza quien
/// ya tiene acceso a sus datos (§6.2). Lo que se pierde por ocultarlo es más que
/// lo que se protege.
///
/// El mismo problema, la misma salida: `TestSupport` ya envuelve sus fallos con
/// `String(reflecting:)` por esto exacto.
public func diagnosticText(for error: any Error) -> String {
    String(reflecting: error)
}

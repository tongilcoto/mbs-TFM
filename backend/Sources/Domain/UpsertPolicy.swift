/// La política de *upsert* de la ingesta, campo a campo (§3.7, `D-18`).
///
/// # Por qué existe
///
/// El BFF solo puede **corregir** lo que la ingesta trae (`D-21`), así que esa
/// corrección **tiene que sobrevivir a la siguiente pasada**; si no, el `PATCH`
/// sería tan poco duradero como un `DELETE`. La alternativa —marcar cada campo
/// corregido con un `..._overridden_at` o un `jsonb` de *overrides*— se descartó
/// en `D-18`: coste alto en esquema y en código para un problema que se resuelve
/// **por clases de campo**, sin banderas nuevas.
///
/// # Las cuatro clases, y qué hace cada una en cada camino
///
/// | Clase | En el INSERT | En el UPDATE |
/// |---|---|---|
/// | **descriptivo** (semilla) | la fuente siembra | **nunca se toca**: el valor bueno es el del administrador |
/// | **volátil** | la fuente siembra | **la fuente gana cuando dice algo** (`D-56`) |
/// | **de propiedad** | lo pone el emparejamiento al crear la fila | **nunca se toca**: es del BFF |
/// | **de emparejamiento** | la fuente siembra | **no sobrescribe; solo rellena hueco** |
///
/// **El INSERT no necesita política**: al crear la fila no hay nada que
/// preservar, así que lo que la fuente diga entra tal cual. Por eso todas las
/// funciones de aquí son la regla del **UPDATE**, que es donde se destruyen
/// datos.
///
/// # Por qué son funciones y no un `if` en cada sitio
///
/// El *merge* de una entidad de ingesta (F5) pasa **campo por campo** por una de
/// estas cuatro, y el nombre en la llamada es lo que permite revisar la fase
/// leyendo el código: un campo que no está clasificado se ve, y uno clasificado
/// mal se lee. Escribir la regla a mano en cada entidad es cómo se acaba con
/// tres versiones distintas de «vacío no sobrescribe».
///
/// # Dos firmas distintas, y no es descuido
///
/// `descriptive` y `owned` **no miran dentro del opcional** —devuelven lo que
/// hay, sea o no `nil`—, así que su `existing` es genérico a secas y sirve
/// igual para una columna `NOT NULL` que para una anulable. `volatile` y
/// `matching` **sí distinguen `nil`**, y por eso lo declaran.
public enum UpsertPolicy {

    // ── Descriptivo (semilla) ────────────────────────────────────────────────

    /// El valor de la fuente **solo sirve para sembrar**: en el UPDATE se
    /// conserva lo que hay.
    ///
    /// Ejemplos (§3.7): `OpponentClub.name`/`short_name`/`crest_key`,
    /// `Competition.division_label`/`group_label`.
    ///
    /// La fuente escribe estos nombres **en mayúsculas y con puntuación
    /// irregular** ([Anexo RFFM §F.5]) y el administrador los arregla. Si la
    /// pasada del lunes los volviera a pisar, la corrección duraría una semana.
    ///
    /// `incoming` se declara y **no se usa**, y es deliberado: la llamada dice
    /// *"esto es lo que trae la fuente, y para este campo da igual"*, que es
    /// justo lo que hay que poder leer en el *merge* de F5.
    public static func descriptive<Value>(existing: Value, incoming: Value?) -> Value {
        existing
    }

    // ── Volátil (propiedad de la federación) ─────────────────────────────────

    /// La fuente manda **cuando dice algo** (`D-56`).
    ///
    /// Ejemplos (§3.7): marcador, `status`, `match_date` y `kickoff_time`,
    /// `venue`, posiciones de `StandingRow`, `LeagueScorer`.
    ///
    /// **`nil` es «la fuente no dijo nada», no «la fuente dice que no hay»**, y
    /// esa es toda la decisión: quien colapse los dos escribe un `UPDATE` ciego
    /// y borra el dato bueno en la primera pasada.
    ///
    /// La frontera se aplica **en el adaptador**, que es quien sabe cómo calla
    /// cada federación: en la RFFM el marcador ausente llega como `""` y en la
    /// FCF como `"0"` ([Anexo FCF §C.10.5]) — leer Cataluña con la regla de
    /// Madrid escribiría un 0-0 en todos los partidos futuros de la liga. Aquí
    /// llega ya traducido a `nil`.
    public static func volatile<Value>(existing: Value?, incoming: Value?) -> Value? {
        incoming ?? existing
    }

    // ── De propiedad ─────────────────────────────────────────────────────────

    /// Lo que la ingesta **no escribe nunca** en un UPDATE, porque tiene otro
    /// dueño (§3.7).
    ///
    /// El único caso hoy es `Team.opponent_club_id`, que es del BFF vía
    /// `/ownership` (`D-20`).
    ///
    /// **Devuelve `existing` aunque sea `nil`**, y ahí está la diferencia con
    /// `matching`: un `nil` aquí **no es un hueco**, es una decisión del
    /// administrador —«este equipo es mío»— y rellenarlo sería deshacerla.
    public static func owned<Value>(existing: Value, incoming: Value?) -> Value {
        existing
    }

    // ── De emparejamiento ────────────────────────────────────────────────────

    /// La clave con la que la ingesta reconoce una fila ya vista (§3.7):
    /// `federation_team_id`, `federation_club_id`, `federation_match_id`.
    ///
    /// **Inmutables** (§3.7): el BFF no las expone en escritura y la ingesta no
    /// las cambia. Si la federación renumerase, se degradaría el emparejamiento,
    /// no la integridad — y el arreglo es la fusión (§9), no un `UPDATE`.
    ///
    /// **Pero sí rellena el hueco** (`D-76`): es el espejo exacto de `volatile`
    /// —allí gana la fuente y el dato viejo es el respaldo; aquí gana el dato y
    /// la fuente solo llega donde no hay nada—. Sin esto, una fila que nació sin
    /// clave porque la inferencia falló ([Anexo RFFM §F.4]) no la recuperaría
    /// nunca y se quedaría emparejándose por nombre, que es el paso inexacto de
    /// la cadena de §3.7.
    public static func matching<Value>(existing: Value?, incoming: Value?) -> Value? {
        existing ?? incoming
    }
}

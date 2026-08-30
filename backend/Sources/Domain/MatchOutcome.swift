/// Cómo acabó la cadena de emparejamiento de §3.7 para **una** fila entrante.
///
/// La cadena **no decide qué hacer**: dice a qué fila corresponde lo que la
/// fuente publica, y **por qué escalón lo supo**. Insertar, actualizar o dejarlo
/// para revisión es de F5; separar las dos cosas es lo que permite probar la
/// regla sin base de datos.
public enum MatchOutcome<ID: Hashable & Sendable>: Equatable, Sendable {
    /// Es esta fila, y se supo **por este escalón**.
    case matched(ID, by: MatchingKey)

    /// El paso inexacto encontró **más de un candidato** igual de bueno.
    ///
    /// **No es `unmatched` y no es un `matched` cualquiera**: dar de alta crearía
    /// justo el duplicado que la cadena existe para evitar, y quedarse con el
    /// primero **congelaría** un emparejamiento posiblemente equivocado —el
    /// riesgo del que avisa `D-76` al estampar la clave, pero sin ni siquiera la
    /// excusa de que el candidato fuese único—. Así que la ingesta ni empareja ni
    /// crea: deja la fila fuera y la reporta, que es el material con el que la
    /// operación de fusión (§9) tendrá que trabajar.
    case ambiguous([ID])

    /// Ningún candidato. En equipos y clubes es el **paso 3**: alta nueva, y de
    /// un rival —la ingesta no crea equipos propios (`D-66`)—. En partidos no es
    /// un escalón de degradación sino simplemente un partido que no habíamos
    /// visto (`D-31`).
    case unmatched
}

/// Por qué escalón de la cadena se reconoció la fila (§3.7).
///
/// **Se devuelve, y no es adorno.** §3.7 remata el paso 3 con *"alta nueva
/// **marcada para revisión manual**"*, y esa marca **no es una columna**: §3.2 no
/// la tiene y `D-18` cerró la fase anterior con *"cuatro clases de campo, cuatro
/// funciones, cero columnas"*. Lo que hace revisable un emparejamiento es saber
/// si fue exacto o degradado, y eso es este valor: viaja en el resultado, lo
/// reporta el job de F6, y no deja rastro en el esquema.
public enum MatchingKey: Equatable, Sendable {
    /// Paso 1: `federation_club_id`, `federation_team_id` o `federation_match_id`.
    /// **Exacto**, y único por §3.5.
    case federationKey

    /// Paso 2 de equipos y clubes: nombre normalizado más la identidad que la
    /// fuente no publica. **Inexacto por declaración propia** (§3.7).
    case normalizedName

    /// Paso 2 de partidos: (`round_id`, `home_team_id`, `away_team_id`).
    /// **Exacto**, y por eso la cadena de partidos no tiene tercer escalón
    /// (`D-31`): son FK internas ya resueltas, no un parecido de texto.
    case coordinates
}

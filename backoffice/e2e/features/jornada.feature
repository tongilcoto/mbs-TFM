# Jornada y clasificación de una competición (plan R4, §3.4; decisión 3).
# /temporadas/<temporada>/competiciones/<id>?jornada=<número>. Los datos, de una competición con jornadas jugadas que se
# inventa la federación falsa (ver ficha.feature); lo que se compara se lee de ella.
#
# Vocabulario de los pasos:
# - «la pantalla de la competición»: la de jornada y clasificación.
# - «la jornada en curso»: la que el servidor marca como tal (`isCurrent`), la primera sin jugar.
# - «una jornada jugada»: una de las que tienen marcador y clasificación, elegida al azar.
Feature: La jornada y la clasificación de una competición

  @ui
  Scenario: La pantalla de la competición, abierta sin jornada, enseña la jornada en curso
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro la pantalla de la competición del equipo, sin jornada
    Then el título de la pantalla de la competición dice su división y su grupo
    And el selector de jornada tiene elegida la jornada en curso, con sus fechas

  @ui
  Scenario: Los partidos de una jornada jugada, partido a partido
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro la pantalla de la competición del equipo en una jornada jugada
    Then la tabla de partidos tiene los de esa jornada, con su fecha, su hora, los dos equipos y el marcador
    And en la tabla de partidos está resaltado el del equipo de mi club

  @ui
  Scenario: La clasificación de una jornada jugada, fila a fila
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro la pantalla de la competición del equipo en una jornada jugada
    Then la clasificación tiene una fila por equipo, en orden de puesto
    And cada fila de la clasificación tiene los jugados, ganados, empatados, perdidos, goles a favor y en contra, diferencia y puntos de la Federación
    And cada fila de la clasificación tiene el puesto de la jornada anterior
    And en la clasificación está resaltada la fila del equipo de mi club

  @ui
  Scenario: La racha de la clasificación dice el número de cada jornada, la más reciente a la izquierda
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro la pantalla de la competición del equipo en la última jornada jugada
    Then la racha de cada equipo tiene sus últimos partidos, hasta cinco, del más reciente al más antiguo
    And cada partido de la racha dice el número de su jornada
    And cada partido de la racha dice al lector si fue victoria, empate o derrota, y en qué jornada

  @ui
  Scenario: Una jornada por jugar no tiene clasificación todavía
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro la pantalla de la competición del equipo en la jornada en curso
    Then la pantalla de la competición dice "Esta jornada aún no tiene clasificación."

  # ── Moverse entre jornadas ──

  @e2e
  Scenario: «Siguiente» lleva a la jornada siguiente
    Given estoy en la pantalla de la competición del equipo de mi club que ha jugado, en una jornada jugada
    When pulso "Siguiente" en la pantalla de la competición
    Then estoy en la jornada siguiente de la competición

  @e2e
  Scenario: «Anterior» lleva a la jornada anterior
    Given estoy en la pantalla de la competición del equipo de mi club que ha jugado, en una jornada jugada que no es la primera
    When pulso "Anterior" en la pantalla de la competición
    Then estoy en la jornada anterior de la competición

  @e2e
  Scenario: Elegir una jornada en el selector la abre
    Given estoy en la pantalla de la competición del equipo de mi club que ha jugado, en la jornada en curso
    When elijo una jornada jugada en el selector de jornada
    Then estoy en esa jornada de la competición

  @e2e
  Scenario: Recargar la pantalla de la competición deja en la misma jornada
    Given estoy en la pantalla de la competición del equipo de mi club que ha jugado, en una jornada jugada
    When recargo la página
    Then estoy en esa jornada de la competición

  @ui
  Scenario: En la primera jornada, «Anterior» está bloqueado
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro la pantalla de la competición del equipo en la primera jornada
    Then el botón "Anterior" de la pantalla de la competición está bloqueado
    And el botón "Siguiente" de la pantalla de la competición está activo

  @ui
  Scenario: En la última jornada, «Siguiente» está bloqueado
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro la pantalla de la competición del equipo en la última jornada
    Then el botón "Siguiente" de la pantalla de la competición está bloqueado
    And el botón "Anterior" de la pantalla de la competición está activo

  # ── Lo que no se puede enseñar ──

  @ui
  Scenario: La pantalla de la competición dice «Cargando jornada…» mientras llegan los datos
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    And la petición de las jornadas de la competición del equipo está retenida
    When abro la pantalla de la competición del equipo, sin jornada
    Then la pantalla de la competición dice "Cargando jornada…"

  @ui
  Scenario: La pantalla de una competición que no existe dice que no se ha encontrado
    Given mi club tiene la temporada en curso
    When escribo en el navegador la dirección de una competición que mi club no tiene
    Then la página dice "No se ha encontrado la competición"
    And la página tiene un enlace a la portada

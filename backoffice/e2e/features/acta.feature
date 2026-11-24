# La pantalla del acta de un partido (plan R7, §3 y decisiones 4, 5, 8 y 11; D-130, D-133).
# Los partidos, sus fechas, sus rivales y sus actas los sirve la Federación falsa, y los trae la ingesta de verdad
# (LLD-B §11.3). La convocatoria, los goles y las tarjetas tienen sus ficheros (acta-convocatoria, acta-goles y
# acta-tarjetas); la carga del acta, el suyo (acta-federacion). Aquí, lo que es de la pantalla entera.
#
# Lo que no tiene escenario, y por qué:
# - «Cargando» y el error del servidor: probados una vez para toda la web (LLD-B §11.5).
# - El móvil: lo mira axe en los dos modos y la revisión a mano.
# - La temporada archivada (decisión 5f, DW-26): la web no abre las temporadas archivadas, ni escribiendo su
#   dirección (R6.18, decisión 2), hasta que se recuperen desde Temporadas en la rebanada 11. Hasta entonces, su
#   solo lectura, su aviso, su sello y su tono los cubren las pruebas de piezas y el servidor (`SEASON_ARCHIVED`);
#   los escenarios llegan con la rebanada 11.
#
# Vocabulario de los pasos:
# - «el equipo»: un equipo de mi club enganchado a una competición de la Federación falsa, en la temporada en curso;
#   «el equipo de mi club que ha jugado», el de resultados.feature, con jornadas jugadas.
# - «un partido por jugar»: uno del equipo cuya hora de comienzo no ha pasado.
# - «un partido jugado sin acta»: uno del equipo cuya hora de comienzo ha pasado y cuya acta la Federación no ha
#   cerrado.
# - «un partido con el acta cargada»: uno del equipo cuya acta ya cargó la ingesta.
# - «el acta»: la pantalla del acta de un partido (`/temporadas/:temporada/partidos/:id`).
# - «el navegador de partidos»: «‹ Anterior», el selector y «Siguiente ›», encima del marcador del acta. Recorre los
#   partidos del equipo en esa competición, por jornada.
Feature: El acta de un partido

  # ── Entrar ──

  @e2e
  Scenario: Pulsar el marcador de un partido en Resultados abre su acta
    Given estoy en la ficha del equipo de mi club que ha jugado
    When pulso el marcador de un partido jugado en la tabla de resultados
    Then estoy en el acta de ese partido

  @ui
  Scenario: El acta de un partido jugado dice su competición, sus equipos, su marcador y cuándo y dónde se jugó
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro el acta de un partido jugado
    Then el título del acta dice la competición del partido
    And el marcador del acta tiene los dos equipos y el resultado de la Federación
    And el acta dice la fecha, la hora y el campo del partido

  @ui
  Scenario: El acta de un partido por jugar dice "Por jugar" en lugar del resultado
    Given el equipo tiene un partido por jugar
    When abro el acta del partido por jugar
    Then el marcador del acta dice "Por jugar" en lugar del resultado

  @e2e
  Scenario: El enlace de vuelta lleva a la pestaña Resultados del equipo
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    And estoy en el acta de un partido jugado
    When pulso el enlace "← Resultados de" y el nombre del equipo, encima del título del acta
    Then estoy en la pestaña Resultados de la ficha del equipo, en la temporada en curso

  @e2e
  Scenario: «Ver la jornada y la clasificación» lleva a la jornada del partido
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    And estoy en el acta de un partido jugado
    When pulso el enlace "Ver la jornada y la clasificación", debajo del título del acta
    Then estoy en la jornada de ese partido, en la pantalla de su competición

  @ui
  Scenario: La dirección de un partido con otra temporada dice que no se ha encontrado
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When escribo en el navegador la dirección del acta de un partido jugado, con la temporada pasada
    Then la página dice "No se ha encontrado el partido"

  @ui
  Scenario: La dirección de un partido entre dos rivales dice que no se ha encontrado
    Given en la competición del equipo hay un partido entre dos rivales
    When escribo en el navegador la dirección del acta del partido entre dos rivales
    Then la página dice "No se ha encontrado el partido"

  # ── En qué situación está el acta ──

  @ui
  Scenario Outline: El acta de <un partido> avisa de <su situación>
    Given el equipo tiene <un partido>
    When abro el acta de <ese partido>
    Then el aviso del acta dice <lo que dice>

    Examples:
      | un partido                    | su situación                 | ese partido                    | lo que dice                                                                 |
      | un partido por jugar          | que aún no ha empezado       | el partido por jugar           | que de momento solo se apunta la convocatoria                               |
      | un partido jugado sin acta    | que el acta aún no ha llegado | el partido jugado sin acta     | que el acta se cargará sola cuando la Federación la cierre                  |
      | un partido con el acta cargada | que el acta está cargada     | el partido con el acta cargada | que el acta viene de la Federación, con la fecha en que se cargó, y qué queda por completar |

  @ui
  Scenario: Antes de la hora de comienzo, el acta no tiene goles ni tarjetas
    Given el equipo tiene un partido por jugar
    When abro el acta del partido por jugar
    Then el acta no tiene la sección de goles
    And el acta no tiene la sección de tarjetas

  @ui
  Scenario: Desde la hora de comienzo, el acta tiene goles y tarjetas
    Given el equipo tiene un partido jugado sin acta
    When abro el acta del partido jugado sin acta
    Then el acta tiene la sección de goles
    And el acta tiene la sección de tarjetas

  # ── El navegador de partidos ──

  @ui
  Scenario: Cada opción del selector de partidos dice la jornada, la fecha, si es en casa o fuera y el rival
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro el acta de un partido jugado
    Then cada opción del selector de partidos dice su jornada, su fecha, en casa o fuera y el rival del equipo

  @ui
  Scenario: La jornada de descanso sale en el selector de partidos y no se puede elegir
    Given el equipo descansa en una jornada de la competición
    When abro el acta de un partido del equipo
    Then el selector de partidos tiene la jornada de descanso bloqueada, diciendo que el equipo descansa

  @e2e
  Scenario: Elegir un partido en el selector abre su acta
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    And estoy en el acta de un partido jugado
    When elijo otro partido en el selector de partidos
    Then estoy en el acta de ese partido

  @e2e
  Scenario: «Siguiente» abre el acta del partido siguiente del equipo
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    And estoy en el acta de un partido que no es el último del equipo
    When pulso "Siguiente" en el navegador de partidos
    Then estoy en el acta del partido siguiente del equipo

  @e2e
  Scenario: «Anterior» abre el acta del partido anterior del equipo
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    And estoy en el acta de un partido que no es el primero del equipo
    When pulso "Anterior" en el navegador de partidos
    Then estoy en el acta del partido anterior del equipo

  @e2e
  Scenario: «Siguiente» se salta la jornada de descanso
    Given el equipo descansa en una jornada de la competición
    And estoy en el acta del partido del equipo justo antes de su jornada de descanso
    When pulso "Siguiente" en el navegador de partidos
    Then estoy en el acta del partido del equipo justo después de su jornada de descanso

  @ui
  Scenario Outline: En el <partido> del equipo, el botón "<botón>" está bloqueado
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro el acta del <partido> del equipo
    Then el botón "<botón>" del navegador de partidos está bloqueado

    Examples:
      | partido        | botón     |
      | primer partido | Anterior  |
      | último partido | Siguiente |

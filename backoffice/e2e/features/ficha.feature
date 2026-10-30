# La ficha del equipo: cómo se llega y su cabecera (plan R4, §3.1 y §3.2; decisiones 3, 4 y 7).
# Las competiciones se las inventa la federación falsa (LLD-B §11.3). «Con jornadas jugadas»: una competición de la
# temporada en curso cuyas primeras jornadas ya se jugaron (con marcador y su clasificación) y el resto está por jugar;
# los marcadores, al azar con la semilla de la pasada.
#
# Vocabulario de los pasos:
# - «la ficha del equipo»: /temporadas/<temporada>/equipos/<id>/resultados.
# - «la caja de la temporada», «la caja de la competición», «la caja de la posición»: las tres de la cabecera.
# - «el equipo de mi club que ha jugado»: el que juega en una competición con jornadas jugadas.
Feature: La ficha del equipo

  # ── Llegar a la ficha ──

  @e2e
  Scenario: En la portada, el nombre de un equipo abre su ficha en la temporada que enseñaba la portada
    Given en una temporada pasada de mi club juega un equipo
    And he cambiado la portada de mi club a una temporada pasada
    When pulso el nombre del equipo en la portada
    Then estoy en la ficha del equipo, en la temporada pasada

  @e2e
  Scenario: La dirección de un equipo sin temporada abre su ficha en la temporada en curso
    Given en la temporada en curso de mi club juega un equipo
    When escribo en el navegador la dirección del equipo, sin temporada
    Then estoy en la ficha del equipo, en la temporada en curso

  @e2e
  Scenario: Cambiar la temporada en la ficha abre la ficha del mismo equipo en esa temporada
    Given el mismo equipo de mi club juega en la temporada en curso y en una pasada
    And estoy en la ficha del equipo, en la temporada en curso
    When elijo la temporada pasada en el selector de la ficha
    Then estoy en la ficha del equipo, en la temporada pasada

  # ── La cabecera ──

  @ui
  Scenario: La cabecera de la ficha de un equipo que ha jugado, caja a caja
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro la ficha del equipo de mi club que ha jugado
    Then el título de la ficha dice la categoría y la letra del equipo, con su género y su modalidad
    And la caja de la temporada dice la temporada en curso
    And la caja de la competición dice su división y su grupo, con la ingesta "Al día"
    And la caja de la posición dice el puesto del equipo tras la última jornada jugada

  @ui
  Scenario: La caja de la posición de un equipo sincronizado sin jornadas jugadas dice que aún no se ha jugado
    Given en la temporada en curso de mi club juega un equipo
    When abro la ficha del equipo
    Then la caja de la posición dice "—" y "aún no se ha jugado"

  @ui
  Scenario: La caja de la competición de un equipo sin sincronizar ofrece sincronizarlo
    Given en la temporada en curso de mi club hay un equipo inscrito sin competición
    When abro la ficha del equipo de mi club inscrito sin competición
    Then la caja de la competición tiene el enlace "Sincronizar con la Federación"
    And la caja de la competición no tiene la acción "Volver a traer los datos de la Federación"
    And la caja de la posición dice "—"

  @e2e
  Scenario: En la ficha, «Sincronizar con la Federación» lleva a sincronizar ese equipo
    Given estoy en la ficha del equipo de mi club inscrito sin competición
    When pulso el enlace "Sincronizar con la Federación" de la caja de la competición
    Then se abre el paso 1 de sincronizar el equipo de mi club inscrito sin competición

  @e2e
  Scenario: En la ficha, la competición lleva a su jornada en curso y su clasificación
    Given estoy en la ficha del equipo de mi club que ha jugado
    When pulso la competición en la caja de la competición
    Then estoy en la jornada en curso de la competición del equipo

  # ── Relanzar la ingesta desde la ficha (decisión 7) ──

  @e2e
  Scenario: En la ficha, volver a traer los datos de una competición con fallos la deja al día
    Given estoy en la ficha del equipo de mi club que ha jugado, con la ingesta de su competición "Con fallos"
    And la Federación ya contesta bien a la competición del equipo
    When pulso la acción "Volver a traer los datos de la Federación" de la caja de la competición
    Then la caja de la competición tiene la ingesta "Al día"

  @ui
  Scenario: Mientras se vuelven a traer los datos, la caja de la competición dice «En marcha» y su acción está bloqueada
    Given estoy en la ficha del equipo de mi club que ha jugado
    And la Federación va a retener la próxima petición del calendario de la competición del equipo
    When pulso la acción "Volver a traer los datos de la Federación" de la caja de la competición
    Then la caja de la competición tiene la ingesta "En marcha"
    And la acción "Volver a traer los datos de la Federación" de la caja de la competición está bloqueada

  # ── Lo que no se puede enseñar ──

  @ui
  Scenario: La ficha de un equipo en una temporada en la que no juega lo dice
    Given en la temporada en curso de mi club juega un equipo
    And mi club tiene una temporada pasada
    When escribo en el navegador la dirección de la ficha del equipo en la temporada pasada
    Then la ficha dice que el equipo no jugó la temporada pasada
    And la ficha tiene el selector de temporada

  @ui
  Scenario: La ficha dice «Cargando equipo…» mientras llega el equipo
    Given en la temporada en curso de mi club juega un equipo
    And la petición del equipo está retenida
    When escribo en el navegador la dirección de la ficha del equipo en la temporada en curso
    Then la ficha dice "Cargando equipo…"

  @ui
  Scenario: La ficha de un equipo que no existe dice que no se ha encontrado
    Given mi club tiene la temporada en curso
    When escribo en el navegador la dirección de la ficha de un equipo que mi club no tiene
    Then la página dice "No se ha encontrado el equipo"
    And la página tiene un enlace a la portada

  # «abc» no es un código de equipo: la web lo sabe sin preguntar al servidor (LLD-B §6.7).
  @ui
  Scenario: La ficha con un código de equipo mal escrito en la dirección dice que no se ha encontrado
    Given mi club tiene la temporada en curso
    When abro la ficha del equipo "abc" en la temporada en curso
    Then la página dice "No se ha encontrado el equipo"
    And la página tiene un enlace a la portada

  @ui
  Scenario: La ficha de un equipo rival dice que no se ha encontrado
    Given en la temporada en curso de mi club juega un equipo
    When escribo en el navegador la dirección de la ficha de uno de los rivales del equipo de mi club que juega
    Then la página dice "No se ha encontrado el equipo"
    And la página tiene un enlace a la portada

# La portada: los equipos del club en una temporada (plan R1, §3.2 y decisión 2).
# Los equipos, sus competiciones y sus fechas se inventan al azar en cada pasada (la skill de escenarios,
# principio 9); solo es fijo lo que decide la rama: el estado de la ingesta.
Feature: La portada

  @ui
  Scenario: Cada equipo con su competición
    Given en la temporada en curso de mi club juega un equipo
    When abro la portada de mi club
    Then la fila del equipo en la portada tiene su competición

  @ui
  Scenario: La última sincronización, con fecha y hora de Madrid
    Given en la temporada en curso de mi club juega un equipo
    When abro la portada de mi club
    Then la fila del equipo en la portada tiene su última sincronización, en hora de Madrid

  @ui
  Scenario: Un equipo inscrito sin competición
    Given en la temporada en curso de mi club hay un equipo inscrito sin competición
    When abro la portada de mi club
    Then la fila del equipo en la portada dice "Sin competición"

  @ui
  Scenario Outline: La ingesta «<estado>»
    Given en la temporada en curso de mi club juega un equipo
    And la ingesta de la competición del equipo está "<estado>"
    When abro la portada de mi club
    Then la fila del equipo en la portada tiene la ingesta "<estado>"

    Examples:
      | estado            |
      | Al día            |
      | Con fallos        |
      | En marcha         |
      | Sin datos todavía |
      | Desactualizada    |

  @ui
  Scenario: En marcha, y la anterior tuvo fallos
    Given en la temporada en curso de mi club juega un equipo
    And la ingesta de la competición del equipo está "En marcha, y la anterior falló"
    When abro la portada de mi club
    Then la fila del equipo en la portada tiene la ingesta "En marcha"
    And la fila del equipo en la portada dice "La anterior tuvo fallos"

  @ui
  Scenario: Mientras llegan los equipos, «Cargando equipos…»
    Given mi club tiene la temporada en curso
    And la petición de las temporadas de mi club está retenida
    When abro la portada de mi club
    Then la portada dice "Cargando equipos…"

  @ui
  Scenario: Si el servidor cae mientras pide los equipos, el error sale en el hueco de la tabla
    Given he abierto la portada de mi club con la petición de las temporadas retenida
    And el servidor está parado
    When la petición de las temporadas sale
    Then la portada dice "No se ha podido conectar con el servidor"
    And la portada ofrece "Reintentar"

  @e2e
  Scenario: Reintentar, con el servidor de vuelta, trae los equipos
    Given en la temporada en curso de mi club juega un equipo
    And la portada de mi club enseña que no se ha podido conectar con el servidor
    And el servidor vuelve a estar en marcha
    When pulso el botón "Reintentar"
    Then la portada tiene la fila del equipo

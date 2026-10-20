# La portada: los equipos del club en una temporada (plan R1, §3.2 y decisión 2).
Feature: La portada

  Scenario: Cada equipo con su competición y cómo va su ingesta
    Given mi club tiene la temporada en curso
    And en la temporada en curso el "Cadete B" juega "PRIMERA CADETE · Grupo 4"
    And la ingesta del "Cadete B" está "Al día"
    When abro la portada de mi club
    Then la fila del "Cadete B" tiene la competición "Cadete · PRIMERA CADETE · Grupo 4"
    And la fila del "Cadete B" tiene la ingesta "Al día"

  Scenario: La última sincronización, con fecha y hora de Madrid
    Given mi club tiene la temporada en curso
    And en la temporada en curso el "Cadete B" juega "PRIMERA CADETE · Grupo 4"
    And el "Cadete B" se sincronizó por última vez el "2026-10-17T21:40:00Z"
    When abro la portada de mi club
    Then la fila del "Cadete B" tiene la última sincronización "17/10/2026 23:40"

  Scenario: Un equipo inscrito sin competición
    Given mi club tiene la temporada en curso
    And en la temporada en curso el "Alevín A" está inscrito sin competición
    When abro la portada de mi club
    Then la fila del "Alevín A" dice "Sin competición"
    And la fila del "Alevín A" dice "Se engancha con la federación desde la ficha del equipo"

  Scenario Outline: La ingesta «<estado>»
    Given mi club tiene la temporada en curso
    And en la temporada en curso el "Cadete B" juega "PRIMERA CADETE · Grupo 4"
    And la ingesta del "Cadete B" está "<estado>"
    When abro la portada de mi club
    Then la fila del "Cadete B" tiene la ingesta "<estado>"

    Examples:
      | estado            |
      | Al día            |
      | Con fallos        |
      | En marcha         |
      | Sin datos todavía |
      | Desactualizada    |

  Scenario: En marcha, y la anterior tuvo fallos
    Given mi club tiene la temporada en curso
    And en la temporada en curso el "Cadete B" juega "PRIMERA CADETE · Grupo 4"
    And la ingesta del "Cadete B" está "En marcha, y la anterior falló"
    When abro la portada de mi club
    Then la fila del "Cadete B" tiene la ingesta "En marcha"
    And la fila del "Cadete B" dice "La anterior tuvo fallos"

  Scenario: Mientras llegan los equipos, «Cargando equipos…»
    Given mi club tiene la temporada en curso
    And la petición de las temporadas de mi club está retenida
    When abro la portada de mi club
    Then la portada dice "Cargando equipos…"

  Scenario: Si el servidor cae mientras pide los equipos, el error sale en el hueco de la tabla
    Given he abierto la portada de mi club con la petición de las temporadas retenida
    And el servidor está parado
    When la petición de las temporadas sale
    Then la portada dice "No se ha podido conectar con el servidor"
    And la portada ofrece "Reintentar"

  Scenario: Reintentar, con el servidor de vuelta, trae los equipos
    Given en la temporada en curso de mi club el "Cadete B" juega "PRIMERA CADETE · Grupo 4"
    And la portada de mi club enseña que no se ha podido conectar con el servidor
    And el servidor vuelve a estar en marcha
    When pulso el botón "Reintentar"
    Then la portada tiene la fila del "Cadete B"

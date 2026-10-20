# Qué temporada enseña la portada, y el selector (plan R1, decisión 5).
# Las temporadas pasadas y futuras se eligen al azar en cada pasada (la skill de escenarios, principio 9).
Feature: La temporada de la portada

  Scenario: Sin temporada en la dirección, la que está en curso
    Given mi club tiene la temporada en curso
    And mi club tiene una temporada pasada
    When abro la portada de mi club
    Then el selector de temporada tiene elegida la temporada en curso

  Scenario: Sin ninguna en curso, la más reciente, que ya terminó
    Given mi club tiene dos temporadas pasadas
    When abro la portada de mi club
    Then la portada dice que enseña la más reciente de las temporadas pasadas, terminada

  Scenario: Sin ninguna en curso, la más reciente, que aún no ha empezado
    Given mi club tiene una temporada que todavía no ha empezado
    When abro la portada de mi club
    Then la portada dice que enseña la temporada que todavía no ha empezado

  Scenario: Elegir otra temporada cambia la dirección
    Given mi club tiene la temporada en curso
    And mi club tiene una temporada pasada
    And estoy en la portada de mi club
    When elijo la temporada pasada
    Then la dirección lleva la temporada pasada

  Scenario: Elegir otra temporada enseña sus equipos
    Given mi club tiene la temporada en curso
    And en una temporada pasada de mi club juega un equipo
    And estoy en la portada de mi club
    When elijo la temporada pasada
    Then la portada tiene la fila del equipo

  Scenario: «Atrás» vuelve a la temporada anterior
    Given mi club tiene la temporada en curso
    And he cambiado la portada de mi club a una temporada pasada
    When vuelvo atrás en el navegador
    Then el selector de temporada tiene elegida la temporada en curso

  Scenario: Una temporada de la dirección que no existe
    Given mi club tiene la temporada en curso
    When abro la portada de mi club en una temporada pasada que mi club no tiene
    Then la portada dice que no hay esa temporada
    And la portada tiene el enlace "Ir a la temporada en curso"

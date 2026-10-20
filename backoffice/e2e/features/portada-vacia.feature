# La portada vacía no es un error (plan R1, decisión 6).
Feature: La portada vacía

  Scenario: El club sin temporadas
    When abro la portada de mi club
    Then la portada dice "Todavía no hay ninguna temporada."
    And la portada no tiene selector de temporada

  Scenario: La temporada sin equipos
    Given mi club tiene la temporada en curso
    When abro la portada de mi club
    Then la portada dice que no hay equipos en la temporada en curso

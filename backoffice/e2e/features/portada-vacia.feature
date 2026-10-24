# La portada vacía no es un error (plan R1, decisión 6).
Feature: La portada vacía

  @ui
  Scenario: El club sin temporadas
    When abro la portada de mi club
    Then la portada dice "Todavía no hay ninguna temporada."
    And la portada no tiene selector de temporada

  @ui
  Scenario: La temporada sin equipos
    Given mi club tiene la temporada en curso
    When abro la portada de mi club
    Then la portada dice que no hay equipos en la temporada en curso

  @ui
  Scenario: El club sin temporadas dice cómo empezar, y ofrece el alta
    When abro la portada de mi club
    Then la portada dice "Para empezar, da de alta el primer equipo. La temporada se crea desde el mismo formulario."
    And la portada tiene el enlace "Dar de alta un equipo"

  @ui
  Scenario: La temporada sin equipos ofrece el alta debajo del mensaje
    Given mi club tiene la temporada en curso
    When abro la portada de mi club
    Then el mensaje de la portada vacía tiene debajo el enlace "Dar de alta un equipo"

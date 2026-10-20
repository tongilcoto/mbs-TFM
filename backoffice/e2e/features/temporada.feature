# Qué temporada enseña la portada, y el selector (plan R1, decisión 5).
Feature: La temporada de la portada

  Scenario: Sin temporada en la dirección, la que está en curso
    Given mi club tiene la temporada en curso
    And mi club tiene la temporada "2019/20"
    When abro la portada de mi club
    Then el selector de temporada tiene elegida la temporada en curso

  Scenario: Sin ninguna en curso, la más reciente, que ya terminó
    Given mi club tiene la temporada "2019/20"
    And mi club tiene la temporada "2020/21"
    When abro la portada de mi club
    Then la portada dice "Temporada 2020/21 · terminada"

  Scenario: Sin ninguna en curso, la más reciente, que aún no ha empezado
    Given mi club tiene la temporada "2090/91"
    When abro la portada de mi club
    Then la portada dice "Temporada 2090/91 · todavía no ha empezado"

  Scenario: Elegir otra temporada cambia la dirección
    Given mi club tiene la temporada en curso
    And mi club tiene la temporada "2019/20"
    And estoy en la portada de mi club
    When elijo la temporada "2019/20"
    Then la dirección es "/?temporada=2019-20"

  Scenario: Elegir otra temporada enseña sus equipos
    Given mi club tiene la temporada en curso
    And en la temporada "2019/20" el "Juvenil A" juega "DIVISIÓN DE HONOR · Grupo 1"
    And estoy en la portada de mi club
    When elijo la temporada "2019/20"
    Then la portada tiene la fila del "Juvenil A"

  Scenario: «Atrás» vuelve a la temporada anterior
    Given mi club tiene la temporada en curso
    And he cambiado la portada de mi club a la temporada "2019/20"
    When vuelvo atrás en el navegador
    Then el selector de temporada tiene elegida la temporada en curso

  Scenario: Una temporada de la dirección que no existe
    Given mi club tiene la temporada en curso
    When abro "/?temporada=2019-20" en la web de mi club
    Then la portada dice "No hay ninguna temporada 2019/20"
    And la portada tiene el enlace "Ir a la temporada en curso"

# Si el club no se puede cargar, una página entera, sin menú (plan R1, §3.1; LLD-B §8.3).
Feature: El club que no se puede cargar

  @ui
  Scenario: El club no existe
    When abro la web de un club que no existe
    Then la página entera dice "Este club no existe. Revisa la dirección"
    And la página entera no tiene menú
    And la página entera no ofrece "Reintentar"

  @ui
  Scenario: Falta el club en la dirección
    When abro la web sin club en la dirección
    Then la página entera dice "Falta el club en la dirección"
    And la página entera dice "Por ejemplo: celtic-castilla.localhost:5174"
    And la página entera no ofrece "Reintentar"

  @ui
  Scenario: El club no está preparado
    Given mi club no tiene preparada su base de datos
    When abro la portada de mi club
    Then la página entera dice "Este club aún no está preparado. Avisa a quien lo administra"
    And la página entera no ofrece "Reintentar"

  @ui
  Scenario: El servidor está parado
    Given el servidor está parado
    When abro la portada de mi club
    Then la página entera dice "No se ha podido conectar con el servidor"
    And la página entera ofrece "Reintentar"

  @e2e
  Scenario: Reintentar, con el servidor de vuelta, abre la web
    Given la web de mi club no ha podido conectar con el servidor
    And el servidor vuelve a estar en marcha
    When pulso el botón "Reintentar"
    Then estoy en la portada

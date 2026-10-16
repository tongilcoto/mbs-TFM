# El escenario de humo del arnés (R0.11): solo comprueba que todo arranca y se habla.
Feature: La web arranca

  Scenario: La portada se abre en español
    When abro la web del club "bo-humo"
    Then veo la zona principal de la página
    And la página está en español

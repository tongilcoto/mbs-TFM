# La portada se refresca sola mientras haya algo en marcha (plan R3, decisión 5; LLD-B §2.4, DW-20).
# Cada 10 s; los límites (la pestaña oculta, los 5 minutos, que un fallo no pinte error) se prueban con Vitest y un
# reloj de mentira, porque aquí costarían minutos de espera de verdad.
Feature: La portada se refresca sola

  @e2e
  Scenario: Cuando acaba la ingesta que estaba en marcha, la portada lo enseña sin recargar
    Given en la temporada en curso de mi club juega un equipo, con su ingesta en marcha y retenida en la Federación
    And estoy en la portada de mi club
    When la Federación suelta la ingesta retenida
    Then la fila del equipo en la portada tiene la ingesta "Al día"

  @ui
  Scenario: Mientras la portada se refresca sola, no dice «Cargando…» y conserva el orden
    Given en la temporada en curso de mi club juegan tres equipos, uno con su ingesta en marcha y retenida en la Federación
    And la portada de mi club está abierta, ordenada al revés por "Equipo"
    When la Federación suelta la ingesta retenida
    Then la portada no dice "Cargando equipos…"
    And la tabla de la portada sigue ordenada al revés por "Equipo"

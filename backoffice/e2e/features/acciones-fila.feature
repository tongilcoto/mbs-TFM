# Las acciones de cada fila de la portada (plan R3, §3.1 y decisión 1; LLD-B §3.7).
# En la rebanada 3, una sola: sincronizar con la Federación. El equipo se inventa al azar en cada pasada; solo es
# fijo lo que decide la rama: que tenga competición en la temporada elegida o no.
Feature: Las acciones de cada fila de la portada

  # ── Lo que enseña cada fila ──

  @ui
  Scenario: En la portada, la fila de un equipo sin competición ofrece sincronizar con la Federación, con enlace y con icono
    Given en la temporada en curso de mi club hay un equipo inscrito sin competición
    When abro la portada de mi club
    Then la fila del equipo en la portada tiene el enlace "Sincronizar con la Federación"
    And la fila del equipo en la portada tiene la acción "Sincronizar con la Federación", con el nombre del equipo para el lector

  @ui
  Scenario: En la portada, la fila de un equipo con competición ofrece sincronizar otra
    Given en la temporada en curso de mi club juega un equipo
    When abro la portada de mi club
    Then la fila del equipo en la portada tiene la acción "Sincronizar otra competición", con el nombre del equipo para el lector

  @ui
  Scenario: En la portada, la fila de un equipo con dos competiciones tiene sus acciones una sola vez
    Given en la temporada en curso de mi club juega un equipo con dos competiciones
    When abro la portada de mi club
    Then la fila del equipo en la portada tiene una sola acción "Sincronizar otra competición"

  # ── El texto del icono ──

  @ui
  Scenario: En la portada, el icono de una acción enseña su texto al llegar con el tabulador
    Given en la temporada en curso de mi club juega un equipo
    And estoy en la portada de mi club
    When llego con el tabulador a la acción de la fila del equipo
    Then la acción de la fila del equipo enseña el texto "Sincronizar otra competición"

  @ui
  Scenario: En la portada, el icono de una acción enseña su texto al pasar el ratón
    Given en la temporada en curso de mi club juega un equipo
    And estoy en la portada de mi club
    When paso el ratón por la acción de la fila del equipo
    Then la acción de la fila del equipo enseña el texto "Sincronizar otra competición"

  @ui
  Scenario: En la portada, Escape esconde el texto del icono de una acción, y el foco se queda en él
    Given en la portada de mi club, la acción de la fila de un equipo enseña su texto porque he llegado con el tabulador
    When pulso la tecla Escape
    Then la acción de la fila del equipo no enseña su texto
    And la acción de la fila del equipo tiene el foco

  # ── Adónde llevan ──

  @e2e
  Scenario: En la portada, el enlace de un equipo sin competición lleva a sincronizar ese equipo
    Given en la temporada en curso de mi club hay un equipo inscrito sin competición
    And estoy en la portada de mi club
    When pulso el enlace "Sincronizar con la Federación" de la fila del equipo
    Then se abre el paso 1 de sincronizar el equipo de mi club inscrito sin competición

  @e2e
  Scenario: En la portada, el icono de un equipo con competición lleva a sincronizar ese equipo
    Given en la temporada en curso de mi club juega un equipo
    And estoy en la portada de mi club
    When pulso la acción "Sincronizar otra competición" de la fila del equipo
    Then se abre el paso 1 de sincronizar el equipo de mi club que juega

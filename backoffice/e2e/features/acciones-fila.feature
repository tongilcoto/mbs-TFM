# Las acciones de cada fila de la portada (plan R3, §3.1 y decisión 1; LLD-B §3.7).
# En la rebanada 3, sincronizar con la Federación; en la 4, el nombre del equipo lleva a su ficha (ficha.feature) y
# relanzar la ingesta, en la celda de la ingesta de cada competición (plan R4, §3.1 y decisión 7). El equipo se
# inventa al azar en cada pasada; solo es fijo lo que decide la rama: que tenga competición en la temporada elegida
# o no, y cómo está su ingesta.
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

  # ── Relanzar la ingesta (plan R4, decisión 7) ──

  @ui
  Scenario: En la portada, la celda de la ingesta de una competición ofrece volver a traer sus datos
    Given en la temporada en curso de mi club juega un equipo
    When abro la portada de mi club
    Then la celda de la ingesta del equipo tiene la acción "Volver a traer los datos de la Federación", con el nombre de la competición para el lector

  @ui
  Scenario: En la portada, la fila de un equipo sin competición no ofrece volver a traer datos
    Given en la temporada en curso de mi club hay un equipo inscrito sin competición
    When abro la portada de mi club
    Then la fila del equipo en la portada no tiene la acción "Volver a traer los datos de la Federación"

  @e2e
  Scenario: En la portada, volver a traer los datos de una competición con fallos la deja al día
    Given en la temporada en curso de mi club juega un equipo
    And la ingesta de la competición del equipo está "Con fallos"
    And estoy en la portada de mi club
    When pulso la acción "Volver a traer los datos de la Federación" de la celda de la ingesta del equipo
    Then la fila del equipo en la portada tiene la ingesta "Al día"

  @e2e
  Scenario: En la portada, volver a traer los datos de una competición cuya Federación falla la deja con fallos
    Given en la temporada en curso de mi club juega un equipo
    And la Federación contesta con un error a la competición del equipo
    And estoy en la portada de mi club
    When pulso la acción "Volver a traer los datos de la Federación" de la celda de la ingesta del equipo
    Then la fila del equipo en la portada tiene la ingesta "Con fallos"

  @ui
  Scenario: En la portada, mientras se vuelven a traer los datos, la celda dice «En marcha» y su acción está bloqueada
    Given en la temporada en curso de mi club juega un equipo
    And la Federación va a retener la próxima petición del calendario de la competición del equipo
    And estoy en la portada de mi club
    When pulso la acción "Volver a traer los datos de la Federación" de la celda de la ingesta del equipo
    Then la fila del equipo en la portada tiene la ingesta "En marcha"
    And la acción "Volver a traer los datos de la Federación" de la celda de la ingesta del equipo está bloqueada

# La pestaña Resultados de la ficha del equipo (plan R4, §3.3; decisiones 1, 2 y 6).
# Los datos, de una competición con jornadas jugadas que se inventa la federación falsa (ver ficha.feature). Lo que se
# compara (marcadores, puestos, puntos) se lee de la Federación falsa, no se escribe en el escenario.
#
# Los partidos aplazados y suspendidos NO tienen escenario: su estado sale del acta (D-57), y la ingesta todavía no la
# lee; hoy todo partido es «finalizado» o «programado», según tenga marcador. Cómo se ven, con Vitest.
#
# Vocabulario de los pasos:
# - «la tabla de resultados»: la de la pestaña Resultados.
# - «un partido jugado», «un partido por jugar con hora», «un partido por jugar sin hora»: una fila de esa tabla.
Feature: Los resultados de un equipo

  @ui
  Scenario: La tabla de resultados tiene todos los partidos del equipo, en orden de jornada
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro la ficha del equipo de mi club que ha jugado
    Then la tabla de resultados tiene un partido por cada jornada en la que juega el equipo
    And la tabla de resultados está en orden de jornada

  @ui
  Scenario: En la tabla de resultados, un partido jugado, columna a columna
    Given estoy en la ficha del equipo de mi club que ha jugado
    When miro en la tabla de resultados un partido jugado
    Then el partido tiene su jornada, su fecha y los dos equipos
    And el partido tiene el marcador de la Federación
    And el partido tiene la letra del resultado del equipo: V, E o D
    And el partido tiene el puesto, los puntos, los ganados, empatados y perdidos, y la diferencia de goles del equipo tras esa jornada
    And cada equipo del partido tiene a su lado su puesto tras esa jornada

  @ui
  Scenario: En la tabla de resultados, un partido por jugar con hora tiene la hora y los puestos de hoy
    Given estoy en la ficha del equipo de mi club que ha jugado
    When miro en la tabla de resultados un partido por jugar con hora
    Then el partido tiene la hora en lugar del marcador
    And el partido no tiene la línea del equipo
    And cada equipo del partido tiene a su lado su puesto de hoy

  @ui
  Scenario: En la tabla de resultados, un partido por jugar sin hora dice «por fijar»
    Given estoy en la ficha del equipo de mi club que ha jugado
    When miro en la tabla de resultados un partido por jugar sin hora
    Then el partido dice "por fijar" en lugar del marcador

  @ui
  Scenario: En la tabla de resultados, los equipos se llaman por el nombre de su club y su letra
    Given mi club tiene un nombre corto
    And en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro la ficha del equipo de mi club que ha jugado
    Then en la tabla de resultados, el equipo de mi club se llama con el nombre de mi club, no el corto, y su letra
    And en la tabla de resultados, cada rival se llama con el nombre de su club y su letra

  @e2e
  Scenario: En la tabla de resultados, el icono de un partido abre su jornada
    Given estoy en la ficha del equipo de mi club que ha jugado
    When pulso el icono "Ver la jornada y la clasificación" de un partido jugado
    Then estoy en la jornada de ese partido, en la pantalla de su competición

  # ── Sin partidos ──

  @ui
  Scenario: La pestaña Resultados de un equipo sin sincronizar dice que aún no tiene partidos
    Given en la temporada en curso de mi club hay un equipo inscrito sin competición
    When abro la ficha del equipo de mi club inscrito sin competición
    Then la pestaña Resultados dice "Este equipo aún no tiene partidos."
    And la pestaña Resultados tiene el enlace "Sincronizar con la Federación"

  @ui
  Scenario: La pestaña Resultados de un equipo recién sincronizado dice que está trayendo el calendario
    Given en la temporada en curso de mi club juega un equipo, con su ingesta en marcha y retenida en la Federación
    When abro la ficha del equipo
    Then la pestaña Resultados dice "Trayendo el calendario de la Federación…"

  @e2e
  Scenario: Cuando acaba la ingesta que estaba en marcha, la pestaña Resultados enseña los partidos sin recargar
    Given en la temporada en curso de mi club juega un equipo, con su ingesta en marcha y retenida en la Federación
    And estoy en la ficha del equipo
    When la Federación suelta la ingesta retenida
    Then la tabla de resultados tiene un partido por cada jornada en la que juega el equipo

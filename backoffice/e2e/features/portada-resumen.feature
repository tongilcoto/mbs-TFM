# La portada del boceto: en cada equipo, su posición, su racha, su último partido y su próximo (plan R5, §3;
# decisiones 2, 3, 5 y 6). Los datos los manda el servidor en la lista de equipos de la temporada (D-113).
#
# Las competiciones se las inventa la federación falsa, como en ficha.feature: «con jornadas jugadas», las primeras
# jornadas jugadas (entre 3 y 5, al azar) y el resto por jugar. Lo que se compara (puestos, marcadores, rivales,
# fechas) se lee de la Federación falsa, no se escribe en el escenario.
#
# Lo que no tiene escenario, y por qué:
# - Un equipo con dos competiciones (liga y copa): el enganche solo da una; cada competición es su fila desde la R1.
# - La ingesta con fallos con datos ya traídos: se enseña lo que hay, igual que «Al día»; lo cubre portada.feature.
# - Los colores de la racha y del resultado: son los de la R4, y axe mira su contraste en los dos modos.
#
# Vocabulario de los pasos:
# - «la fila del equipo en la portada»: la de su competición.
# - «la posición», «la racha», «el último partido», «el próximo partido»: las cuatro columnas nuevas de esa fila.
# - «un cuadro de la racha»: el de una jornada, con su número.
Feature: El resumen de cada equipo en la portada

  # ── La posición ──

  @ui
  Scenario: La posición es el puesto del equipo tras la última jornada jugada
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro la portada de mi club
    Then la posición del equipo en la portada es su puesto tras la última jornada jugada

  # ── La racha ──

  @ui
  Scenario: La racha tiene las últimas jornadas jugadas, hasta cinco, la más reciente primero
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro la portada de mi club
    Then la racha del equipo en la portada tiene un cuadro por cada jornada jugada, hasta cinco
    And la racha del equipo en la portada va de la jornada más reciente a la más antigua
    And cada cuadro de la racha del equipo en la portada dice el número de su jornada
    And cada cuadro de la racha del equipo en la portada dice al lector si fue victoria, empate o derrota, y en qué jornada

  @ui
  Scenario: La jornada en la que el equipo descansó sale en la racha como un cuadro vacío
    Given en la temporada en curso de mi club juega un equipo que descansó en una de las jornadas jugadas
    When abro la portada de mi club
    Then la racha del equipo en la portada tiene un cuadro vacío en la jornada en la que descansó
    And el cuadro vacío de la racha del equipo en la portada dice al lector "Descansó en la jornada" y su número

  # ── El último partido ──

  @ui
  Scenario: El último partido, con su resultado, dónde se jugó, el marcador y el rival
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro la portada de mi club
    Then el último partido del equipo en la portada es el de la última jornada jugada
    And el último partido tiene la letra del resultado del equipo: V, E o D
    And el último partido dice si el equipo jugó en casa o fuera
    And el último partido tiene el marcador de la Federación, el local primero
    And el último partido tiene el rival, con el nombre de su club y su letra
    And el último partido tiene a la izquierda del rival el puesto con el que llegó, el de la jornada anterior

  @ui
  Scenario: Si el equipo descansó en la última jornada jugada, el último partido es el de antes
    Given en la temporada en curso de mi club juega un equipo que descansó en la última jornada jugada
    When abro la portada de mi club
    Then el último partido del equipo en la portada es el de la jornada anterior a la del descanso

  # ── El próximo partido ──

  @ui
  Scenario: El próximo partido, con su fecha y hora, dónde se juega y el rival
    Given en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas
    When abro la portada de mi club
    Then el próximo partido del equipo en la portada es el de la jornada en curso
    And el próximo partido tiene el día de la semana, la fecha y la hora
    And el próximo partido dice si el equipo juega en casa o fuera
    And el próximo partido tiene el rival, con el nombre de su club y su letra
    And el próximo partido tiene a la izquierda del rival su puesto de hoy

  @ui
  Scenario: Un próximo partido sin hora dice «hora por fijar»
    Given en la temporada en curso de mi club juega un equipo cuyo próximo partido no tiene hora
    When abro la portada de mi club
    Then el próximo partido del equipo en la portada dice "hora por fijar"

  @ui
  Scenario: Si el equipo descansa en la próxima jornada, el próximo partido lo dice
    Given en la temporada en curso de mi club juega un equipo que descansa en la próxima jornada
    When abro la portada de mi club
    Then el próximo partido del equipo en la portada dice que descansa, y en qué jornada

  # ── Los que no tienen todo ──

  @ui
  Scenario: Un equipo inscrito sin competición no tiene resumen
    Given en la temporada en curso de mi club hay un equipo inscrito sin competición
    When abro la portada de mi club
    Then la fila del equipo en la portada no tiene posición, racha, último partido ni próximo partido

  @ui
  Scenario: Una competición sin jornadas jugadas solo tiene el próximo partido
    Given en la temporada en curso de mi club juega un equipo en una competición sin jornadas jugadas
    When abro la portada de mi club
    Then la fila del equipo en la portada no tiene posición, racha ni último partido
    And la fila del equipo en la portada tiene el próximo partido, el de la primera jornada

  @ui
  Scenario: Una competición con todas las jornadas jugadas no tiene próximo partido
    Given en la temporada en curso de mi club juega un equipo en una competición con todas las jornadas jugadas
    When abro la portada de mi club
    Then la fila del equipo en la portada tiene el último partido, el de la última jornada
    And la fila del equipo en la portada no tiene próximo partido

  # ── Adónde lleva ──

  @e2e
  Scenario: Un cuadro de la racha abre su jornada
    Given estoy en la portada de mi club, con un equipo que ha jugado
    When pulso en la portada un cuadro de la racha del equipo
    Then estoy en la jornada de ese cuadro, en la pantalla de la competición del equipo

  @e2e
  Scenario: El próximo partido abre su jornada
    Given estoy en la portada de mi club, con un equipo que ha jugado
    When pulso en la portada el próximo partido del equipo
    Then estoy en la jornada del próximo partido, en la pantalla de la competición del equipo

  # ── Ordenar ──

  @ui
  Scenario: Ordenar por la posición pone primero al mejor clasificado, y al final los que no tienen puesto
    Given en la temporada en curso de mi club juegan tres equipos con jornadas jugadas, en puestos distintos, y uno sin competición
    And estoy en la portada de mi club
    When ordeno la tabla de la portada por "Posición"
    Then la tabla de la portada tiene los equipos de mejor a peor puesto
    And la tabla de la portada tiene al final el equipo sin puesto

  # ── Ponerse al día ──

  @e2e
  Scenario: Cuando acaba la ingesta que estaba en marcha, la portada enseña el resumen sin recargar
    Given en la temporada en curso de mi club juega un equipo recién sincronizado en una competición con jornadas jugadas, con su primera ingesta retenida en la Federación
    And estoy en la portada de mi club
    When la Federación suelta la ingesta retenida
    Then la posición del equipo en la portada es su puesto tras la última jornada jugada

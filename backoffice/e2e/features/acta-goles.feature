# Los goles del acta de un partido (plan R7, decisiones 5d y 7, y R7.3 P5 y P6; D-09, D-52, D-131, D-135, D-137).
# Los goles que hay antes de cada escenario se apuntan por la API (`createGoal`), y los de la Federación, con la
# ingesta. Los jugadores, al azar.
#
# Lo que no tiene escenario, y por qué:
# - Lo que el servidor rechaza y la web no ofrece (un penalti fuera del área o con lado del remate, un gol antes de
#   la hora de comienzo): pruebas del servidor.
# - Un gol de la Federación sin cuadre con el marcador (D-53): no se comprueba nada.
# - La temporada archivada: aún no se abre en la web; lo dice la cabecera de acta.feature.
#
# Vocabulario de los pasos (además del de acta.feature):
# - «la tabla de goles»: la sección Goles del acta.
# - «el formulario del gol»: el diálogo que abren «+ Añadir gol» y el icono «Completar» de un gol.
# - «lo obligatorio»: el equipo que marca; todo lo demás es opcional (R7.3, P5).
# - «el desglose»: tipo de jugada, asistencia, zona, lado del ataque, lado del remate y parte del cuerpo.
# - «los goles apuntados»: los guardados, leídos por la API (`listGoals` del partido).
# - «un gol de la Federación»: uno que cargó la ingesta con el acta, o que apuntó el club y la carga dio por el mismo;
#   lo guarda el gol (D-137). «Un gol que apuntó el club», uno que el acta no traía.
# - «la convocatoria de la página»: la plantilla del equipo y los refuerzos apuntados, como en acta-convocatoria.
Feature: Los goles del acta

  # ── Lo que hay al entrar ──

  @ui
  Scenario: La tabla de goles tiene de cada gol su minuto, su goleador, su tipo, su desglose y su comentario
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay apuntado un gol del club con todos los datos
    When abro el acta del partido jugado sin acta
    Then la fila del gol tiene el minuto, el goleador y el tipo de jugada apuntados
    And la fila del gol tiene el desglose apuntado
    And la fila del gol tiene el comentario apuntado

  @ui
  Scenario: Un gol sin tipo dice que falta elegirlo
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay apuntado un gol del club sin tipo de jugada
    When abro el acta del partido jugado sin acta
    Then la fila del gol dice que el tipo está sin elegir

  @ui
  Scenario: Un gol del rival dice «Jugador rival» en el goleador
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay apuntado un gol del rival
    When abro el acta del partido jugado sin acta
    Then la fila del gol dice "Jugador rival" y el nombre del rival

  @ui
  Scenario: Un comentario largo se corta en la tabla y se lee entero al pasar el ratón
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay apuntado un gol con un comentario más largo que su columna
    And estoy en el acta del partido jugado sin acta
    When paso el ratón por el comentario del gol
    Then la tabla de goles enseña el comentario entero

  # ── Apuntar un gol ──

  @e2e
  Scenario: Un gol del club con solo lo obligatorio se guarda
    Given el equipo tiene un partido jugado sin acta
    And en el formulario de un gol nuevo del acta he dejado el equipo del club y nada más
    When pulso "Guardar" en el formulario del gol
    Then la tabla de goles tiene un gol más, del equipo del club, sin goleador, sin minuto y sin tipo
    And los goles apuntados tienen ese gol, sin desglose ni comentario

  @e2e
  Scenario Outline: Un gol con solo <dato> lo guarda
    Given el equipo tiene un partido jugado sin acta
    And en el formulario de un gol nuevo del acta he rellenado solo <dato>
    When pulso "Guardar" en el formulario del gol
    Then la fila del gol nuevo tiene <dato> que rellené
    And los goles apuntados tienen el gol nuevo con <dato> que rellené y nada más

    Examples:
      | dato                     |
      | el goleador              |
      | el minuto                |
      | el tipo de jugada        |
      | la asistencia y de quién |
      | la zona                  |
      | el lado del ataque       |
      | el lado del remate       |
      | la parte del cuerpo      |
      | el comentario            |

  @e2e
  Scenario: Un gol con todos los datos los guarda
    Given el equipo tiene un partido jugado sin acta
    And en el formulario de un gol nuevo del acta he rellenado todos los datos
    When pulso "Guardar" en el formulario del gol
    Then la fila del gol nuevo tiene todos los datos que rellené
    And los goles apuntados tienen el gol nuevo con todos los datos que rellené

  @e2e
  Scenario: Un gol del rival se guarda sin goleador
    Given el equipo tiene un partido jugado sin acta
    And en el formulario de un gol nuevo del acta he elegido el equipo rival
    When pulso "Guardar" en el formulario del gol
    Then la tabla de goles tiene un gol más, del rival, con "Jugador rival"
    And los goles apuntados tienen ese gol del rival, sin goleador

  @e2e
  Scenario Outline: Un gol en propia puerta <cuál> se guarda a nombre de <quién> y no le suma
    Given el equipo tiene un partido jugado sin acta
    And en el formulario de un gol nuevo del acta he elegido <el equipo> y marcado «En propia puerta»
    When pulso "Guardar" en el formulario del gol
    Then los goles apuntados tienen un gol en propia puerta del equipo <el equipo que marca>, a nombre de <quién>
    And la fila del gol dice que fue en propia puerta

    Examples:
      | cuál       | el equipo         | el equipo que marca | quién                              |
      | a favor    | el equipo del club | del club            | nadie, porque lo mete un rival     |
      | en contra  | el equipo rival   | rival               | el jugador del club que lo mete    |

  @ui
  Scenario: En un gol del rival, el goleador es «Jugador rival» y está bloqueado
    Given el equipo tiene un partido jugado sin acta
    And estoy en el formulario de un gol nuevo del acta
    When elijo el equipo rival en el formulario del gol
    Then el goleador del formulario dice "Jugador rival" y está bloqueado

  @ui
  Scenario: En propia puerta, el formulario no pregunta el tipo de jugada ni la asistencia
    Given el equipo tiene un partido jugado sin acta
    And estoy en el formulario de un gol nuevo del acta
    When marco «En propia puerta» en el formulario del gol
    Then el formulario del gol no tiene el tipo de jugada
    And el formulario del gol no tiene la asistencia

  @ui
  Scenario: En un penalti, la zona no ofrece «Fuera del área» y no hay lado del remate
    Given el equipo tiene un partido jugado sin acta
    And estoy en el formulario de un gol nuevo del acta
    When elijo «Penalti» en el tipo de jugada del formulario del gol
    Then la zona del formulario no ofrece "Fuera del área"
    And el formulario del gol no tiene el lado del remate

  @ui
  Scenario: En un gol de jugada, la zona ofrece «Fuera del área» y hay lado del remate
    Given el equipo tiene un partido jugado sin acta
    And estoy en el formulario de un gol nuevo del acta
    When elijo «De jugada» en el tipo de jugada del formulario del gol
    Then la zona del formulario ofrece "Fuera del área"
    And el formulario del gol tiene el lado del remate

  @ui
  Scenario: La lista del goleador tiene a toda la convocatoria de la página
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay convocados, no convocados y un refuerzo apuntado
    When abro el formulario de un gol nuevo del acta
    Then la lista del goleador tiene a todos los de la convocatoria, en su orden, también los no convocados y el refuerzo

  # ── Corregir, cancelar y borrar ──

  @e2e
  Scenario: Corregir el tipo de un gol lo cambia
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay apuntado un gol del club con un tipo de jugada
    And en el formulario de ese gol he elegido otro tipo de jugada
    When pulso "Guardar" en el formulario del gol
    Then la fila del gol tiene el tipo de jugada nuevo
    And los goles apuntados tienen el gol con el tipo de jugada nuevo

  @e2e
  Scenario: Cancelar un gol nuevo con datos no guarda nada
    Given el equipo tiene un partido jugado sin acta
    And en el formulario de un gol nuevo del acta he rellenado el goleador y el minuto
    When pulso "Cancelar" en el formulario del gol
    Then la tabla de goles tiene los mismos goles que antes
    And los goles apuntados son los mismos que antes

  @e2e
  Scenario: Borrar un gol lo quita del acta
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay apuntados dos goles
    And estoy en el acta del partido jugado sin acta
    When pulso el icono "Borrar" de uno de los goles
    Then la tabla de goles no tiene ese gol
    And los goles apuntados tienen solo el otro gol

  # ── Con el acta cargada ──

  @ui
  Scenario: En un gol de la Federación, el equipo, el goleador, la propia puerta y el minuto están bloqueados
    Given el equipo tiene un partido con el acta cargada, con un gol del club que no fue penalti
    When abro el formulario de ese gol de la Federación
    Then el equipo, el goleador, «En propia puerta» y el minuto del formulario están bloqueados
    And el desglose y el comentario del formulario están sin bloquear

  @ui
  Scenario: Un gol de la Federación que no fue penalti no ofrece «Penalti»
    Given el equipo tiene un partido con el acta cargada, con un gol del club que no fue penalti
    When abro el formulario de ese gol de la Federación
    Then el tipo de jugada del formulario no ofrece "Penalti"
    And el formulario del gol dice que la Federación solo dice que no fue penalti

  @ui
  Scenario: En un penalti de la Federación, el tipo de jugada está bloqueado
    Given el equipo tiene un partido con el acta cargada, con un penalti
    When abro el formulario del penalti de la Federación
    Then el tipo de jugada del formulario dice "Penalti" y está bloqueado

  @e2e
  Scenario: Elegir el tipo de un gol de la Federación lo guarda
    Given el equipo tiene un partido con el acta cargada, con un gol del club que no fue penalti
    And en el formulario de ese gol de la Federación he elegido un tipo de jugada
    When pulso "Guardar" en el formulario del gol
    Then la fila del gol tiene el tipo de jugada elegido
    And los goles apuntados tienen el gol con el tipo elegido y con el goleador y el minuto de la Federación

  @ui
  Scenario: Con el acta cargada no se añaden goles ni se borran los de la Federación
    Given el equipo tiene un partido con el acta cargada, con goles
    When abro el acta del partido con el acta cargada
    Then la sección de goles no tiene el botón "+ Añadir gol"
    And ningún gol de la Federación tiene el icono "Borrar"

  @ui
  Scenario: Con el acta cargada, un gol que apuntó el club tiene el icono «Borrar»
    Given el equipo tiene un partido con el acta cargada, y un gol que apuntó el club y que el acta no traía
    When abro el acta del partido con el acta cargada
    Then el gol que apuntó el club tiene el icono "Borrar"

# La convocatoria del acta de un partido (plan R7, decisiones 3, 5 y 12, y R7.3 P3, P4, P7, P9 y P10; D-129, D-132,
# D-134). Los jugadores se inventan al azar y se dan de alta por la API (`createPlayer`); lo apuntado antes de cada
# escenario, también por la API (`createAppearance`), nunca por la pantalla que se prueba.
#
# Lo que no tiene escenario, y por qué:
# - Lo que el servidor rechaza y la web no ofrece (un «Jugado» antes de la hora de comienzo, pasar entre estados que
#   la tabla de la decisión 5b no permite): pruebas del servidor.
# - Los bordes de los minutos (1 y 120): pruebas de piezas; aquí, un caso de cada lado.
# - Cómo carga la convocatoria la ingesta: acta-federacion.feature.
# - La temporada archivada: aún no se abre en la web; lo dice la cabecera de acta.feature.
#
# Vocabulario de los pasos (además del de acta.feature):
# - «la convocatoria»: la sección Convocatoria del acta. Tiene una fila por cada jugador de la plantilla del equipo
#   en esa temporada y por cada refuerzo apuntado.
# - «lo apuntado»: las convocatorias guardadas, leídas por la API (`listAppearances` del partido).
# - Los estados: «Convocado» (antes de la hora de comienzo) y «Convocado sin minutos» (después) son el mismo estado
#   guardado; «Jugado», «Baja médica» y «Sancionado»; y «No convocado» es no tener nada apuntado.
# - «marcar» a un jugador: pulsar la casilla de su fila.
# - «un refuerzo»: un jugador de la plantilla de otro equipo de mi club en la misma temporada.
# - «la convocatoria del acta»: la que trajo la Federación, tal como llegó, que guarda el partido (`getMatch`).
# - «el dorsal del acta» y «el dorsal de la plantilla»: en estos escenarios, siempre distintos.
Feature: La convocatoria del acta

  # ── Lo que hay al entrar ──

  @ui
  Scenario: La convocatoria tiene a toda la plantilla, por dorsal, y después a los que no tienen dorsal, por nombre
    Given el equipo tiene un partido por jugar
    And la plantilla del equipo tiene jugadores con dorsal y jugadores sin dorsal, en un orden de alta distinto
    When abro el acta del partido por jugar
    Then la convocatoria tiene una fila por cada jugador de la plantilla
    And la convocatoria tiene primero a los que tienen dorsal, del más bajo al más alto
    And la convocatoria tiene después a los que no tienen dorsal, por orden alfabético

  @ui
  Scenario: La cabecera de la convocatoria cuenta a los jugadores de cada estado
    Given el equipo tiene un partido por jugar
    And en el partido por jugar hay apuntados algunos convocados, alguno de baja médica y alguno sancionado
    When abro el acta del partido por jugar
    Then la cabecera de la convocatoria dice cuántos convocados hay
    And la cabecera de la convocatoria dice cuántos están de baja médica o sancionados
    And la cabecera de la convocatoria dice cuántos están sin convocar

  @ui
  Scenario Outline: Antes del partido, una fila «<estado>» tiene <lo que tiene>
    Given el equipo tiene un partido por jugar
    And en el partido por jugar hay un jugador «<estado>»
    When abro el acta del partido por jugar
    Then la fila de ese jugador tiene <lo que tiene>
    And la fila de ese jugador no tiene <lo que no tiene>

    Examples:
      | estado       | lo que tiene                                                 | lo que no tiene                        |
      | No convocado | la casilla y las opciones «Baja médica» y «Sancionado»       | iconos de acción                       |
      | Convocado    | el icono «Anular»                                            | la casilla ni las opciones de apuntar  |
      | Baja médica  | el icono «Anular»                                            | la casilla ni las opciones de apuntar  |
      | Sancionado   | el icono «Anular»                                            | la casilla ni las opciones de apuntar  |

  # ── Antes del partido ──

  @e2e
  Scenario: «Apuntar» deja «Convocado» a los marcados
    Given el equipo tiene un partido por jugar
    And en el acta del partido por jugar he marcado a dos jugadores sin convocar
    When pulso "Apuntar" en la convocatoria
    Then las filas de los dos jugadores dicen "Convocado"
    And lo apuntado tiene a los dos jugadores, convocados sin minutos

  @e2e
  Scenario Outline: «Apuntar» deja «<estado>» al marcado con ese «Apuntar como»
    Given el equipo tiene un partido por jugar
    And en el acta del partido por jugar he elegido «<estado>» en la fila de un jugador sin convocar
    When pulso "Apuntar" en la convocatoria
    Then la fila del jugador dice "<estado>"
    And lo apuntado tiene al jugador con el estado «<estado>»

    Examples:
      | estado      |
      | Baja médica |
      | Sancionado  |

  @ui
  Scenario: Elegir un «Apuntar como» marca la casilla de su fila
    Given el equipo tiene un partido por jugar
    And estoy en el acta del partido por jugar
    When elijo «Baja médica» en la fila de un jugador sin convocar
    Then la casilla de la fila del jugador está marcada

  @ui
  Scenario: Pulsar otra vez el «Apuntar como» elegido lo deja sin elegir
    Given el equipo tiene un partido por jugar
    And en el acta del partido por jugar he elegido «Sancionado» en la fila de un jugador sin convocar
    When pulso otra vez «Sancionado» en la fila del jugador
    Then ninguna opción de «Apuntar como» está elegida en la fila del jugador

  @ui
  Scenario: Sin nadie marcado, «Apuntar» está bloqueado
    Given el equipo tiene un partido por jugar
    When abro el acta del partido por jugar
    Then el botón "Apuntar" de la convocatoria está bloqueado

  @e2e
  Scenario: «Anular» a un convocado lo deja sin convocar
    Given el equipo tiene un partido por jugar
    And en el partido por jugar hay un jugador «Convocado»
    And estoy en el acta del partido por jugar
    When pulso el icono "Anular" en la fila del jugador convocado
    Then la fila del jugador dice "No convocado"
    And lo apuntado no tiene al jugador

  @e2e
  Scenario Outline: Un refuerzo apuntado <cuándo> queda «<estado>», con su equipo
    Given el equipo tiene <un partido>
    And en el acta de <ese partido> he elegido un refuerzo en el buscador de "+ De otro equipo del club"
    When pulso "Apuntar" en el buscador de "+ De otro equipo del club"
    Then la convocatoria tiene una fila del refuerzo que dice "<estado>" y el nombre de su equipo
    And lo apuntado tiene al refuerzo, convocado sin minutos, con el equipo del partido

    Examples:
      | cuándo                        | un partido                 | ese partido                | estado                |
      | antes de la hora de comienzo  | un partido por jugar       | el partido por jugar       | Convocado             |
      | después de la hora de comienzo | un partido jugado sin acta | el partido jugado sin acta | Convocado sin minutos |

  @ui
  Scenario: El buscador de «+ De otro equipo del club» ofrece solo jugadores de otras plantillas del club
    Given el equipo tiene un partido por jugar
    And otro equipo de mi club tiene jugadores en la plantilla de la temporada en curso
    And en el acta del partido por jugar he abierto el buscador de "+ De otro equipo del club"
    When escribo en el buscador parte del nombre de un jugador de mi club
    Then el buscador ofrece solo jugadores de la plantilla de otro equipo de mi club en la temporada en curso

  # ── Desde la hora de comienzo, sin acta ──

  @ui
  Scenario Outline: Un convocado se rotula «<rótulo>» <cuándo>
    Given el equipo tiene <un partido>
    And en <ese partido> hay un jugador convocado
    When abro el acta de <ese partido>
    Then la fila del jugador dice "<rótulo>"

    Examples:
      | rótulo                | cuándo                         | un partido                 | ese partido                |
      | Convocado             | antes de la hora de comienzo   | un partido por jugar       | el partido por jugar       |
      | Convocado sin minutos | desde la hora de comienzo      | un partido jugado sin acta | el partido jugado sin acta |

  @ui
  Scenario Outline: Desde la hora de comienzo, una fila «<estado>» tiene <acciones>
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay un jugador «<estado>»
    When abro el acta del partido jugado sin acta
    Then la fila de ese jugador tiene <acciones>

    Examples:
      | estado                | acciones                                                             |
      | Convocado sin minutos | la casilla y los iconos «Ha jugado» y «Anular»                        |
      | Jugado                | solo el icono «Anular»                                                |
      | Baja médica           | solo el icono «Anular»                                                |
      | Sancionado            | solo el icono «Anular»                                                |
      | No convocado          | la casilla y las opciones «Baja médica» y «Sancionado», sin iconos   |

  @e2e
  Scenario: «Ha jugado» deja «Jugado» a los marcados
    Given el equipo tiene un partido jugado sin acta
    And en el acta del partido jugado sin acta he marcado a dos jugadores «Convocado sin minutos»
    When pulso "Ha jugado" en la convocatoria
    Then las filas de los dos jugadores dicen "Jugado"
    And lo apuntado tiene a los dos jugadores como jugado, sin minutos

  @e2e
  Scenario: El icono «Ha jugado» de una fila la deja «Jugado»
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay un jugador «Convocado sin minutos»
    And estoy en el acta del partido jugado sin acta
    When pulso el icono "Ha jugado" en la fila del jugador
    Then la fila del jugador dice "Jugado"
    And lo apuntado tiene al jugador como jugado

  @e2e
  Scenario Outline: «Anular» a uno «<estado>» lo deja «<estado final>»
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay un jugador «<estado>»
    And estoy en el acta del partido jugado sin acta
    When pulso el icono "Anular" en la fila del jugador
    Then la fila del jugador dice "<estado final>"
    And lo apuntado tiene al jugador <cómo>

    Examples:
      | estado                | estado final          | cómo                     |
      | Convocado sin minutos | No convocado          | no                       |
      | Jugado                | Convocado sin minutos | convocado sin minutos    |
      | Baja médica           | No convocado          | no                       |
      | Sancionado            | No convocado          | no                       |

  @e2e
  Scenario: «Anular» a un «Jugado» con minutos le quita los minutos
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay un jugador «Jugado» con minutos
    And estoy en el acta del partido jugado sin acta
    When pulso el icono "Anular" en la fila del jugador
    Then la fila del jugador no tiene caja de minutos
    And lo apuntado tiene al jugador convocado sin minutos, sin minutos

  @ui
  Scenario: «Ha jugado» y «Apuntar» cuentan cada uno a los marcados que les tocan
    Given el equipo tiene un partido jugado sin acta
    And en el acta del partido jugado sin acta he marcado a dos jugadores «Convocado sin minutos»
    When marco a un jugador sin convocar
    Then el botón "Ha jugado" de la convocatoria dice que cuenta a 2
    And el botón "Apuntar" de la convocatoria dice que cuenta a 1

  # ── Los minutos ──

  @ui
  Scenario: Solo las filas «Jugado» tienen caja de minutos
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay jugadores en cada estado
    When abro el acta del partido jugado sin acta
    Then las filas «Jugado» tienen caja de minutos
    And las demás filas no tienen caja de minutos

  @e2e
  Scenario: Los minutos escritos en un «Jugado» se guardan
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay un jugador «Jugado» sin minutos
    And estoy en el acta del partido jugado sin acta
    When escribo unos minutos entre 1 y 120 en la caja de minutos del jugador
    Then lo apuntado tiene al jugador como jugado, con esos minutos

  @ui
  Scenario Outline: Unos minutos <cuáles> no se guardan, y la caja dice por qué
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay un jugador «Jugado» sin minutos
    And estoy en el acta del partido jugado sin acta
    When escribo <minutos> en la caja de minutos del jugador
    Then la caja de minutos del jugador dice que van de 1 a 120
    And lo apuntado tiene al jugador como jugado, sin minutos

    Examples:
      | cuáles         | minutos |
      | a cero         | 0       |
      | de más de 120  | 121     |

  # ── Con el acta cargada ──

  @ui
  Scenario: Con el acta cargada, la convocatoria avisa de que es la del acta y se puede corregir
    Given el equipo tiene un partido con el acta cargada
    When abro el acta del partido con el acta cargada
    Then la convocatoria tiene un recuadro que dice que es la del acta de la Federación, que se puede corregir y que lo cambiado deja de coincidir con el acta oficial

  @ui
  Scenario: Sin el acta cargada, la convocatoria no tiene el recuadro del acta
    Given el equipo tiene un partido jugado sin acta
    When abro el acta del partido jugado sin acta
    Then la convocatoria no tiene el recuadro del acta de la Federación

  @ui
  Scenario: Con el acta cargada, el dorsal de cada fila es el del acta
    Given el equipo tiene un partido con el acta cargada, con dorsales del acta distintos de los de la plantilla
    When abro el acta del partido con el acta cargada
    Then cada fila de un jugador del acta tiene el dorsal del acta

  @ui
  Scenario: Sin el acta cargada, el dorsal de cada fila es el de la plantilla
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay jugadores convocados con dorsal en la plantilla
    When abro el acta del partido jugado sin acta
    Then cada fila tiene el dorsal de la plantilla

  @e2e
  Scenario: Con el acta cargada, «Ha jugado» deja «Jugado» a un convocado sin minutos del acta
    Given el equipo tiene un partido con el acta cargada
    And estoy en el acta del partido con el acta cargada
    When pulso el icono "Ha jugado" en la fila de un jugador que el acta trajo «Convocado sin minutos»
    Then la fila del jugador dice "Jugado"
    And lo apuntado tiene al jugador como jugado

  @ui
  Scenario Outline: Una fila <cambiada> lleva la marca «Cambiado por el club»
    Given el equipo tiene un partido con el acta cargada
    And en el partido con el acta cargada, el club ha <cambiado> a un jugador
    When abro el acta del partido con el acta cargada
    Then la fila del jugador lleva la marca "Cambiado por el club"

    Examples:
      | cambiada                         | cambiado                                                     |
      | pasada a «Jugado»                | pasado a «Jugado» siendo del acta «Convocado sin minutos»     |
      | anulada, que venía en el acta    | anulado siendo del acta                                      |
      | apuntada, que no venía en el acta | apuntado con «Baja médica» sin venir en el acta              |

  @ui
  Scenario: Una fila tal como la trajo el acta no lleva la marca «Cambiado por el club»
    Given el equipo tiene un partido con el acta cargada
    And en el partido con el acta cargada, el club no ha cambiado nada
    When abro el acta del partido con el acta cargada
    Then ninguna fila de la convocatoria lleva la marca "Cambiado por el club"

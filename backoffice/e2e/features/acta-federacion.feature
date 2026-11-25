# La carga del acta de la Federación, con la ingesta (plan R7, decisiones 1, 8 a 12, y R7.3 P8; D-125 a D-128,
# D-131 a D-134). La Federación falsa sirve el acta de la RFFM de cada partido (`acta-partido/<código>`) como la que
# declara cada escenario, con jugadores inventados al azar; la ingesta es la de verdad (LLD-B §11.3).
#
# Lo que no tiene escenario, y por qué:
# - Traducir cada código de la RFFM y casar nombres, una regla a una: pruebas del adaptador de la RFFM; aquí, un caso
#   de cada.
# - Un código de gol o de tarjeta desconocido (D-131, punto 4): pruebas del adaptador.
# - Los partidos entre dos rivales y las jornadas de descanso: no tienen acta (D-130), y no se piden.
# - Cuántas actas cargó cada pasada: no se enseña en ninguna pantalla.
# - Que un acta que no se cargó se pida en la pasada siguiente: lo dice la regla de cuándo se pregunta (D-133,
#   punto 1), que cubren las pruebas del servidor; aquí, que no queda cargada.
#
# Vocabulario de los pasos (además del de acta.feature):
# - «pasa la ingesta»: una pasada de la ingesta de la competición del equipo.
# - «la Federación cierra el acta»: publica el acta del partido con `acta_cerrada = 1`; «sin cerrar», con `0`.
# - «el acta publica a un jugador como <titular | suplente que entra en un cambio | suplente sin cambio>».
# - «lo apuntado», «los goles apuntados» y «las tarjetas apuntadas»: lo guardado del partido, leído por la API
#   (`listAppearances`, `listGoals`, `listCards`).
# - «la convocatoria del acta»: la copia que guarda el partido (`getMatch`).
# - «el acta cargada»: el partido marcado como cargado, con su fecha (`getMatch`).
# - «la plantilla»: la del equipo en esa temporada (`listPlayers`); «el perfil»: el del jugador
#   (`GET /player-profiles?q=`), con su código de la Federación si lo tiene.
# - «el mismo jugador» en la Federación y en el club: con el mismo código; sin código, con el mismo nombre de la
#   sincronización de la plantilla (plantilla-federacion.feature).
Feature: La carga del acta de la Federación

  # ── El acta entera ──

  @e2e
  Scenario: Al pasar la ingesta, se carga el acta cerrada de un partido jugado
    Given el equipo tiene un partido jugado sin acta
    And la Federación cierra el acta del partido
    When pasa la ingesta
    Then el partido tiene el acta cargada, con la fecha de ahora
    And la convocatoria del acta tiene a los jugadores del equipo que publica el acta

  @e2e
  Scenario: Un acta que la Federación no ha cerrado no se carga
    Given el equipo tiene un partido jugado sin acta
    And la Federación publica el acta del partido sin cerrar
    When pasa la ingesta
    Then el partido no tiene el acta cargada
    And lo apuntado del partido está como antes de la ingesta

  @e2e
  Scenario: El acta de un partido cuya hora de comienzo no ha pasado no se pide
    Given el equipo tiene un partido por jugar
    And la Federación cierra el acta del partido por jugar
    When pasa la ingesta
    Then la Federación no ha recibido ninguna petición del acta del partido por jugar
    And el partido por jugar no tiene el acta cargada

  @e2e
  Scenario: Un acta ya cargada no se vuelve a leer, aunque la Federación la cambie
    Given el equipo tiene un partido con el acta cargada
    And la Federación cambia el acta del partido, con un gol más
    When pasa la ingesta
    Then la Federación no ha recibido ninguna petición del acta del partido
    And los goles apuntados del partido son los mismos que antes

  @e2e
  Scenario Outline: Si la Federación <qué hace> con el acta, no se carga nada
    Given el equipo tiene un partido jugado sin acta
    And la Federación cierra el acta del partido, y <qué hace> en la próxima petición del acta
    When pasa la ingesta
    Then el partido no tiene el acta cargada
    And lo apuntado, los goles apuntados y las tarjetas apuntadas del partido están como antes

    Examples:
      | qué hace |
      | falla    |
      | tarda    |

  @e2e
  Scenario: Con la plantilla sin sincronizar, la primera acta la sincroniza
    Given el equipo no sincronizado tiene un partido jugado sin acta, y ninguno con el acta cargada
    And la Federación publica la plantilla del equipo y cierra el acta del partido
    When pasa la ingesta
    Then la plantilla tiene a los jugadores que publica la Federación en la plantilla del equipo
    And la plantilla dice cuándo se sincronizó, con la fecha de ahora

  # ── Cada jugador del acta ──

  @e2e
  Scenario Outline: Un <cómo juega> del acta queda «<estado>», con el dorsal del acta
    Given el equipo tiene un partido jugado sin acta
    And la Federación cierra el acta del partido, con un jugador de la plantilla como <cómo juega> y un dorsal distinto del de la plantilla
    When pasa la ingesta
    Then lo apuntado tiene al jugador como <estado>, con el dorsal del acta y sin minutos
    And la convocatoria del acta tiene al jugador como <estado>

    Examples:
      | cómo juega                  | estado                |
      | titular                     | jugado                |
      | suplente que entra en un cambio | jugado            |
      | suplente sin cambio         | convocado sin minutos |

  @e2e
  Scenario: Al que el club ya tenía apuntado, el acta le pone su estado y le deja los minutos
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay un jugador «Jugado» con minutos
    And la Federación cierra el acta del partido, con ese jugador como suplente sin cambio
    When pasa la ingesta
    Then lo apuntado tiene al jugador como convocado sin minutos, con los minutos que tenía

  @e2e
  Scenario: El apuntado por el club que el acta no trae se queda como estaba
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay un jugador «Baja médica»
    And la Federación cierra el acta del partido, sin ese jugador
    When pasa la ingesta
    Then lo apuntado tiene al jugador con baja médica
    And la convocatoria del acta no tiene al jugador

  @e2e
  Scenario: El que no está en ninguna plantilla del club se da de alta en la del equipo
    Given el equipo tiene un partido jugado sin acta
    And la Federación cierra el acta del partido, con un jugador que mi club no tiene
    When pasa la ingesta
    Then la plantilla tiene al jugador nuevo, con el nombre y el código de la Federación
    And lo apuntado tiene al jugador nuevo con el estado que dice el acta

  @e2e
  Scenario: El de otro equipo del club queda como refuerzo, sin darse de alta
    Given el equipo tiene un partido jugado sin acta
    And otro equipo de mi club tiene un jugador en la plantilla de la temporada en curso
    And la Federación cierra el acta del partido, con el jugador del otro equipo
    When pasa la ingesta
    Then la plantilla del equipo no tiene al jugador del otro equipo
    And lo apuntado tiene al jugador del otro equipo, con el equipo del partido

  @e2e
  Scenario: El que el club dio de baja en el equipo se da de alta otra vez
    Given el equipo tiene un partido jugado sin acta
    And mi club ha dado de baja a un jugador de la plantilla del equipo
    And la Federación cierra el acta del partido, con el jugador dado de baja
    When pasa la ingesta
    Then la plantilla tiene otra vez al jugador
    And lo apuntado tiene al jugador con el estado que dice el acta

  @e2e
  Scenario: Un jugador casa por su código aunque el club le haya cambiado el nombre
    Given el equipo tiene un partido jugado sin acta
    And un jugador de la plantilla tiene en su perfil el código de la Federación y un nombre distinto del de la Federación
    And la Federación cierra el acta del partido, con ese jugador
    When pasa la ingesta
    Then lo apuntado tiene a ese jugador de la plantilla
    And la plantilla tiene los mismos jugadores que antes de la ingesta

  @e2e
  Scenario: Sin código en su perfil, un jugador casa por el nombre y se le guarda el código
    Given el equipo tiene un partido jugado sin acta
    And un jugador de la plantilla no tiene código en su perfil y tiene el mismo nombre que en la Federación
    And la Federación cierra el acta del partido, con ese jugador
    When pasa la ingesta
    Then lo apuntado tiene a ese jugador de la plantilla
    And el perfil del jugador tiene el código de la Federación

  # ── Los goles ──

  @e2e
  Scenario Outline: Un gol <de qué clase> del acta se carga <cómo>
    Given el equipo tiene un partido jugado sin acta
    And la Federación cierra el acta del partido, con un gol <de qué clase> de un jugador del club
    When pasa la ingesta
    Then los goles apuntados tienen el gol <cómo>, con el minuto del acta

    Examples:
      | de qué clase    | cómo                                                                        |
      | normal          | del club, con su goleador y sin tipo de jugada                               |
      | de penalti      | del club, con su goleador y como penalti                                     |
      | en propia puerta | del rival, en propia puerta y a nombre del jugador del club que lo mete     |

  @e2e
  Scenario: Un gol del rival se carga sin goleador
    Given el equipo tiene un partido jugado sin acta
    And la Federación cierra el acta del partido, con un gol del rival
    When pasa la ingesta
    Then los goles apuntados tienen el gol del rival, sin goleador y con el minuto del acta

  @e2e
  Scenario: Un gol que el club ya apuntó no se repite y conserva su desglose
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay apuntado un gol del club con su goleador, su minuto y todo el desglose
    And la Federación cierra el acta del partido, con ese gol, del mismo goleador en el mismo minuto
    When pasa la ingesta
    Then los goles apuntados tienen ese gol una sola vez
    And el gol conserva el desglose y el comentario que tenía

  @e2e
  Scenario: Un gol del mismo goleador en otro minuto se carga aparte
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay apuntado un gol del club con su goleador y su minuto
    And la Federación cierra el acta del partido, con un gol del mismo goleador en otro minuto
    When pasa la ingesta
    Then los goles apuntados tienen los dos goles del goleador, cada uno con su minuto

  # ── Las tarjetas ──

  @e2e
  Scenario Outline: Una tarjeta <de qué clase> del acta se carga como «<tarjeta>»
    Given el equipo tiene un partido jugado sin acta
    And la Federación cierra el acta del partido, con una tarjeta <de qué clase> a un jugador del club
    When pasa la ingesta
    Then las tarjetas apuntadas tienen al jugador con una tarjeta «<tarjeta>», con el minuto del acta
    And las tarjetas apuntadas no tienen más tarjetas del jugador

    Examples:
      | de qué clase                          | tarjeta          |
      | amarilla                              | Amarilla         |
      | roja                                  | Roja directa     |
      | amarilla y una segunda amarilla       | Segunda amarilla |

  @e2e
  Scenario: Una tarjeta que el club ya apuntó no se repite y conserva su comentario
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay apuntada una amarilla a un jugador, con un comentario
    And la Federación cierra el acta del partido, con una amarilla al mismo jugador
    When pasa la ingesta
    Then las tarjetas apuntadas tienen una sola amarilla del jugador, con el comentario que tenía

  @e2e
  Scenario: Las tarjetas del rival no se cargan
    Given el equipo tiene un partido jugado sin acta
    And la Federación cierra el acta del partido, con una tarjeta a un jugador del rival
    When pasa la ingesta
    Then las tarjetas apuntadas del partido no tienen ninguna tarjeta

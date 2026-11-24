# Las tarjetas del acta de un partido (plan R7, decisión 5e, y R7.3 P5 y P6; D-45, D-46, D-131, D-136).
# Las tarjetas que hay antes de cada escenario se apuntan por la API (`createCard`), y las de la Federación, con la
# ingesta. Los jugadores, al azar.
#
# Lo que no tiene escenario, y por qué:
# - Lo que el servidor rechaza y la web no ofrece (una tarjeta antes de la hora de comienzo): pruebas del servidor.
# - Las tarjetas del rival: no se apuntan (D-136), y la carga no las trae (acta-federacion.feature).
# - La temporada archivada: aún no se abre en la web; lo dice la cabecera de acta.feature.
#
# Vocabulario de los pasos (además del de acta.feature):
# - «la tabla de tarjetas»: la sección Tarjetas del acta.
# - «el formulario de la tarjeta»: el diálogo que abren «+ Añadir tarjeta» y el icono «Corregir» de una tarjeta.
# - «lo obligatorio»: el jugador y la tarjeta; el minuto y el comentario son opcionales (R7.3, P5).
# - Las tarjetas: «Amarilla», «Roja directa» y «Segunda amarilla» (la doble amarilla: una roja, D-45).
# - «las tarjetas apuntadas»: las guardadas, leídas por la API (`listCards` del partido).
# - «una tarjeta de la Federación»: una que cargó la ingesta con el acta.
Feature: Las tarjetas del acta

  # ── Lo que hay al entrar ──

  @ui
  Scenario: La tabla de tarjetas tiene de cada tarjeta su minuto, su jugador y su tarjeta
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay apuntada una tarjeta con minuto
    When abro el acta del partido jugado sin acta
    Then la fila de la tarjeta tiene el minuto, el jugador y la tarjeta apuntados

  @ui
  Scenario Outline: La tarjeta «<tarjeta>» lleva <icono> de icono
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay apuntada una tarjeta «<tarjeta>»
    When abro el acta del partido jugado sin acta
    Then la fila de la tarjeta dice "<tarjeta>" con <icono> de icono

    Examples:
      | tarjeta          | icono                         |
      | Amarilla         | una cartulina amarilla        |
      | Roja directa     | una cartulina roja            |
      | Segunda amarilla | dos cartulinas amarillas      |

  # ── Apuntar una tarjeta ──

  @e2e
  Scenario: Una tarjeta con solo lo obligatorio se guarda
    Given el equipo tiene un partido jugado sin acta
    And en el formulario de una tarjeta nueva del acta he elegido solo el jugador y la tarjeta
    When pulso "Guardar" en el formulario de la tarjeta
    Then la tabla de tarjetas tiene una tarjeta más, con el jugador y la tarjeta elegidos y sin minuto
    And las tarjetas apuntadas tienen esa tarjeta, sin minuto ni comentario

  @e2e
  Scenario Outline: Una tarjeta con solo <dato> además de lo obligatorio lo guarda
    Given el equipo tiene un partido jugado sin acta
    And en el formulario de una tarjeta nueva del acta he elegido el jugador y la tarjeta, y rellenado solo <dato>
    When pulso "Guardar" en el formulario de la tarjeta
    Then las tarjetas apuntadas tienen la tarjeta nueva con <dato> que rellené

    Examples:
      | dato          |
      | el minuto     |
      | el comentario |

  @e2e
  Scenario: Una tarjeta con todos los datos los guarda
    Given el equipo tiene un partido jugado sin acta
    And en el formulario de una tarjeta nueva del acta he rellenado todos los datos
    When pulso "Guardar" en el formulario de la tarjeta
    Then la fila de la tarjeta nueva tiene el minuto, el jugador y la tarjeta que rellené
    And las tarjetas apuntadas tienen la tarjeta nueva con todos los datos que rellené

  @ui
  Scenario Outline: Una tarjeta <cuál> no se guarda, y el formulario dice por qué
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay apuntada una tarjeta «<la que hay>» a un jugador
    And en el formulario de una tarjeta nueva del acta he elegido al mismo jugador y la tarjeta «<la nueva>»
    When pulso "Guardar" en el formulario de la tarjeta
    Then el formulario de la tarjeta dice que <por qué>
    And las tarjetas apuntadas son las mismas que antes

    Examples:
      | cuál                                      | la que hay | la nueva         | por qué                                                       |
      | repetida                                  | Amarilla   | Amarilla         | el jugador ya tiene esa tarjeta en el partido                 |
      | de segunda amarilla con una amarilla suelta | Amarilla   | Segunda amarilla | hay que borrar antes la amarilla, que queda dentro de la roja |

  @ui
  Scenario: La lista del jugador de la tarjeta tiene a toda la convocatoria de la página
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay convocados, no convocados y un refuerzo apuntado
    When abro el formulario de una tarjeta nueva del acta
    Then la lista del jugador tiene a todos los de la convocatoria, en su orden, también los no convocados y el refuerzo

  # ── Corregir, cancelar y borrar ──

  @e2e
  Scenario: Corregir el minuto de una tarjeta lo cambia
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay apuntada una tarjeta con minuto
    And en el formulario de esa tarjeta he cambiado el minuto
    When pulso "Guardar" en el formulario de la tarjeta
    Then la fila de la tarjeta tiene el minuto nuevo
    And las tarjetas apuntadas tienen la tarjeta con el minuto nuevo

  @e2e
  Scenario: Cancelar una tarjeta nueva con datos no guarda nada
    Given el equipo tiene un partido jugado sin acta
    And en el formulario de una tarjeta nueva del acta he elegido el jugador y la tarjeta
    When pulso "Cancelar" en el formulario de la tarjeta
    Then la tabla de tarjetas tiene las mismas tarjetas que antes
    And las tarjetas apuntadas son las mismas que antes

  @e2e
  Scenario: Borrar una tarjeta la quita del acta
    Given el equipo tiene un partido jugado sin acta
    And en el partido jugado sin acta hay apuntadas dos tarjetas
    And estoy en el acta del partido jugado sin acta
    When pulso el icono "Borrar" de una de las tarjetas
    Then la tabla de tarjetas no tiene esa tarjeta
    And las tarjetas apuntadas tienen solo la otra tarjeta

  # ── Con el acta cargada ──

  @ui
  Scenario: En una tarjeta de la Federación, el jugador, el minuto y la tarjeta están bloqueados
    Given el equipo tiene un partido con el acta cargada, con una tarjeta
    When abro el formulario de esa tarjeta de la Federación
    Then el jugador, el minuto y la tarjeta del formulario están bloqueados
    And el comentario del formulario está sin bloquear

  @e2e
  Scenario: El comentario de una tarjeta de la Federación se guarda
    Given el equipo tiene un partido con el acta cargada, con una tarjeta
    And en el formulario de esa tarjeta de la Federación he escrito un comentario
    When pulso "Guardar" en el formulario de la tarjeta
    Then las tarjetas apuntadas tienen la tarjeta con ese comentario y con el jugador, el minuto y la tarjeta de la Federación

  @ui
  Scenario: Con el acta cargada no se añaden ni se borran tarjetas
    Given el equipo tiene un partido con el acta cargada, con una tarjeta
    When abro el acta del partido con el acta cargada
    Then la sección de tarjetas no tiene el botón "+ Añadir tarjeta"
    And ninguna tarjeta tiene el icono "Borrar"

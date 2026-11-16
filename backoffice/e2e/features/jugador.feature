# La ficha del jugador, corregir y dar de baja (plan R6, decisiones 6, 7, 8 y 10).
# La ficha es la del jugador en una temporada: /temporadas/:temporada/jugadores/:id. Corregir y dar de baja se abren
# igual desde la fila de la plantilla (✎ y 🗑) que desde la ficha. El diálogo de corregir separa lo del jugador, que
# vale para todas sus temporadas (nombre y año, su perfil, D-119), de lo de esta plantilla (dorsal, demarcación y foto).
# El nombre se corrige; el año, solo si está vacío, con confirmación; y los dos a la vez, no (decisión 1 de R6.12):
# así un perfil no se reutiliza para otra persona.
# Guardar el dorsal, la demarcación o la foto los copia también al perfil, como ayuda para la próxima alta (D-122).
# Los jugadores se inventan al azar y se dan de alta por la API.
#
# Vocabulario de los pasos:
# - «la ficha del jugador»: la pantalla del jugador en una temporada; una página, no un diálogo. Encima lleva el
#   enlace de vuelta a la plantilla de su equipo («← Plantilla del Cadete A»).
# - «el diálogo de corregir»: el que abren ✎ en la fila y «Corregir» en la ficha.
# - «el perfil del jugador»: lo que devuelve de él la búsqueda de perfiles, por la API (`GET /player-profiles?q=`).
# - «de la plantilla» y «de su perfil»: de dónde sale cada dato. La ficha enseña el dorsal, la demarcación y la foto
#   de su fila de esa temporada, y el nombre y el año de su perfil; nunca el dorsal, la demarcación o la foto que el
#   perfil guarda como ayuda (D-122).
Feature: La ficha de un jugador, corregirlo y darlo de baja

  # ── La ficha ──

  @ui
  Scenario: La ficha del jugador tiene sus datos
    Given un equipo de mi club tiene en la plantilla de la temporada en curso un jugador con dorsal, demarcación y foto en la plantilla, distintos de los de su perfil, y con año en su perfil
    When abro la ficha del jugador, en la temporada en curso
    Then la ficha del jugador tiene el nombre de su perfil como «Nombre Apellidos»
    And la ficha del jugador tiene su equipo y la temporada en curso
    And la ficha del jugador tiene el dorsal de la plantilla
    And la ficha del jugador tiene la demarcación de la plantilla
    And la ficha del jugador tiene el año de su perfil

  @ui
  Scenario: La ficha de un jugador sin año en su perfil dice «Sin año»
    Given un equipo de mi club tiene en la plantilla de la temporada en curso un jugador sin año en su perfil
    When abro la ficha del jugador, en la temporada en curso
    Then la ficha del jugador dice "Sin año" en el año de nacimiento

  @e2e
  Scenario: Desde la ficha del jugador se vuelve a la plantilla de su equipo
    Given estoy en la ficha de un jugador de mi club, en la temporada en curso
    When pulso el enlace "← Plantilla del" y su equipo, encima de la ficha del jugador
    Then estoy en la pestaña Plantilla de la ficha de su equipo, en la temporada en curso

  @ui
  Scenario: La ficha de un jugador con la temporada equivocada en el camino no se encuentra
    Given un equipo de mi club tiene jugadores en la plantilla de la temporada en curso
    When abro la ficha de un jugador de la plantilla con una temporada pasada en el camino
    Then la página dice "No se ha encontrado el jugador"
    And la página tiene un enlace a la portada

  # ── Corregir ──

  @e2e
  Scenario: «Corregir» en la fila de la plantilla abre el diálogo de corregir con los datos del jugador
    Given estoy en la pestaña Plantilla de la ficha de un equipo de mi club con jugadores, en la temporada en curso
    When pulso la acción "Corregir" de la fila de un jugador
    Then el diálogo de corregir está abierto
    And el diálogo de corregir tiene el nombre y el año de su perfil
    And el diálogo de corregir tiene el dorsal, la demarcación y la foto de la plantilla

  @e2e
  Scenario: «Corregir» en la ficha del jugador abre el mismo diálogo de corregir
    Given estoy en la ficha de un jugador de mi club, en la temporada en curso
    When pulso "Corregir" en la ficha del jugador
    Then el diálogo de corregir está abierto
    And el diálogo de corregir tiene el nombre y el año de su perfil
    And el diálogo de corregir tiene el dorsal, la demarcación y la foto de la plantilla

  @ui
  Scenario: El diálogo de corregir separa lo del jugador de lo de esta plantilla
    Given estoy en la pestaña Plantilla de la ficha de un equipo de mi club con jugadores, en la temporada en curso
    When pulso la acción "Corregir" de la fila de un jugador
    Then el diálogo de corregir tiene un bloque "Del jugador, en todas sus temporadas" con el nombre y el año
    And el diálogo de corregir tiene un bloque con el equipo y la temporada en curso, con el dorsal, la demarcación y la foto

  @e2e
  Scenario: Corregir el dorsal lo cambia en la plantilla
    Given tengo abierto el diálogo de corregir de un jugador de mi club desde la plantilla, en la temporada en curso
    And he cambiado el dorsal por uno libre en el diálogo de corregir
    When pulso "Guardar" en el diálogo de corregir
    Then la fila del jugador en la plantilla tiene el dorsal nuevo
    And el perfil del jugador tiene el dorsal nuevo

  @e2e
  Scenario: Corregir el nombre lo cambia en la plantilla
    Given tengo abierto el diálogo de corregir de un jugador de mi club desde la plantilla, en la temporada en curso
    And he cambiado el nombre en el diálogo de corregir
    When pulso "Guardar" en el diálogo de corregir
    Then la fila del jugador en la plantilla tiene el nombre nuevo

  # ── El año: solo si está vacío ──

  @ui
  Scenario: El año de un jugador que lo tiene está bloqueado en el diálogo de corregir
    Given un equipo de mi club tiene en la plantilla de la temporada en curso un jugador con año en su perfil
    And estoy en la pestaña Plantilla de la ficha del equipo, en la temporada en curso
    When pulso la acción "Corregir" de la fila del jugador
    Then el campo "Año de nacimiento" del diálogo de corregir tiene el año de su perfil, bloqueado

  @ui
  Scenario: Poner el año a un jugador sin año pide confirmación al guardar
    Given un equipo de mi club tiene en la plantilla de la temporada en curso un jugador sin año en su perfil
    And en el diálogo de corregir del jugador, desde la plantilla, he puesto su año de nacimiento
    When pulso "Guardar" en el diálogo de corregir
    Then la confirmación del año dice que no se podrá cambiar después
    And la confirmación del año dice que, si es un error, hay que dar de baja al jugador y darlo de alta como nuevo

  @e2e
  Scenario: Confirmar el año lo guarda
    Given un equipo de mi club tiene en la plantilla de la temporada en curso un jugador sin año en su perfil
    And en el diálogo de corregir del jugador, desde la plantilla, he puesto su año de nacimiento y he pulsado "Guardar"
    When confirmo el año
    Then la fila del jugador en la plantilla tiene el año que he puesto

  @e2e
  Scenario: Cancelar la confirmación del año no lo guarda
    Given un equipo de mi club tiene en la plantilla de la temporada en curso un jugador sin año en su perfil
    And en el diálogo de corregir del jugador, desde la plantilla, he puesto su año de nacimiento y he pulsado "Guardar"
    When cancelo la confirmación del año
    Then la fila del jugador en la plantilla dice "Sin año" en el año de nacimiento

  @ui
  Scenario: Cambiar a la vez el nombre y el año no deja guardar, y dice qué hacer
    Given un equipo de mi club tiene en la plantilla de la temporada en curso un jugador sin año en su perfil
    And en el diálogo de corregir del jugador, desde la plantilla, he cambiado su nombre y he puesto su año de nacimiento
    When pulso "Guardar" en el diálogo de corregir
    Then el diálogo de corregir dice que no se pueden cambiar a la vez el nombre y el año
    And el diálogo de corregir dice que, si es otra persona, hay que dar de baja a este jugador y dar de alta al otro como nuevo

  # ── Corregir: el dorsal cogido, y cancelar ──

  @ui
  Scenario: Corregir con el dorsal de otro jugador del equipo dice quién lo tiene
    Given tengo abierto el diálogo de corregir de un jugador de mi club desde la plantilla, en la temporada en curso
    And he cambiado el dorsal por el de otro jugador del equipo en el diálogo de corregir
    When pulso "Guardar" en el diálogo de corregir
    Then el campo "Dorsal" del diálogo de corregir dice "ya lo tiene" y el nombre del otro jugador

  @e2e
  Scenario: Cancelar la corrección no cambia nada
    Given tengo abierto el diálogo de corregir de un jugador de mi club desde la plantilla, en la temporada en curso
    And he cambiado el dorsal por uno libre en el diálogo de corregir
    When pulso "Cancelar" en el diálogo de corregir
    Then la fila del jugador en la plantilla tiene el dorsal de antes

  # ── La foto ──

  @e2e
  Scenario: Poner una foto desde la ficha la enseña en la ficha
    Given estoy en la ficha de un jugador de mi club sin foto en la plantilla, en la temporada en curso
    When pongo una foto al jugador desde su ficha
    Then la ficha del jugador tiene su foto
    And el perfil del jugador tiene la foto nueva

  @e2e
  Scenario: Quitar la foto desde la ficha deja sus iniciales
    Given estoy en la ficha de un jugador de mi club con foto en la plantilla, en la temporada en curso
    When pulso "Quitar foto" en la ficha del jugador
    Then la ficha del jugador tiene las iniciales de su nombre en el sitio de la foto
    And el perfil del jugador no tiene foto

  @ui
  Scenario: La foto que llega a la web no lleva la ubicación de la foto original
    Given estoy en la ficha de un jugador de mi club sin foto en la plantilla, en la temporada en curso
    When pongo al jugador desde su ficha una foto con la ubicación dentro
    Then la foto de la ficha del jugador no tiene ubicación

  # ── Dar de baja ──

  @ui
  Scenario: «Dar de baja» en la fila pide confirmación, y dice qué pasa
    Given estoy en la pestaña Plantilla de la ficha de un equipo de mi club con jugadores, en la temporada en curso
    When pulso la acción "Dar de baja" de la fila de un jugador
    Then la confirmación de la baja pregunta si dar de baja al jugador, con su nombre y su equipo
    And la confirmación de la baja dice que sus goles y tarjetas siguen contando para el equipo
    And la confirmación de la baja dice que sincronizar con la Federación no lo volverá a añadir

  @e2e
  Scenario: Confirmar la baja lo quita de la plantilla
    Given en la plantilla de un equipo de mi club, en la temporada en curso, he pedido dar de baja a un jugador
    When confirmo la baja
    Then la plantilla ya no tiene al jugador
    And la pestaña Plantilla avisa "Dado de baja"

  @e2e
  Scenario: Dar de baja desde la ficha del jugador vuelve a la plantilla, sin él
    Given estoy en la ficha de un jugador de mi club, en la temporada en curso
    And he pedido dar de baja al jugador desde su ficha
    When confirmo la baja
    Then estoy en la pestaña Plantilla de la ficha de su equipo, en la temporada en curso
    And la plantilla ya no tiene al jugador

  @e2e
  Scenario: Tras la baja, su dorsal queda libre
    Given un jugador con dorsal de la plantilla de un equipo de mi club se ha dado de baja
    And en el diálogo del alta de la plantilla del equipo he rellenado un jugador nuevo con el dorsal del dado de baja
    When pulso "Guardar" en el diálogo del alta
    Then la plantilla tiene al jugador nuevo con ese dorsal

  @e2e
  Scenario: Cancelar la baja no la hace
    Given en la plantilla de un equipo de mi club, en la temporada en curso, he pedido dar de baja a un jugador
    When cancelo la baja
    Then la plantilla sigue teniendo al jugador

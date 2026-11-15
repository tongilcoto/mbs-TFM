# La pestaña Plantilla de la ficha del equipo (plan R6, §3; decisiones 5, 7 y 8).
# Los jugadores se inventan al azar en cada pasada y se dan de alta por la API (`createPlayer`), salvo en los
# escenarios del alta, que la prueban (alta-jugador.feature). Lo que se compara se lee de lo inventado, no se escribe
# en el escenario. En la base el nombre va en mayúsculas; la web lo enseña como «Nombre Apellidos».
#
# Lo que no tiene escenario, y por qué:
# - Una federación que no publica plantillas (sin «Sincronizar con la Federación»): la federación falsa es la RFFM,
#   que sí las publica; la regla la cubren las pruebas de piezas.
# - Un equipo rival: no tiene ficha en la web, así que no tiene pestaña Plantilla.
# - Las reglas de las mayúsculas del nombre, una a una: las cubren las pruebas de piezas de la función que lo
#   formatea; aquí, un escenario con un nombre que las junta.
#
# Vocabulario de los pasos:
# - «la plantilla»: la tabla de la pestaña Plantilla.
# - «la fila del jugador»: la suya en esa tabla.
# - «de la plantilla» y «de su perfil»: de dónde sale cada dato. El dorsal, la demarcación y la foto, de su fila de
#   esa temporada; el nombre y el año, de su perfil (D-119). El perfil también guarda un dorsal, una demarcación y
#   una foto, solo como ayuda para el alta (D-122): la pantalla nunca los enseña.
Feature: La plantilla de un equipo

  # ── Entrar ──

  @e2e
  Scenario: La pestaña Plantilla de la ficha enseña la plantilla del equipo en esa temporada
    Given un equipo de mi club tiene jugadores en la plantilla de la temporada en curso
    And estoy en la ficha del equipo, en la temporada en curso
    When pulso la pestaña "Plantilla" de la ficha
    Then la plantilla tiene a los jugadores del equipo en la temporada en curso

  @ui
  Scenario: Al recargar en la pestaña Plantilla, se sigue en ella
    Given un equipo de mi club tiene jugadores en la plantilla de la temporada en curso
    And estoy en la pestaña Plantilla de la ficha del equipo, en la temporada en curso
    When recargo la página
    Then la plantilla tiene a los jugadores del equipo en la temporada en curso

  @ui
  Scenario: Cambiar de temporada en la ficha enseña la plantilla de esa temporada
    Given un equipo de mi club tiene jugadores en la plantilla de la temporada en curso y en una temporada pasada
    And estoy en la pestaña Plantilla de la ficha del equipo, en la temporada en curso
    When cambio la ficha a la temporada pasada
    Then la plantilla tiene a los jugadores del equipo en la temporada pasada

  # ── El orden ──

  @ui
  Scenario: Los jugadores van por dorsal, y los que no tienen, al final por nombre
    Given un equipo de mi club tiene en la plantilla de la temporada en curso jugadores con dorsal y jugadores sin dorsal
    When abro la pestaña Plantilla de la ficha del equipo, en la temporada en curso
    Then la plantilla tiene primero a los jugadores con dorsal, del más bajo al más alto
    And la plantilla tiene después a los jugadores sin dorsal, por orden de nombre

  # ── Cada fila ──

  @ui
  Scenario: Cada fila tiene el dorsal, el nombre, la demarcación y el año de nacimiento del jugador
    Given un equipo de mi club tiene en la plantilla de la temporada en curso un jugador con dorsal, demarcación y foto en la plantilla, distintos de los de su perfil, y con año en su perfil
    When abro la pestaña Plantilla de la ficha del equipo, en la temporada en curso
    Then la fila del jugador tiene el dorsal de la plantilla
    And la fila del jugador tiene el nombre de su perfil como «Nombre Apellidos»
    And la fila del jugador tiene la demarcación de la plantilla
    And la fila del jugador tiene el año de su perfil

  @ui
  Scenario: Un jugador sin dorsal ni demarcación tiene una raya en las dos
    Given un equipo de mi club tiene en la plantilla de la temporada en curso un jugador sin dorsal ni demarcación en la plantilla
    When abro la pestaña Plantilla de la ficha del equipo, en la temporada en curso
    Then la fila del jugador tiene una raya en el dorsal
    And la fila del jugador tiene una raya en la demarcación

  @ui
  Scenario: La fila de un jugador sin año en su perfil dice «Sin año»
    Given un equipo de mi club tiene en la plantilla de la temporada en curso un jugador sin año en su perfil
    When abro la pestaña Plantilla de la ficha del equipo, en la temporada en curso
    Then la fila del jugador dice "Sin año" en el año de nacimiento

  @ui
  Scenario: El nombre se enseña con las partículas en minúscula y mayúscula tras el guion
    Given un equipo de mi club tiene en la plantilla de la temporada en curso un jugador con un apellido con partícula y otro con guion
    When abro la pestaña Plantilla de la ficha del equipo, en la temporada en curso
    Then la fila del jugador tiene la partícula de su apellido en minúscula
    And la fila del jugador tiene en mayúscula la letra que sigue al guion

  @ui
  Scenario: Un jugador sin foto tiene sus iniciales
    Given un equipo de mi club tiene en la plantilla de la temporada en curso un jugador sin foto en la plantilla
    When abro la pestaña Plantilla de la ficha del equipo, en la temporada en curso
    Then la fila del jugador tiene las iniciales de su nombre en el sitio de la foto

  @ui
  Scenario: Un jugador con foto la tiene en su fila
    Given un equipo de mi club tiene en la plantilla de la temporada en curso un jugador con foto en la plantilla
    When abro la pestaña Plantilla de la ficha del equipo, en la temporada en curso
    Then la fila del jugador tiene la foto de la plantilla
    And la foto de la fila del jugador dice al lector su nombre

  @ui
  Scenario: Cada fila tiene las acciones de corregir y dar de baja
    Given un equipo de mi club tiene jugadores en la plantilla de la temporada en curso
    When abro la pestaña Plantilla de la ficha del equipo, en la temporada en curso
    Then cada fila de la plantilla tiene la acción "Corregir"
    And cada fila de la plantilla tiene la acción "Dar de baja"

  @e2e
  Scenario: El nombre de un jugador lleva a su ficha
    Given un equipo de mi club tiene jugadores en la plantilla de la temporada en curso
    And estoy en la pestaña Plantilla de la ficha del equipo, en la temporada en curso
    When pulso el nombre de un jugador de la plantilla
    Then estoy en la ficha de ese jugador, en la temporada en curso

  # ── Sin jugadores ──

  @ui
  Scenario: Un equipo sin jugadores lo dice, y ofrece darlos de alta y sincronizar con la Federación
    Given un equipo de mi club sin jugadores en la plantilla de la temporada en curso
    When abro la pestaña Plantilla de la ficha del equipo, en la temporada en curso
    Then la pestaña Plantilla dice "Este equipo aún no tiene jugadores en" y la temporada en curso
    And la pestaña Plantilla tiene el botón "Dar de alta un jugador"
    And la pestaña Plantilla tiene el botón "Sincronizar con la Federación"

  # ── Una temporada archivada ──

  @ui
  Scenario: En una temporada archivada, la plantilla se ve pero no se cambia
    Given un equipo de mi club tiene jugadores en la plantilla de una temporada pasada archivada
    When abro la pestaña Plantilla de la ficha del equipo, en la temporada archivada
    Then la plantilla tiene a los jugadores del equipo en la temporada archivada
    And la pestaña Plantilla no tiene el botón "Dar de alta un jugador"
    And la pestaña Plantilla no tiene el botón "Sincronizar con la Federación"
    And las filas de la plantilla no tienen acciones

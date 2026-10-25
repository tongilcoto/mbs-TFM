# Sincronizar un equipo con la Federación: el enganche (plan R3, §3.2–§3.4; decisiones 2 a 6).
# Las competiciones se las inventa la federación falsa en cada pasada, con la edad, el género y la modalidad que le
# toquen al equipo (LLD-B §11.3). La dirección que se pega es la de la RFFM de verdad; el servidor de pruebas la
# pide a la falsa. Solo es fijo lo que decide la rama: de qué temporada es el calendario, qué tiene de raro, y
# quién del club tiene ya un equipo del grupo.
#
# Los mensajes de cada código de error se prueban con Vitest (errors.ts); aquí, uno por cada sitio donde puede salir
# un error (decisión 6): junto al campo, arriba del paso 1 con y sin «Reintentar», y arriba del paso 2.
#
# Vocabulario de los pasos:
# - «el equipo que se sincroniza»: el equipo del club abierto en la pantalla.
# - «el que es del equipo que se sincroniza»: su nombre en la lista de equipos de la Federación (paso 2).
# - Los pasos que abren la pantalla nombran el equipo por lo que lo distingue: «inscrito sin competición», «que juega».
# - Los textos esperados largos van en una tabla, una fila por frase.
Feature: Sincronizar un equipo con la Federación

  # ── Entrar en la pantalla ──

  @ui
  Scenario: La pantalla de sincronizar, abierta escribiendo la dirección en el navegador, dice qué equipo se sincroniza
    Given en la temporada en curso de mi club hay un equipo inscrito sin competición
    When escribo en el navegador la dirección de la pantalla de sincronizar el equipo de mi club inscrito sin competición
    Then la pantalla de sincronizar dice el nombre del equipo de mi club inscrito sin competición
    And la línea de pasos dice que estoy en "La dirección"

  @ui
  Scenario: La pantalla de sincronizar dice «Cargando equipo…» mientras llega el equipo
    Given en la temporada en curso de mi club hay un equipo inscrito sin competición
    And la petición del equipo de mi club inscrito sin competición está retenida
    When escribo en el navegador la dirección de la pantalla de sincronizar el equipo de mi club inscrito sin competición
    Then la pantalla de sincronizar dice "Cargando equipo…"

  @ui
  Scenario: La pantalla de sincronizar de un equipo que no existe dice que no se ha encontrado
    Given mi club tiene la temporada en curso
    When escribo en el navegador la dirección de la pantalla de sincronizar de un equipo que mi club no tiene
    Then la página dice "No se ha encontrado el equipo"
    And la página tiene un enlace a la portada

  # «abc» no es un código de equipo: la web lo sabe sin preguntar al servidor (LLD-B §6.7).
  @ui
  Scenario: La pantalla de sincronizar con un código de equipo mal escrito en la dirección dice que no se ha encontrado
    Given mi club tiene la temporada en curso
    When abro "/equipos/abc/federacion" en la web de mi club
    Then la página dice "No se ha encontrado el equipo"
    And la página tiene un enlace a la portada

  @ui
  Scenario: La pantalla de sincronizar de un equipo rival dice que no se ha encontrado
    Given en la temporada en curso de mi club juega un equipo
    When escribo en el navegador la dirección de la pantalla de sincronizar de uno de los rivales del equipo de mi club que juega
    Then la página dice "No se ha encontrado el equipo"
    And la página tiene un enlace a la portada

  # ── El paso 1: la dirección ──

  @ui
  Scenario: El paso 1 de sincronizar, campo a campo
    Given en la temporada en curso de mi club hay un equipo inscrito sin competición
    When abro desde la portada la pantalla de sincronizar el equipo de mi club inscrito sin competición
    Then el campo "Dirección del calendario" del paso 1 es obligatorio, con la ayuda:
      | Cópiala de la web de la Federación, en la página del calendario del grupo. |
    And el paso 1 tiene el botón "Comprobar en la Federación"

  @ui
  Scenario: En el paso 1, comprobar sin dirección marca el campo, sin preguntar a la Federación
    Given estoy en el paso 1 de sincronizar un equipo de mi club sin competición
    When compruebo en la Federación sin escribir la dirección
    Then la lista de errores del paso 1 tiene el foco
    And la lista de errores del paso 1 nombra "Dirección del calendario"

  @ui
  Scenario: En el paso 1, mientras se comprueba, el botón dice «Comprobando…» y no se puede pulsar
    Given estoy en el paso 1 de sincronizar un equipo de mi club sin competición
    And la Federación tiene una competición de la temporada en curso para el equipo que se sincroniza, que tarda en contestar
    When compruebo en la Federación la dirección de la competición que tiene para el equipo que se sincroniza
    Then el botón del paso 1 dice "Comprobando…"
    And el botón del paso 1 está bloqueado

  @ui
  Scenario: En el paso 1, una dirección que no es la de un calendario da el error junto al campo
    Given estoy en el paso 1 de sincronizar un equipo de mi club sin competición
    When compruebo en la Federación una dirección que no es la de un calendario
    Then el campo "Dirección del calendario" del paso 1 dice:
      | Esa dirección no es la de un calendario de la Federación. |
      | Cópiala de la página del calendario del grupo.            |

  @ui
  Scenario: En el paso 1, una dirección donde la Federación no tiene calendario da el error junto al campo
    Given estoy en el paso 1 de sincronizar un equipo de mi club sin competición
    When compruebo en la Federación la dirección de un calendario que la Federación no tiene
    Then el campo "Dirección del calendario" del paso 1 dice:
      | La Federación no tiene ningún calendario en esa dirección. |
      | Revisa que esté completa.                                  |

  @ui
  Scenario: En el paso 1, si la Federación responde con un error, el aviso sale arriba con «Reintentar» y la dirección sigue escrita
    Given estoy en el paso 1 de sincronizar un equipo de mi club sin competición
    And la Federación tiene una competición de la temporada en curso para el equipo que se sincroniza, que contesta con un error
    When compruebo en la Federación la dirección de la competición que tiene para el equipo que se sincroniza
    Then el paso 1 avisa arriba:
      | La Federación ha respondido con un error. |
      | Prueba otra vez en un rato.               |
    And el paso 1 ofrece "Reintentar"
    And el campo "Dirección del calendario" del paso 1 conserva la dirección de la competición

  @e2e
  Scenario: En el paso 1, «Reintentar» con la Federación ya bien pasa al paso 2
    Given en el paso 1 de sincronizar un equipo de mi club, la Federación ha respondido con un error al comprobar la competición que tiene para él
    And la Federación ya contesta bien a la competición que tiene para el equipo que se sincroniza
    When pulso el botón "Reintentar"
    Then estoy en el paso 2 de la pantalla de sincronizar

  @ui
  Scenario: En el paso 1, si la Federación no dice de qué temporada es el calendario, el aviso sale arriba sin «Reintentar»
    Given estoy en el paso 1 de sincronizar un equipo de mi club sin competición
    And la Federación tiene una competición para el equipo que se sincroniza de una temporada que mi club no tiene, sin decir cuál es
    When compruebo en la Federación la dirección de la competición que tiene para el equipo que se sincroniza
    Then el paso 1 avisa arriba:
      | La Federación no dice de qué temporada es ese calendario. |
    And el paso 1 no ofrece "Reintentar"

  @ui
  Scenario: En el paso 1, si la temporada del club ya está sincronizada con otro código, el aviso sale arriba
    Given la temporada en curso de mi club ya está sincronizada con un código de la Federación
    And estoy en el paso 1 de sincronizar un equipo de mi club sin competición
    And la Federación tiene una competición para el equipo que se sincroniza con la misma temporada y otro código
    When compruebo en la Federación la dirección de la competición que tiene para el equipo que se sincroniza
    Then el paso 1 avisa arriba:
      | Esa temporada ya está sincronizada con otro código de la Federación. |
      | Revisa que el calendario sea de la temporada correcta.               |

  # ── Del paso 1 al paso 2 ──

  @e2e
  Scenario: Comprobar en el paso 1 la dirección de una competición lleva al paso 2, con su resumen
    Given estoy en el paso 1 de sincronizar un equipo de mi club sin competición
    And la Federación tiene una competición de la temporada en curso para el equipo que se sincroniza
    When compruebo en la Federación la dirección de la competición que tiene para el equipo que se sincroniza
    Then estoy en el paso 2 de la pantalla de sincronizar
    And el resumen del paso 2 tiene la división y el grupo de la competición
    And el resumen del paso 2 tiene la edad y la modalidad del equipo que se sincroniza
    And el resumen del paso 2 tiene la temporada en curso

  @ui
  Scenario: El paso 2 enseña los equipos del grupo en orden alfabético y sin ninguno elegido
    Given estoy en el paso 1 de sincronizar un equipo de mi club sin competición
    And la Federación tiene una competición de la temporada en curso para el equipo que se sincroniza
    When compruebo en la Federación la dirección de la competición que tiene para el equipo que se sincroniza
    Then la lista de equipos del paso 2 tiene los de la competición, en orden alfabético
    And la lista de equipos del paso 2 no tiene ninguno elegido
    And el botón del paso 2 dice "Sincronizar"

  # ── El paso 2: lo que hay en la dirección ──

  @ui
  Scenario: El paso 2 de una competición de una temporada que el club no tiene la marca «nueva» y avisa de que se creará
    Given estoy en el paso 1 de sincronizar un equipo de mi club sin competición
    And la Federación tiene una competición para el equipo que se sincroniza de la temporada que viene, que mi club no tiene
    When compruebo en la Federación la dirección de la competición que tiene para el equipo que se sincroniza
    Then el resumen del paso 2 dice que la temporada que viene es nueva
    And el paso 2 avisa que la temporada que viene se creará al sincronizar

  @ui
  Scenario: El paso 2 de una competición de otra edad avisa de qué no cuadra y no deja sincronizar
    Given estoy en el paso 1 de sincronizar un equipo de mi club sin competición
    And la Federación tiene una competición de la temporada en curso de otra edad que la del equipo que se sincroniza
    When compruebo en la Federación la dirección de la competición que tiene para el equipo que se sincroniza
    Then el paso 2 avisa que no cuadra, con la edad del equipo que se sincroniza y la de la competición
    And el botón "Sincronizar" del paso 2 está desactivado

  @ui
  Scenario: El paso 2 de una competición cuyo nombre no dice la edad lo avisa y deja sincronizar
    Given estoy en el paso 1 de sincronizar un equipo de mi club sin competición
    And la Federación tiene una competición de la temporada en curso para el equipo que se sincroniza, sin la edad en su nombre
    When compruebo en la Federación la dirección de la competición que tiene para el equipo que se sincroniza
    Then el paso 2 avisa que la Federación no dice la edad de la competición y se usará la del equipo que se sincroniza
    And el botón "Sincronizar" del paso 2 está activo

  @ui
  Scenario: En el paso 2, un equipo del grupo sin código sale desactivado y con el motivo
    Given estoy en el paso 1 de sincronizar un equipo de mi club sin competición
    And la Federación tiene una competición de la temporada en curso para el equipo que se sincroniza, con un equipo publicado sin código
    When compruebo en la Federación la dirección de la competición que tiene para el equipo que se sincroniza
    Then en la lista de equipos del paso 2, el equipo sin código está desactivado
    And en la lista de equipos del paso 2, el equipo sin código dice:
      | La Federación no publica su código: no se puede elegir |

  # Dos equipos del club en el mismo grupo (D-110): el primero ya está sincronizado, y su primera ingesta trajo al
  # segundo como rival. Los dos salen desactivados, cada uno con su motivo. El segundo no se puede sincronizar
  # todavía: la salida es de la rebanada 13.
  @ui
  Scenario: En el paso 2, los equipos del grupo que ya tiene el club salen desactivados y diciendo por qué
    Given en la temporada en curso de mi club juega un equipo, en una competición donde el club tiene otro equipo sin sincronizar
    And estoy en el paso 1 de sincronizar el otro equipo
    When compruebo en la Federación la dirección de la competición que tiene para el equipo que se sincroniza
    Then en la lista de equipos del paso 2, el que es del equipo de mi club que ya juega está desactivado
    And en la lista de equipos del paso 2, el que es del equipo de mi club que ya juega dice "Ya está sincronizado con" y su nombre
    And en la lista de equipos del paso 2, el que es del equipo que se sincroniza está desactivado
    And en la lista de equipos del paso 2, el que es del equipo que se sincroniza dice:
      | Ya está en el club como rival: la Federación lo trajo antes de sincronizarlo |

  @ui
  Scenario: En el paso 2 de la competición que el equipo ya tiene, su equipo dice «Ya está sincronizado con este equipo»
    Given en la temporada en curso de mi club juega un equipo
    And estoy en el paso 1 de sincronizar el equipo de mi club que juega
    When compruebo en la Federación la dirección de la competición en la que juega el equipo que se sincroniza
    Then en la lista de equipos del paso 2, el que es del equipo que se sincroniza dice "Ya está sincronizado con este equipo"

  # ── El paso 2: elegir y sincronizar ──

  @ui
  Scenario: En el paso 2, al elegir el equipo, el botón dice su nombre
    Given estoy en el paso 2 de sincronizar un equipo de mi club con una competición de la temporada en curso
    When elijo en la lista del paso 2 el que es del equipo que se sincroniza
    Then el botón del paso 2 dice "Sincronizar" seguido del nombre elegido en la lista

  @ui
  Scenario: En el paso 2, sincronizar sin elegir equipo dice qué falta
    Given estoy en el paso 2 de sincronizar un equipo de mi club con una competición de la temporada en curso
    When pulso el botón "Sincronizar" del paso 2
    Then la lista de errores del paso 2 tiene el foco
    And la lista de errores del paso 2 nombra "Elige tu equipo"

  @e2e
  Scenario: En el paso 2, «Editar la dirección» vuelve al paso 1 con la dirección escrita
    Given estoy en el paso 2 de sincronizar un equipo de mi club con una competición de la temporada en curso
    When pulso "Editar la dirección" en el paso 2
    Then estoy en el paso 1 de la pantalla de sincronizar
    And el campo "Dirección del calendario" del paso 1 conserva la dirección de la competición

  @e2e
  Scenario: En el paso 2, «Volver a comprobar» se queda en el paso 2 con el equipo elegido
    Given estoy en el paso 2 de sincronizar un equipo de mi club sin competición, con el equipo de la lista que le corresponde ya elegido
    When pulso "Volver a comprobar en la Federación" en el paso 2
    Then estoy en el paso 2 de la pantalla de sincronizar
    And la lista de equipos del paso 2 tiene elegido el que es del equipo que se sincroniza

  @ui
  Scenario: En el paso 2, si la Federación ha quitado el equipo entre comprobar y sincronizar, el aviso sale arriba y lo elegido sigue
    Given estoy en el paso 2 de sincronizar un equipo de mi club sin competición, con el equipo de la lista que le corresponde ya elegido
    And la Federación ha quitado del calendario de la competición el equipo elegido en la lista del paso 2
    When pulso el botón "Sincronizar" del paso 2
    Then el paso 2 avisa arriba:
      | Ese equipo ya no está en el calendario de la Federación. |
      | Vuelve a comprobar con el botón ↻ de la dirección.       |
    And la lista de equipos del paso 2 tiene elegido el que es del equipo que se sincroniza

  # ── Salir de la pantalla: adónde lleva, y que allí está lo que se hizo ──

  @e2e
  Scenario: Sincronizar un equipo sin competición lleva a la portada en la temporada en curso, con su competición
    Given estoy en el paso 2 de sincronizar un equipo de mi club sin competición, con el equipo de la lista que le corresponde ya elegido
    When pulso el botón "Sincronizar" del paso 2
    Then estoy en la portada, en la temporada en curso
    And la fila del equipo en la portada tiene su competición

  @ui
  Scenario: Al sincronizar un equipo, la portada lo avisa y el equipo sale «En marcha»
    Given estoy en el paso 2 de sincronizar un equipo de mi club sin competición, con el equipo de la lista que le corresponde ya elegido
    And la primera ingesta de la competición del paso 2 va a tardar
    When pulso el botón "Sincronizar" del paso 2
    Then la portada tiene el aviso:
      | Sincronizado.                      |
      | La primera ingesta está en marcha. |
    And la fila del equipo en la portada tiene la ingesta "En marcha"

  @e2e
  Scenario: Sincronizar con el calendario de la temporada que viene lleva a la portada en esa temporada, con el equipo
    Given estoy en el paso 2 de sincronizar un equipo de mi club con una competición de la temporada que viene, con el equipo de la lista que le corresponde ya elegido
    When pulso el botón "Sincronizar" del paso 2
    Then estoy en la portada, en la temporada que viene
    And la fila del equipo en la portada tiene su competición

  @e2e
  Scenario: Sincronizar un equipo desde la portada solo con el teclado
    Given en la temporada en curso de mi club hay un equipo inscrito sin competición
    And la Federación tiene una competición de la temporada en curso para el equipo que se sincroniza
    And estoy en la portada de mi club
    When desde la portada, sincronizo el equipo de mi club inscrito sin competición con la competición que la Federación tiene para él, usando solo el teclado
    Then estoy en la portada, en la temporada en curso
    And la fila del equipo en la portada tiene su competición

  @e2e
  Scenario: Después de sincronizar un equipo, «Atrás» lleva a la portada de partida, no a la pantalla de sincronizar
    Given he sincronizado desde la portada de mi club un equipo sin competición
    When vuelvo atrás en el navegador
    Then estoy en la portada, en la temporada en curso
    And la fila del equipo en la portada tiene su competición

  @ui
  Scenario: Salir del paso 1 con la dirección escrita pregunta antes, sin salir
    Given estoy en el paso 1 de sincronizar un equipo de mi club, con una dirección escrita
    When pulso "Cancelar" en el paso 1
    Then sigo en el paso 1 de la pantalla de sincronizar
    And la pantalla de sincronizar pregunta:
      | Tienes cambios sin guardar. |
      | ¿Salir sin guardar?         |

  @e2e
  Scenario: «Cancelar» en el paso 1 sin nada escrito vuelve a la portada sin preguntar, y sin sincronizar nada
    Given estoy en el paso 1 de sincronizar un equipo de mi club sin competición
    When pulso "Cancelar" en el paso 1
    Then estoy en la portada, en la temporada en curso
    And la fila del equipo en la portada dice "Sin competición"

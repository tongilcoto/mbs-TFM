# El alta de equipo (plan R2, §3.2 y §3.4; decisiones 5 y 6).
# El equipo que se da de alta se inventa al azar en cada pasada (la skill de escenarios, principio 9); solo es fijo
# lo que decide la rama: que ya exista, en esa temporada o en otra.
Feature: El alta de equipo

  # ── Entrar en la página: con qué temporada se abre ──

  @e2e
  Scenario: «Dar de alta un equipo» abre el formulario con la temporada que enseñaba la portada
    Given mi club tiene la temporada en curso
    And he cambiado la portada de mi club a una temporada pasada
    When pulso el enlace "Dar de alta un equipo" de la portada
    Then estoy en el formulario de alta
    And el selector de temporada del formulario de alta tiene elegida la temporada pasada

  @ui
  Scenario: Al recargar el formulario, conserva la temporada con la que se abrió
    Given mi club tiene la temporada en curso
    And estoy en el formulario de alta de equipo, abierto desde la portada de mi club en una temporada pasada
    When recargo el formulario de alta
    Then sigo en el formulario de alta
    And el selector de temporada del formulario de alta tiene elegida la temporada pasada

  @ui
  Scenario: Abierto el formulario escribiendo su dirección, la temporada en curso
    Given mi club tiene la temporada en curso
    And mi club tiene una temporada pasada
    When abro "/equipos/nuevo" en la web de mi club
    Then estoy en el formulario de alta
    And el selector de temporada del formulario de alta tiene elegida la temporada en curso

  # ── Usar la página: los campos, y lo que el formulario no deja guardar ──

  @ui
  Scenario: El formulario de alta, campo a campo
    Given mi club tiene la temporada en curso
    When abro el formulario de alta de equipo desde la portada de mi club
    Then el campo "Categoría" del formulario de alta es obligatorio
    And el campo "Letra" del formulario de alta es opcional, con la ayuda "Si el club tiene varios equipos de la misma categoría: A, B…"
    And el campo "Género" del formulario de alta es obligatorio
    And el campo "Modalidad" del formulario de alta es obligatorio
    And el campo "Temporada" del formulario de alta es obligatorio

  @ui
  Scenario: Enviar el alta sin rellenar marca los obligatorios a la vez
    Given mi club tiene la temporada en curso
    And estoy en el formulario de alta de equipo, abierto desde la portada de mi club
    When envío el formulario de alta sin rellenar
    Then la lista de errores del formulario de alta tiene el foco
    And la lista de errores del formulario de alta nombra "Categoría"
    And la lista de errores del formulario de alta nombra "Género"
    And la lista de errores del formulario de alta nombra "Modalidad"

  @ui
  Scenario: En un club sin temporadas, enviar el alta todo vacío marca también la temporada
    Given estoy en el formulario de alta de equipo de un club sin temporadas
    When envío el formulario de alta sin rellenar
    Then la lista de errores del formulario de alta tiene el foco
    And la lista de errores del formulario de alta nombra "Categoría"
    And la lista de errores del formulario de alta nombra "Género"
    And la lista de errores del formulario de alta nombra "Modalidad"
    And la lista de errores del formulario de alta nombra "Temporada"

  @ui
  Scenario: Un equipo que ya está en esa temporada: el aviso arriba, y lo escrito sigue ahí
    Given en la temporada en curso de mi club hay un equipo inscrito sin competición
    And estoy en el formulario de alta de equipo, abierto desde la portada de mi club
    When en el formulario de alta, doy de alta el mismo equipo en la temporada en curso
    Then el formulario de alta avisa arriba "Ese equipo ya está dado de alta en esta temporada"
    And el formulario de alta conserva la categoría del equipo
    And el formulario de alta conserva la letra del equipo

  # ── Salir de la página: adónde lleva, y que esa pantalla tiene lo que se metió en el formulario ──

  @e2e
  Scenario: Dar de alta un equipo en la temporada que enseñaba la portada
    Given mi club tiene la temporada en curso
    And estoy en el formulario de alta de equipo, abierto desde la portada de mi club
    When en el formulario de alta, doy de alta un equipo nuevo
    Then estoy en la portada, en la temporada en curso
    And la tabla de la portada tiene el equipo que he dado de alta, con su categoría y su letra
    And la fila del equipo en la portada dice "Sin competición"

  @ui
  Scenario: Al guardar, la portada dice «Guardado»
    Given mi club tiene la temporada en curso
    And estoy en el formulario de alta de equipo, abierto desde la portada de mi club
    When en el formulario de alta, doy de alta un equipo nuevo
    Then estoy en la portada, en la temporada en curso
    And la portada tiene el aviso "Guardado"

  @e2e
  Scenario: Dar de alta un equipo en otra temporada lleva a la portada en la del equipo
    Given mi club tiene la temporada en curso
    And mi club tiene una temporada pasada
    And estoy en el formulario de alta de equipo, abierto desde la portada de mi club
    When en el formulario de alta, doy de alta un equipo nuevo en la temporada pasada
    Then estoy en la portada, en la temporada pasada
    And la tabla de la portada tiene el equipo que he dado de alta, con su categoría y su letra

  @e2e
  Scenario: El mismo equipo en otra temporada queda inscrito en la nueva
    Given en una temporada pasada de mi club juega un equipo
    And mi club tiene la temporada en curso
    And estoy en el formulario de alta de equipo, abierto desde la portada de mi club
    When en el formulario de alta, doy de alta el mismo equipo en la temporada en curso
    Then estoy en la portada, en la temporada en curso
    And la tabla de la portada tiene el equipo que he dado de alta, con su categoría y su letra

  @e2e
  Scenario: El equipo dado de alta en otra temporada sigue en la suya
    Given he dado de alta en la temporada en curso el equipo que jugaba en una temporada pasada
    When elijo la temporada pasada en el selector de la portada
    Then estoy en la portada, en la temporada pasada
    And la tabla de la portada tiene el equipo que he dado de alta, con su categoría y su letra

  @e2e
  Scenario: Dar de alta un equipo solo con el teclado
    Given mi club tiene la temporada en curso
    And estoy en la portada de mi club
    When desde la portada, doy de alta un equipo nuevo usando solo el teclado
    Then estoy en la portada, en la temporada en curso
    And la tabla de la portada tiene el equipo que he dado de alta, con su categoría y su letra

  @e2e
  Scenario: Después de guardar, «Atrás» lleva a la portada de partida, no al formulario
    Given he dado de alta un equipo nuevo desde la portada de mi club
    When vuelvo atrás en el navegador
    Then estoy en la portada, en la temporada en curso
    And la tabla de la portada tiene el equipo que he dado de alta, con su categoría y su letra

  @ui
  Scenario: Salir con cambios sin guardar pregunta antes, sin salir
    Given estoy en el formulario de alta de equipo con una categoría elegida
    When pulso "Cancelar" en el formulario de alta
    Then sigo en el formulario de alta
    And el formulario de alta pregunta "Tienes cambios sin guardar. ¿Salir sin guardar?"

  @e2e
  Scenario: «Cancelar» sin cambios vuelve a la portada sin preguntar, y sin dar de alta nada
    Given mi club tiene la temporada en curso
    And estoy en el formulario de alta de equipo, abierto desde la portada de mi club
    When pulso "Cancelar" en el formulario de alta
    Then estoy en la portada, en la temporada en curso
    And la portada dice que no hay equipos en la temporada en curso

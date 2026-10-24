# «Crear nueva temporada», desde el formulario de alta (plan R2, §3.3; decisiones 2, 4 y 6).
# Las temporadas se eligen por su relación con hoy (la en curso, la siguiente, una pasada); solo son fijas las
# etiquetas mal escritas, que deciden qué error sale.
Feature: La temporada nueva

  # ── Usar el diálogo: crear la temporada, y lo que no deja crear ──

  @e2e
  Scenario: Un club sin temporadas crea la primera, que queda elegida
    Given estoy en el formulario de alta de equipo de un club sin temporadas
    When en el formulario de alta, creo la temporada en curso con «Crear nueva temporada»
    Then sigo en el formulario de alta
    And el selector de temporada del formulario de alta tiene elegida la temporada en curso

  @e2e
  Scenario: Un club con temporadas crea la siguiente, que queda elegida
    Given mi club tiene la temporada en curso
    And estoy en el formulario de alta de equipo, abierto desde la portada de mi club
    When en el formulario de alta, creo la temporada siguiente con «Crear nueva temporada»
    Then sigo en el formulario de alta
    And el selector de temporada del formulario de alta tiene elegida la temporada siguiente

  @ui
  Scenario: Una etiqueta con mal formato: el error del catálogo, junto al campo
    Given tengo abierto «Crear nueva temporada» en el formulario de alta de equipo
    When en el diálogo «Crear nueva temporada», creo la temporada "2026-27"
    Then el campo del diálogo «Crear nueva temporada» dice "El formato no es válido. Por ejemplo: 2024/25"

  @ui
  Scenario: Una etiqueta con años que no siguen: el motivo del servidor, junto al campo
    Given tengo abierto «Crear nueva temporada» en el formulario de alta de equipo
    When en el diálogo «Crear nueva temporada», creo la temporada "2026/28"
    Then el campo del diálogo «Crear nueva temporada» dice 'debe ser AAAA/AB con AB el año siguiente, como "2025/26"'

  @ui
  Scenario: Una temporada que ya existe, archivada: el aviso arriba del diálogo
    Given mi club tiene una temporada pasada archivada
    And tengo abierto «Crear nueva temporada» en el formulario de alta de equipo
    When en el diálogo «Crear nueva temporada», creo la temporada archivada
    Then el diálogo «Crear nueva temporada» avisa arriba "Ya existe una temporada con esa etiqueta. Si no la ves en el selector, está archivada: se recupera desde Temporadas"

  # ── Salir del diálogo: adónde lleva, y que esa pantalla tiene lo que se metió ──

  @e2e
  Scenario: Cancelar el diálogo vuelve al formulario sin crear la temporada escrita
    Given mi club tiene la temporada en curso
    And tengo abierto «Crear nueva temporada» en el formulario de alta, con la temporada siguiente escrita
    When pulso "Cancelar" en el diálogo «Crear nueva temporada»
    Then sigo en el formulario de alta
    And el selector de temporada del formulario de alta tiene elegida la temporada en curso
    And el selector de temporada del formulario de alta no tiene la temporada siguiente

  @ui
  Scenario: Escape cierra el diálogo y el foco vuelve al botón
    Given tengo abierto «Crear nueva temporada» en el formulario de alta de equipo
    When pulso Escape en el diálogo «Crear nueva temporada»
    Then sigo en el formulario de alta
    And el foco está en el botón "Crear nueva temporada" del formulario de alta

  @e2e
  Scenario: Dar de alta el primer equipo en la temporada recién creada
    Given he creado la temporada en curso desde el formulario de alta de un club sin temporadas
    When en el formulario de alta, doy de alta un equipo nuevo en la temporada elegida
    Then estoy en la portada, en la temporada en curso
    And la tabla de la portada tiene el equipo que he dado de alta, con su categoría y su letra

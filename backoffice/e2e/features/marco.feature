# El marco, común a todas las pantallas (plan R1, §3.1 y §3.3).
Feature: El marco de la web

  Scenario: La cabecera enseña el nombre corto del club
    Given mi club tiene un nombre corto
    When abro la portada de mi club
    Then la cabecera dice el nombre corto de mi club

  Scenario: La pestaña del navegador dice la pantalla y el club
    Given mi club tiene un nombre corto
    When abro la portada de mi club
    Then la pestaña del navegador dice "Equipos" y el nombre corto de mi club

  Scenario: El interruptor cambia de modo
    Given estoy en la portada de mi club en modo claro
    When pulso el botón "Cambiar a modo oscuro"
    Then la web está en modo oscuro

  Scenario: La elección de modo se recuerda al volver a abrir la web
    Given he cambiado la web de mi club a modo oscuro
    When vuelvo a abrir la portada de mi club
    Then la web está en modo oscuro

  Scenario: «Saltar al contenido» lleva el foco al contenido de la página
    Given estoy en la portada de mi club
    When salto al contenido con el teclado
    Then el foco está en el contenido de la página

  Scenario: Un camino que la web no conoce
    When abro "/equipoz" en la web de mi club
    Then el contenido de la página tiene el título "Esta página no existe"
    And el contenido de la página tiene el enlace "Ir a la portada"

  Scenario: «Ir a la portada» lleva a la portada
    Given estoy en "/equipoz" en la web de mi club
    When pulso el enlace "Ir a la portada"
    Then estoy en la portada

  Scenario: /equipos lleva a la portada
    When abro "/equipos" en la web de mi club
    Then estoy en la portada

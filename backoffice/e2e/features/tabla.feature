# La tabla de la portada: ordenar por sus columnas y los equipos que se llamarían igual (bloque T del plan R2).
# Los equipos se inventan al azar; solo es fijo el estado de la ingesta, que decide el orden. Son tres, y los
# estados se reparten para que el orden del servidor, el de peor a mejor y el de mejor a peor sean los tres
# distintos: si no, un clic que no hiciera nada pasaría por bueno.
Feature: La tabla de la portada

  @ui
  Scenario: Ordenar por la ingesta pone primero lo que hay que mirar
    Given en la temporada en curso de mi club juegan tres equipos, con la ingesta "Al día", "Con fallos" y "Desactualizada"
    And estoy en la portada de mi club
    When ordeno la tabla de la portada por "Ingesta"
    Then la tabla de la portada tiene los equipos de peor a mejor ingesta

  @ui
  Scenario: La cabecera ordenada lo dice
    Given en la temporada en curso de mi club juega un equipo
    And estoy en la portada de mi club
    When ordeno la tabla de la portada por "Ingesta"
    Then la cabecera "Ingesta" de la tabla de la portada dice que está en orden ascendente

  @ui
  Scenario: El segundo clic ordena al revés
    Given la portada de mi club está ordenada por "Ingesta", con tres equipos "Al día", "Con fallos" y "Desactualizada"
    When ordeno la tabla de la portada por "Ingesta"
    Then la tabla de la portada tiene los equipos de mejor a peor ingesta

  @ui
  Scenario: El tercer clic vuelve al orden de siempre
    Given la portada de mi club está ordenada al revés por "Ingesta", con tres equipos "Al día", "Con fallos" y "Desactualizada"
    When ordeno la tabla de la portada por "Ingesta"
    Then la tabla de la portada tiene los equipos en el orden del servidor

  @ui
  Scenario: El orden sobrevive a recargar
    Given la portada de mi club está ordenada por "Ingesta", con tres equipos "Al día", "Con fallos" y "Desactualizada"
    When recargo la portada
    Then la tabla de la portada tiene los equipos de peor a mejor ingesta

  @ui
  Scenario: «Atrás» vuelve al orden anterior
    Given la portada de mi club está ordenada por "Ingesta", con tres equipos "Al día", "Con fallos" y "Desactualizada"
    When vuelvo atrás en el navegador
    Then la tabla de la portada tiene los equipos en el orden del servidor

  @ui
  Scenario: Dos equipos con la misma categoría y letra salen distinguidos
    Given en la temporada en curso de mi club hay dos equipos con la misma categoría y letra y distinto género
    When abro la portada de mi club
    Then la tabla de la portada tiene la fila de cada uno, con su género

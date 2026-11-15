# «Sincronizar con la Federación» en la plantilla (plan R6, decisión 9 y parte E; D-120, D-121 y D-122).
# La federación falsa publica la ficha de equipo de la RFFM (fichaequipo/<código>): por cada jugador, su código y su
# nombre como «APELLIDOS, NOMBRE»; ni dorsal, ni demarcación, ni año. Los jugadores se inventan al azar. Sincronizar
# solo añade: casa con los perfiles del club por el nombre exacto, sin tildes; no corrige ni da de baja a nadie, y
# no añade a quien el club dio de baja, a quien tiene en otro equipo esa temporada ni un nombre que no vale. Cada
# jugador dice si está «Federado» o «No federado». Al que casa con un perfil le copia de él su año, su dorsal, su
# demarcación y su foto; el dorsal, solo si nadie de la plantilla lo tiene.
#
# Cómo están ordenados los escenarios:
# 1. Lo que es de la plantilla entera: la fecha, el estado antes de sincronizar nunca, y la Federación que falla o
#    tarda.
# 2. Lo que pasa con cada jugador, según cómo está en el club y en la Federación: no hay un escenario de «sincronizar
#    añade a todos», porque no es verdad; cada caso tiene el suyo, y lo que haya en la plantilla además no cuenta.
# 3. El resumen: cuenta, así que cada fila parte de un estado conocido de la plantilla y de lo que publica la
#    Federación, y cada estado sale del anterior (la primera vez; otra vez sin cambios; otra vez con un cambio; y
#    otra vez con el mismo cambio dos veces, para ver que el contador acumula).
#    Cuántos jugadores hay se inventa al azar; la tabla dice qué va en cada contador.
# 4. La ficha del jugador.
#
# Lo que no tiene escenario, y por qué:
# - Pasar «APELLIDOS, NOMBRE» a «NOMBRE APELLIDOS»: lo cubren las pruebas del adaptador de la RFFM.
# - Dos competiciones del mismo equipo (liga y copa), con dos fechas de sincronización: el enganche solo da una.
#
# Vocabulario de los pasos:
# - «el equipo»: un equipo de mi club enganchado a una competición de la Federación falsa (R3); sin eso no hay
#   botón, así que lo da por hecho cada escenario. Si su plantilla se ha sincronizado antes o no, lo dice el escenario
#   solo cuando importa («ya se ha sincronizado», «no sincronizado»).
# - «sincronizar la plantilla»: pulsar «Sincronizar con la Federación» en la pestaña Plantilla.
# - «el resumen de la sincronización»: el aviso que sale al acabar.
# - «el perfil del jugador»: lo que devuelve de él la búsqueda de perfiles, por la API (`GET /player-profiles?q=`).
# - «el mismo nombre»: igual una vez en mayúsculas, con un solo espacio entre palabras y sin tildes ni diéresis
#   («GARCIA» es «GARCÍA»), como casa la sincronización (D-120, punto 4). La eñe cuenta como letra distinta
#   («MUNOZ» no es «MUÑOZ»).
# - «un nombre que no vale»: uno que no cumple las reglas del nombre (D-120, punto 6), como uno de una sola palabra.
# - En el resumen, «todos», «ninguno», «1» y «2» se cuentan sobre lo que publica la Federación; «los de antes» y «los
#   demás», sobre los que ya estaban en la plantilla al empezar.
Feature: Sincronizar la plantilla con la Federación

  # ── La plantilla entera ──

  @ui
  Scenario: Junto al botón sale cuándo se sincronizó la plantilla por última vez
    Given la Federación publica la plantilla del equipo
    And estoy en la pestaña Plantilla del equipo, en la temporada en curso
    When sincronizo la plantilla
    Then la pestaña Plantilla dice "Última sincronización" con la fecha y la hora de ahora

  @ui
  Scenario: Una plantilla que nunca se ha sincronizado no dice si sus jugadores son federados
    Given el equipo no sincronizado tiene jugadores dados de alta a mano en la temporada en curso
    When abro la pestaña Plantilla del equipo no sincronizado, en la temporada en curso
    Then ninguna fila de la plantilla dice "Federado" ni "No federado"

  @e2e
  Scenario: Si la Federación falla, la plantilla no cambia
    Given la Federación contesta con un error a la plantilla del equipo
    And estoy en la pestaña Plantilla del equipo, en la temporada en curso
    When sincronizo la plantilla
    Then la plantilla tiene los mismos jugadores que antes de sincronizar

  @ui
  Scenario: Si la Federación falla, la pestaña avisa que se puede volver a intentar
    Given la Federación contesta con un error a la plantilla del equipo
    And estoy en la pestaña Plantilla del equipo, en la temporada en curso
    When sincronizo la plantilla
    Then la pestaña Plantilla avisa que la Federación no ha contestado y que se puede volver a intentar

  @ui
  Scenario: Mientras la Federación tarda, el botón dice que está sincronizando
    Given la Federación va a retener la próxima petición de la plantilla del equipo
    And estoy en la pestaña Plantilla del equipo, en la temporada en curso
    When sincronizo la plantilla
    Then el botón "Sincronizar con la Federación" está bloqueado y dice que está sincronizando

  # ── Un jugador que la Federación publica y la plantilla no tiene ──

  @e2e
  Scenario: Un jugador que mi club no tiene se da de alta en la plantilla, con un perfil nuevo
    Given la Federación publica en la plantilla del equipo a un jugador que mi club no tiene
    And estoy en la pestaña Plantilla del equipo, en la temporada en curso
    When sincronizo la plantilla
    Then la plantilla tiene al jugador nuevo en el club, con su nombre como «Nombre Apellidos»
    And la fila del jugador nuevo en el club no tiene dorsal ni demarcación
    And la fila del jugador nuevo en el club dice "Federado"
    And el perfil del jugador nuevo en el club tiene su nombre, sin año

  @e2e
  Scenario Outline: Un jugador con un nombre <cómo> no se añade
    Given la Federación publica en la plantilla del equipo a un jugador con un nombre <cómo>
    And estoy en la pestaña Plantilla del equipo, en la temporada en curso
    When sincronizo la plantilla
    Then la plantilla no tiene al jugador con el nombre <cómo>

    Examples:
      | cómo                  |
      | vacío                 |
      | de una sola palabra   |
      | con un número         |
      | con un símbolo        |
      | de más de 120 letras  |

  @e2e
  Scenario: Un nombre completo sencillo de jugador que el club tuvo en otra temporada se reconoce, y trae lo de su perfil
    Given la Federación publica en la plantilla del equipo a un jugador con un nombre completo sencillo que mi club tuvo en una temporada pasada, con año, dorsal, demarcación y foto en su perfil
    And estoy en la pestaña Plantilla del equipo, en la temporada en curso
    When sincronizo la plantilla
    Then la fila del jugador de la temporada pasada tiene el año de su perfil
    And la fila del jugador de la temporada pasada tiene el dorsal de su perfil
    And la fila del jugador de la temporada pasada tiene la demarcación de su perfil
    And la fila del jugador de la temporada pasada tiene la foto de su perfil

  @e2e
  Scenario: Si el dorsal de su perfil ya lo tiene otro de la plantilla, el jugador llega sin dorsal
    Given la Federación publica en la plantilla del equipo a un jugador que mi club tuvo en una temporada pasada, con un dorsal en su perfil
    And la plantilla del equipo, en la temporada en curso, tiene a otro jugador con ese dorsal
    When sincronizo la plantilla
    Then la fila del jugador de la temporada pasada no tiene dorsal

  @e2e
  Scenario Outline: Si el nombre casa con dos jugadores del club, <cómo>, se da de alta con un perfil nuevo
    Given mi club tiene dos jugadores con el mismo nombre que uno que publica la Federación en la plantilla del equipo, <cómo>
    And estoy en la pestaña Plantilla del equipo, en la temporada en curso
    When sincronizo la plantilla
    Then la plantilla tiene al jugador con nombre repetido
    And mi club tiene ahora tres perfiles con el mismo nombre

    Examples:
      | cómo                                                  |
      | los dos escritos igual que la Federación              |
      | uno con la tilde que pone la Federación y otro sin ella |
      | los dos sin la tilde que pone la Federación           |

  @e2e
  Scenario: Un jugador que el club tiene en otro equipo de la temporada no se añade
    Given la Federación publica en la plantilla del equipo a un jugador que mi club tiene en otro equipo en la temporada en curso
    And estoy en la pestaña Plantilla del equipo, en la temporada en curso
    When sincronizo la plantilla
    Then la plantilla no tiene al jugador del otro equipo

  @e2e
  Scenario: A quien el club dio de baja, la sincronización no lo vuelve a añadir
    Given la plantilla del equipo ha dado de baja a un jugador que la Federación publica
    When sincronizo la plantilla
    Then la plantilla no tiene al jugador dado de baja

  # ── Un jugador que la Federación publica y la plantilla ya tiene ──

  @e2e
  Scenario: Volver a sincronizar no repite a los que ya están
    Given la plantilla del equipo ya se ha sincronizado con la Federación
    And estoy en la pestaña Plantilla del equipo, en la temporada en curso
    When sincronizo la plantilla
    Then la plantilla tiene a cada jugador que publica la Federación una sola vez

  @e2e
  Scenario: Lo que el club corrigió no lo toca la sincronización
    Given la plantilla del equipo ya se ha sincronizado con la Federación
    And he puesto dorsal, demarcación y año a un jugador de la plantilla
    When sincronizo la plantilla
    Then el jugador tiene en la plantilla el dorsal, la demarcación y el año que le puse

  @ui
  Scenario Outline: Un jugador dado de alta a mano <en el club> que la Federación publica <en la Federación> se reconoce
    Given el equipo tiene dado de alta a mano a un jugador <en el club> que la Federación publica <en la Federación>
    And estoy en la pestaña Plantilla del equipo, en la temporada en curso
    When sincronizo la plantilla
    Then la plantilla tiene al jugador una sola vez
    And la fila del jugador dice "Federado"

    Examples:
      | en el club                        | en la Federación          |
      | con tilde                         | sin ella                  |
      | sin tilde                         | con ella                  |
      | con diéresis                      | sin ella                  |
      | en minúsculas                     | en mayúsculas             |
      | con espacios de más               | con uno entre palabras    |

  @e2e
  Scenario: Un jugador dado de alta a mano sin la eñe que la Federación sí pone no se reconoce, y queda repetido
    Given el equipo tiene dado de alta a mano a un jugador sin la eñe que la Federación pone en su nombre
    And estoy en la pestaña Plantilla del equipo, en la temporada en curso
    When sincronizo la plantilla
    Then la plantilla tiene al jugador dado de alta a mano
    And la plantilla tiene al jugador de la Federación, con su eñe, con un perfil nuevo

  # ── Un jugador de la plantilla que la Federación no publica ──

  @ui
  Scenario: Un jugador que la Federación ha dejado de publicar sigue en la plantilla, como no federado
    Given la plantilla del equipo ya se ha sincronizado con la Federación
    And la Federación ha quitado a un jugador de la plantilla del equipo
    When sincronizo la plantilla
    Then la fila del jugador quitado dice "No federado"

  @ui
  Scenario: Un jugador dado de alta a mano que la Federación no publica es no federado
    Given el equipo tiene dado de alta a mano a un jugador que la Federación no publica
    And estoy en la pestaña Plantilla del equipo, en la temporada en curso
    When sincronizo la plantilla
    Then la fila del jugador dado de alta a mano dice "No federado"

  # ── El resumen ──

  @ui
  Scenario Outline: El resumen cuenta lo que ha hecho: <caso>
    Given estoy en la pestaña Plantilla del equipo, <de partida>
    And la Federación publica en la plantilla del equipo <lo que publica>
    When sincronizo la plantilla
    Then el resumen de la sincronización dice <añadidos> añadidos y <ya estaban> que ya estaban
    And el resumen de la sincronización dice <sin año> sin año de nacimiento
    And el resumen de la sincronización dice <de baja> dados de baja en el club y <otro equipo> en otro equipo
    And el resumen de la sincronización dice <repetidos> con nombre repetido y <no valen> con un nombre que no vale

    Examples:
      | caso                                                                             | de partida                              | lo que publica                                                       | añadidos | ya estaban   | sin año | de baja | otro equipo | repetidos | no valen |
      | la primera vez, con jugadores en la Federación que mi club no tiene              | sin jugadores y sin sincronizar nunca   | jugadores que mi club no tiene                                       | todos    | ninguno      | todos   | ninguno | ninguno     | ninguno   | ninguno  |
      | otra vez, sin cambios en la Federación                                           | ya sincronizada                         | los mismos jugadores                                                 | ninguno  | todos        | ninguno | ninguno | ninguno     | ninguno   | ninguno  |
      | otra vez, con uno más en la Federación que mi club no tiene                      | ya sincronizada                         | los mismos y uno que mi club no tiene                                | 1        | los de antes | 1       | ninguno | ninguno     | ninguno   | ninguno  |
      | otra vez, con uno más en la Federación que mi club tuvo otra temporada           | ya sincronizada                         | los mismos y uno que mi club tuvo en una temporada pasada, con año   | 1        | los de antes | ninguno | ninguno | ninguno     | ninguno   | ninguno  |
      | otra vez, con uno que la Federación publica y mi club dio de baja                | ya sincronizada y con uno dado de baja  | los mismos jugadores                                                 | ninguno  | los demás    | ninguno | 1       | ninguno     | ninguno   | ninguno  |
      | otra vez, con uno más en la Federación que mi club tiene en otro equipo          | ya sincronizada                         | los mismos y uno que mi club tiene en otro equipo                    | ninguno  | los de antes | ninguno | ninguno | 1           | ninguno   | ninguno  |
      | otra vez, con uno más en la Federación con el nombre de dos de mi club           | ya sincronizada                         | los mismos y uno con el nombre de dos jugadores de mi club           | 1        | los de antes | 1       | ninguno | ninguno     | 1         | ninguno  |
      | otra vez, con uno más en la Federación con un nombre que no vale                 | ya sincronizada                         | los mismos y uno con un nombre que no vale                           | ninguno  | los de antes | ninguno | ninguno | ninguno     | ninguno   | 1        |
      | otra vez, con dos más en la Federación que mi club no tiene                      | ya sincronizada                         | los mismos y dos que mi club no tiene                                | 2        | los de antes | 2       | ninguno | ninguno     | ninguno   | ninguno  |
      | otra vez, con dos más en la Federación que mi club tuvo otra temporada           | ya sincronizada                         | los mismos y dos que mi club tuvo en una temporada pasada, con año   | 2        | los de antes | ninguno | ninguno | ninguno     | ninguno   | ninguno  |
      | otra vez, con dos que la Federación publica y mi club dio de baja                | ya sincronizada y con dos dados de baja | los mismos jugadores                                                 | ninguno  | los demás    | ninguno | 2       | ninguno     | ninguno   | ninguno  |
      | otra vez, con dos más en la Federación que mi club tiene en otro equipo          | ya sincronizada                         | los mismos y dos que mi club tiene en otro equipo                    | ninguno  | los de antes | ninguno | ninguno | 2           | ninguno   | ninguno  |
      | otra vez, con dos más en la Federación, cada uno con el nombre de dos de mi club | ya sincronizada                         | los mismos y dos, cada uno con el nombre de dos jugadores de mi club | 2        | los de antes | 2       | ninguno | ninguno     | 2         | ninguno  |
      | otra vez, con dos más en la Federación con un nombre que no vale                 | ya sincronizada                         | los mismos y dos con un nombre que no vale                           | ninguno  | los de antes | ninguno | ninguno | ninguno     | ninguno   | 2        |

  @ui
  Scenario: El resumen nombra al jugador con nombre repetido, para revisarlo
    Given mi club tiene dos jugadores con el mismo nombre que uno que publica la Federación en la plantilla del equipo
    And estoy en la pestaña Plantilla del equipo, en la temporada en curso
    When sincronizo la plantilla
    Then el resumen de la sincronización nombra al jugador con nombre repetido, para revisarlo

  @ui
  Scenario: El resumen nombra al jugador que el club tiene en otro equipo de la temporada, con su equipo
    Given la Federación publica en la plantilla del equipo a un jugador que mi club tiene en otro equipo en la temporada en curso
    And estoy en la pestaña Plantilla del equipo, en la temporada en curso
    When sincronizo la plantilla
    Then el resumen de la sincronización nombra al jugador del otro equipo, con su equipo

  @ui
  Scenario: El resumen nombra al jugador con un nombre que no vale, para darlo de alta a mano
    Given la Federación publica en la plantilla del equipo a un jugador con un nombre que no vale
    And estoy en la pestaña Plantilla del equipo, en la temporada en curso
    When sincronizo la plantilla
    Then el resumen de la sincronización nombra al jugador con un nombre que no vale, para darlo de alta a mano

  # ── La ficha del jugador ──

  @ui
  Scenario: La ficha de un jugador federado dice cuándo lo publicó la Federación por última vez
    Given la plantilla del equipo ya se ha sincronizado con la Federación
    When abro la ficha de un jugador de la plantilla, en la temporada en curso
    Then la ficha del jugador dice "Federado"
    And la ficha del jugador dice la fecha y la hora de la última vez que lo publicó la Federación

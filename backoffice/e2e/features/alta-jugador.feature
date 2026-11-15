# El alta de un jugador en la plantilla, en un diálogo encima de ella (plan R6, decisiones 5, 7, 8, 9 y 10).
# El buscador encuentra a los jugadores del club que ya existen (su perfil, D-119), sin tildes ni mayúsculas y palabra
# a palabra; elegir uno crea solo su fila en esta plantilla, y el diálogo trae del perfil su último dorsal, su última
# demarcación y su última foto (D-122). La última opción es el jugador nuevo. Guardar copia esos tres al perfil.
# Los jugadores se inventan al azar; solo es fijo lo que decide la rama (un nombre de una palabra, un dorsal fuera de
# 1–99, una foto que no vale).
# Un jugador está en una sola plantilla por temporada (D-121): para cambiarlo de equipo, baja en uno y alta en otro.
#
# Vocabulario de los pasos:
# - «el diálogo del alta»: el que abre «Dar de alta un jugador» en la pestaña Plantilla.
# - «el buscador del alta»: su campo «Nombre y apellidos», con la lista que sale debajo al escribir.
# - «un jugador presente en el club»: uno con perfil en el club (fila en otro equipo o en otra temporada), y que no
#   está en esta plantilla.
# - «todos sus datos»: el nombre, el año, el dorsal, la demarcación y la foto.
# - «el perfil del jugador»: lo que devuelve de él la búsqueda de perfiles, por la API (`GET /player-profiles?q=`).
# - «el mismo nombre»: igual una vez en mayúsculas, con un solo espacio entre palabras y sin tildes ni diéresis
#   («GARCIA» es «GARCÍA»), como casa la sincronización (D-120, punto 4). La eñe cuenta como letra distinta
#   («MUNOZ» no es «MUÑOZ»).
Feature: El alta de un jugador

  # ── Abrir el diálogo ──

  @e2e
  Scenario: «Dar de alta un jugador» abre el diálogo del alta encima de la plantilla
    Given estoy en la pestaña Plantilla de la ficha de un equipo de mi club, en la temporada en curso
    When pulso el botón "Dar de alta un jugador" de la pestaña Plantilla
    Then el diálogo del alta está abierto
    And el título del diálogo del alta dice el equipo y la temporada en curso

  @ui
  Scenario: El diálogo del alta empieza con el buscador vacío
    Given estoy en la pestaña Plantilla de la ficha de un equipo de mi club, en la temporada en curso
    When pulso el botón "Dar de alta un jugador" de la pestaña Plantilla
    Then el buscador del alta está vacío y tiene el foco
    And el buscador del alta tiene la ayuda "Nombre y apellidos"

  # ── El buscador ──

  @ui
  Scenario: Al escribir tres letras del nombre de un jugador presente en el club, el buscador lo ofrece
    Given hay un jugador presente en el club
    And tengo abierto el diálogo del alta en la plantilla de un equipo de mi club, en la temporada en curso
    When escribo en el buscador del alta las tres primeras letras del nombre del jugador presente en el club
    Then el buscador del alta ofrece al jugador presente en el club
    And el jugador presente en el club sale en el buscador con su año de nacimiento
    And el jugador presente en el club sale en el buscador con su último equipo y su temporada

  @ui
  Scenario: Con menos de tres letras, el buscador no busca
    Given hay un jugador presente en el club
    And tengo abierto el diálogo del alta en la plantilla de un equipo de mi club, en la temporada en curso
    When escribo en el buscador del alta las dos primeras letras del nombre del jugador presente en el club
    Then el buscador del alta no ofrece ningún jugador

  @ui
  Scenario: El buscador encuentra sin tildes ni mayúsculas, palabra a palabra
    Given hay un jugador presente en el club con una tilde en el apellido
    And tengo abierto el diálogo del alta en la plantilla de un equipo de mi club, en la temporada en curso
    When escribo en el buscador del alta, en minúsculas y sin tildes, el comienzo de su nombre y el de su apellido
    Then el buscador del alta ofrece al jugador presente en el club

  @ui
  Scenario: El buscador no ofrece a quien ya está en esta plantilla
    Given un equipo de mi club tiene jugadores en la plantilla de la temporada en curso
    And tengo abierto el diálogo del alta en la plantilla del equipo, en la temporada en curso
    When escribo en el buscador del alta el nombre entero de un jugador de la plantilla
    Then el buscador del alta no ofrece a ese jugador

  @ui
  Scenario: La última opción del buscador es dar de alta lo escrito como jugador nuevo
    Given tengo abierto el diálogo del alta en la plantilla de un equipo de mi club, en la temporada en curso
    When escribo en el buscador del alta un nombre que mi club no tiene
    Then la última opción del buscador del alta dice "Dar de alta a" lo escrito "como jugador nuevo"

  # ── Elegir un jugador que ya existe ──

  @ui
  Scenario: Al elegir un jugador presente en el club, el diálogo trae lo de su perfil
    Given hay un jugador presente en el club con dorsal, demarcación y foto en su perfil
    And tengo abierto el diálogo del alta en la plantilla de un equipo de mi club, en la temporada en curso
    When elijo en el buscador del alta al jugador presente en el club
    Then el diálogo del alta tiene el nombre y el año del jugador presente en el club, bloqueados
    And el campo "Dorsal" del diálogo del alta tiene el dorsal de su perfil
    And el campo "Demarcación" del diálogo del alta tiene la demarcación de su perfil
    And el campo "Foto" del diálogo del alta tiene la foto de su perfil

  @e2e
  Scenario: Guardar un jugador presente en el club sin cambiar nada lo añade con lo de su perfil
    Given hay un jugador presente en el club con dorsal, demarcación y foto en su perfil
    And en el diálogo del alta de la plantilla de un equipo de mi club he elegido al jugador presente en el club
    When pulso "Guardar" en el diálogo del alta
    Then la fila del jugador presente en el club tiene su nombre y su año de siempre
    And la fila del jugador presente en el club tiene el dorsal de su perfil
    And la fila del jugador presente en el club tiene la demarcación de su perfil
    And la fila del jugador presente en el club tiene la foto de su perfil

  @e2e
  Scenario Outline: Cambiar <el dato> que trae el perfil lo guarda en la plantilla y en el perfil
    Given hay un jugador presente en el club con dorsal, demarcación y foto en su perfil
    And en el diálogo del alta de la plantilla de un equipo de mi club he elegido al jugador presente en el club y he cambiado <el dato>
    When pulso "Guardar" en el diálogo del alta
    Then la fila del jugador presente en el club tiene <el dato> que he puesto
    And el perfil del jugador presente en el club tiene <el dato> que he puesto

    Examples:
      | el dato         |
      | el dorsal       |
      | la demarcación  |
      | la foto         |

  @e2e
  Scenario: Borrar lo que trae el perfil lo deja vacío en la plantilla y en el perfil
    Given hay un jugador presente en el club con dorsal, demarcación y foto en su perfil
    And en el diálogo del alta de la plantilla de un equipo de mi club he elegido al jugador presente en el club y he borrado su dorsal, su demarcación y su foto
    When pulso "Guardar" en el diálogo del alta
    Then la fila del jugador presente en el club no tiene dorsal
    And la fila del jugador presente en el club no tiene demarcación
    And la fila del jugador presente en el club no tiene foto
    And el perfil del jugador presente en el club no tiene dorsal, ni demarcación, ni foto

  # ── Un jugador nuevo ──

  @ui
  Scenario: Un jugador nuevo pide el nombre y el año; el dorsal, la demarcación y la foto son opcionales
    Given tengo abierto el diálogo del alta en la plantilla de un equipo de mi club, en la temporada en curso
    When elijo en el buscador del alta dar de alta lo escrito como jugador nuevo
    Then el campo "Nombre y apellidos" del diálogo del alta es obligatorio y tiene lo escrito
    And el campo "Año de nacimiento" del diálogo del alta es obligatorio
    And el campo "Dorsal" del diálogo del alta es opcional, con la ayuda "Del 1 al 99"
    And el campo "Demarcación" del diálogo del alta es opcional
    And el campo "Foto" del diálogo del alta es opcional, con la ayuda "JPEG o PNG, hasta 5 MB"

  @e2e
  Scenario: Guardar un jugador nuevo sin ningún campo opcional lo añade a la plantilla solo con su nombre y su año
    Given en el diálogo del alta de la plantilla de un equipo de mi club he rellenado un jugador nuevo solo con su nombre y su año
    When pulso "Guardar" en el diálogo del alta
    Then la fila del jugador nuevo tiene su nombre y su año
    And la fila del jugador nuevo no tiene dorsal
    And la fila del jugador nuevo no tiene demarcación
    And la fila del jugador nuevo no tiene foto
    And el perfil del jugador nuevo tiene su nombre y su año, sin dorsal, ni demarcación, ni foto

  @e2e
  Scenario Outline: Guardar un jugador nuevo solo con <el dato>, además del nombre y el año
    Given en el diálogo del alta de la plantilla de un equipo de mi club he rellenado un jugador nuevo con su nombre, su año y solo <el dato>
    When pulso "Guardar" en el diálogo del alta
    Then la fila del jugador nuevo tiene <el dato> que he puesto
    And la fila del jugador nuevo no tiene <los otros>
    And el perfil del jugador nuevo tiene <el dato> que he puesto
    And el perfil del jugador nuevo no tiene <los otros>

    Examples:
      | el dato         | los otros                  |
      | el dorsal       | demarcación, ni foto       |
      | la demarcación  | dorsal, ni foto            |
      | la foto         | dorsal, ni demarcación     |

  @e2e
  Scenario: Guardar un jugador nuevo con todos los campos opcionales los guarda en la plantilla y en el perfil
    Given en el diálogo del alta de la plantilla de un equipo de mi club he rellenado un jugador nuevo con todos sus datos
    When pulso "Guardar" en el diálogo del alta
    Then la fila del jugador nuevo tiene su nombre y su año
    And la fila del jugador nuevo tiene el dorsal que he puesto
    And la fila del jugador nuevo tiene la demarcación que he puesto
    And la fila del jugador nuevo tiene la foto que he puesto
    And el perfil del jugador nuevo tiene el dorsal, la demarcación y la foto que he puesto

  @ui
  Scenario: El buscador ofrece al jugador del club aunque se escriba su nombre entero, y deja dar de alta a otro con el mismo nombre
    Given hay un jugador presente en el club
    And tengo abierto el diálogo del alta en la plantilla de un equipo de mi club, en la temporada en curso
    When escribo en el buscador del alta el nombre entero del jugador presente en el club
    Then el buscador del alta ofrece al jugador presente en el club, con su año y su último equipo
    And la última opción del buscador del alta dice "Dar de alta a" lo escrito "como jugador nuevo"

  @e2e
  Scenario Outline: Dar de alta como nuevo a un jugador con el mismo nombre que otro del club, <cómo>, crea un perfil más
    Given hay un jugador presente en el club
    And en el diálogo del alta de la plantilla de un equipo de mi club he rellenado como jugador nuevo uno con el nombre del jugador presente en el club, <cómo>, y otro año
    When pulso "Guardar" en el diálogo del alta
    Then la plantilla tiene al jugador nuevo, con su año
    And mi club tiene ahora dos perfiles con el mismo nombre

    Examples:
      | cómo                      |
      | escrito igual             |
      | sin una tilde que él tiene |

  @e2e
  Scenario: Al volver a la plantilla tras el alta, un aviso dice que se ha guardado
    Given en el diálogo del alta de la plantilla de un equipo de mi club he rellenado un jugador nuevo con todos sus datos
    When pulso "Guardar" en el diálogo del alta
    Then la pestaña Plantilla avisa "Guardado"

  @e2e
  Scenario: «Guardar y dar de alta otro» guarda y deja el diálogo abierto y vacío
    Given en el diálogo del alta de la plantilla de un equipo de mi club he rellenado un jugador nuevo con todos sus datos
    When pulso "Guardar y dar de alta otro" en el diálogo del alta
    Then el diálogo del alta sigue abierto
    And el buscador del alta está vacío y tiene el foco
    And el diálogo del alta avisa que el jugador nuevo se ha guardado

  @e2e
  Scenario: Cancelar el alta no da de alta a nadie
    Given un equipo de mi club tiene jugadores en la plantilla de la temporada en curso
    And en el diálogo del alta de la plantilla del equipo he rellenado un jugador nuevo con todos sus datos
    When pulso "Cancelar" en el diálogo del alta
    Then la plantilla tiene los mismos jugadores que antes de abrir el diálogo

  # ── Lo que el alta no deja guardar ──

  @ui
  Scenario: Guardar un jugador nuevo sin nombre ni año dice qué falta
    Given en el diálogo del alta de la plantilla de un equipo de mi club he elegido dar de alta un jugador nuevo
    And he borrado el nombre del diálogo del alta
    When pulso "Guardar" en el diálogo del alta
    Then el campo "Nombre y apellidos" del diálogo del alta dice "Escribe el nombre y al menos un apellido"
    And el campo "Año de nacimiento" del diálogo del alta dice "Falta el año de nacimiento"

  @ui
  Scenario Outline: Un nombre <cómo> no se guarda
    Given en el diálogo del alta de la plantilla de un equipo de mi club he elegido dar de alta un jugador nuevo
    And he escrito en el nombre del diálogo del alta un nombre <cómo>
    When pulso "Guardar" en el diálogo del alta
    Then el campo "Nombre y apellidos" del diálogo del alta dice "<aviso>"

    Examples:
      | cómo                    | aviso                                                                  |
      | de una sola palabra     | Escribe el nombre y al menos un apellido                               |
      | con un número           | Solo letras, espacios, guion y apóstrofo                               |
      | con un símbolo          | Solo letras, espacios, guion y apóstrofo                               |
      | de más de 120 letras    | Como mucho, 120 letras                                                 |

  @ui
  Scenario: Un dorsal que ya tiene otro jugador del equipo dice quién lo tiene
    Given un equipo de mi club tiene jugadores con dorsal en la plantilla de la temporada en curso
    And en el diálogo del alta de la plantilla del equipo he rellenado un jugador nuevo con el dorsal de otro jugador
    When pulso "Guardar" en el diálogo del alta
    Then el campo "Dorsal" del diálogo del alta dice "ya lo tiene" y el nombre del otro jugador

  @ui
  Scenario Outline: Un dorsal <cuál> no se guarda
    Given en el diálogo del alta de la plantilla de un equipo de mi club he elegido dar de alta un jugador nuevo
    And he escrito en el dorsal del diálogo del alta "<dorsal>"
    When pulso "Guardar" en el diálogo del alta
    Then el campo "Dorsal" del diálogo del alta dice "Del 1 al 99"

    Examples:
      | cuál            | dorsal |
      | cero            | 0      |
      | de tres cifras  | 100    |

  @ui
  Scenario: Un jugador que ya está en otra plantilla de la temporada sale en el buscador, desactivado
    Given mi club tiene un jugador en la plantilla de otro equipo en la temporada en curso
    And tengo abierto el diálogo del alta en la plantilla de un equipo de mi club, en la temporada en curso
    When escribo en el buscador del alta el nombre entero del jugador de la otra plantilla
    Then el buscador del alta enseña al jugador de la otra plantilla, desactivado
    And el jugador de la otra plantilla sale en el buscador con "Ya está en" y el nombre de su equipo

  # ── La foto en el alta ──

  @ui
  Scenario Outline: Una foto <cuál> deja al jugador dado de alta, sin foto, y lo avisa
    Given en el diálogo del alta de la plantilla de un equipo de mi club he rellenado un jugador nuevo con una foto <cuál>
    When pulso "Guardar" en el diálogo del alta
    Then la pestaña Plantilla avisa "Guardado, sin la foto:" y "<motivo>"

    Examples:
      | cuál                       | motivo                            |
      | que no es una imagen       | el fichero no es una imagen       |
      | de más de 5 MB             | pesa más de 5 MB                  |
      | en un formato que no es JPEG ni PNG | solo JPEG o PNG          |

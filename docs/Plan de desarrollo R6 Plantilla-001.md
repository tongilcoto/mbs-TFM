# Plan de desarrollo R6 · Plantilla

> Rebanada 6 del [plan de desarrollo del backoffice](./Plan%20de%20desarrollo%20backoffice-001.md) (§4). Como las
> rebanadas [1](./Plan%20de%20desarrollo%20R1%20Portada%20base-001.md) a
> [5](./Plan%20de%20desarrollo%20R5%20Portada%20del%20boceto-001.md), toca la web y el servidor, y lo que se haga en
> el servidor se apunta **solo aquí**.
>
> Parte de: el [LLD del backoffice](./Backoffice%20LLD-001.md) y su
> [anexo de decisiones](./Backoffice%20LLD-Anexo-Decisiones-Disenho-001.md); el
> [LLD del backend](./API_y_BBDD%20LLD-001.md) y su
> [bitácora de decisiones](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md); el boceto 5
> ([`5-Team-Roster.png`](./design-assets/mobile/5-Team-Roster.png)); y la rebanada 5, cerrada el 2026-11-14 con
> su mini-fase `R5.12`: **853 tests** en el backend y, en la web, **453 pruebas de piezas y 170 escenarios**.
>
> **Convención de remisiones**, la de siempre: `LLD-B §x` y `DW-nn` son el LLD de la web y su anexo; `LLD §x` y
> `D-nn`, el LLD del backend y su bitácora.
>
> **Este fichero es plan y registro a la vez.** Un paso sin su renglón de estado no está hecho.
>
> **Estado del documento: las nueve decisiones de la §4, revisadas una a una con el desarrollador el 2026-11-14**,
> con una maqueta en HTML para la 7 y lo medido en la RFFM para la 9. La revisión añadió dos decisiones que no
> estaban: **el jugador que dura entre temporadas** (8, `D-119`, enmienda a `D-05`) y **sincronizar la plantilla con
> la federación** (9, `D-120`), que la RFFM publica.
> Al revisar los escenarios (`R6.3`, 2026-11-15) salieron dos más: **un jugador, una plantilla por temporada**
> (`D-121`, dentro de la 9) y **el perfil guarda el último dorsal, demarcación y foto** (10, `D-122`).
> **Dos ramas**, como en la R5: el servidor en `feature/plantilla-backend` (partes A y B) y la web en otra.

---

## 1. Objetivo

**El club da de alta la plantilla de cada equipo y ve la ficha de cada jugador**: su nombre, su dorsal, su
demarcación y su foto. Puede corregirlos, quitar la foto y dar de baja a un jugador.

**Por qué ahora**: es lo primero que el club escribe a mano, sin la federación detrás (la federación no publica
plantillas de fútbol base). Y lo necesitan las rebanadas siguientes: el acta (R7) apunta goles y tarjetas a un
jugador, las ausencias (R8) son de un jugador, y las cifras (R10) se cuentan por jugador.

---

## 2. Qué se tiene al terminar

| Qué | Dónde se describe |
|---|---|
| **La pestaña Plantilla** de la ficha del equipo: los jugadores del equipo en esa temporada, por dorsal | §3 · decisión 7 |
| **Dar de alta, corregir y dar de baja a un jugador** | §3 · decisiones 5 y 7 |
| **La ficha del jugador**, con sus datos y su foto, y subir o quitar la foto | §3 · decisiones 1 a 3 y 6 |
| **El alta elige el jugador**: uno que ya existe, con un buscador, o uno nuevo | §4 · decisiones 8 y 9 |
| **«Sincronizar con la Federación»** en la plantilla, si la federación la publica: da de alta a quien falte, y cada jugador dice si está federado | §4 · decisión 9 |
| En el servidor, **las 7 operaciones de jugadores y 2 nuevas** (buscar perfiles y sincronizar), las tablas del jugador y su perfil, y el sitio donde se guardan las fotos | §5 |

**Lo que no trae** (llega después): la disponibilidad y las ausencias (R8); las cifras de cada jugador, sus
tarjetas y sus goles (R10); y **arrastrar la plantilla de una temporada a la siguiente**, que sigue abierto
(LLD §9, punto 8).

---

## 3. La ficha de las pantallas

### La pestaña Plantilla (`/temporadas/:temporada/equipos/:id/plantilla`)

La tercera pestaña de la ficha del equipo, hermana de Resultados (R4) y Estadísticas (R10), con la misma
cabecera.

**Lo que enseña el boceto 5 de cada jugador, y qué entra en esta rebanada:**

| Dato | ¿En la R6? | De dónde sale |
|---|---|---|
| La foto, o sus iniciales si no tiene | Sí | `photoUrl` (decisiones 1 a 3) |
| El dorsal | Sí | `shirtNumber` |
| El nombre | Sí | `fullName` |
| La demarcación (Portero, Defensa…) | Sí | `position` |
| Tarjetas amarillas y rojas | No: R10 | — |
| Disponible / No disponible, y desde cuándo | No: R8 | — |
| Jugados, baja médica, sanción | No: R8 y R10 | — |
| Los goles y cómo se marcaron | No: R10 | — |

*(La réplica de cómo quedaría, con datos inventados, se pone aquí al cerrar la decisión 7.)*

### La ficha del jugador (`/jugadores/:id`, decisión 6)

Sus datos, su foto, y las acciones de corregir, subir o quitar la foto y dar de baja.

### Los casos que el boceto no enseña

- **Un equipo sin jugadores**: no es un error; un mensaje que lo dice y lleva a dar de alta el primero
  (LLD-B §4).
- **Un jugador sin foto**: sus iniciales; es lo normal, no un alta a medias.
- **La foto se describe con el nombre del jugador**: la web le pone como texto alternativo el nombre formateado,
  al pintarla; no se guarda en ningún sitio, ni en la base ni dentro del fichero (R6.3, 2026-11-15).
- **Un jugador sin dorsal** (decisión 5): sin número, y al final de la lista, por nombre.
- **Un dorsal repetido** en el mismo equipo y temporada: el servidor lo rechaza (409), y el formulario lo dice
  junto al dorsal.
- **Una temporada archivada**: se ve, pero no se cambia: ni dar de alta, ni sincronizar, ni corregir, ni dar de baja
  (422). La web no enseña esos botones ni las acciones de las filas (R6.3, 2026-11-15).
- **Un equipo rival**: no tiene plantilla; la pestaña no se ofrece.
- **Una foto que no vale** (no es imagen, pesa más de 5 MB, o es un formato que no es JPEG ni PNG): un aviso
  que dice cuál de las tres.
- **Un jugador dado de baja**: deja de verse, y su dorsal queda libre.

---

## 4. Decisiones antes de construir

**Revisadas una a una con el desarrollador** (`R6.1`, 2026-11-14), cada una con lo que hizo falta para verla. Lo
que ya estaba decidido en el LLD del backend y sigue igual (`D-35`, `D-36`, `D-37`): el equipo y la temporada que
no se cambian, la baja que esconde sin borrar, y la foto que entra aparte y saneada.

### Decisión 1 · Dónde se guardan las fotos mientras no hay Supabase: en una carpeta del disco

**El problema.** Lo decidido para producción es Supabase Storage (ADR del backend, punto 2), pero en desarrollo
no hay nada de Supabase: el servidor corre en el Mac y Docker solo levanta Postgres. Ni los escudos se guardan
todavía (`D-19`): `ClubHandler` devuelve su enlace vacío, con un `TODO` a la espera del almacén.

**Las opciones.** En las tres, el servidor habla con el almacén a través de un puerto propio, así que pasar a
Supabase al desplegar es cambiar una pieza.

| Opción | A favor | En contra |
|---|---|---|
| **A. Una carpeta del disco**, elegida en la configuración | Nada que instalar ni levantar; las fotos se ven con el Finder; cada base con su carpeta | La pieza de Supabase se escribe y se prueba en la R16 |
| B. Supabase Storage de verdad, ya | Lo de producción, sin traducir nada después | Cuenta y claves ya; los escenarios dependerían de internet; fotos de menores en la nube antes de tiempo |
| C. MinIO en Docker, que habla S3 como Supabase Storage | La pieza valdría casi tal cual para Supabase | Un contenedor más y una librería de S3 en el servidor |

**Decidido (2026-11-14): A** → [`D-115`](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md).

- **El almacén, un puerto** (guardar, leer y borrar por clave); la carpeta, su adaptador; Supabase, otro
  adaptador en la R16.
- **La carpeta, en la configuración**: la del desarrollador, la de los escenarios (`tfm_test`) y la de cada
  prueba, distintas.
- **La clave lleva el club delante**, y es **nueva en cada subida** (enmendado en `R6.4`): no sale del `playerId`,
  porque una foto puede ser de varias filas y de su perfil (decisión 10), y subir otra a una fila pasada cambiaría
  la de la temporada en curso.
- **El escudo del club usará el mismo almacén** cuando le toque.

### Decisión 2 · Cómo se limpia la foto en el servidor: con dos librerías escritas en Swift

**El problema.** La API comprueba que la foto es de verdad un JPEG o un PNG, la guarda como JPEG, la reduce y le
quita lo que lleva dentro (`D-35`), igual en el Mac y en el contenedor Ubuntu de producción, que hoy no instala
ninguna herramienta de imágenes. Lo que solo hay en Mac (`sips`, las librerías de Apple) no vale.

| Opción | A favor | En contra |
|---|---|---|
| A. Llamar a ImageMagick | Muy conocida; gira, reduce y quita los datos con una orden | Un programa aparte en el Mac y en el contenedor; fallos graves con ficheros preparados a mala fe, y reglas para limitarla que alguna vez se han saltado |
| B. libvips | Rápida | Instalarla en los dos sitios, sin una forma cuidada de usarla desde Swift |
| **C. `swift-jpeg` y `swift-png`** | Dentro del servidor, sin instalar nada; abrir la foto y volver a guardarla desde sus puntos de color no deja pasar nada de dentro; solo entienden JPEG y PNG | De un único autor y poco usadas; el giro y la reducción, código nuestro; la velocidad, sin medir |

**Decidido (2026-11-14): C** → [`D-116`](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md).

- **Primero se gira** según la nota de orientación del móvil, y después se guarda sin ella: si no, la foto sale
  tumbada.
- **Se comprueba al empezar `R6.8`** con una foto de verdad del móvil del desarrollador: cuánto tarda, que sale
  derecha y que no le queda nada dentro. Si falla, se vuelve aquí y se elige A.
- **La licencia se mira en el repositorio** antes de añadirlas (un registro dice Apache 2.0 y otro MPL 2.0).

**Comprobado al empezar `R6.8`** (2026-11-16), con una foto HEIC del iPhone del desarrollador (5712 × 4284, con
la nota de orientación 6 y la ubicación), pasada a JPEG sin quitarle nada:

- **Las licencias**: Apache 2.0 las dos (`swift-jpeg` 2.1.0 y `swift-png` 4.5.2) y las dos pequeñas que traen.
- **La velocidad**: el paso de la librería que junta los colores a tamaño completo tardaba 11 s en una foto de
  12 megapíxeles. **Se hace con código nuestro**, que junta los colores a la vez que reduce: la foto entera queda
  en **unos 2 s**.
- **Sale derecha**: las ocho orientaciones posibles salen como las gira Apple.
- **No le queda nada dentro**: ni la ubicación, ni la marca y el modelo del móvil.

**El tamaño, decidido (2026-11-16): 800 puntos en el lado largo**, comparado con la foto a 400, 640, 800, 1024 y
1600, como se ve en la fila y en la ficha. La ficha la enseña a 240 × 320 y una pantalla de Mac necesita el doble;
con 800 sobra también en el móvil. Unos 33 KB por foto. **Un solo tamaño**: la fila usa la misma, y la que es más
pequeña no se agranda.

**La calidad, decidida (2026-11-16): 75**, en la escala de 0 a 100 de los programas de fotos, comparada con 50, 75,
85, 90 y 95 en la ficha y con lupa sobre la cara. Bien en la ficha, con algo de ruido solo mirando de cerca: unos
43 KB por foto y 1 MB la plantilla de 25. La librería usa otra escala; la traducción, código nuestro.

**Un tope de puntos, decidido (2026-11-16): 30 millones**, leídos en la cabecera **antes de abrir la foto**. Salió
al probar: un PNG de 1,2 MB y 20.000 × 20.000 puntos pasa el tope de 5 MB y costó 35 s y 1,9 GB de memoria, lo
bastante para tumbar el contenedor. La foto normal de un móvil (la del desarrollador, 24,5 millones) entra con
margen y pide unos 250 MB; una de 48 megapíxeles casi nunca baja de 5 MB. Responde **413**, como el tope de peso:
para quien la sube es lo mismo, «demasiado grande». Se escribe en el catálogo con la operación, en `R6.9`.

**Dónde va el código, decidido (2026-11-16): dos piezas nuevas del servidor.** Las dos reglas («guardar, leer y
borrar una foto por su clave» y «sanear una foto») van en `Application`, como los demás puertos; lo que hace el
trabajo, en `Storage` (la carpeta, y Supabase en la R16) y en `Imaging` (el saneado, la única que ve las dos
librerías). Cambian por motivos distintos y así cada cambio toca una sola; sus tests corren sin Docker, como los
de `Federation`. Se descartaron una sola pieza para las dos cosas y meterlas en `Persistence`, que es la de Postgres.

**La carpeta en el Mac, decidida (2026-11-16): `backend/fotos/`, sin grabar** (en `.gitignore`), o la de
`PHOTOS_DIR`. A mano junto al proyecto; el desarrollador no usa fotos de verdad, así que no importa que Obsidian
la vea. Se descartaron una carpeta fuera del repositorio y no tener ninguna por defecto.

### Decisión 3 · Cómo llega la foto a la web: un enlace firmado de una hora

**El problema.** `photoUrl` es un enlace firmado que caduca (`D-35`), pero con la carpeta del disco nadie lo hace.
Y con el inicio de sesión (R16) la web manda su permiso en una cabecera, que una imagen puesta en la página no
puede mandar: el navegador la pide solo. La firma hace de permiso dentro del enlace.

| Opción | A favor | En contra |
|---|---|---|
| **A. Un enlace firmado que caduca, hecho por nuestro servidor**, y una ruta que entrega el fichero si la firma vale | Igual que Supabase: la web pone la imagen y ya está, hoy y en la R16; la foto de un menor nunca queda abierta | Una ruta y una clave secreta más; una página abierta más de una hora enseña las iniciales hasta recargar |
| B. Una ruta sin firma, `GET /players/{id}/photo` | Lo más simple hoy | En la R16, o queda abierta o la web pide cada foto con su permiso y la monta ella |
| C. La foto dentro de la respuesta, como texto | Ninguna petición más | Cerca de 2 MB por plantilla. Descartada |

**Decidido (2026-11-14): A** → [`D-117`](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md). Se revisó con un
dibujo de los dos caminos: ahora, nuestro servidor firma el enlace y, cuando el navegador pide la imagen, mira la
firma y la hora y lee la carpeta; con Supabase, nuestro servidor le pide el enlace a Supabase y el navegador pide
la imagen directamente a Supabase Storage. La web no nota la diferencia.

- **El enlace dura una hora y se hace nuevo en cada lectura.** Cierra el punto 7 de la §9 del LLD.
- **La ruta que entrega el fichero entra en el catálogo como la operación 86** (decidido en `R6.4`, 2026-11-15):
  `getPlayerPhotoFile`, `GET /player-photos/{clave}` con la hora en que caduca y la firma. Va por la clave del
  fichero y no por el jugador, porque una foto puede ser a la vez de la fila y del perfil (`D-122`). Una firma que
  no vale o ha caducado contesta 404, igual que una foto que no existe, para no decir qué claves hay. Su
  descripción dice que solo existe mientras las fotos están en el disco: en la R16, con Supabase, desaparece.
  Descartado dejarla aparte, sin contar: habría que enseñar al censo a saltársela. Sirve igual para los escudos.

**Decidido al empezar `R6.9`** (2026-11-16), una a una:

- **A dónde apunta el enlace: un prefijo en la configuración**, `PHOTOS_URL_PREFIX`, por defecto `/api`. La web
  no habla con el servidor directamente: su recepcionista pasa lo que empieza por `/api`, quitándolo y dejando el
  club en la dirección. Con el prefijo, `photoUrl` es `/api/v1/player-photos/…` y la web lo usa tal cual, como
  hará con el de Supabase. Descartados que la web le añada el `/api` (tendría que distinguir los dos enlaces) y
  una dirección completa con el puerto de la web (que hoy solo sabe la web). En la R16 el ajuste desaparece con
  la ruta.
- **Qué lleva la ruta: solo el fichero** (`<código>.jpg`); **el club sale de la dirección**, como en el resto de
  la API. La clave lleva una barra (`<club>/<código>.jpg`), que dentro de un trozo de ruta habría que escribir
  `%2F`, y no todos los programas del camino lo entienden igual. La firma cubre la clave entera, con su club: el
  enlace de un club no vale en la dirección de otro, y da 404. Descartados la clave entera con `%2F` y el club y
  el fichero en dos trozos (el club iría dos veces). En el catálogo cambia solo la descripción del trozo.
- **La clave secreta: `PHOTOS_SIGNING_KEY` si está; si no, una al azar al arrancar**, que no se guarda. Firma
  con HMAC-SHA256, de una librería que el servidor ya tiene. Al relanzar, los enlaces de antes dejan de valer y la
  página enseña las iniciales hasta recargar, como al pasar la hora. Descartados hacerla obligatoria (un ajuste
  más en el Mac, los escenarios y cada test, para que el enlace sobreviva a un relanzamiento) y una clave fija en
  el código (cualquiera que lea el repositorio fabricaría enlaces).
- **Los códigos de error de la subida, con nombre de imagen**: `NOT_AN_IMAGE` (400), `IMAGE_TOO_LARGE` (413, por
  peso o por puntos, y el detalle dice cuál) y `UNSUPPORTED_IMAGE_TYPE` (415). Valen tal cual para el escudo, que
  pasará por el mismo saneado (`D-19`). Descartados los de foto (el escudo necesitaría otros casi iguales) y los
  generales (el 400 se confundiría con cualquier petición mal hecha).
- **Un fallo de la R6.6, encontrado al conectar la foto: el alta con un perfil le borraba la foto al perfil**
  (copiaba la de una fila vacía). **Decidido: la fila empieza con la foto del perfil**, como en la sincronización
  y como enseña el diálogo (`D-122`, corregido). Descartado que empiece sin foto: habría que volver a subirla.
  Grabado aparte, antes que la R6.9.

### Decisión 4 · Los permisos («rol elevado»): sin comprobar hasta la rebanada 16

El catálogo pide rol elevado (LLD §7.3) para dar de alta, corregir y dar de baja a un jugador, y para subir o
quitar su foto; leer, no. Hoy no hay inicio de sesión: solo una pieza que saca el club de la dirección
(`AmbientTenantActorResolver`), pensada para cambiarse sola en la R16.

| Opción | Veredicto |
|---|---|
| **(a) Como `createTeam` en la R2: sin comprobar hasta la R16** | **Elegida (2026-11-14)** |
| (b) Preparar ya la comprobación, con una pieza que de momento siempre dice «sí» | Descartada: los permisos se hacen de una vez, para todas las operaciones, en la R16 |

Sin entrada en ninguna bitácora: es lo que ya se hace con el resto de operaciones.

### Decisión 5 · El dorsal: opcional, y sin repetir entre los que lo tienen

**El problema.** El catálogo pedía a todo jugador un dorsal del 1 al 99, sin repetir en su equipo y temporada.
Pero en la federación el dorsal es de cada partido: el acta de la RFFM lo trae junto a cada jugador de ese partido
(anexo RFFM §F.10), y nada obliga a un club a llevar dorsales fijos.

| Opción | Veredicto |
|---|---|
| (a) Obligatorio y sin repetir, como estaba | Descartada: un equipo sin dorsales fijos tendría que inventárselos |
| **(b) Opcional, y sin repetir entre los que lo tienen** | **Elegida (2026-11-14)** → [`D-118`](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md) |

- **Tiene que valer para cualquier club**, no para el del desarrollador (lo pidió él).
- **Lo que no puede pasar es repetir número** en el mismo equipo y temporada (409). Los que no tienen no chocan.
- **El 409 lleva solo su código, `SHIRT_NUMBER_TAKEN`** (decidido en `R6.4`, 2026-11-15): quién tiene el dorsal lo
  busca la web en la plantilla que ya pinta. Como el enganche, cuyo 409 solo trae su código y la vista previa dice
  antes con quién choca (`D-110`). Descartado que el *Problem* lleve el jugador: un campo nuevo en todos los errores,
  y el nombre de un menor en uno. Si otro usuario cambia la plantilla a la vez, la web dice solo «ya está cogido».
- **La plantilla, por dorsal**, y después los que no tienen, por nombre.
- **El dorsal del acta va aparte**: lo manda la federación y no lo controlamos; se guarda con el partido (R7), sin
  comprobarlo contra el de la plantilla.

### Decisión 6 · El camino de la ficha del jugador: con la temporada delante

El mapa tenía `/jugadores/:id` como borrador (LLD-B §6.1), y desde la R4 lo que es de una temporada lleva la
temporada en el camino (`DW-22`).

| Opción | Ejemplo | Veredicto |
|---|---|---|
| (a) Sin temporada, como el borrador | `/jugadores/:id` | Descartada **para esta versión**: sería la única pantalla de una temporada sin ella en el camino |
| **(b) Con la temporada delante** | `/temporadas/2025-26/jugadores/:id` | **Elegida (2026-11-14)**, como las competiciones |
| (c) Dentro de su equipo | `/temporadas/2025-26/equipos/:id/jugadores/:id` | Descartada: la más larga, y a la ficha también se llegará desde Estadísticas (R10) |

- **`:id` es el jugador en esa temporada**; si la temporada del camino no casa, la pantalla de «no se ha
  encontrado», como con una competición de otra temporada.
- **Al revisarla, el desarrollador señaló que un jugador no es efímero como una competición**: su nombre y su
  nacimiento son datos de una persona que sigue de un año a otro. De ahí la decisión 8. **Para una versión
  siguiente** (el año que viene) queda una pantalla del jugador de todas sus temporadas, `/jugadores/:id`, con el
  código del jugador que dura, no el de una temporada.

### Decisión 7 · Cómo se ve la plantilla: una tabla; el alta en un diálogo; corregir y dar de baja, en la ficha

**Revisada el 2026-11-14 sobre una maqueta en HTML** (con datos inventados; no se guarda en el repositorio, como
en la R3 y la R4): la plantilla como tabla y como tarjetas, sin jugadores, el diálogo del alta, la ficha y la
confirmación de la baja. **Decidido (2026-11-14): la propuesta entera.**

| Parte | Opciones | Elegida |
|---|---|---|
| **(a) La plantilla** | Tabla, o tarjetas como el boceto 5 | **Tabla**: como la portada y Resultados. Las tarjetas, con solo cuatro datos hasta la R8 y la R10, se quedan para el móvil |
| **(b) El alta** | Un diálogo encima de la plantilla, o una pantalla aparte como el alta de equipo | **Diálogo**, con «Guardar y dar de alta otro»: una plantilla de 25 se teclea sin salir de ella |
| **(c) Corregir y dar de baja** | Solo en la ficha del jugador, o también con iconos en cada fila | **En cada fila y en la ficha** (enmienda del 2026-11-14, al ver la maqueta sin ellos: el desarrollador se había perdido esa parte entre tantas vueltas) |

- **Columnas**: foto (o iniciales), dorsal, nombre, demarcación y año de nacimiento. Por dorsal, y los que no
  tienen, al final por nombre.
- **La foto se puede poner en el alta**: el servidor la recibe en una segunda petición (`D-35`), pero es un solo
  «Guardar». Si falla, el jugador queda dado de alta sin foto, con un aviso.
- **El dorsal cogido**: el aviso dice quién lo tiene.
- **En la fila**: el nombre lleva a la ficha; **✎ abre el diálogo de corregir y 🗑 la confirmación de la baja ahí
  mismo**, sin salir de la plantilla, y al acabar se sigue en ella. En la ficha, «Corregir» y «Dar de baja» abren
  los mismos diálogos.
- **Corregir** abre el mismo diálogo del alta, con sus datos, **separados en dos bloques**: «Del jugador, en todas
  sus temporadas» (el nombre y el año, del perfil, decisión 8) y «En el Cadete A, 2025/26» (dorsal, demarcación y
  foto). **Si se cambia el nombre o el año, el diálogo avisa antes de guardar** de que cambia el perfil del jugador
  en todas sus temporadas. Cuidado: hoy la pantalla mezcla los dos, y es lo que más se puede confundir.
- **La baja pide confirmación**: deja de salir en la plantilla, su dorsal queda libre y sus goles y tarjetas siguen
  contando. Después, de vuelta a la plantilla con un aviso, como el «Guardado» de la R2.
- **La foto se cambia o se quita en la ficha.**

### Decisión 8 · El jugador que dura más que una temporada (enmienda a `D-05`)

Abierta al revisar la decisión 6: en esta versión, la fila del jugador en una temporada lleva el código de un
jugador que dura (una clave ajena), como el equipo y su inscripción (`D-102`). `D-05` lo había descartado («no hay
identidad "persona" estable entre filas»).

**El reparto de los datos** (aceptado el 2026-11-14):

| Dónde | Qué datos |
|---|---|
| **El jugador**, que dura | El nombre (y la fecha de nacimiento, si entra: punto siguiente) |
| **El jugador en una temporada** (la fila de hoy, con la clave del jugador) | El equipo, la temporada, el dorsal, la demarcación y la foto: cambian cada año |

- **El alta en la plantilla crea a la vez el jugador y su fila** de esa temporada. Elegir uno que ya existe llega
  con la versión siguiente o con el alta en bloque (LLD §9, punto 8).
- **Goles, tarjetas y ausencias (R7, R8) apuntan a la fila de la temporada**: cuentan para el equipo con el que se
  hicieron.
- **Corregir el nombre corrige el del jugador**, en todas sus temporadas.
- **El código de la federación del jugador** (`codjugador` del acta) **es informativo**: nunca sirve para que el
  sistema funcione (ni para casar jugadores). Lo dijo el desarrollador.

**El nacimiento: solo el año, opcional** (2026-11-14), en el jugador que dura. Es un dato de un menor, y el RGPD
pide guardar solo lo que hace falta (ADR, requisito 7): en fútbol base la categoría sale del año, y el día y el mes
no deciden nada. En esta rebanada solo se guarda y se enseña en la ficha; no se comprueba contra la categoría del
equipo, porque un chaval puede jugar en una superior.

| Opción | Veredicto |
|---|---|
| (a) Nada por ahora | Descartada: es un dato real de la persona |
| (b) La fecha completa, opcional | Descartada: lo que más identifica a un menor, para nada que el sistema use |
| **(c) Solo el año, opcional** | **Elegida** |

**Los nombres en el catálogo: `Player` se queda como está** (2026-11-14), la fila de la temporada, y el que dura
es una pieza nueva, **`PlayerProfile`**.

| Opción | Veredicto |
|---|---|
| (a) Como los equipos: `Player` pasa a ser el que dura, y la fila, `PlayerRegistration` | Descartada: cambian las 7 operaciones y lo que `playerId` significa en ausencias, convocatorias, tarjetas y goles; y un jugador que cambia de equipo a mitad de temporada tiene dos filas en ella, una dada de baja (`D-37`), así que la ruta de los equipos no le sirve |
| **(c) `Player` se queda; el que dura, `PlayerProfile`** | **Elegida** |

- **Las 7 operaciones y sus rutas no cambian.** `PlayerResponse` suma `profileId` y el año de nacimiento; el
  nombre se lee del perfil.
- **Todo lo que ya apunta a `playerId`** (ausencias, convocatorias, tarjetas y goles) sigue apuntando a la fila de
  la temporada, que es lo que se quiere.
- **El perfil no tiene operaciones propias** hasta la versión siguiente.

**Las dos tablas se crean ya, en la R6** (2026-11-14): la del perfil (nombre y año de nacimiento) y la de
temporada+jugador, con su clave ajena al perfil; el alta escribe en las dos a la vez. Hoy no existe ninguna de las
dos en la base. Descartado crear solo la de temporada+jugador con una columna de «código de jugador» que aún no
apunta a nada: en esta versión habría un código por fila, y el año que viene tocaría mover el nombre y el año a la
tabla nueva con una migración de datos.

**Dar de baja la fila no toca el perfil** (2026-11-14): la fila solo se esconde (`D-36`) y se puede recuperar, así
que su perfil sigue ahí. Descartado esconder el perfil con su última fila: más reglas, y esconder no es borrar.
**El purgado de una temporada (R11) borra también los perfiles que se queden sin ninguna fila**, para que no se
queden el nombre y el año de nacimiento de un menor; apuntado en la fila de la R11 del plan del backoffice. El
desarrollador apuntó, sin desarrollarlo, que la versión siguiente puede avisar de los perfiles sin filas y ofrecer
borrarlos.

**Decidido entero (2026-11-14)** → [`D-119`](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md), enmienda a `D-05`.

### Decisión 9 · Cargar la plantilla desde la federación

Propuesta por el desarrollador al revisar la maqueta (2026-11-14): **la RFFM publica la plantilla de cada equipo**
en su ficha de equipo (`https://www.rffm.es/fichaequipo/<código del equipo en la federación>`), contra lo que daba
por hecho el catálogo («la federación no publica plantillas de fútbol base»). Con un botón «Cargar plantilla desde
la Federación» en la plantilla vacía, si la federación del club la publica (una capacidad nueva de la federación,
como `federationProvidesScorers`, `D-48`).

**Lo medido (2026-11-14)**, con dos equipos del desarrollador (el Cadete A y el Senior A): la página lleva sus
datos en el mismo bloque `__NEXT_DATA__` que ya lee el adaptador de la RFFM (`NextDataExtractor`). Por cada
jugador, **solo su código en la federación y su nombre**, como «APELLIDOS, NOMBRE» (24 y 22 jugadores, todos con
coma): **ni dorsal, ni demarcación, ni nacimiento**. Trae también los técnicos y los delegados del equipo (código y
nombre), y datos de contacto del club. **La RFFM no deja que otra web lea la página desde el navegador**: no manda
la cabecera `Access-Control-Allow-Origin`.

**Entra en la R6, como una parte aparte al final** (2026-11-14), como la `R5.12`: primero las 7 operaciones y la
foto, y después la carga (§7, parte D). **Los técnicos y los delegados**, para la R15 (Personal): apuntado en su
fila del plan del backoffice.

**La hace el servidor, no el navegador**: lo decide lo medido (la RFFM no deja leer la página desde otra web), la
regla de que la web solo habla con nuestro servidor (LLD-B), y que el servidor ya lee las páginas de la RFFM y ya
declara qué publica cada federación (`D-48`).

**Al pulsar el botón** (2026-11-14): el servidor lee la página de la RFFM en ese momento y da de alta a los
jugadores, como el `/preview` del enganche (R3). Descartado hacerlo en la ingesta de cada semana: la ingesta es para
lo que manda la federación, y la plantilla es del club; pisaría lo que el club corrige, o habría que decidir quién
gana en cada campo. Si la RFFM tarda o falla, se avisa.

**La demarcación pasa a ser opcional, como el dorsal** (2026-11-14): los cargados entran sin ella y el club la pone
desde la ficha; en la tabla, una raya. Vale para cualquier club, también para los equipos de los pequeños, donde
rotan. Descartados poner a todos la misma (un dato inventado que parece verdad) y elegir la de cada uno antes de
guardar la carga (unas 24 elecciones seguidas y una pantalla más). Enmienda al catálogo (`PlayerPosition`, en el
alta), con `D-120` al cerrar la decisión.

**El nombre: en mayúsculas en la base, y la web lo formatea al pintarlo** (2026-11-14, propuesto por el
desarrollador). Medido en las dos plantillas (46 jugadores): todos en mayúsculas, como «APELLIDOS, NOMBRE» con una
sola coma; 7 con tilde o eñe, 7 con nombre compuesto, 1 con partícula y 2 con un solo apellido.

- **El servidor guarda el nombre siempre en mayúsculas**, venga del alta a mano o de la carga, en la regla del
  jugador antes de guardar (no un `upper()` de Postgres): con sus pruebas y en un solo sitio. Las mayúsculas
  conservan tildes y eñes.
- **La carga solo da la vuelta por la coma** (el adaptador de la RFFM): «GARCÍA DE LA FUENTE, JUAN CARLOS» →
  «JUAN CARLOS GARCÍA DE LA FUENTE».
- **La web lo formatea con una función** en `components/`, con sus pruebas de piezas: todo a minúsculas
  (`toLocaleLowerCase('es-ES')`), mayúscula la primera letra de cada palabra y tras un guion, y en minúscula «de»,
  «del», «la», «las», «los» e «y» salvo al principio. **El CSS no basta**: `text-transform: capitalize` no baja el
  resto de la palabra. Se usa en la tabla, la ficha y el diálogo de corregir.
- **Lo que se gana**: la tabla nunca mezcla formas, el orden por nombre es el mismo para todos y comparar nombres es
  directo (punto siguiente). Al lector de pantalla, el nombre le llega formateado.
- **Lo que se asume**: «McDonald» sale «Mcdonald», y un cliente futuro (el móvil) repite la regla.

Descartados pasarlo a «Nombre Apellidos» en el servidor (las mayúsculas mal puestas se guardarían) y guardarlo tal
cual (dos formas en la misma tabla).

**Que el nombre sea válido** (2026-11-14), en el servidor, y la web avisa antes de enviar; igual en el alta, la
corrección y la carga:

- **Se limpian los espacios**: fuera los del principio y el final, y uno solo entre palabras.
- **Solo letras** (con tildes, eñe y diéresis), espacios, guion y apóstrofo; hasta 120 caracteres.
- **Al menos dos palabras**, nombre y un apellido (lo eligió el desarrollador, frente a una sola).
- **En la sincronización, un nombre de la federación que no vale no se añade**, y el resumen lo nombra para que el
  club lo dé de alta a mano (2026-11-15, en R6.3). Los 46 medidos valían todos, pero la federación puede publicar
  cualquier cosa.
- **Un nombre que no vale, 422 con `INVALID_VALUE`** (decidido en `R6.4`, 2026-11-15), y el detalle
  `fullName: <motivo>`, para que la web lo enseñe junto al campo. Lo comprueba el dominio, no el catálogo, que solo
  pide de 1 a 120 caracteres: así vale igual para la sincronización, que no pasa por él. Como el nombre vacío del
  club. Descartado un 400 con las reglas como patrón en el catálogo: habría que repetirlas en el dominio.

**El alta elige el jugador: uno que ya existe, o uno nuevo, con un buscador mientras se escribe** (2026-11-14,
propuesto por el desarrollador). Con la tabla del perfil ya creada, la fila nueva tiene que decir de qué perfil es
(su clave ajena); si cada alta creara uno, habría duplicados desde el primer año. Sin entrar todavía en las
pantallas del perfil, el diálogo del alta lo resuelve:

1. Desde **3 letras**, y al dejar de teclear (unos 300 ms), la web busca en el servidor: **hasta 10 jugadores** del
   club, cada uno con su año y su último equipo y temporada («JUAN GARCÍA FUENTE · 2010 · Cadete B 2024/25»).
2. **Elegir uno** crea solo su fila en esta plantilla; se piden el dorsal, la demarcación y la foto.
3. **La última opción, «Dar de alta a "…" como jugador nuevo»**, crea el perfil y la fila. Se deja hacer aunque haya
   otro con el mismo nombre: pueden ser dos chavales, y la lista ya lo ha enseñado.
4. **La búsqueda no distingue tildes ni mayúsculas**, y busca cada palabra por separado («juan fuen»).
5. **No salen los que ya están en esta plantilla.** Los que están en otro equipo de la misma temporada salen, pero
   no se pueden elegir: dicen dónde están («Ya está en Cadete B»). Enmendado el 2026-11-15 (punto siguiente).

**Un jugador, una plantilla por temporada; para cambiarlo de equipo, baja en uno y alta en el otro** (2026-11-15, `D-121`,
en R6.3; enmienda a `D-37`, que dejaba dos filas a la vez). Lo dijo el desarrollador: en el club no hay jugadores
repetidos entre equipos de una misma temporada. Así:

- **En la base, una sola fila no borrada por perfil y temporada** (un índice único parcial, como el del dorsal).
- **El alta de quien ya tiene fila en otro equipo de la temporada, 409**, y dice en qué equipo está. El 409 lleva
  solo su código, `PLAYER_ALREADY_IN_ROSTER` (decidido en `R6.4`): el equipo ya lo ha dicho el buscador.
- **Cambiarlo de equipo a mitad de temporada son dos pasos**: darle de baja en el viejo y de alta en el nuevo. La
  fila dada de baja solo se esconde (`D-36`): sus goles y tarjetas siguen contando para el equipo con que los hizo,
  que es lo que pedía `D-37`.
- **La sincronización no añade a quien el club tiene en otro equipo** de la temporada; el resumen lo dice.
- Descartado no dejar ni una fila dada de baja (nunca dos filas): obligaría a mover la fila de equipo, y sus goles
  pasados contarían para el otro.
- **Lo que no cambia**: en un partido puede jugar uno de otro equipo del club (de categoría o división inferior);
  eso es del acta (rebanada 7), no de la plantilla, y está apuntado en el plan del backoffice.

En el servidor: **una operación nueva, buscar perfiles por nombre** (`GET /player-profiles?q=`), y **el alta acepta
o un `profileId` o el nombre y el año**; un `profileId` que no existe en el club, 422. Enmienda el punto 6 de
`D-119`: el perfil tiene ya una operación en esta versión.
**En el catálogo, dos formas cerradas** (decidido en `R6.4`, 2026-11-15): el alta acepta una de dos, «con perfil»
(equipo, temporada y `profileId`) o «jugador nuevo» (equipo, temporada, nombre y año), las dos con el dorsal y la
demarcación si se quieren. Mandar las dos cosas a la vez, o ninguna, es un 400 que da el propio catálogo. Como el
alta de una competición, por dirección o por campos. Descartada una sola forma con todo opcional y la regla
comprobada a mano en el servidor: el catálogo no la ve.
**Corregir manda la ficha entera** (decidido en `R6.6`, 2026-11-15): `PUT /players/{id}` con el nombre, el
año, el dorsal y la demarcación. Salió al generar el código: con una corrección parcial no se distinguía «no lo
cambio» de «déjalo vacío», porque el generador lee igual un campo que no llega y uno con `null`. Lo que no llega
o llega vacío queda vacío; el nombre tiene que llegar, y el año solo se queda vacío si el perfil no lo tenía.
Descartado marcar aparte qué se vacía (`"clear": [...]`): dos formas de decir algo del mismo campo. Y en el mismo
arreglo, **la demarcación «o nula» se escribe como `takenBy`**, porque el generador descartaba en silencio la
forma con `oneOf` y un `null`.
**La búsqueda filtra en el servidor** (decidido en `R6.4`, 2026-11-15): recibe `q` (desde 3 letras; con menos,
400), `teamId` y `seasonId`, los tres obligatorios, como `listPlayers`. Quita a los de esa plantilla, y cada jugador
lleva `profileId`, nombre, año, el último dorsal, demarcación y foto, **su última plantilla** (la fila no borrada
más reciente, con su equipo y temporada, o `null`) y **`otherTeamThisSeason`** (el equipo si ya está en otro esta
temporada, o `null`). Descartado recibir solo `q` y filtrar en la web: si 4 de los 10 eran de esta plantilla,
enseñaría 6 aunque hubiera más, y las reglas quedarían repartidas.

**La sincronización contesta al momento** (decidido en `R6.4`, 2026-11-15): un 200 con el resumen cuando ha
terminado, y mientras, el botón dice «Sincronizando…». Descartado un 202 a la cola, como la ingesta del enganche:
una operación más, un resumen que guardar y la web preguntando, por una página de unos 25 jugadores. Así:

- **La dirección**: `POST /teams/{teamId}/registrations/{seasonId}/roster-sync`, colgada de la inscripción, que es
  la que tiene el código de la federación y donde se guarda la fecha.
- **El resumen**: `syncedAt`; **números** de los añadidos, los que ya estaban, los que no tienen año y los dados de
  baja; y **listas con nombre** de los de nombre repetido, los de otro equipo (con su equipo) y los de nombre que no
  vale (como lo escribe la federación). Lo que cuenta cada lista es su largo.
- **Los errores**: 404 si el equipo no existe; 422 con la temporada archivada, si la federación no publica
  plantillas o si el equipo no está enganchado; 502 y 504, como el enganche.
- **La fecha se lee en la inscripción** (decidido en `R6.4`): `TeamRegistrationResponse` gana `rosterSyncedAt`, o
  `null` si nunca se ha sincronizado. La ficha del equipo ya la pide al abrirse, y tras sincronizar la web toma
  `syncedAt` del resumen. Descartado devolverla con `listPlayers`: dejaría de ser una lista y cambiaría una
  operación que ya existe.

**La carga desde la federación crea los perfiles que falten** (2026-11-14): por cada jugador de la RFFM, si el
club ya tiene su perfil, le crea solo la fila; si no, crea el perfil y la fila. El primer día de un club con el
sistema, los crea todos.

**Cómo sabe la carga que un perfil ya existe: por el nombre exacto, sin contar tildes** (2026-11-14). El de la
RFFM, ya como «NOMBRE APELLIDOS» y en mayúsculas, contra los perfiles del club: si casa con **uno**, se usa ese;
con **ninguno**, perfil nuevo; con **varios**, perfil nuevo, y el resultado de la carga lo dice. Descartados casar
por parecido (puede unir a dos chavales distintos, peor que un duplicado) y preguntar los dudosos (una pantalla más,
de la versión siguiente). Un duplicado se une después, con las pantallas del perfil.
**Qué es «el mismo nombre»** (2026-11-15, en R6.3): igual una vez en mayúsculas, con un solo espacio entre palabras
y sin tildes ni diéresis («GARCIA» es «GARCÍA»); **la eñe cuenta como letra distinta** («MUNOZ» no es «MUÑOZ»), lo
eligió el desarrollador. El buscador del alta, que no compara sino que ayuda a encontrar, sí encuentra «Muñoz» al
escribir «munoz».

**El año de nacimiento: obligatorio en el alta a mano; la carga no lo pide** (2026-11-14, enmienda al punto 3 de la
decisión 8, que lo dejaba opcional siempre). Se miró pedir en la carga un año para todos, que en la cantera acierta
casi siempre (dos años por categoría), pero no en juvenil (tres) ni en senior (cualquiera), y el dato puesto para
todos parece comprobado. Así:

- **Un jugador nuevo dado de alta a mano lleva su año**, obligatorio.
- **En la carga, el perfil casado ya tiene el suyo**; el que se crea queda **sin año, y se ve claramente** en la
  tabla y en la ficha, para que el club lo rellene, que es quien sale ganando.
- En la base, el año admite vacío: solo lo deja vacío la carga.

**Se llama «Sincronizar con la Federación», como con las competiciones, y se puede pulsar siempre: solo añade**
(2026-11-14). Da de alta a quien no esté en la plantilla; no corrige ni da de baja a nadie, y **no vuelve a crear a
quien el club dio de baja** aunque la federación lo siga listando, **ni añade a quien el club tiene en otro
equipo de la temporada** (enmienda del 2026-11-15, `D-121`). Al acabar dice qué ha hecho. Sale en la barra de
la plantilla y en la plantilla vacía.

**Cada fila dice si está federado** (2026-11-14): **«Federado»** si la última sincronización lo listó, **«No
federado»** si no (lo más probable, según el desarrollador: el club lo pone en el equipo antes de que la federación
lo tenga), y vacío mientras esa plantilla no se ha sincronizado nunca o si la federación no publica plantillas. En la
tabla, junto al nombre; en la ficha, con su fecha. La baja sigue siendo del club. **Tres campos**, que escribe cada
sincronización:

| Dónde | Campo |
|---|---|
| **La inscripción del equipo** (`team_registrations`), la que tiene el código de la federación que se usó | **La última sincronización de la plantilla**, en una **columna propia** (`roster_synced_at`, vacía hasta la primera): la fecha junto al botón. Con dos competiciones (liga y copa), la más reciente de las dos. **No `updated_at`**: cambia cada vez que se guarda la inscripción por cualquier motivo (en la base del desarrollador, 3 de 6 ya, por el enganche) |
| **El jugador en la temporada** | **Federado o no federado**, guardado: se miró calcularlo comparando la fecha del jugador con la de la inscripción, y el desarrollador prefirió el campo, porque sacarlo obliga a mirar dos tablas |
| **El jugador en la temporada** | **La última vez que la federación lo listó** |

Descartado sacar la fecha de la plantilla de las de los jugadores (la más reciente): si la federación no lista a
nadie, no se toca ninguna fila y la fecha se queda antigua. Y descartada `ingestion_runs`, que va por competición y
no sabe de qué equipo propio es cada pasada.

**En el catálogo, sí, no o nulo** (decidido en `R6.4`, 2026-11-15): `PlayerResponse` lleva `federated` (`true`,
`false`, o `null` mientras la plantilla no se ha sincronizado nunca) y `lastListedAt` (la fecha, o `null`), como
el resto del catálogo, que usa `null` para «no hay dato». Descartados tres valores con nombre (`federated`,
`notFederated`, `neverSynced`): una lista cerrada más para un sí o un no. **Un alta a mano después de una
sincronización sale «No federado»** (`false`): la plantilla ya se ha sincronizado y la federación aún no lo tiene;
antes de la primera, vacío (`null`). Propuesto al decidir el formato.

**Decidida entera (2026-11-14)** → [`D-120`](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md), con la capacidad
nueva de la federación, `federationProvidesTeamRoster`.

### Decisión 10 · El perfil guarda el último dorsal, la última demarcación y la última foto, como ayuda

Abierta al revisar los escenarios del alta (`R6.3`, 2026-11-15), propuesta por el desarrollador. Además del nombre y
el año, **el perfil guarda el último dorsal, la última demarcación y la última foto** del jugador. **No mandan**: lo
que vale es lo de la fila de la plantilla; lo del perfil es una ayuda para no teclear dos veces, y no importa que
esté perfectamente al día.

- **Al elegir un jugador en el buscador del alta**, el diálogo trae esos tres datos del perfil, y se pueden cambiar.
  Si se dejan, son clics que se ahorran.
- **Cada vez que se guardan en una fila** (alta, corregir, poner o quitar la foto), **se copian también al perfil**,
  sea de la temporada que sea. Lo vacío también se copia: el perfil dice lo último que se guardó.
- **La sincronización con la federación los copia del perfil a la fila** del jugador que casa, y el entrenador los
  cambia después si quiere. **Si el dorsal ya lo tiene otro de la plantilla, se deja vacío.**
- **La búsqueda de perfiles devuelve el registro entero**: nombre, año, dorsal, demarcación y foto.
- **La foto, en el perfil también**, aunque es lo más delicado de un menor: cada club la usará a su manera, y el
  sistema es para todos. Se borra con el perfil, en el purgado de la R11, cuando se queda sin filas.

| Opción para qué pone al día el perfil | Veredicto |
|---|---|
| **(a) El alta y corregir, en cualquier temporada** | **Elegida**: es una ayuda, no un dato que mande |
| (b) Solo si la fila es la de la temporada más reciente del jugador | Descartada: una regla más, para un dato que no tiene que ser exacto |
| (c) Solo el alta | Descartada: el perfil se quedaría con lo de antes de corregir |

**Decidida entera (2026-11-15)** → [`D-122`](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md), enmienda a `D-119`
(lo que guarda el perfil) y a `D-120` (lo que trae la sincronización).

---

## 5. Lo que le falta al servidor

**Hoy no hay nada de jugadores**: ni la tabla ni el código. Las 7 operaciones están en el catálogo desde F1.

| Qué | Capas | ¿Mini-fase? | Decisión |
|---|---|---|---|
| **Lo que haya que cambiar en el catálogo** por las decisiones | Catálogo | Si hace falta | 3, 5 |
| **Las tablas de jugadores**, con su migración (la 22ª): el perfil que dura (nombre, año de nacimiento, y el último dorsal, demarcación y foto, decisión 10) y el jugador en una temporada, con su clave al perfil, el dorsal opcional y único solo entre los no borrados, y una sola fila no borrada por perfil y temporada | Persistencia | No | 5, 8, 10 |
| **El jugador en el dominio**, con sus reglas (equipo propio, temporada sin archivar, dorsal) | Dominio y Aplicación | No | 5 |
| **`listPlayers`, `getPlayer`, `createPlayer`, `updatePlayer` y `deletePlayer`** | Aplicación, Persistencia y HTTP | No | 4 |
| **El sitio de las fotos**, detrás de un puerto, para cambiarlo por Supabase al desplegar | Aplicación e infraestructura | No | 1 |
| **El saneado de la foto** | Infraestructura | No | 2 |
| **`uploadPlayerPhoto` y `deletePlayerPhoto`**, y la `photoUrl` en las respuestas | Aplicación y HTTP | No | 1 a 3 |
| **🆕 Buscar perfiles por nombre**, con el registro entero, y el alta con un perfil que ya existe o uno nuevo; guardar una fila copia su dorsal, demarcación y foto al perfil | Todas | Con la del catálogo | 8, 9, 10 |
| **🆕 Sincronizar la plantilla con la federación**: la capacidad nueva, la lectura de la ficha de equipo de la RFFM, el casado por nombre, lo que se copia del perfil y los dos campos de «federado» | Todas | Con la del catálogo | 9, 10 |

**El censo y la mutación**, como siempre (plan del backoffice, §2.5). Cada endpoint, a la tabla de §0 del README
del backend en su paso.

**Al terminar**, el servidor sirve **27** operaciones: las 17 de antes, las 7 de jugadores y las 3 nuevas, que
suben el catálogo de 85 a 88, con la ruta que entrega la foto (decisión 3, cerrada en `R6.4`).

---

## 6. Los escenarios

Escritos y revisados con el desarrollador en `R6.3` (2026-11-15), con la *skill* de escenarios, sin definir, con
las etiquetas `@e2e` y `@ui` y axe en los dos modos. **119 escenarios** (contando cada ejemplo de los esquemas), en
cuatro ficheros de `backoffice/e2e/features/`:

| Fichero | Escenarios | `@e2e` | `@ui` | Qué cubre |
|---|---|---|---|---|
| `plantilla.feature` | 14 | 2 | 12 | La pestaña: entrar, recargar, cambiar de temporada; el orden; cada dato de la fila, de la plantilla o de su perfil; el nombre formateado; foto o iniciales; las acciones; el nombre que lleva a la ficha; sin jugadores; la temporada archivada, de solo lectura |
| `alta-jugador.feature` | 37 | 16 | 21 | El diálogo; el buscador (3 letras, sin tildes, palabra a palabra, no ofrece a los de esta plantilla, enseña desactivados a los de otro equipo); elegir uno que existe, que trae lo de su perfil; guardar, un campo opcional cada vez, ninguno o todos, mirando la fila y el perfil; otro con el mismo nombre; lo que no deja guardar; la foto que no vale |
| `jugador.feature` | 22 | 12 | 10 | La ficha (una página, con su enlace de vuelta); corregir desde la fila y desde la ficha, con sus dos bloques y el aviso al cambiar nombre o año; la foto; la baja y su dorsal libre |
| `plantilla-federacion.feature` | 46 | 17 | 29 | La plantilla entera (la fecha, nunca sincronizada, la federación que falla o tarda); cada caso de jugador, según cómo está en el club y en la federación; el resumen, que cuenta, estado a estado y con el mismo cambio dos veces; la ficha del federado |

**Cómo se ordenan y se escriben**, lo que se aprendió al revisarlos:

- **Cada dato dice de dónde sale**: de la plantilla (dorsal, demarcación, foto) o de su perfil (nombre y año).
- **Sin escenarios generales que no son verdad** («sincronizar añade a todos»): uno por caso.
- **Sin condiciones que no aplican** (una plantilla vacía, ya sincronizada): solo cuando cambian el resultado.
- **Lo que cuenta (el resumen) se prueba por estados**, cada uno saliendo del anterior, y con el mismo cambio dos
  veces para ver que acumula.
- **Un «Then» comprueba un estado, no hace una acción**: «se puede cambiar» no; «bloqueado» o «desactivado», sí.

---

## 7. Los pasos

### A · Las decisiones y los escenarios

| Paso | Qué |
|---|---|
| `R6.1` | La revisión de las decisiones con el desarrollador, una a una |
| `R6.2` | Los documentos de lo decidido: la bitácora del backend (`D-nn`), el LLD-B y su anexo si hace falta (`DW-nn`), y esta ficha al día |
| `R6.3` | Los escenarios escritos y revisados, sin definir |

*Puestos al día al empezar `R6.4` (2026-11-15), con lo que salió en `R6.3`: dos tablas en vez de una, buscar
perfiles, `D-121`, `D-122` y los pasos de la sincronización, que faltaban.*

### B · El servidor (esta rama)

| Paso | Qué |
|---|---|
| `R6.4` | **La mini-fase del catálogo**: `PlayerProfile`; lo que cambia en `PlayerResponse`, `CreatePlayerRequest` y `UpdatePlayerRequest` (`profileId`, año, demarcación opcional, los campos de «federado»); los 409 (dorsal cogido, jugador en otra plantilla) y el 422 de la temporada archivada; las dos operaciones nuevas (buscar perfiles y sincronizar); la capacidad `federationProvidesTeamRoster`; si la ruta que entrega la foto es la operación 86; y la enmienda al LLD del backend (§3 y §5) |
| `R6.5` | **Las dos tablas y sus reglas**, en ciclos TDD: la migración 22ª (el perfil y la plantilla, con el índice del dorsal y el de una fila por perfil y temporada, `D-118` y `D-121`); en el dominio, el nombre (mayúsculas, limpieza, validación) y las reglas de la plantilla (equipo propio, temporada sin archivar) |
| `R6.6` | **Las cinco operaciones de los datos** (`listPlayers`, `getPlayer`, `createPlayer`, `updatePlayer`, `deletePlayer`), en ciclos TDD: el alta con un perfil o con nombre y año; guardar copia el dorsal y la demarcación al perfil (`D-122`); cada una, a la tabla del README del backend |
| `R6.7` | **Buscar perfiles**, en ciclos TDD: desde 3 letras, hasta 10, sin tildes ni mayúsculas, palabra a palabra; sin los de esta plantilla, y con los de otro equipo marcados; al README |
| `R6.8` | **El sitio de las fotos y su saneado**, en ciclos TDD. Empieza con la prueba de las dos librerías con una foto de verdad del móvil del desarrollador, y sus licencias (`D-116`) |
| `R6.9` | **Las dos operaciones de la foto**, en ciclos TDD: la `photoUrl` firmada y la ruta que entrega el fichero (`D-117`); la foto copiada al perfil, y el fichero borrado solo cuando no lo usa nadie (`D-122`); al README |
| `R6.10` | **El cierre del servidor sin la sincronización**: tests, mutación, censo |

### C · La web (otra rama)

| Paso | Qué |
|---|---|
| `R6.11` | La pestaña Plantilla |
| `R6.12` | El alta con su buscador, la corrección y la baja. **El buscador se queda solo con la respuesta de lo último escrito** (apuntado en `R6.7`): busca al dejar de teclear unos 300 ms, pero si salen dos búsquedas seguidas la primera puede llegar después, y no debe pintar lo de «jua» cuando ya pone «juan g» |
| `R6.13` | La ficha del jugador y su foto |

**Cuatro decisiones al empezar `R6.11`** (2026-11-16), una a una con el desarrollador, en la rama
`feature/r6-plantilla-backoffice`:

| Qué | Opciones | Elegida |
|---|---|---|
| **1 · Los botones que aún no hacen nada** («Dar de alta un jugador», «Sincronizar con la Federación», ✎, 🗑 y el nombre como enlace) | Cada paso pone los suyos, o ponerlos ya desactivados | **Cada paso pone los suyos**: `R6.11` deja la tabla de solo lectura y el mensaje de «sin jugadores». Sus escenarios siguen sin definir hasta el paso que los hace funcionar |
| **2 · El rótulo «Federación»** a la derecha de las pestañas | Sin rótulo en Plantilla, que diga «Club», o dejarlo | **Sin rótulo en Plantilla**: sus datos se teclean y se corrigen aquí. Quién viene de la federación lo dice cada fila desde `R6.16` |
| **3 · El equipo que no juega esa temporada** | Sin inscripción, sin pestañas, como hoy; o enseñar Plantilla también ahí | **Como hoy**, y además **el servidor rechaza el alta de un jugador si el equipo no está inscrito en esa temporada**: hoy solo mira que el equipo sea propio y la temporada no esté archivada. Va al final de la rebanada (`R6.17`) |
| **4 · Dónde va el código** | La plantilla en ficheros propios, todo dentro de la ficha, o cada pestaña en su fichero | **Cada pestaña en su fichero**, también Resultados: falta la tercera, Estadísticas (R10). La ficha se queda con la cabecera, las cajas y la barra de pestañas |

**Cómo se hace `R6.11`, en dos commits**: primero sacar Resultados a su fichero, sin cambiar nada de lo que se ve
(las pruebas y los 170 escenarios de antes, en verde); después, la pestaña Plantilla. Los jugadores se piden solo
al abrir su pestaña.

### D · Sincronizar la plantilla con la federación (decisión 9, `D-120`)

| Paso | Qué |
|---|---|
| `R6.14` | **El servidor, en su propia rama**, en ciclos TDD: la migración 23ª (`roster_synced_at` en la inscripción; «federado» y la última vez listado en la plantilla); la capacidad; el adaptador de la RFFM lee la ficha de equipo (con una grabación de verdad); el casado por nombre y lo que se copia del perfil; la operación y su resumen; al README |
| `R6.15` | **La federación falsa** de los escenarios publica la ficha de equipo, con lo que piden: los jugadores de cada caso, el error y la petición retenida |
| `R6.16` | **La web**, en su rama: el botón, el resumen, la fecha y «Federado» o «No federado» |

### E · Los escenarios en verde y el cierre

| Paso | Qué |
|---|---|
| `R6.17` | **El servidor: el alta de un jugador pide que el equipo esté inscrito en esa temporada** (decisión 3 de `R6.11`), en ciclos TDD, con su entrada en la bitácora del backend y su código de error. Si la sincronización da de alta por el mismo camino, también |
| `R6.18` | Los 119 escenarios de la rebanada en verde, con axe en los dos modos |
| `R6.19` | La revisión a mano: el teclado y el zoom al 200 % |
| `R6.20` | El cierre: cifras, `AGENTS.md`, el plan del backoffice (§4 y §6) y lo aprendido |

---

## 8. Estado

| Paso | Hecho | Lo que se comprobó |
|---|---|---|
| `R6.1` | 2026-11-14 | Las nueve decisiones, una a una, con lo que hizo falta para verlas: el almacén, los escudos y la configuración del servidor (1); las herramientas de imágenes del Mac y del contenedor (2); un dibujo de los dos caminos de la foto, ahora y con Supabase (3); la R2 (4); el acta de la RFFM (5); `DW-22` (6); una maqueta en HTML de la plantilla, la ficha, el alta y la baja (7); `D-05` y lo que ya apunta a `playerId` en el catálogo (8); y la ficha de equipo de la RFFM de dos equipos del desarrollador, sus nombres medidos sin sacarlos y sus cabeceras (9). La 8 y la 9 salieron al revisar la 6 y la 7. Escritas en la bitácora del backend `D-115` a `D-120`; en el plan del backoffice, la fila de la R11 (el purgado borra los perfiles sin filas) y la de la R15 (técnicos y delegados desde la federación) |
| `R6.2` | 2026-11-15 | **Los documentos de lo decidido.** En la bitácora del backend, `D-115` a `D-120`, escritos con cada decisión y grabados con `R6.1`. En el LLD-B, el camino de la ficha del jugador (§6.1, decidido; y §6.5, que la ficha del jugador también lleva la temporada); sin entrada nueva en su anexo: aplica `DW-22`. En el plan del backoffice, el camino del mapa y la fila de la R6 con lo que cambia en sus operaciones y las dos nuevas. En `AGENTS.md`, la rebanada empezada, en «Documentación clave» y en el estado. **La enmienda al LLD del backend** (§3 y §5) va con el catálogo (`R6.4`), como en la R5. **No hay que relanzar el servidor**: solo documentos |
| `R6.3` | 2026-11-15 | **Los escenarios**, 119 en cuatro ficheros, revisados uno a uno con el desarrollador (§6); la pasada en seco da 289: los 170 de antes, intactos, y los 119, sin definir. Salieron **dos decisiones**: un jugador, una plantilla por temporada (`D-121`, dentro de la 9, enmienda a `D-37`) y el perfil guarda el último dorsal, demarcación y foto (10, `D-122`); y **cuatro reglas**: la temporada archivada, de solo lectura entera; la foto se describe con el nombre del jugador, que la web le pone al pintarla; el nombre de la federación que no vale no se añade y el resumen lo nombra; y «el mismo nombre» es sin tildes ni diéresis, pero con la eñe distinta. Aparte, en el plan del backoffice: el jugador de otro equipo que juega en un partido, para la R7. **Queda para la parte D** (`R6.15`): la ficha de equipo de la RFFM en la federación falsa. **No hay que relanzar el servidor**: solo escenarios y documentos |
| `R6.4` | 2026-11-15 | **El catálogo, con siete decisiones** revisadas una a una: el alta en dos formas cerradas; el nombre que no vale, 422 `INVALID_VALUE`; «federado» como sí, no o nulo; los dos 409 solo con su código; la búsqueda de perfiles filtrada en el servidor; la sincronización al momento, con su resumen; y la fecha en la inscripción. Y la ruta de la foto, la operación 86. **88 operaciones** (tres nuevas: `getPlayerPhotoFile`, `searchPlayerProfiles`, `syncTeamRoster`); el servidor sigue sirviendo 17. La capacidad `federationProvidesTeamRoster` ya sale en `getClub` (RFFM sí; FCF, sin medir, no), con su test; `rosterSyncedAt` viaja ausente hasta `R6.14`, apuntado en el censo. **Salió una enmienda**: la clave de la foto es nueva en cada subida, no sale del `playerId` (`D-115`, punto 3). La enmienda al LLD del backend: §3.1, §3.2, §3.5, §3.6, §3.7, §5.1, §5.2, §5.3 y §5.6. 854 tests y el censo, en verde. **Hay que relanzar el servidor**: `getClub` devuelve un campo nuevo |
| `R6.5` | 2026-11-15 | **Las dos tablas y sus reglas**, en ciclos TDD. En el dominio: el nombre (`PlayerName`: limpio, en mayúsculas, la tilde en dos piezas guardada como una, solo letras, espacio, guion y apóstrofo, cada palabra con letras, al menos dos y hasta 120), el año (1900 al año en curso, que pone quien llama), el dorsal (1 a 99), la demarcación, el perfil y la fila, lo que el perfil recuerda de una fila (`D-122`, lo vacío también) y las dos reglas de la plantilla (`RosterRules`: equipo propio y temporada sin archivar), con sus dos códigos nuevos, `TEAM_NOT_OWN` y `SEASON_ARCHIVED` (422), apuntados en el censo hasta que los lance la R6.6. En la base, **la migración 22ª** (`CreatePlayers`): las dos tablas a la vez, la FK al perfil `RESTRICT`, la cascada desde el equipo y la temporada, cinco `CHECK` y los dos índices únicos parciales, el del dorsal y el de una fila por perfil y temporada (`D-118`, `D-121`), con 11 pruebas contra Postgres. **882 tests** (28 nuevos) y el censo, en verde. **No hace falta relanzar el servidor**: ninguna operación servida cambia. La migración llega a los clubes con `swift run Run migrate-tenants` |
| `R6.6` | 2026-11-15 | **Las cinco operaciones de datos**, en ciclos TDD: `listPlayers`, `getPlayer`, `createPlayer`, `updatePlayer` y `deletePlayer`, con sus repositorios (el perfil y la fila), sus casos de uso y sus *handlers*. **Salieron dos fallos del catálogo de la R6.4**, arreglados en su commit (`453f4a1`): la demarcación «o nula» con `oneOf` y un `null` desaparecía del código generado, y una corrección parcial no distinguía «no lo cambio» de «déjalo vacío»; **corregir pasa a `PUT` con la ficha entera**, elegido por el desarrollador. Los 409 (`SHIRT_NUMBER_TAKEN`, `PLAYER_ALREADY_IN_ROSTER`) se miran antes de escribir, como el alta de temporada; lo que el cuerpo nombra y no existe es **422 `REFERENCE_NOT_FOUND`**, con el campo en el `detail`; el jugador que no existe, **404 `PLAYER_NOT_FOUND`**. «Federado», la última vez listado y la foto viajan nulos hasta la R6.14 y la R6.9, y los tests lo afirman. **920 tests** (38 nuevos), censo en `0`; el servidor sirve **22** operaciones. **Hay que relanzar el servidor** y migrar los clubes (`swift run Run migrate-tenants`): sin la migración 22ª, las cinco fallan |
| `R6.7` | 2026-11-15 | **Buscar perfiles**, en ciclos TDD: `searchPlayerProfiles`. **Cómo busca** (`PlayerSearch`, en el dominio): desde 3 letras, contando todas las palabras (con menos, 400); sin tildes, diéresis ni mayúsculas, y la eñe como «n»; cada palabra escrita, el comienzo de una palabra del nombre, y tras un guion o un apóstrofo empieza otra. **La base busca con la misma tabla de letras** (`translate`), para que los dos pliegues sean el mismo; probado contra Postgres con eñe, diéresis, «ã», guion y apóstrofo. Quita en la consulta a los de esa plantilla (los dados de baja sí salen), por orden de nombre y hasta 10; cada uno con su perfil entero, su última plantilla (la de la temporada más reciente) y el otro equipo de esta temporada, si lo hay. La foto del perfil viaja nula hasta la R6.9. Sin índice: un club tiene unos cientos de perfiles. **937 tests** (17 nuevos), censo en `0`; el servidor sirve **23** operaciones. **Hay que relanzar el servidor** |
| `R6.8` | 2026-11-16 | **El almacén de fotos y su saneado**, en ciclos TDD. **La prueba del arranque**, con una foto HEIC del iPhone del desarrollador (orientación 6 y ubicación): licencias Apache 2.0; sale derecha en las ocho orientaciones, como la gira Apple, y sin ubicación ni datos del móvil; **un hallazgo**: el paso de la librería que junta los colores tardaba 11 s en 12 megapíxeles, y lo hace código nuestro a la vez que reduce (unos 2 s la foto entera). **Cuatro decisiones**, una a una: 800 px en el lado largo, calidad 75, no abrir más de 30 millones de puntos (un PNG de 1,2 MB pedía 1,9 GB) y dos piezas nuevas del servidor, `Storage` e `Imaging`; y la carpeta, `backend/fotos/` sin grabar (`PHOTOS_DIR`), porque en el Mac no se usan fotos de verdad. Los puertos `PhotoStore` y `PhotoSanitizer` y la clave `PhotoKey` (`<club>/<código>.jpg`, que no acepta otra forma), en `Application`. Lo transparente de un PNG, en blanco. **955 tests** (18 nuevos), sin Docker los de las dos piezas; censo en `0`, sin operaciones nuevas. **No hace falta relanzar el servidor**: nada lo usa hasta la R6.9 |
| `R6.9` | 2026-11-16 | **Las tres operaciones de la foto**, en ciclos TDD. **Cinco decisiones**, una a una: el enlace empieza por `PHOTOS_URL_PREFIX` (`/api`, el del recepcionista de la web); la ruta lleva solo el fichero y el club sale de la dirección; la clave secreta, `PHOTOS_SIGNING_KEY` o una al azar al arrancar; los códigos `NOT_AN_IMAGE`, `IMAGE_TOO_LARGE` y `UNSUPPORTED_IMAGE_TYPE`; y la foto del perfil en el alta. **Subir** sanea fuera de la transacción (el acceso a los datos es de una conexión, `D-100`), guarda con clave nueva y la pone en la fila y en el perfil; **quitar** la deja vacía en los dos; **el fichero de antes se borra solo si ya no lo usa nadie**, contando las filas dadas de baja. `photoUrl` y `lastPhotoUrl`, firmados en cada lectura. **Un fallo de la R6.6, grabado aparte**: el alta con un perfil le borraba la foto. **979 tests** (22 nuevos, más los 2 del arreglo), censo en `0`; el servidor sirve **26** operaciones. **Hay que relanzar el servidor** |
| `R6.10` | 2026-11-16 | **Cierre del servidor sin la sincronización.** **La mutación, 43/43** (`Tools/Mutate/Catalogs/R6-10.json`), sobre el código de la R6.5 a la R6.9: el nombre, el año, el dorsal y las reglas de la plantilla; el alta, corregir, la lista y el buscador; la foto, su clave, su saneado, su enlace firmado y sus tres rutas. **Antes de la pasada**, al escribir el catálogo, dos comprobaciones que sobraban, fuera (la clave nueva nunca está entre las de antes; una nota de orientación rara ya la deja tal cual el giro), y cuatro tests que faltaban (el fichero nuevo se borra si falla apuntar su clave; unas tablas delante del marco del JPEG; la foto del perfil en el buscador; el prefijo y la clave por omisión). **La primera pasada dejó vivas tres**, las tres por tests que no comprobaban lo que decían: quitar la foto probado con otro perfil, la clave con dos barras que caía por otro motivo, y el tope de peso probado con 4 MB en vez de 5 justos; arreglados, cazadas. **El recuento**, leído del XML de `REQUIRE_DB=1 swift test --xunit-output`: **981** (978 + 3 omitidos), sin fallos; **937 → 981** en la R6.8 a la R6.10. El censo, salida `0`. **No hace falta relanzar el servidor**: solo cambian tests y dos comprobaciones que no cambiaban nada. **Lo siguiente: fusionar la rama**, antes de la web (`R6.11`) |

---

## 9. Lo aprendido

*(Al cerrar la rebanada.)*

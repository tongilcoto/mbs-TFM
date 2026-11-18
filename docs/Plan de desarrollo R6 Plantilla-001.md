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
sola coma; 7 con tilde o eñe, 7 con nombre compuesto, 1 con partícula y 2 con un solo apellido. **La RFFM no
siempre pone las tildes**: los otros 39 van sin ellas, también los que las llevan al escribirse bien («FERNANDEZ
PEREZ, JORGE»; visto al sincronizar de verdad el 2026-11-17: de 51 perfiles, uno con tilde o eñe, y 26 palabras
acabadas en «-EZ» sin ella). Por eso la sincronización compara sin tildes, y la web no las añade: el club las pone
con «Corregir».

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
las etiquetas `@e2e` y `@ui` y axe en los dos modos. **119 escenarios** (contando cada ejemplo de los esquemas; **121** desde la decisión 1 de `R6.12`, **125** desde la decisión 3 de `R6.16`, y **123** desde la decisión 2 de `R6.18`), en
cuatro ficheros de `backoffice/e2e/features/`:

| Fichero | Escenarios | `@e2e` | `@ui` | Qué cubre |
|---|---|---|---|---|
| `plantilla.feature` | 14 (16 desde `R6.16`, 15 desde `R6.18`) | 2 | 12 (14, 13) | La pestaña: entrar, recargar, cambiar de temporada; el orden; cada dato de la fila, de la plantilla o de su perfil; el nombre formateado; foto o iniciales; las acciones; el nombre que lleva a la ficha; sin jugadores; la temporada archivada, de solo lectura |
| `alta-jugador.feature` | 37 | 16 | 21 | El diálogo; el buscador (3 letras, sin tildes, palabra a palabra, no ofrece a los de esta plantilla, enseña desactivados a los de otro equipo); elegir uno que existe, que trae lo de su perfil; guardar, un campo opcional cada vez, ninguno o todos, mirando la fila y el perfil; otro con el mismo nombre; lo que no deja guardar; la foto que no vale |
| `jugador.feature` | 22 (24 desde `R6.12`, 26 desde `R6.16`, 25 desde `R6.18`) | 12 (14) | 10 (12, 11) | La ficha (una página, con su enlace de vuelta); corregir desde la fila y desde la ficha, con sus dos bloques y el aviso al cambiar nombre o año; la foto; la baja y su dorsal libre |
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

**Cinco decisiones de `R6.11`** (2026-11-16), una a una con el desarrollador, en la rama
`feature/r6-plantilla-backoffice`:

| Qué | Opciones | Elegida |
|---|---|---|
| **1 · Los botones que aún no hacen nada** («Dar de alta un jugador», «Sincronizar con la Federación», ✎, 🗑 y el nombre como enlace) | Cada paso pone los suyos, o ponerlos ya desactivados | **Cada paso pone los suyos**: `R6.11` deja la tabla de solo lectura y el mensaje de «sin jugadores». Sus escenarios siguen sin definir hasta el paso que los hace funcionar |
| **2 · El rótulo «Federación»** a la derecha de las pestañas | Sin rótulo en Plantilla, que diga «Club», o dejarlo | **Sin rótulo en Plantilla**: sus datos se teclean y se corrigen aquí. Quién viene de la federación lo dice cada fila desde `R6.16` |
| **3 · El equipo que no juega esa temporada** | Sin inscripción, sin pestañas, como hoy; o enseñar Plantilla también ahí | **Como hoy**, y además **el servidor rechaza el alta de un jugador si el equipo no está inscrito en esa temporada**: hoy solo mira que el equipo sea propio y la temporada no esté archivada. Va al final de la rebanada (`R6.17`) |
| **4 · Dónde va el código** | La plantilla en ficheros propios, todo dentro de la ficha, o cada pestaña en su fichero | **Cada pestaña en su fichero**, también Resultados: falta la tercera, Estadísticas (R10). La ficha se queda con la cabecera, las cajas y la barra de pestañas |
| **5 · Los nombres con tilde o eñe, detrás de la Z** (salió al construir la pestaña) | Lo arregla el servidor, o la web reordena | **El servidor, en `R6.17`**: ordena por el número de cada letra, así que «ÁLVARO», «ÑAKO» y «ÓSCAR» van detrás de «ZAPATA». Le pasa a la plantilla (el `<` de Swift en `ListPlayers.ordered`) y al buscador de perfiles (el `ORDER BY` de la base, que en el contenedor ordena igual). La web pinta en el orden que le llega |

**Cómo se hace `R6.11`, en dos commits** (más uno aparte, que no venía en el plan: los mensajes de los diez códigos de error nuevos): primero sacar Resultados a su fichero, sin cambiar nada de lo que se ve
(las pruebas y los 170 escenarios de antes, en verde); después, la pestaña Plantilla. Los jugadores se piden solo
al abrir su pestaña.

**Decisiones de `R6.12`** (2026-11-16), una a una con el desarrollador:

| Qué | Opciones | Elegida |
|---|---|---|
| **1 · Corregir el nombre y el año** | Un aviso de que cambian en sus otras temporadas (el servidor no dice cuáles son: el buscador quita a los de esta plantilla y solo da la última), o no dejar que un perfil pase a ser otra persona | **El nombre se corrige** («Marcso» → «Marcos»). **El año, solo si está vacío** (lo deja así la sincronización), con una confirmación al guardar: no se podrá cambiar después, y si es un error hay que dar de baja al jugador y darlo de alta como nuevo. **Los dos a la vez, no**: si es otra persona, baja de este y alta del otro como nuevo. Sin aviso de las otras temporadas: el nombre y el año son del perfil, y se sabe. **Se asume**: un año mal tecleado en el alta ya no se corrige, y el perfil con el año malo sigue en el buscador hasta el purgado de la R11. **El servidor cumplirá la regla también** (`R6.17`): hoy acepta cambiar el año siempre |
| **2 · Qué enseña el alta al abrirse** (salió al verlo en el navegador, tras grabar el alta) | Primero el buscador, y los demás campos al elegir; o los cinco a la vista desde el principio | **Los cinco desde el principio**, como en la maqueta: son pocos y caben sin desplazarse (619 px en una pantalla de 800). **El campo del nombre es el buscador**: elegir uno del club bloquea su nombre y su año y trae lo de su perfil; sin elegir a nadie, es un jugador nuevo. «Dar de alta a «…» como jugador nuevo» se queda, y solo cierra la lista. Los escenarios del alta valen tal cual |

**Los escenarios de corregir, reescritos** (`jugador.feature`, 22 → 24; la rebanada, 119 → 121): fuera el aviso de las
otras temporadas (2), «cambiar el dorsal no avisa de nada más» y «corregir el año lo cambia en la otra temporada»;
entran corregir el nombre, el año bloqueado, la confirmación del año, confirmarla, cancelarla, y nombre y año a la vez.
Cada guardado se mira en la fila de la plantilla, a la que se vuelve.

### D · Sincronizar la plantilla con la federación (decisión 9, `D-120`)

| Paso | Qué |
|---|---|
| `R6.14` | **El servidor, en su propia rama**, en ciclos TDD: la migración 23ª (`roster_synced_at` en la inscripción; «federado» y la última vez listado en la plantilla); la capacidad; el adaptador de la RFFM lee la ficha de equipo (con una grabación de verdad); el casado por nombre y lo que se copia del perfil; la operación y su resumen; al README |
| `R6.15` | **La federación falsa** de los escenarios publica la ficha de equipo, con lo que piden: los jugadores de cada caso, el error y la petición retenida |
| `R6.16` | **La web**, en su rama: el botón, el resumen, la fecha y «Federado» o «No federado»; el botón, solo en la temporada en curso; y la temporada pasada, sin botones ni acciones, como la archivada (decisiones 1 y 4 de `R6.14`), con sus escenarios |

**Decisiones de `R6.14`** (2026-11-17), una a una con el desarrollador, en la rama `feature/r6-plantilla-backend-2`.
Antes, **lo medido**: el código de la federación que guarda cada inscripción es el de su ficha de equipo
(`fichaequipo/821` es el Cadete A del desarrollador; `fichaequipo/3349086`, su Senior A), leída sin sacar nombres.

| Qué | Opciones | Elegida |
|---|---|---|
| **1 · En qué temporada se sincroniza** | En cualquiera sin archivar, como decía el catálogo, o solo en la en curso | **Solo en la en curso**: la ficha de equipo **no dice de qué temporada es** (de sus 33 campos, ninguno), así que es la plantilla de hoy; en una temporada pasada metería a los de hoy sin un solo error (el riesgo de `D-84`). En una pasada no se toca; en una futura, la plantilla es a mano. **El servidor responde con error** (un código nuevo) y **la web no enseña el botón** (`R6.16`). Enmienda a `D-120` |
| **2 · La grabación de la ficha para las pruebas** | Tal cual, una página mínima escrita a mano, o la de verdad con los datos personales cambiados | **La de verdad, con los datos cambiados**: lleva los nombres y los códigos de 24 menores, y el contacto del club. Nombres inventados con la misma forma («APELLIDOS, NOMBRE», con tildes, eñe, guion y partícula), códigos inventados y el contacto vacío, por un guion que se queda en el repositorio para repetirla si la RFFM cambia |
| **3 · Los arreglos del servidor de `R6.17`** (alta solo con inscripción, orden en español, año que no se cambia) | En esta rama, o al final | **Al final, en `R6.17`**, como estaba |
| **5 · Una ficha que llega sin jugadores** (salió al medir en el paso 3: hay fichas con la lista vacía, y no se sabe si a un equipo con jugadores le puede llegar vacía de forma pasajera) | Que no cambie nada, con un error; o aceptarla como verdad | **Aceptarla como verdad**: toda la plantilla queda «No federado» y se pone la fecha; si fue un fallo pasajero, se arregla al sincronizar otra vez. Se asume que va contra la regla de que lo vacío no sobrescribe (`D-56`, `D-75`), a sabiendas |
| **6 · Los dos 422 sin código** (la federación no publica plantillas; el equipo no está enganchado esa temporada) | Dos códigos nuevos, o reutilizar `FEDERATION_ADAPTER_MISSING` e `INVALID_VALUE` | **Dos nuevos**: `FEDERATION_ROSTER_UNAVAILABLE` y `TEAM_NOT_LINKED`, cada uno diciendo lo que pasa. La web no los verá: no enseña el botón en esos casos. **Y lo decidió Claude, contado**: con liga y copa de códigos distintos, se pide la ficha con el código de la competición más antigua de la inscripción, y la fecha va en esa fila |
| **4 · Qué se puede hacer en cada temporada** (salió al cerrar la 1) | Solo la archivada de solo lectura, como hasta ahora, o también la pasada | **La pasada, como la archivada: se ve, pero no se cambia** (ni alta, ni sincronizar, ni corregir, ni dar de baja, ni la foto). **La en curso**, todo. **La futura**, todo menos sincronizar (decisión 1). Un nombre o un año mal puestos son del perfil, y se corrigen desde la en curso. **La web** quita los botones de la pasada en `R6.16`; **el servidor** rechaza con error lo que se escriba en una pasada en `R6.17`; **los escenarios** ganan el caso de la pasada, revisados antes de escribirlos |

**Decisión de `R6.15`** (2026-11-17), con el desarrollador, en la rama `feature/r6-plantilla-backoffice-2`:

| Qué | Opciones | Elegida |
|---|---|---|
| **1 · Quién retiene la petición en «Mientras la Federación tarda»** | La federación falsa, que tarda en contestar la ficha; o la web, que retiene su petición al servidor (`hold-request.ts`) | **La federación falsa**: el servidor de verdad se queda esperando a la RFFM, que es lo que dice el escenario; como el calendario retenido de la ficha del equipo. Con la web, la pantalla sería la misma, pero ni el servidor ni la federación tardarían |

**Decisiones de `R6.16`** (2026-11-17), una a una con el desarrollador, en la misma rama:

| Qué | Opciones | Elegida |
|---|---|---|
| **1 · Dónde sale el resumen de la sincronización** (hasta seis números y tres listas con nombres; el aviso breve se borra a los 5 s) | Una caja encima de la tabla, o una ventana encima de la página | **Una caja encima de la tabla**: se queda hasta cerrarla con ✕ o cambiar de temporada o de pestaña, y se ve a la vez que las filas que nombra. El lector la lee al aparecer, sin mover el foco. La ventana tapa la tabla, y al cerrarla para ver a los añadidos el resumen desaparece |
| **2 · Cómo sabe la pestaña si la federación del club publica plantillas** (`federationProvidesTeamRoster`, en los datos del club, que el marco pide al arrancar y no pasa a las pantallas) | El club en un sitio común, o la pestaña lo pide otra vez | **Un sitio común** (`club.ts`), como el aviso «Guardado»: sin otra petición, y como dice el LLD-B §2.1 (el club se pide una vez y se mantiene en memoria). Servirá a la R10. [`DW-24`](./Backoffice%20LLD-Anexo-Decisiones-Disenho-001.md) |
| **3 · La temporada pasada y la futura en la web, y sus escenarios** (decisión 4 de `R6.14`) | — | **Por sus fechas**: pasada, la que acabó antes de hoy (archivada o no); en curso, la que contiene hoy (`isCurrent`); futura, la que empieza después. **Cuatro escenarios nuevos** (121 → 125), revisados antes de escribirlos: la plantilla de una pasada, archivada y sin archivar, se ve pero no se cambia (el de la archivada pasa a esquema, 1 → 2); la de una futura se cambia a mano, pero no se sincroniza; y la ficha del jugador de una pasada, archivada y sin archivar, sin botones. El equipo sin enganchar, sin escenario: lo cubren las pruebas de piezas |
| **4 · Dónde sale el aviso si la Federación falla o no contesta** (502 o 504, con sus textos ya en `errors.ts`; la plantilla no cambia) | En la caja del resumen, o con la pieza de error de las cargas y su «Reintentar» | **En la caja del resumen**, como aviso de error: se cierra con ✕, y otra sincronización lo quita; se vuelve a intentar con el mismo botón, sin un segundo que haga lo mismo. El lector lo lee al aparecer. Sustituye al resumen anterior, si lo había |
| **5 · Cómo dice la ficha del jugador «Federado» y la fecha** (`federated` y `lastListedAt`, que se queda aunque deje de publicarlo) | Un dato «Federación» con la fecha dentro, o dos datos | **Un dato, «Federación»**: «Federado · publicado el 17/11/2026 18:30»; «No federado · publicado por última vez el …» si lo publicó antes; «No federado» si nunca; y sin el dato si la plantilla nunca se ha sincronizado o la federación no las publica, como la tabla. Con dos, una línea más, casi siempre con raya en las altas a mano. En la tabla, como estaba: «Federado» o «No federado» junto al nombre, sin fecha |

### E · Los escenarios en verde y el cierre

| Paso | Qué |
|---|---|
| `R6.17` | **El servidor: el alta de un jugador pide que el equipo esté inscrito en esa temporada** (decisión 3 de `R6.11`), en ciclos TDD, con su entrada en la bitácora del backend y su código de error. Si la sincronización da de alta por el mismo camino, también. Y **el orden por nombre en español** (decisión 5 de `R6.11`): la plantilla y el buscador de perfiles, con las tildes junto a su letra y la eñe detrás de la ene. Y **corregir no cambia un año que ya está, ni el nombre y el año a la vez** (decisión 1 de `R6.12`). Y **nada se escribe en una temporada pasada**, como en la archivada (decisión 4 de `R6.14`). Y **el diccionario de nombres y apellidos** (`D-123`): la lista, revisada antes de grabarla; la sincronización que la usa; y la migración de los perfiles publicados alguna vez |
| `R6.18` | Los 123 escenarios de la rebanada en verde (125 hasta su decisión 2), con axe en los dos modos, en cuatro partes, una por fichero (`plantilla.feature`, `alta-jugador.feature`, `jugador.feature` y `plantilla-federacion.feature`), cada una con su commit |
| `R6.19` | La revisión a mano: el teclado y el zoom al 200 % |
| `R6.20` | El cierre: cifras, `AGENTS.md`, el plan del backoffice (§4 y §6; y en el mapa de pantallas, la Plantilla y la Ficha del jugador, de ámbar a verde) y lo aprendido |


**El diccionario de nombres y apellidos, para `R6.17`** (2026-11-17, propuesto por el desarrollador al sincronizar de
verdad en R6.16: la RFFM quita tildes y eñes, «FERNANDEZ PEREZ, JORGE»). Una lista de nombres y apellidos en
castellano; al sincronizar, cada palabra que llega se busca en ella sin mirar tildes ni eñes, y si está, se guarda
como en la lista. Lo que no está, como llega. **Para dejar las menos correcciones posibles.** Decisiones, una a una,
escritas en [`D-123`](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md):

| Qué | Opciones | Elegida |
|---|---|---|
| **1 · A qué nombres se aplica** | Solo a los que llegan de la Federación, o también al alta y a la corrección a mano | **Solo a los de la Federación**: es la que quita las tildes. Lo que teclea el club se queda como lo escribe («Jesus», si es su nombre) |
| **2 · De dónde sale la lista** | Escrita por Claude y revisada por el desarrollador; las del INE (por lo que se sabe, sin tildes); o una regla («-EZ» lleva tilde) | **Escrita por Claude, revisada por el desarrollador**: solo las palabras con tilde, eñe o diéresis, unas 300 a 400 de las más frecuentes; con dos formas, la castellana («Jesús», «Román», «Martín», «Muñoz»), y las que existen de las dos maneras («Díez» y «Diez»), una a una. Antes de grabarla, medido cuánto cubre en la base del desarrollador. Con sus pruebas: cada palabra con su marca, y ninguna repetida |
| **3 · Los perfiles ya guardados** (la base no guarda de dónde salió cada perfil) | Solo los que la Federación ha publicado alguna vez, o todos | **Una migración, solo para los publicados alguna vez**: los que tienen alguna fila con `last_listed_at`, cuyo nombre es el de la RFFM salvo tildes. Lo dado de alta a mano que la RFFM nunca ha publicado, como está. Sin ella, un «MUNOZ» guardado antes no casaría con el «MUÑOZ» que da el diccionario, y saldría repetido. Se asume: un «Jesus» tecleado a mano que luego publica la RFFM queda «Jesús» |

**Decisiones de `R6.17`** (2026-11-18), una a una con el desarrollador, en la rama `feature/r6-plantilla-backend-3`:

| Qué | Opciones | Elegida |
|---|---|---|
| **1 · Dónde se ordena por nombre en español** (hoy la plantilla en Swift y el buscador en la base, los dos por el número de cada letra: «ÁLVARO», «ÑAKO» y «ÓSCAR», detrás de «ZAPATA») | Los dos en la base, con la ordenación española de Postgres; o la plantilla en Swift con una comparación en español | **Los dos en la base**, con `es-ES-x-icu`: medido que el Postgres del desarrollador la trae y ordena «ÁLVARO · NUÑO · NURIA · ÑAKO · ÓSCAR · ZAPATA». La plantilla pasa a ordenarse en la consulta (por dorsal, y los que no tienen, al final por nombre). Una regla en un sitio, probada contra Postgres. En Swift, sin comprobar que en Linux compare en español, y dos reglas que tendrían que coincidir. **Para R16**: comprobar que el Postgres de Supabase la trae. [`D-124`](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md) |
| **2 · Qué código da el alta de un jugador si el equipo no está inscrito en esa temporada** (la web no lo verá: sin inscripción no hay pestañas) | Reutilizar `TEAM_NOT_REGISTERED`, como 422; o uno nuevo | **Reutilizar `TEAM_NOT_REGISTERED`, como 422**: la misma causa, con el mismo nombre; 422 y no 404 porque el equipo y la temporada existen y lo que falla es una regla. Hoy es el 404 de pedir la inscripción. La sincronización ya lo cumple: sin inscripción no hay código de la federación (`TEAM_NOT_LINKED`) |
| **3 · Qué código da escribir en una temporada pasada sin archivar** (alta, corregir, baja y foto; la web no lo verá) | Uno nuevo, `SEASON_ENDED`; reutilizar `SEASON_ARCHIVED`; o `SEASON_NOT_CURRENT` | **Uno nuevo, `SEASON_ENDED`** (422), «Esta temporada ya terminó: se ve, pero no se cambia.». Si está terminada y archivada, `SEASON_ARCHIVED`, como hasta ahora. `SEASON_ARCHIVED` diría «archivada» de una que no lo está; `SEASON_NOT_CURRENT` habla de sincronizar, y en la futura sí se escribe. Sincronizar sigue con `SEASON_NOT_CURRENT` |
| **4 · Qué código dan las dos reglas del año al corregir** (el año ya puesto no se cambia; el nombre y el año, no a la vez; decisión 1 de `R6.12`) | `INVALID_VALUE` con su motivo; o dos códigos nuevos | **`INVALID_VALUE`** (422), con el detalle «campo: motivo» que la web ya enseña junto al campo: `birthYear: ya está puesto y no se cambia; si es un error, da de baja al jugador y dalo de alta como nuevo`, y `birthYear: no se cambia a la vez que el nombre; si es otra persona, da de baja a este y da de alta al otro como nuevo`. Sin códigos nuevos para algo que la web ya impide |
| **5 · Las palabras del diccionario que existen de las dos maneras** (`D-123`; salió al revisar la lista: 292 palabras, y 8 aparte) | Una a una: que entre (siempre con tilde) o que no (como llegue) | **Entran Díez, Sáez, Martí, Mía y Éric; fuera Saiz, Zoe e Iker**, que se escriben sin tilde (Iker, además, no es castellano). Medido en la base del desarrollador: de 50 perfiles publicados, el diccionario arregla 34 (50 palabras), y cubre los 26 apellidos en «-EZ» |

**Decisiones de `R6.18`** (2026-11-18), una a una con el desarrollador, en la rama `feature/r6-plantilla-backoffice-3`:

| Qué | Opciones | Elegida |
|---|---|---|
| **1 · Cómo se ponen jugadores en una temporada pasada** (desde `R6.17` el servidor no deja escribir en una terminada, así que el alta por la API falla; lo piden seis escenarios, uno con la foto en su perfil) | Una fecha fija para el servidor de pruebas; escribir el perfil, la fila y la foto con SQL; o dar de alta por la API en la temporada en curso y mover la fila con SQL | **Alta por la API en la en curso, y una línea de SQL que mueve la fila a la pasada**: el perfil, la foto y lo que el perfil copia de la fila salen por la aplicación; el SQL solo cambia de qué temporada es la fila, con su porqué en el código, como `addArchivedSeason`. Una fecha fija cambiaría el servidor solo para las pruebas, y no sería la del navegador; el SQL entero repetiría el alta y necesitaría el fichero de la foto. Solo en la base de las pruebas (`tfm_test`) |
| **2 · La temporada archivada** (salió al pasar `plantilla.feature`: la ficha del equipo dice «No hay ninguna temporada 2013/14», porque la web solo pide las temporadas sin archivar; así se decidió en la R2, y una archivada «se recupera desde Temporadas», en la R11) | Que las fichas del equipo y del jugador la encuentren si se escribe su dirección; o dejarla para la R11 | **Para la R11**, donde una archivada se ve y se recupera: fuera el ejemplo «archivada» de los dos esquemas (la plantilla y la ficha del jugador de una pasada), que quedan en un escenario cada uno (125 → 123), y los dos casos, apuntados en la fila de la R11 del plan del backoffice. La regla de solo lectura sigue probada en la web (`canChange`) y en el servidor (`SEASON_ARCHIVED`). Los enlaces viejos a una temporada que se archive, una pregunta para cuando exista archivar |
| **3 · Cómo publica los nombres la federación falsa** (la RFFM manda casi todos sin tildes ni eñes, y el servidor se las pone con el diccionario desde `R6.17`, `D-123`; la falsa los publicaba con sus marcas). Medido: de las 29 palabras con marca de los nombres inventados, 28 están en el diccionario tal cual; «ÍÑIGO», no, porque el diccionario lo escribe «IÑIGO»; y ninguna sin marca la cambiaría | Como ahora, con sus marcas; o como la RFFM, la mayoría sin ellas | **Como la RFFM**: cuatro de cada cinco, sin tildes, diéresis ni eñes (`asTheRFFM`), salvo cuando el escenario pide que la Federación ponga la marca. Casi cada sincronización pasa por el diccionario, como en la realidad, y los pasos esperan el nombre bien escrito. En los nombres inventados, «IÑIGO», como lo escribe el diccionario |

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
| `R6.11` | 2026-11-16 | **La pestaña Plantilla**, en `feature/r6-plantilla-backoffice`, con **cinco decisiones** una a una (§7 C): cada paso pone sus botones; sin rótulo «Federación» en Plantilla; el equipo que no juega la temporada sigue sin pestañas, y el servidor rechazará el alta sin inscripción (`R6.17`, paso nuevo; los tres últimos se corren un número); cada pestaña en su fichero; y el orden de los nombres con tilde, al servidor en `R6.17`. **Primero, Resultados a su fichero** (`ResultsTab.vue`), sin cambiar lo que se ve: 453 pruebas de piezas y los 170 escenarios de antes en verde (semilla 328427). **Después, Plantilla**: `RosterTab.vue` (pide los jugadores solo al abrirse; cargando, error con «Reintentar», «Este equipo aún no tiene jugadores en 2026/27.» o la tabla), `roster.ts` (la raya, «Sin año», la demarcación por su nombre), y en `components/`, `playerName.ts` (el nombre como «Nombre Apellidos» y las iniciales: las de las dos primeras palabras que no son partícula; tras un apóstrofo, minúscula) y `PlayerPhoto.vue` (la foto con el nombre para el lector; sin ella, o si no carga, las iniciales, que el lector no lee). El camino `/temporadas/:temporada/equipos/:id/plantilla`, y el selector de temporada se queda en la pestaña. **Un fallo encontrado por su prueba**: cambiar de pestaña volvía a pedir la cabecera, porque vigilar equipo y temporada en una lista nueva cuenta como cambio en cada navegación. **Aparte** (`6dea57d`): la web no compilaba desde la fusión del servidor; faltaban los mensajes de diez códigos. `typecheck`, `lint` (los 3 avisos de siempre), **453 → 482** pruebas de piezas y `build` en verde; los escenarios, 170 en verde y los 119 de la rebanada sin definir (semilla 31847). **Visto en el navegador** con los datos del desarrollador: el Cadete A, su pestaña Plantilla sin jugadores; la tabla con jugadores no, porque el club no tiene ninguno. **No hay que relanzar el servidor**: solo cambia la web |
| `R6.12` | 2026-11-16 | **El alta, corregir y la baja**, en tres commits, con **una decisión** (§7 C): el nombre se corrige, el año solo si está vacío y con confirmación, y los dos a la vez no; los escenarios de corregir, reescritos (119 → 121). **El alta** (`3fa2c98`): «Dar de alta un jugador» abre `PlayerDialog.vue`; el buscador (`profileSearch.ts`) pregunta desde 3 letras, al dejar de teclear 300 ms, y se queda con la respuesta de lo último escrito (cancela la anterior y comprueba que la que llega es la última); cada opción lleva su nombre entero para el lector («Juan García Fuente, 2010 · Celtic Infantil A 2025/26»), porque la lista pone ese de nombre y lo de dentro no se lee; el de otro equipo, desactivado. Las reglas del nombre, el año y el dorsal, en `playerForm.ts`, copiadas de las del servidor. La foto aparte (`photoUpload.ts`), en crudo con su tipo; si falla, «Guardado, sin la foto: <motivo>». **Corregir** (`fee4583`): ✎ en cada fila, el mismo diálogo en dos bloques. **La baja**: 🗑 (`trash-2` de Lucide 1.62.0) y `RemovePlayerDialog.vue`, que dice que su dorsal queda libre, que sus goles y tarjetas siguen contando y que sincronizar no lo vuelve a añadir, con el foco en «Cancelar»; al confirmar, «Dado de baja». Sin botones ni acciones en una temporada archivada. **Visto en el navegador** con los datos del desarrollador: el diálogo del alta, el buscador con «Dar de alta a «Ana Ruiz» como jugador nuevo» y los campos del jugador nuevo, sin guardar; **salió que el servidor no sirve `listTeams`** (404), con el que se iban a nombrar los equipos del buscador: van con el nombre que manda el servidor. **Después, la decisión 2** (los cinco campos desde el principio): y al verla, que **la ventana llevaba el foco a su ✕ al terminar de aparecer**, también en la confirmación de la baja; ahora lo pone la web otra vez entonces, como en la ventana de cambios sin guardar. **Quedaba para `R6.19`** el botón de elegir la foto, que salía con el texto del navegador («Choose File» en uno en inglés): resuelto en `R6.13`. `typecheck`, `lint` (los 3 avisos de siempre), **482 → 540** pruebas de piezas y `build` en verde; los escenarios, 170 en verde y los 121 de la rebanada sin definir (semilla 405288; tras la decisión 2, semilla 515199). **No hay que relanzar el servidor**: solo cambia la web |
| `R6.13` | 2026-11-17 | **La ficha del jugador y su foto**, sin decisiones nuevas (las 6 y 7). `screens/player/PlayerScreen.vue`, en `/temporadas/:temporada/jugadores/:id`: el nombre de su perfil, su equipo y la temporada, y el dorsal, la demarcación y el año («—» y «Sin año» si faltan); encima, «← Plantilla del Cadete A». Si la temporada del camino no es la suya, o no existe, «No se ha encontrado el jugador» con el enlace a la portada. **La foto se guarda en cuanto se elige** («Poner foto» o «Cambiar foto», y «Quitar foto»), sin otro botón: es lo único que cambia; si no vale, lo dice y la de antes se queda. «Corregir» y «Dar de baja» abren los mismos diálogos de la fila; tras la baja, de vuelta a la plantilla con «Dado de baja». Sin acciones en una temporada archivada. **El nombre de cada fila de la plantilla lleva a la ficha.** **Pieza común nueva**, `components/PhotoPicker.vue`: un botón con el texto de la web que abre el selector de ficheros, escondido; la usan la ficha y el diálogo, así que **el «Choose File» del navegador, apuntado para `R6.19`, queda resuelto**. `typecheck`, `lint` (los 3 avisos de siempre), **540 → 555** pruebas de piezas y `build` en verde; los escenarios, 170 en verde y 121 sin definir (semilla 327187). **Visto en el navegador** solo el jugador que no existe: el club del desarrollador no tiene jugadores. **No hay que relanzar el servidor**: solo cambia la web |
| `R6.14` | 2026-11-17 | **El servidor de la sincronización**, en `feature/r6-plantilla-backend-2`, con **seis decisiones** una a una (§7 D): solo en la temporada en curso (la ficha de equipo no dice de qué temporada es); la grabación con los datos cambiados; los arreglos de `R6.17`, al final; la temporada pasada, como la archivada; una ficha sin jugadores se acepta como verdad; y dos códigos nuevos. En cinco commits. **1 · El catálogo** (`d83966d`): `SEASON_NOT_CURRENT` y la enmienda a `D-120`. **2 · La migración 23ª** (`9a504d0`, `AddRosterSyncColumns`): `roster_synced_at` en la inscripción, y `federated` y `last_listed_at` en la fila, anulables; la inscripción da la fecha más reciente de sus filas; salió que el resumen de cada competición rearmaba la inscripción y la perdía. **3 · El adaptador** (`7b912ec`): `fetchTeamRoster` en el puerto, sin implementación por defecto; `RFFMTeamSheetParser` lee `fichaequipo/<código>` y da la vuelta a «APELLIDOS, NOMBRE» solo con una coma; **medido**: el código es el de la inscripción, la ficha no dice temporada, a un código que no existe responde `team: null`, y hay fichas sin jugadores (anexo de la RFFM, §F.21; y la guía de alta de una federación). La grabación, con los datos personales cambiados por `Tools/Fixtures/anonymize-rffm-team-sheet.swift`, comprobado aparte: ningún nombre ni código de los de verdad. **4 · La sincronización** (`55a8022`): `SyncTeamRoster` en tres tiempos (que se pueda; la federación, fuera de la transacción; todo lo escrito, en una), `PlayerName.sameNameKey` («el mismo nombre»: sin tildes ni diéresis, con la eñe distinta), el resumen, «federado» en cada fila y la fecha en la fila de la competición más antigua con código; `FEDERATION_ROSTER_UNAVAILABLE` y `TEAM_NOT_LINKED`; un alta a mano tras sincronizar, «No federado». **Dos fallos** salidos por el camino: corregir le quitaba a la fila «federado» (del paso 2), y al catálogo le faltaba el 400 de la operación. **5 · El cierre**: antes de la pasada, dos pruebas que faltaban (enganchar conserva la fecha; cambiar la foto conserva «federado»); **la mutación, 36/36** (`Tools/Mutate/Catalogs/R6-14.json`) a la primera; **el recuento**, leído del XML: **1024** (1021 + 3 omitidos), sin fallos; **981 → 1024** en la R6.14; el censo, salida `0` (51 códigos en la lista). El servidor sirve **27** operaciones. **Sin probar contra la RFFM de verdad**: solo contra su grabación y dobles. **Para instalar**: fusionar la rama, `swift run Run migrate-tenants` y relanzar el servidor |
| `R6.15` | 2026-11-17 | **La federación falsa publica la ficha de equipo**, en `feature/r6-plantilla-backoffice-2`, con **una decisión** (§7 D): la petición que tarda la retiene la federación falsa, no la web. **La ficha** (`fake-federation.ts`): `fichaequipo/<código>` de cada equipo de una competición inventada, con los mismos campos y en el mismo orden que la grabada; los jugadores que publica el escenario (`publishRoster`), o ninguno; a un código de nadie, `team: null`. **Que falle** (`failRoster`, 500, y `answerRoster`) y **que tarde** (`holdRoster`, `heldRosterArrived`, soltada con `releaseAll`). **Los jugadores inventados** (`invented.ts`): «APELLIDOS, NOMBRE» en mayúsculas, con las formas de los 46 medidos (tildes, eñe, diéresis, compuestos, partícula, guion, uno de cada cinco con un solo apellido; que en la RFFM la mayoría vayan sin tildes se supo después, en R6.16); con la marca que pida el caso (tilde, diéresis, eñe o ninguna); sin dos con «el mismo nombre» de la sincronización (`sameNameKey`, con la eñe distinta); sus códigos; y los cinco nombres que no valen de los escenarios. **Comprobado a mano** contra la federación falsa en un puerto aparte: la ficha vacía, la de un código de nadie, la de un rival, los diez jugadores, el 500, y la retenida, que no contesta hasta soltarla. `typecheck` y `lint` en verde; los escenarios, 170 en verde y los 121 de la rebanada sin definir (semilla 237133). Los pasos de los 46 escenarios, con la web (`R6.16`). **No hay que relanzar el servidor**: solo cambian las pruebas de la web |
| `R6.16` | 2026-11-17 | **La web de la sincronización**, en `feature/r6-plantilla-backoffice-2`, con **cinco decisiones** una a una (§7 D): el resumen en una caja encima de la tabla; el club en un sitio común (`DW-24`); la temporada pasada y la futura por sus fechas, con cuatro escenarios nuevos (121 → 125); el aviso de fallo en la misma caja; y la ficha del jugador con un dato «Federación» y su fecha. En cinco commits. **1 · Las decisiones** (`03ff183`), con los escenarios y `DW-24` (y el LLD-B §2.1). **2 · El club** (`0386842`): `club.ts`, que guarda el marco y leen las pantallas. **3 · La temporada pasada** (`6b38b9b`): `seasonPhase` y `canChange` en `seasons.ts`; en una pasada, archivada o no, la plantilla sin «Dar de alta» ni acciones, y la ficha sin corregir, baja ni foto. **4 · Sincronizar** (`d309bc9`): `rosterSync.ts` (cuándo se ofrece: en curso, federación que publica plantillas y equipo enganchado; la fecha; las líneas del resumen, la primera siempre y las demás solo si hay algo); en la pestaña, el botón y la fecha en la barra, «Sincronizando…» bloqueado, la caja del resumen (zona que el lector lee sin mover el foco, con ✕, el icono `x` de Lucide) o del error (una alerta), y «Federado» o «No federado» junto al nombre; la ficha del equipo guarda la fecha nueva para la vuelta a la pestaña. **5 · La ficha del jugador** (`d9b67fd`): `federationText`. **Salió por el camino**: una alerta vacía siempre en la página la encontraba la prueba de la carga en vez de la del error; ahora la alerta solo está cuando hay error. Las pruebas nuevas, comprobadas quitando lo que prueban (la regla de la pasada, la fecha que se guarda): fallan. `typecheck`, `lint` (los 3 avisos de siempre), **555 → 598** pruebas de piezas y `build` en verde; los escenarios, 170 en verde y 125 sin definir (semilla 206053). **Visto en el navegador** con los datos del desarrollador: el Cadete A en 2026/27, con «Todavía no se ha sincronizado con la Federación» y el botón; **sin pulsarlo**, porque daría de alta en su base a los jugadores de verdad; la pasada no, porque su club solo tiene 2026/27. Los pasos de los 46 escenarios, en `R6.18`. **No hay que relanzar el servidor**: solo cambia la web |
| `R6.17` | 2026-11-18 | **El servidor de los arreglos y el diccionario**, en `feature/r6-plantilla-backend-3`, con **cinco decisiones** una a una (§7 E): el orden en español, en la base (`D-124`); el alta sin inscripción, `TEAM_NOT_REGISTERED` como 422; la temporada terminada, `SEASON_ENDED`; las reglas del año, `INVALID_VALUE`; y las palabras del diccionario que existen de las dos maneras. En siete commits. **1 · Las decisiones** (`d3958ad`). **2 · El catálogo** (`775f70f`), con el mensaje nuevo en la web. **3 · La temporada terminada y la inscripción** (`68c69d9`): `Season.hasEnded(on:)` por días de Madrid y `RosterRules` con el día que pone quien llama; la sincronización solo mira la archivada (lo demás, su `SEASON_NOT_CURRENT`). **4 · El año al corregir** (`dec232e`). **5 · El orden** (`516db0d`): la plantilla, ordenada en la consulta, que junta la fila con su perfil; el buscador, igual; con `es-ES-x-icu`. **6 · El diccionario** (`9410f6a`, `D-123`): `CastilianNames`, 297 palabras escritas por Claude y revisadas por el desarrollador; `PlayerName.spelledInCastilian`; la sincronización lo usa antes de casar y de guardar («MUNOZ» casa ya con «MUÑOZ»); y **la migración 24ª**, `SpellPublishedNamesInCastilian`, para los perfiles publicados alguna vez. **Dos cosas salidas por el camino**: la prueba de la API de la plantilla no tenía reloj propio, y con el de verdad su «vigente» 2025/26 ya había terminado (ahora lo tiene, con sus equipos inscritos); y yo esperaba «NURIA» antes que «NUÑO», cuando en español la eñe va entre la ene y la o (se corrigió la prueba, no el código). Las pruebas que escribían en la temporada anterior lo hacen con un reloj de cuando estaba en curso. **La mutación, 21/21** a la primera (`Tools/Mutate/Catalogs/R6-17.json`); **el recuento**, leído del XML: **1044** (1041 + 3 omitidos), sin fallos; **1024 → 1044**; el censo, salida `0`. **Medido en la base del desarrollador**: el diccionario arregla 34 de sus 50 perfiles publicados. **Hay que migrar los clubes y relanzar el servidor**: `swift run Run migrate-tenants` y `swift run Run serve` |
| `R6.18` | 2026-11-19 | **Los escenarios de la rebanada en verde**, en `feature/r6-plantilla-backoffice-3`, en cuatro partes, una por fichero, con **tres decisiones** una a una (§7 E): los jugadores de una temporada pasada, por la API en la en curso y su fila movida con una línea de SQL; la temporada archivada, para la R11 (125 → 123); y la federación falsa publica los nombres como la RFFM, la mayoría sin tildes ni eñes. **1 · La plantilla** (`ca6f063`), 15. **2 · El alta** (`9181221`, `a1fe80e`), 37. **3 · La ficha del jugador** (`6903eb7`), 25. **4 · La federación**, 46. Los datos, por la API (`e2e/support/players.ts`): el perfil se lee con el buscador, preguntando desde una temporada pasada; las fotos de las pruebas, dos cuadrados de un color, y las que no valen y la de la ubicación, fabricadas en la prueba. **Lo que encontraron, en commits aparte**: la ficha del jugador no pasaba axe (el rojo de «Dar de baja» y el campo de la foto sin nombre, `a06f6b2`); el buscador del alta tampoco (el texto de las opciones y su contraste), sacaba el «sin resultados» de PrimeVue con dos letras y el foco no siempre llegaba al año (`b4e99a3`); y las fotos de las pruebas caían en `backoffice/fotos/` (`6482136`). **598 → 603** pruebas de piezas; `typecheck`, `lint` (los 3 avisos de siempre) y `build` en verde. **La pasada entera: 293 de 293** (semilla 812524, 10 min 15 s), los 170 de antes y los 123 de la rebanada, con axe en los dos modos. **No hay que relanzar el servidor**: solo cambian la web y sus pruebas |

---

## 9. Lo aprendido

*(Al cerrar la rebanada.)*

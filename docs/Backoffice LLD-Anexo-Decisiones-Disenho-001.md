# Anexo de Decisiones · Bitácora de decisiones de diseño del backoffice

- **Estado:** vivo — se añade una entrada cada vez que se descarta una alternativa
- **Fecha:** 2026-10-15. Las catorce primeras entradas se **trasladaron** del LLD-B, cerrado el 2026-10-14:
  no son decisiones nuevas, solo cambian de sitio
- **Documento principal:** [Backoffice LLD-001](./Backoffice%20LLD-001.md)

> **Qué es este anexo.** El **por qué** del diseño de la web: qué alternativa había, por qué se descartó, qué
> se eligió y **qué se asume a cambio**. El LLD-B dice la regla en una línea y enlaza aquí.
>
> **Por qué existe.** Por lo mismo que la bitácora del backend ([D-26]): un LLD que mezcla la regla con su
> discusión se vuelve difícil de usar como referencia al construir.
>
> **Cómo se lee.** No de corrido: se entra por el índice o por el enlace `[DW-nn]` desde el LLD-B o el plan.
> Cada entrada se entiende sola.
>
> **Ámbito.** Solo las decisiones de **diseño de la web**. Las **tecnológicas** (Vue, PrimeVue, Fly.io, las
> herramientas de pruebas) viven en el [ADR-Backoffice-001](./ADR-Backoffice-001.md). Las que cambian **lo que
> responde el servidor** van en la [bitácora del backend](./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md)
> aunque las pida una pantalla, porque las apps del móvil usarán las mismas respuestas.

---

## Índice

| Id | Decisión | Impacta (LLD-B) |
|---|---|---|
| **Cómo está hecha por dentro** | | |
| **DW-01** | Tres partes, y la frontera entre ellas la vigila el revisor de código | §1.2 |
| **DW-02** | Los datos van bajo `/api/v1`; el servidor sigue en `/v1` | §1.3 |
| **DW-03** | Cada pantalla pide sus datos al entrar: sin memoria entre pantallas | §2.4, §3.3 |
| **DW-04** | Un solo límite de 30 s, por encima de los 20 s que el servidor espera a la federación | §3.4, §4.4 |
| **DW-05** | El «cargando…» se enseña desde el primer momento | §3.1, §3.5 |
| **DW-19** | Las acciones de una fila son iconos con su texto por ratón y por teclado, no un menú ⋮ ni botones con texto | §3.7 |
| **DW-20** | Lo que está en marcha se refresca solo, cada 10 s y como mucho 5 minutos | §2.4 |
| **DW-21** | Un nulo puede llegar como clave ausente, y la web los trata igual | §3.8 |
| **Cómo se comporta** | | |
| **DW-06** | El campo de un error se lee del texto de `detail`, sin esperar a un campo `field` | §4.3, §4.5 |
| **DW-07** | Las reglas de los formularios se leen del catálogo con Ajv | §5.1 |
| **DW-08** | Dos personas editando lo mismo: se queda lo último que se guardó | §5.6 |
| **DW-09** | En el camino va el identificador del servidor, no un nombre legible | §6.3 |
| **DW-22** | La temporada va en el camino de lo que es de una temporada; en la portada, detrás de `?` | §2.2, §6.4, §6.5 |
| **DW-18** | Un 502, 503 o 504 sin código es «no se ha podido conectar»: es el recepcionista, no el servidor | §4.1, §4.4 |
| **Las reglas del negocio en la pantalla** | | |
| **DW-10** | Lo que no se permite nunca se oculta; lo que se permite a veces se desactiva con el motivo a la vista | §7.4, §10 |
| **Lo transversal** | | |
| **DW-11** | Un club por dirección, sin selector de club | §8.2, §12 |
| **DW-12** | Modo claro y oscuro, aunque los bocetos son solo oscuros | §9.3, §9.4 |
| **Las pruebas** | | |
| **DW-13** | Los clubs de los escenarios llevan el prefijo `bo_` | §11.2 |
| **DW-14** | La federación falsa va detrás del servidor, y eso no es un simulacro | §11.3 |
| **DW-15** | Las pruebas de piezas buscan por papel y nombre, y por eso Testing Library usa la versión 10 de su parte común | §11 |
| **DW-16** | TypeScript 5.9 y no 6, para que los tipos se fabriquen del catálogo sin forzar nada | §1.1 |
| **DW-17** | «Cargando» y «error» se prueban reteniendo la petición y parando el servidor de pruebas, sin simulacros | §11.5 |

---

## Cómo está hecha por dentro

### DW-01 · Tres partes, y la frontera entre ellas la vigila el revisor de código

**Qué hay que decidir.** Cómo se reparte el código de la web para que se pueda probar sin simular el servidor,
que es lo que pide el ADR (decisión 6).

**Decisión.** Tres partes —**pantallas** (`screens/`), **piezas** (`components/`) y **conexión** (`api/`)—, y
cada una solo usa la de debajo. Las piezas **no pueden** hablar con el servidor.

**Por qué este reparto: se ve desde las pruebas.** Las **piezas** se prueban con Vitest pasándoles datos, como
a una función; las **pantallas**, en los escenarios BDD contra el servidor real. No queda nada a medio camino
—una pieza que pide sus propios datos— que obligue a simular el servidor para probarla.

**Por qué la regla la comprueba una herramienta.** Es la misma idea que las capas del servidor (LLD del
backend §2.2, [D-01]): las dependencias van en un solo sentido, y **eso no se deja a la buena voluntad**. El
revisor de código (ESLint) da error si un fichero de `components/` usa algo de `api/`, antes de ejecutar nada.

---

### DW-02 · Los datos van bajo `/api/v1`; el servidor sigue en `/v1`

**Qué hay que decidir.** Con qué comienzo pide la web los datos, sabiendo que en producción la web y la API
comparten dirección (nota de CORS) y el servidor contesta hoy en `/v1/…`.

**La alternativa descartada: pedir directamente en `/v1/…`.** No toca nada, pero al leer una dirección no se
sabe a la primera si es de datos o de la web: `/v1/teams` podría ser una pantalla.

**Decisión.** Desde el navegador, siempre `/api/v1/…`. El recepcionista (Vite en local, Caddy en producción)
quita el `/api` al pasarle la petición al servidor, que **no cambia**.
`https://celtic-castilla.miapp.com/api/v1/teams` se lee como datos sin conocer el proyecto.

**Lo que se asume a cambio.** La misma petición tiene **dos formas de escribirse**, según por dónde entre:
`/api/v1/…` por el recepcionista (la web, las apps del móvil, la prueba de humo) y `/v1/…` directo al servidor
(sus pruebas y un `curl` al 8080). **Lo que lo controla:** una dirección con `/api` que llega al servidor sin
pasar por el recepcionista da «no encontrado», y esa es la pista de que alguien se lo saltó.

---

### DW-03 · Cada pantalla pide sus datos al entrar: sin memoria entre pantallas

**Qué hay que decidir.** Si la web guarda en memoria lo que ya descargó para enseñarlo al volver a una
pantalla.

**La alternativa descartada.** Una herramienta que guarda en memoria lo ya descargado (Pinia Colada, TanStack
Query) y, al volver a una pantalla, enseña al momento lo que tenía mientras lo actualiza por detrás.

**Decisión.** Cada pantalla pide sus datos al entrar, también al volver a una que ya se había visto, y no se
guarda nada en memoria entre pantallas. Tras guardar un cambio, la pantalla vuelve a pedir lo que enseña.

**Razones:**

- **Siempre se ve lo que hay en el servidor**, también lo que acaba de cambiar un compañero. Lo grave en
  esta web no es esperar un momento, sino corregir un acta mirando datos viejos.
- **No hay que acordarse de nada después de guardar.** Con datos guardados, cada cambio obliga a decir qué
  otros datos ya no valen; si se olvida, la pantalla enseña algo que ya no es verdad.
- **Las pruebas ven lo que respondió el servidor**, sin una pantalla que cambia sola después de aparecer y
  pasos que tienen que esperar a que se asiente.
- **El coste es pequeño:** pocos usuarios, un servidor que responde rápido y pantallas que piden poco.

**Lo que se asume a cambio.** Un «cargando…» corto al entrar en cada pantalla (LLD-B §3).

**Cuándo se revisa.** Si una pantalla **se mide** lenta. Entonces se añade la memoria solo donde haga falta. Es
barato porque todas las peticiones salen de `api/` ([DW-01]).

---

### DW-04 · Un solo límite de 30 s, por encima de los 20 s que el servidor espera a la federación

**Qué hay que decidir.** Cuánto espera la web una respuesta antes de rendirse, y si el límite es el mismo para
todas las peticiones.

**Decisión.** **30 segundos, uno solo para todas.**

**Por qué 30 y no menos.** La vista previa del enganche con la federación
(`POST /v1/teams/{id}/federation-link/preview`) pregunta **en directo** a la federación, y el servidor espera
hasta **20 segundos** antes de dar su propio error (`backend/Sources/Federation/HTTPFederationTransport.swift`,
LLD del backend §2.3-c). Ese error dice más («la federación no responde») que el de la web («el servidor no
responde»). Si la web se rindiera antes de los 20 s, ese mensaje no llegaría nunca.

**Lo que hay que vigilar.** El número depende de otro que vive en el servidor. **Si alguna vez se sube el
límite del servidor, hay que subir este por encima.**

---

### DW-05 · El «cargando…» se enseña desde el primer momento

**Qué hay que decidir.** Si el «cargando…» aparece en cuanto se pide, o tras una pequeña espera, para que no
parpadee cuando la respuesta llega enseguida.

**La alternativa descartada.** Esperar unos milisegundos y enseñarlo solo si la respuesta no ha llegado.

**Decisión.** Se enseña **en cuanto se pide**.

**Lo que se asume a cambio.** Puede parpadear un instante con un servidor rápido. A cambio, **la pantalla se
comporta siempre igual**, y el escenario que comprueba el estado *cargando* no depende de la velocidad del
servidor.

---

## Cómo se comporta

### DW-06 · El campo de un error se lee del texto de `detail`, sin esperar a un campo `field`

**Qué hay que decidir.** Cómo sabe la web junto a qué campo del formulario enseñar un error de valor
(`INVALID_VALUE`, 422, y `NOT_EDITABLE_AFTER_SYNC`, 409), si el error del servidor no trae un campo que lo
diga.

**Lo que hay hoy.** El servidor escribe `detail` siempre igual: `<campo>: <motivo>` (`name: no puede estar
vacío`). Y el catálogo ya dice que `detail` «nombra el campo, para que la UI pueda señalarlo» (`openapi.yaml`,
respuesta 422 de `PATCH /club`), aunque no dice el formato exacto.

**La alternativa descartada: añadir ahora un campo `field` al error.** El servidor comprueba **un campo cada
vez** (el Dominio se para en el primer error). Lo que de verdad hace falta es que devuelva **todos los errores
a la vez**, y con ese cambio habrá que decidir cómo viaja el campo de cada uno. Añadir `field` antes sería
tocar el error dos veces.

**Decisión.** La web lee ese formato tal cual. **Es un acuerdo publicado, no un truco**: depende de algo que
el catálogo ya promete, y lo que falta —escribir el formato exacto en el catálogo— se hace con la portada.

**Lo que hay que vigilar.** Si el servidor cambia el formato, el error deja de salir junto a su campo. Lo
vigila un escenario BDD que provoca un error de valor y comprueba dónde sale.

**Cuándo se revisa.** Cuando el servidor aprenda a devolver todos los errores de valor a la vez.

---

### DW-07 · Las reglas de los formularios se leen del catálogo con Ajv

**Qué hay que decidir.** De dónde saca la web las reglas para comprobar un formulario antes de enviarlo
(obligatorio, longitud, lista cerrada…), sabiendo que el servidor ya las tiene escritas en el catálogo.

**Las dos alternativas descartadas.**

| Opción | Por qué no |
|---|---|
| Escribirlas a mano en la web | Una segunda copia de las reglas, que se queda atrás el día que cambie el catálogo |
| Generar código de comprobación a partir del catálogo | Funciona, pero añade otra cosa generada que mantener para conseguir lo mismo que la siguiente |

**Decisión.** El catálogo es **OpenAPI 3.1**, y en esa versión cada dato se describe en un formato estándar de
reglas (*JSON Schema*). Un comprobador ya hecho, **Ajv**, lee esas reglas **tal cual**, sin traducirlas ni
generar código, y devuelve todos los fallos con su campo.

**Amplía la decisión 3 del ADR**, que generaba del catálogo «solo las descripciones de los datos». La idea es la
misma —una sola fuente de verdad, sin copias a mano— y no añade código generado: Ajv usa la descripción que ya
está en el catálogo.

**Lo que se asume a cambio.** Lo que el catálogo no puede describir lo sigue comprobando solo el servidor (que
ya exista un equipo igual, un nombre que solo tiene espacios…), y llega como error, de uno en uno. **El
servidor sigue siendo quien manda**: la comprobación de la web solo ahorra un viaje y enseña todos los fallos
juntos.

**Cómo llega el catálogo a la web** (añadido el 2026-10-23, con la rebanada 2,
[su decisión 3](./Plan%20de%20desarrollo%20R2%20Alta%20de%20equipo-001.md)). La web se ejecuta en el navegador y
no puede leer `openapi.yaml`, y el servidor no lo publica. Así que llega **igual que las descripciones de los
datos**: `npm run gen:api` genera, además de `schema.d.ts`, un `src/api/schemas.json` con solo los esquemas
(`components/schemas`, con esa estructura para que sus `$ref` sigan valiendo), sin guardarlo en el repositorio.
Tipos y reglas salen del mismo catálogo, a la vez: la web nunca comprueba con unas reglas distintas de las de los
tipos con los que compiló. Se descartaron importar el `.yaml` al compilar (una pieza más de Vite, y el catálogo
entero dentro de la web) y pedírselo al servidor al abrir (podría ser otro catálogo que el de los tipos).

- **Las piezas**: `ajv` 8 con `Ajv2020` (el catálogo es OpenAPI 3.1, que es JSON Schema 2020-12), `ajv-formats`
  para `format: uuid`, y `yaml` para leer el catálogo en `gen:api`.
- **Ajv en modo estricto**: las palabras de OpenAPI que no son de JSON Schema (`discriminator`…) se le declaran,
  en vez de apagarlo, para que una regla mal escrita siga saltando.
- **El mensaje de un `pattern` lleva el ejemplo del catálogo** (`examples`): «El formato no es válido. Por
  ejemplo: 2024/25». Sigue sin haber texto por campo escrito a mano.
- **Lo que supone para el despliegue**: el fichero nace al compilar y viaja dentro de `dist/`. La web solo hay que
  recompilarla cuando cambia el catálogo; las reglas de cómo se coordina con el servidor, pendientes de la
  rebanada 16, están en el plan del backoffice (§4).

---

### DW-08 · Dos personas editando lo mismo: se queda lo último que se guardó

**Qué hay que decidir.** Qué pasa si dos personas abren y guardan lo mismo a la vez.

**La alternativa descartada.** Detectar el choque y avisar a la segunda persona. Hoy el servidor no detecta
ese choque.

**Decisión.** **Se queda lo último que se guardó**, sin aviso.

**Por qué se acepta.** Los usuarios son pocos y rara vez tocarán lo mismo a la vez.

**Cuándo se revisa.** Si algún día molesta. Y entonces **se resuelve en el servidor, no en la web**.

---

### DW-09 · En el camino va el identificador del servidor, no un nombre legible

**Qué hay que decidir.** Cómo se nombra cada equipo, partido o jugador en la dirección
(`/equipos/:id/plantilla`).

**La alternativa descartada.** Un nombre legible: `/equipos/cadete-a`. Exigiría añadir ese dato al servidor y
mantener que no se repita.

**Decisión.** `:id` es **el identificador que da el servidor** (un UUID): `/equipos/3f2a91c4-…/plantilla`.

**Lo que se asume a cambio.** Una dirección larga e ilegible. Se acepta porque es una herramienta interna en la
que casi nadie escribe los caminos a mano, y no pide nada al servidor.

---

## Las reglas del negocio en la pantalla

### DW-10 · Lo que no se permite nunca se oculta; lo que se permite a veces se desactiva con el motivo a la vista

**Qué hay que decidir.** Qué ve el usuario ante una acción que no puede hacer: nada, un botón desactivado, o
un botón que al pulsarlo da error.

**Decisión.**

- **Lo que no se permite nunca, no aparece.** En un partido no hay botón «Borrar».
- **Lo que se permite a veces aparece desactivado y con el motivo escrito**, por ejemplo: «No se puede borrar:
  el equipo está sincronizado con la Federación». *(Decía «Para dejar de gestionarlo, libéralo»; corregido el
  2026-10-25: liberar deshace una reclamación, no un enganche. Dejar de sincronizar no existe todavía; es de la
  rebanada 13.)* Así el usuario sabe que la
  acción existe y qué le falta para poder hacerla.

**La alternativa descartada para el motivo: un globo al pasar el ratón.** No lo ve quien usa el teclado ni
quien usa un lector de pantalla (LLD-B §10). Por eso el motivo va **escrito en la pantalla**.

---

## Lo transversal

### DW-11 · Un club por dirección, sin selector de club

**Qué hay que decidir.** Si dentro de la web se puede cambiar de club.

**La alternativa descartada.** Un selector de club dentro de la web.

**Decisión.** **No hay forma de cambiar de club dentro de la web.** Cambiar de club es abrir otra dirección, y
eso arranca la web desde cero, con la memoria vacía.

**Por qué.** Así **los datos de dos clubes no se pueden mezclar nunca**, ni por una respuesta que llega tarde
ni por algo que quedó en memoria.

**Cuándo se revisa.** Si algún día una persona trabaja para dos clubes, lo resolverá el inicio de sesión
(LLD-B §12).

---

### DW-12 · Modo claro y oscuro, aunque los bocetos son solo oscuros

**Qué hay que decidir.** Si la web tiene solo el modo oscuro de los bocetos del móvil o también uno claro.

**La alternativa descartada.** Solo oscuro, como los bocetos.

**Decisión.** **Los dos, con un interruptor.** La primera vez se sigue la preferencia del sistema; después
manda la elección del usuario.

**Por qué.** El fondo oscuro va bien en el móvil, pero en el ordenador, que es donde más se usará el backoffice
(ADR §1), el contexto cambia: oficinas con luz, pantallas grandes, ratos largos.

**Lo que se asume a cambio.**

- **Cada color tiene dos valores**, uno por modo, y todo texto tiene que leerse en los dos. Por eso el análisis
  de axe mira cada pantalla dos veces.
- **Se guarda una cosa en el navegador**, la elección del modo: es la única excepción con nombre a «en el
  navegador no se guarda nada» (LLD-B §2.3).

---

## Las pruebas

### DW-13 · Los clubs de los escenarios llevan el prefijo `bo_`

**Qué hay que decidir.** Cómo se llaman los clubs que crea cada escenario, para poder barrerlos después sin
tocar nada más.

**Las alternativas descartadas: `e2e_` o `test_`.** Las pruebas del backend borran al arrancar los *schemas*
con esos dos prefijos (`TestEnvironment.swift`, `disposableSchemaPrefixes`). Si los escenarios los usaran, una
pasada de las pruebas del backend se llevaría los clubs de un escenario a medias.

**Decisión.** **`bo_`**. Y al revés: el barrido de los escenarios solo toca `bo_`, así que tampoco se lleva lo
del backend.

---

### DW-14 · La federación falsa va detrás del servidor, y eso no es un simulacro

**Qué hay que decidir.** Cómo preparan los escenarios los datos que solo trae la federación (partidos,
competiciones, clasificación), si el ADR prohíbe simular el servidor y esos datos no se pueden crear por el
servidor (LLD-B §7).

**Decisión.** Una **federación falsa**: un servidor pequeño que devuelve las respuestas grabadas que ya usa el
backend, puesto en el lugar de rffm.es. El escenario engancha el equipo y **ejecuta la ingesta de verdad**,
como en producción.

**Por qué no contradice el «sin simulacros» del ADR.** **No sustituye a nada nuestro**: se pone detrás del
servidor, no delante. El «sin simulacros» hablaba de nuestro servidor, que aquí funciona entero. Es lo mismo
que hacen las pruebas del backend, que nunca llaman a la federación de verdad. Y de paso la ingesta queda
probada.

**Por qué una sola técnica.** Sirve igual para los `Given` de la portada que para las pantallas en las que el
servidor llama a la federación en ese momento (el enganche). Cada escenario elige su `Given`; por debajo,
siempre la misma pieza.

**Lo que se asume a cambio.** Si un escenario necesita algo que no está grabado, hay que grabar una respuesta
nueva.

---

### DW-15 · Las pruebas de piezas buscan por papel y nombre, y por eso Testing Library usa la versión 10 de su parte común

**Qué hay que decidir.** El ADR eligió Testing Library porque busca las cosas como lo haría un usuario
(decisión 6): «el botón que dice *Dar de alta*». Eso es buscar por **papel** (botón, párrafo, encabezado…) y
**nombre**, y es lo que hace que una prueba de piezas compruebe de paso la accesibilidad: si la búsqueda no
encuentra el botón, un lector de pantalla tampoco. Al montar las pruebas (`R0.2`, 2026-10-16) apareció que
Testing Library para Vue, en su última versión (8.1), trae dentro una versión vieja (9.3) de
`@testing-library/dom`, la parte que hace las búsquedas. Esa versión no conoce algunos papeles: buscar un
párrafo por su papel fallaba antes de comparar nada.

**La alternativa descartada: dejarla y buscar por texto cuando un papel no se reconozca.** No cuesta nada
hoy, pero una búsqueda por papel que falla sin motivo a la vista es justo el rojo que no prueba nada
(Plan backoffice §2.3), y cada vez habría que averiguar si falla la pieza o la herramienta.

**Decisión.** Obligar a Testing Library para Vue a usar la **10.4**, la misma que ya usa jest-dom, con
`overrides` en `package.json`. Comprobado: el párrafo y un botón se encuentran por su papel, y el
`package-lock.json` solo pierde los 67 paquetes de la copia vieja, sin añadir ni cambiar ninguno.

**Lo que se asume a cambio.** Testing Library para Vue no está hecho para la 10, aunque funciona. Si algún
día da problemas, se quita el `overrides` y se vuelve a buscar por texto donde un papel no se reconozca. Y
cuando salga una versión de Testing Library para Vue que traiga la 10, el `overrides` sobra.

---

### DW-16 · TypeScript 5.9 y no 6, para que los tipos se fabriquen del catálogo sin forzar nada

**Qué hay que decidir.** El ADR decidió que la web saca sus tipos de datos del catálogo (decisión 3), y la
herramienta que los fabrica es `openapi-typescript` (LLD-B §1.1). Al montarla (`R0.3`, 2026-10-16), su última
versión (7.13, de junio de 2026) **no se dejaba instalar**: solo acepta TypeScript 5, y la plantilla de Vite
había traído TypeScript 6.

**La alternativa descartada: instalarla ignorando el aviso** (`--legacy-peer-deps`). Se instala, pero nadie
garantiza que fabrique bien los tipos con TypeScript 6, y un tipo mal fabricado es un error que el editor no
avisaría: la herramienta que tiene que vigilar el catálogo sería la primera sin vigilar. Además, el aviso se
queda apagado para todos los paquetes, no solo para este.

**Decisión.** **TypeScript 5.9.3**, la última de la serie 5. Con ella encaja todo sin forzar nada: Vue,
`vue-tsc` y la configuración de Vue aceptan cualquier versión desde la 5.8. Comprobado: en el
`package-lock.json` solo cambia TypeScript, y los tipos, las pruebas y la fabricación de la web siguen en
verde.

**Lo que se asume a cambio.** La web va una versión de TypeScript por detrás de la que trae Vite. Cuando salga
una versión de `openapi-typescript` que acepte TypeScript 6 (o 7), se puede subir.

---

### DW-17 · «Cargando» y «error» se prueban reteniendo la petición y parando el servidor de pruebas, sin simulacros

**Qué hay que decidir.** Cada pantalla tiene cuatro estados (LLD-B §3.1), y los escenarios tienen que probar
los cuatro. Pero el ADR no admite simulacros (decisión 6), y el servidor de pruebas contesta en milisegundos:
«cargando» dura demasiado poco para verlo, y el servidor no falla si nadie lo tumba. Se decidió con la portada
([Plan R1, decisión 4](./Plan%20de%20desarrollo%20R1%20Portada%20base-001.md)).

| Opción | Por qué no |
|---|---|
| Un retraso de mentira en el servidor | Sería código del servidor que solo existe para las pruebas |
| Probar «cargando» solo con Vitest | La pantalla entera quedaría sin probar en ese estado |
| Que Playwright guarde la respuesta y la entregue más tarde | Funciona, pero Playwright tendría que coger la respuesta y volver a servirla él. Retener la petición es más sencillo y no toca la respuesta |

**Decisión.**

- **Cargando: se retiene la petición.** Playwright la para antes de que salga, el escenario comprueba el
  «cargando» y luego la suelta tal cual. Llega al servidor de verdad y la respuesta vuelve sin que nadie la
  toque. Solo cambia **cuándo** sale.
- **Error de servidor: se para el servidor de pruebas** (el 8081) y se vuelve a arrancar al acabar, que cuesta
  0,25 s (medido en `R0.9`). Nunca se toca el servidor del desarrollador ni su Postgres.
- **Hay dos errores de servidor, y se prueban por separado.** Lo primero que pide la web es el club: con el
  servidor parado antes de abrir, sale **la página entera** (LLD-B §8). Para el error **dentro de la
  pantalla**, se retiene su petición, se para el servidor y se suelta: va a un servidor parado y falla de
  verdad. Después se arranca otra vez y *Reintentar* tiene que traer los datos.

**Por qué no es un simulacro.** Es el argumento de [DW-14]: todo es de verdad salvo lo que no se puede
controlar. La petición y la respuesta son las del servidor; el fallo es un servidor parado de verdad. El
escenario solo elige el momento.

**Lo que se asume a cambio.** Parar el servidor de pruebas solo es seguro porque **los escenarios se ejecutan
de uno en uno** (`cucumber.mjs` no pide ejecución en paralelo). Si algún día se ejecutan en paralelo, estos
escenarios necesitarán su propio servidor.

---

### DW-18 · Un 502, 503 o 504 sin código es «no se ha podido conectar»: es el recepcionista, no el servidor

**Qué hay que decidir.** Qué enseña la web cuando el servidor está caído. La web no habla con él directamente:
pasa por el recepcionista (Vite en desarrollo, Caddy en producción, LLD-B §1.3). Medido el 2026-10-18, con la
web apuntando a un servidor que no existe:

```
HTTP/1.1 502 Bad Gateway
Content-Type: text/plain
(cuerpo vacío)
```

Así que la web **no ve un fallo de conexión**: ve un error **sin código**. Con la regla del LLD-B §4.1, el
número elige un mensaje genérico de su familia, y saldría «error del servidor» **sin** *Reintentar*. Es justo
el fallo pasajero para el que existe el botón.

**Decisión.** Un **502, 503 o 504 sin código** es «No se ha podido conectar con el servidor», **con
*Reintentar***. Los 502 y 504 que manda el propio servidor (los de la federación, `INGESTION_FAILED`) traen su
`code`, así que no se confunden: sin código solo puede venir del recepcionista.

**Lo que se asume a cambio.** Si algún día delante del servidor hubiera otra pieza que contestara con su propio
cuerpo de error (un balanceador con página HTML, por ejemplo), seguiría sin traer `code` y caería en esta
regla, que es lo correcto. Lo que no cubre es un recepcionista que contestara 500: ése seguiría siendo «error
del servidor».

---

### DW-19 · Las acciones de una fila son iconos con su texto por ratón y por teclado, no un menú ⋮ ni botones con texto

**Qué hay que decidir** (2026-10-25, rebanada 3). La portada tiene que dejar hacer cosas desde la fila del equipo
sin entrar en su ficha. La rebanada 3 trae la primera, sincronizar con la Federación; la 14, relanzar la ingesta, y
la 13 puede poner otras (corregir, borrar). Se decidió sobre una maqueta en HTML de cada forma con las acciones de
las tres rebanadas, para ver cómo crece.

| Opción | Lo que se vio | Veredicto |
|---|---|---|
| (a) Un botón ⋮ con menú | Cabe todo sin ensanchar la tabla, pero la acción no se ve hasta abrirlo; y relanzar la ingesta es **de cada competición**, así que el menú del equipo necesita un apartado con una opción por competición | Descartada |
| (b) Un botón con texto por acción | Con cuatro o cinco acciones aprieta la tabla y repite lo mismo en cada línea | Descartada: no escala |
| **(c) Iconos, con su texto al pasar el ratón o al llegar con el teclado** | Ocupan poco, y cada uno puede ir **donde está lo que afecta**: el de relanzar, en la celda de la ingesta de su competición | **Elegida** |

**Decisión: (c)**, con las condiciones del LLD-B §3.7: el texto sale por los dos caminos, el lector lee el nombre
con la fila detrás, y 40 × 40 px.

**No contradice [DW-10]**, que descartó el globo al pasar el ratón para el **motivo** de lo desactivado. Aquí el
texto es el **nombre** de la acción, y llega también por teclado y al lector. Una acción desactivada sigue
llevando su motivo escrito a la vista (§7.4): el de relanzar una ingesta que ya está en marcha es el propio «En
marcha» de su celda.

**Lo que se asume a cambio.** Un icono no se lee solo: hay que elegir dibujos reconocibles, y quien no pasa el
ratón ni usa el teclado ve solo el dibujo. Por eso el caso que más lo pide, el equipo sin competición, lleva
además un enlace con texto. Y cada acción nueva ensancha la columna unos 40 px.

### DW-20 · Lo que está en marcha se refresca solo, cada 10 s y como mucho 5 minutos

**Qué hay que decidir** (2026-10-25, rebanada 3). Al sincronizar un equipo, la portada lo enseña «En marcha», y
la ingesta acaba unos segundos o minutos después. [DW-03] dice que cada pantalla pide sus datos al entrar; sin
más, «En marcha» se queda hasta recargar, y en la maqueta parecía colgada.

| Opción | Veredicto |
|---|---|
| (a) Nada: hasta recargar | Descartada: parece colgada, y hasta la rebanada 14 no hay otro sitio donde verlo acabar |
| (b) Volver a pedir una vez, a los pocos segundos | Descartada: acierta solo si la ingesta ya acabó |
| **(c) Volver a pedir cada 10 s mientras haya algo en marcha** | **Elegida** |

**Decisión: (c)**, con sus límites: solo con la pestaña a la vista, como mucho 5 minutos seguidos por si una pasada
no acaba nunca, sin «Cargando…» ni errores pintados por un refresco, y sin anunciarlo al lector (LLD-B §2.4). Vale
para todas las filas, también para las ingestas que lanza `launchd`.

**Lo que se asume a cambio.** Una petición cada 10 s mientras dure la ingesta, y una enmienda a [DW-03]: los datos
ya no se piden **solo** al entrar. Se prueba sin simulacros ([DW-17]): la federación falsa retiene el calendario y
el escenario ve el cambio sin recargar.

### DW-21 · Un nulo puede llegar como clave ausente, y la web los trata igual

**Qué hay que decidir** (2026-10-25, rebanada 3, R3.5). Al añadir `takenBy` al `/preview`, obligatorio y anulable,
el JSON de verdad enseñó que **los nulos no viajan**: el `Codable` que genera `swift-openapi-generator` usa
`encodeIfPresent`, y un campo vacío sale sin su clave. Ya pasaba con `crestUrl` y con `federationTeamId`; el
catálogo dice una cosa y el servidor manda otra.

| Opción | Veredicto |
|---|---|
| **(a) Aceptarlo: la web trata «falta» igual que «nulo»** | **Elegida** |
| (b) Que el servidor mande `null` explícito en `takenBy` | Descartada: una conversión a JSON escrita a mano para un campo, y el resto de nulos de la API seguiría igual |

**Decisión: (a)** (LLD-B §3.8). Es lo que ya pasa con todos los nulos de la API, y la web no necesita
distinguirlos: ningún campo del catálogo da un significado distinto a «falta» y a «nulo» en una respuesta.

**Lo que se asume a cambio.** El catálogo promete una clave que no llega, y los tipos de TypeScript no lo avisan;
la regla vive en el LLD-B y en las pruebas de piezas que prueban la clave ausente. Si un día un cliente valida las
respuestas contra el catálogo (Ajv, la app del móvil), fallará en los obligatorios anulables, y se arregla en el
servidor para todos a la vez.


### DW-22 · La temporada va en el camino de lo que es de una temporada; en la portada, detrás de `?`

**Qué hay que decidir** (2026-10-29, rebanada 4, R4.2). La R1 decidió que la temporada va detrás de `?` en todas las
pantallas (`/?temporada=2025-26`, `/equipos/:id/plantilla?temporada=2025-26`; plan R1, decisión 5). Al decidir el
camino de jornada y clasificación, el desarrollador lo propuso con la temporada **en el camino**
(`/temporadas/:temporada/competiciones/:id`), y al revisar el de la ficha señaló que tenía que ser igual: los
resultados también son de una temporada.

| Opción | Veredicto |
|---|---|
| (a) Siempre detrás de `?`, como hasta ahora | Descartada: la temporada no es un filtro de la ficha sino parte de lo que se mira |
| **(b) En el camino lo que es de una temporada; detrás de `?` lo que se elige dentro de la pantalla** | **Elegida** |
| (c) En el camino también en la portada (`/temporadas/2025-26/equipos`) | Descartada: `/` a secas tiene que llevar a algún sitio, y la portada ya funciona así desde la R1 |

**Decisión: (b)** (LLD-B §6.5). La ficha del equipo y sus pestañas son el equipo **en una temporada**, que en el
servidor es su inscripción (`/teams/{teamId}/registrations/{seasonId}`, `D-102`): resultados, plantilla y
estadísticas lo son. Una competición es de una sola temporada. Lo que va detrás de `?` es lo que se elige mirando
esa pantalla: la jornada, el orden. **Queda más estructurado**, y el camino dice de un vistazo de qué temporada es
lo que se ve.

**Lo que se asume a cambio.**

- **La portada es distinta de las demás**: `/?temporada=`. Se acepta porque es la entrada.
- **Cambiar de temporada en la ficha cambia el camino**, no un parámetro; para quien navega es lo mismo.
- **`/equipos/:id` sin temporada** abre la ficha en la temporada en curso, para que un enlace al equipo funcione sin
  saberla.
- **La sección de gestión `/temporadas`** (rebanada 11) y estos caminos comparten el principio; no chocan, porque
  `/temporadas` a secas es la lista y lo de debajo, lo de cada una.
---

[D-01]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-26]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[DW-01]: ./Backoffice%20LLD-Anexo-Decisiones-Disenho-001.md
[DW-14]: ./Backoffice%20LLD-Anexo-Decisiones-Disenho-001.md
[DW-10]: ./Backoffice%20LLD-Anexo-Decisiones-Disenho-001.md
[DW-17]: ./Backoffice%20LLD-Anexo-Decisiones-Disenho-001.md

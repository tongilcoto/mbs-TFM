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
| **Cómo se comporta** | | |
| **DW-06** | El campo de un error se lee del texto de `detail`, sin esperar a un campo `field` | §4.3, §4.5 |
| **DW-07** | Las reglas de los formularios se leen del catálogo con Ajv | §5.1 |
| **DW-08** | Dos personas editando lo mismo: se queda lo último que se guardó | §5.6 |
| **DW-09** | En el camino va el identificador del servidor, no un nombre legible | §6.3 |
| **Las reglas del negocio en la pantalla** | | |
| **DW-10** | Lo que no se permite nunca se oculta; lo que se permite a veces se desactiva con el motivo a la vista | §7.4, §10 |
| **Lo transversal** | | |
| **DW-11** | Un club por dirección, sin selector de club | §8.2, §12 |
| **DW-12** | Modo claro y oscuro, aunque los bocetos son solo oscuros | §9.3, §9.4 |
| **Las pruebas** | | |
| **DW-13** | Los clubs de los escenarios llevan el prefijo `bo_` | §11.2 |
| **DW-14** | La federación falsa va detrás del servidor, y eso no es un simulacro | §11.3 |

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
  el equipo está enganchado a la federación. Para dejar de gestionarlo, libéralo». Así el usuario sabe que la
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

[D-01]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[D-26]: ./API_y_BBDD%20LLD-Anexo-Decisiones-Disenho-001.md
[DW-01]: ./Backoffice%20LLD-Anexo-Decisiones-Disenho-001.md

# ADR-Backoffice-001 · Cómo se construye la web del backoffice

- **Estado:** En curso. Decididas 5 de 6 (ver §2).
- **Fecha de apertura:** 2026-10-12
- **Decisores:** desarrollador único (+ Claude Code)
- **Relacionado:** [Project HLD-001](./Project%20HLD-001.md) §2.3 ·
  [ADR-API_y_BBDD-001](./ADR-API_y_BBDD-001.md) · [Borrador inicial del backoffice](./backoffice_initial_draft.md) ·
  [LLD de API y BD](./API_y_BBDD%20LLD-001.md)

> **Cómo leer este ADR.** Cada decisión sigue el mismo formato: **qué se decide → opciones con sus pros y
> contras → decisión → razones**. La §2 las resume todas de un vistazo. Se escribe en lenguaje llano: cada
> término técnico se explica la primera vez que aparece.

---

## 1. Contexto y requisitos

El **backoffice** es la web desde la que el personal del club gestiona sus datos: equipos, jugadores,
partidos, goles, tarjetas, convocatorias… Lo que la federación no da, y lo que el club quiere corregir de
lo que sí da.

De las tres piezas del sistema, dos ya existen: **la base de datos**, con datos reales de la federación que
se actualizan solos, y **el servidor** (la API), el programa que recibe las peticiones, comprueba que tienen
sentido y lee o escribe en la base. **Falta la web**: lo que la persona ve en el navegador. Este ADR decide
**con qué y cómo** se construye. Qué pantallas tendrá y en qué orden se hacen va después, en el LLD y en su
plan.

**Lo que viene decidido de antes y condiciona todo lo demás:**

1. **El servidor ya existe y es quien manda.** Valida, aplica las reglas del negocio y es la única puerta a
   la base de datos ([ADR-API_y_BBDD-001](./ADR-API_y_BBDD-001.md), requisito 6). La web pide y enseña;
   no decide.
2. **Hay un catálogo escrito de todo lo que el servidor sabe hacer** (`backend/Sources/APIContract/openapi.yaml`),
   y es la fuente de verdad (`D-65`). Hoy funcionan 6 de sus 83 operaciones; cada pantalla nueva activa las
   que necesite.
3. **Cada club entra por su propia dirección** (`celtic-castilla.miapp.com`), y el servidor sabe de qué club
   es cada petición por esa dirección (LLD §6.1).
4. **El inicio de sesión será con Supabase Auth** (ADR-API_y_BBDD-001, decisión 3), y se monta **al final**
   (borrador, §3). Mientras tanto, web y servidor en local.
5. **Presupuesto: unos 20 $/mes** para todo lo que esté en la nube.
6. **Un solo desarrollador.** Se prefieren herramientas sencillas de mantener y muy usadas, con
   documentación abundante.
7. **Datos de menores (RGPD).** La web no debe guardar en el navegador más de lo necesario.

**Cómo será el uso, que es lo que más pesa en las decisiones:**

- **Herramienta interna, con usuario y contraseña.** No tiene que aparecer en Google.
- **Mucho formulario y mucha tabla que se edita**: el acta de un partido con goles, tarjetas y minutos, la
  plantilla, la convocatoria…
- **Pocos usuarios a la vez**: el personal de un club.
- **Se usa sobre todo desde el ordenador**; las apps del móvil son las de consulta.

---

## 2. Resumen de decisiones

| # | Qué se decide | Estado | Decisión |
|---|---|---|---|
| 1 | Qué tipo de web | ✅ Decidido (2026-10-12) | **Se descarga entera al navegador y después solo pide datos** al servidor que ya existe |
| 2 | Con qué herramienta se construye | ✅ Decidido (2026-10-12) | **Vue, escrito en TypeScript** |
| 3 | Cómo sabe la web qué datos manda y recibe | ✅ Decidido (2026-10-12) | **Se generan del catálogo `openapi.yaml` solo las descripciones de los datos**; las peticiones, con una pieza pequeña que las usa |
| 4 | El aspecto visual | ✅ Decidido (2026-10-12) | **PrimeVue**, con un tema oscuro inspirado en los bocetos del móvil |
| 5 | Dónde se publica y cuánto cuesta | ✅ Decidido (2026-10-12) | **Dos máquinas en Fly.io**: «web» (Caddy + ficheros, única puerta pública) y «api» (`Run serve`, solo red privada). ~3 $/mes |
| 6 | Cómo se prueba | ⏳ En discusión | — |

---

## 3. Decisión 1 — Qué tipo de web

**Qué se decide:** quién construye las pantallas, el navegador o un servidor.

| Opción | Cómo funciona | A favor | En contra |
|---|---|---|---|
| **A. Se descarga al navegador y pide datos** | La primera vez, el navegador se baja la aplicación entera. Después, al moverse por ella, solo pide datos al servidor y los coloca en pantalla, sin recargar la página. *Como Gmail, Trello o Google Calendar.* | Muy fluida con formularios y tablas. Publicarla es dejar unos ficheros en internet: gratis o casi. Habla con el servidor igual que las apps del móvil | Primera carga algo más lenta. Google no la indexa bien (aquí da igual) |
| **B. Un segundo servidor fabrica las páginas** | Otro programa, además del servidor de datos, construye cada página y la manda ya hecha. *Como la web de un periódico o de una tienda.* | La primera página aparece antes y Google la posiciona mejor | Un segundo programa que alojar, pagar y mantener, y un segundo sitio donde podrían acabar reglas del negocio |
| **C. El servidor actual fabrica también las páginas** | El programa en Swift que sirve los datos genera además las pantallas. *Como una intranet clásica.* | Un solo programa | Swift tiene muy pocas herramientas para webs: formularios y tablas editables costarían mucho más. Mezcla servir datos y dibujar pantallas |

**Decisión: A.**

**Razones:**

- **Es una herramienta interna con inicio de sesión**: lo que B aporta (Google, primera carga) no se
  necesita.
- **Va a tener mucho formulario y tabla editable**, que es donde A funciona mejor.
- **El servidor ya existe y es quien manda** (requisito 1): la web es un cliente más, igual que las apps del
  móvil. Con B habría dos servidores y la tentación de repartir reglas entre ellos.
- **Cabe sobrado en el presupuesto**: publicar unos ficheros cuesta 0 € o casi.

**Consecuencia que hay que resolver, y cómo:** con A, la web está en el navegador y pide datos al servidor.
Si los dos estuvieran en direcciones distintas, el navegador exigiría un permiso previo en cada petición
(CORS) y una lista de clubes permitidos que mantener. **Se evita poniendo web y servidor bajo la misma
dirección de cada club** y repartiendo por el principio del camino (`/v1/…` al servidor, lo demás a la web),
con un «recepcionista» en la puerta. Explicado en
[CORS explicado sencillo](./lessonsToLearn/CORS%20explicado%20sencillo%20-%20la%20web%20y%20la%20API%20en%20la%20misma%20direcci%C3%B3n.md)
y, con el detalle técnico, en
[Dominios, subdominios, API y CORS](./lessonsToLearn/Dominios%2C%20subdominios%2C%20API%20y%20CORS.md). Dónde
vive ese recepcionista se decide en la decisión 5.

---

## 4. Decisión 2 — Con qué herramienta se construye

**Qué se decide:** sobre qué juego de piezas se escribe la web. Nadie la escribe desde cero: se usa una
herramienta que resuelve lo repetitivo (pintar listas, reaccionar a un clic, refrescar la pantalla cuando
llegan datos). Las cuatro candidatas son gratuitas y muy usadas.

**El idioma no se discute:** los navegadores hablan JavaScript, y se escribe en **TypeScript**, que es
JavaScript con «etiquetas» que avisan de los errores antes de ejecutar, como hace Swift en el servidor.

| Opción | Cómo es | A favor | En contra |
|---|---|---|---|
| **React** (Meta) | La más usada del mundo | La mayor colección de piezas ya hechas; mil respuestas para cada duda | HTML y lógica mezclados en el mismo código: cuesta más leerlo sin conocerlo. Trae poco de serie y hay que elegir complementos |
| **Vue** | La «todo incluido» amable | Se lee casi como HTML normal, con la lógica aparte. Fácil de aprender y muy estable. Colecciones de piezas completas «en una caja» (tablas editables, formularios, calendarios con el mismo estilo) | Menos piezas ya hechas que React, aunque de sobra para este proyecto |
| **Svelte** | La que menos código pide | Elegante y muy rápida | Comunidad pequeña; cambió su forma de trabajar en 2024 y hay menos ejemplos al día |
| **Angular** (Google) | La de empresa grande | Lo trae todo, con normas para todo | Pesada y con muchos conceptos: demasiado para un desarrollador solo |

**Decisión: Vue, escrito en TypeScript.**

**Razones:**

- **Quien mantiene el proyecto es ingeniero de pruebas, no desarrollador, y no conoce ninguna de las
  cuatro.** Lo que más reduce el riesgo es que **pueda leer un trozo de la web y entender qué hace**, para
  revisarlo y probarlo, igual que ha hecho con el servidor. En Vue, la parte visible de una pantalla es casi
  HTML y la lógica va separada; en React van entretejidas.
- **Lo que se pierde frente a React es poco**: hay piezas de sobra para tablas y formularios, y las
  colecciones «en una caja» encajan bien con una herramienta de gestión (decisión 4).
- **No condiciona las pruebas**: las que se hacen con un navegador de verdad funcionan igual con cualquiera
  de las cuatro (decisión 6).
- **Se descartan Svelte y Angular**: la primera por comunidad y por su cambio reciente, la segunda por peso.

## 5. Decisión 3 — Cómo sabe la web qué datos manda y recibe

**Qué se decide:** cómo conoce la web la forma de cada dato (un club tiene `id`, `name`, `shortName` y
`slug`) y de cada petición (a qué dirección va y qué lleva). Si la web cree que un campo se llama `nombre` y
el servidor manda `name`, la pantalla sale vacía, y eso se descubre **usándola**, delante del usuario.

En el servidor esto ya está resuelto: el catálogo `openapi.yaml` es la fuente de verdad (`D-65`) y de él se
generan las descripciones en Swift. Si el catálogo cambia y el código no, no compila.

| Opción | Cómo funciona | A favor | En contra |
|---|---|---|---|
| **A. A mano** | Se escribe en TypeScript cómo es cada dato y cada petición, copiándolo del catálogo | Nada que instalar | Dos copias de lo mismo que se separan con el tiempo; un cambio del servidor se descubre usando la web |
| **B. Generar solo las descripciones** | Una herramienta lee el catálogo y escribe las descripciones de todos los datos; una pieza pequeña hace las peticiones usándolas (p. ej. `openapi-typescript` + `openapi-fetch`) | Una sola fuente de verdad, como en el servidor. Los errores salen **antes de ejecutar**, en el editor. Lo generado es corto y legible | Hay que regenerar cuando cambia el catálogo (se hace solo, al arrancar o al fabricar la web) |
| **C. Generar un cliente completo** | Una herramienta escribe además una función por operación, con su lógica de llamada | Todavía menos código a mano | Mucho código generado, difícil de leer y de revisar; más «magia» entre la web y el servidor |

**Decisión: B.**

**Razones:**

- **Repite lo que ya funciona en el servidor**: un catálogo y dos lados generados de él, que no pueden
  separarse sin que salte un error antes de ejecutar.
- **Es lo que mejor se revisa**: lo generado se lee bien y lo que se escribe a mano es poco. La C esconde
  demasiado para quien tiene que verificar lo que pasa.

**Cuándo ocurre:** la generación es parte de **fabricar** la web (en el Mac del desarrollador o en el CI),
no de ejecutarla. Lo generado acaba dentro de los ficheros `.js` que corren en el navegador, y ningún
proceso lee el catálogo mientras la web funciona. Es lo mismo que pasa con `Run`: las descripciones en Swift
se generan al compilar, y `Run serve` ya no mira el catálogo.

```
                         openapi.yaml
                        /            \
          al compilar el servidor   al fabricar la web
                   ↓                          ↓
              Run (Swift)             dist/*.js (TypeScript)
```

**Dos consecuencias que hay que tener presentes:**

1. **Lo generado describe, pero no comprueba.** Es la misma lección que en el servidor (`D-65`): si llega
   un dato mal formado, la web no lo detecta sola. Quien valida es el servidor.
2. **La web conoce las 83 operaciones del catálogo desde el primer día, aunque solo funcionen las que el
   servidor tiene activadas** (hoy, 6). Cada pantalla usa solo las que su rebanada activó; si usara otra, el
   servidor respondería «no encontrado». Eso lo controla el plan de rebanadas, no esta decisión.

## 6. Decisión 4 — El aspecto visual

**Qué se decide:** de dónde salen los botones, tablas, formularios, calendarios y menús, y cómo se les da un
estilo común.

**Punto de partida:** los bocetos del móvil (`docs/design-assets/mobile/`, hechos con Stitch) tienen un
estilo reconocible: **fondo oscuro, tarjetas, verde para victorias y rojo para derrotas**. Conviene que el
backoffice se le parezca, sin que sea obligatorio.

| Opción | Cómo es | A favor | En contra |
|---|---|---|---|
| **A. Colección completa «en una caja»** (PrimeVue, Vuetify) | Más de 80 piezas ya hechas con el mismo estilo: tablas que se editan en el sitio, formularios, calendarios, ventanas, menús | Lo más pesado —tablas editables y formularios largos— **viene hecho y probado**. El aspecto se ajusta con un «tema» | Se parecerá a otras webs hechas con la misma colección si no se le da tema propio |
| **B. Piezas sin estilo + estilo propio** (Tailwind con piezas «en blanco») | Las piezas traen el funcionamiento; el aspecto se escribe aparte | Control total; puede quedar idéntica a los bocetos | Hay que **diseñar cada pieza**: muchas decisiones visuales para quien no es diseñador |
| **C. Todo a mano** | CSS propio para todo | — | Muchísimo trabajo sin nada que ganar aquí |

**Dentro de la A**, las dos candidatas:

- **PrimeVue**: la tabla más completa (edición por celda o por fila, filtros, orden, columnas fijas), buenos
  formularios y calendarios, y un sistema de temas que permite acercarla a los bocetos oscuros.
- **Vuetify**: también completa, pero con el estilo de Google (Material Design) muy marcado, y darle otro
  aire cuesta más.

**Decisión: A, con PrimeVue**, y un tema oscuro inspirado en los bocetos del móvil.

**Razones:**

- **Una sola persona, que no es diseñadora**, construye una herramienta de gestión: lo que más pesa es que
  tablas y formularios vengan resueltos, no el control fino del aspecto.
- **La tabla editable es la pieza central** del backoffice (plantilla, acta del partido, convocatoria), y la
  de PrimeVue es la más completa de las dos.
- **Su sistema de temas** permite parecerse a las apps del móvil sin diseñar pieza a pieza.

**Detalles que quedan para el LLD:** los colores exactos del tema, el idioma de las piezas (fechas en
`dd/mm/aaaa`, calendario empezando en lunes, textos en español) y si se ofrece también un modo claro.

## 7. Decisión 5 — Dónde se publica y cuánto cuesta

**Qué se decide:** dónde viven el recepcionista y los ficheros de la web en producción, y cómo llegan a
ellos las peticiones. El servidor va a Fly.io (ADR-API_y_BBDD-001, decisión 6). Qué hacen el recepcionista y
quien entrega los ficheros, y por qué hacen falta, está explicado en la
[nota de CORS](./lessonsToLearn/CORS%20explicado%20sencillo%20-%20la%20web%20y%20la%20API%20en%20la%20misma%20direcci%C3%B3n.md),
secciones 5 y 6.

**Comprobado en la documentación el 2026-10-12, no de memoria:**

| Pregunta | Respuesta | Fuente |
|---|---|---|
| ¿Fly.io emite el certificado comodín `*.miapp.com`? | Sí, con comprobación por DNS (un registro `_acme-challenge`). **1 $/mes** por comodín | [Fly.io, dominios propios](https://docs.fly.io/networking/custom-domain) y [precios](https://docs.fly.io/about/pricing) |
| ¿Puede Fly.io entregar los ficheros de la web sin programa propio (`[[statics]]`)? | **No sirve aquí**: no devuelve `index.html` en caminos desconocidos y no deja poner cabeceras de caché. Incumple las dos reglas de la sección 6 de la nota | [Fly.io, configuración](https://docs.fly.io/reference/configuration) |
| ¿Caddy pasa intacto el nombre de la dirección (`Host`)? | Sí, por defecto. **Excepción**: desde la v2.11 lo cambia si reenvía a un destino `https`. Dentro de la red privada de Fly.io el reenvío es `http`, así que no aplica | [Caddy, `reverse_proxy`](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy) |
| ¿Cuánto cuesta la máquina más pequeña? | 2,19 $/mes (256 MB, encendida todo el mes); 3,69 $ con 512 MB | [Fly.io, precios](https://docs.fly.io/about/pricing) |

| Opción | Cómo queda | Coste extra | A favor | En contra |
|---|---|---|---|---|
| **A. Todo en una máquina** | Caddy, ficheros y `Run serve` en la misma máquina | 0 $ | La más barata | Cambiar la web obliga a recompilar y subir el servidor Swift. Dos programas en un contenedor |
| **B. Dos máquinas en Fly.io** | «web»: Caddy y los ficheros, única dirección pública, con el certificado. «api»: `Run serve`, **sin dirección pública**, solo por la red privada | +2,19 $/mes | Cada pieza se publica por su lado. El servidor queda escondido tras una única puerta. El nombre llega intacto sin tocar el servidor | Una máquina más que vigilar |
| **C. Web en un servicio externo gratuito** (Cloudflare Pages, Netlify) que reenvía `/v1` a Fly.io | Ficheros repartidos por el mundo | 0 $ | Gratis y rápida | Estos servicios suelen cambiar el nombre al reenviar: habría que leer `X-Forwarded-Host` en el servidor (código de seguridad nuevo). Dos proveedores |
| **D. Sin recepcionista** | `Run serve` entrega también la web | 0 $ | Un solo programa | Como la A, y además las dos reglas de los ficheros habría que programarlas en Swift |

**Decisión: B.**

```
navegador / apps ──https──► entrada de Fly.io (*.miapp.com, certificado)
                                   │
                                   ▼
                      máquina «web»: Caddy
                      ├─ /v1/*  ──http, red privada──► máquina «api»: Run serve ──► Supabase (Postgres)
                      └─ lo demás ─► ficheros de la web (dist/)
```

**Razones:**

- **Separa lo que cambia a distinto ritmo.** La web cambiará mucho y el servidor menos: publicar la web es
  copiar ficheros, sin recompilar Swift (ver la nota *Medir la RAM de un build en Docker*).
- **El servidor deja de estar expuesto.** Todo —también las apps del móvil— entra por el recepcionista.
- **El nombre de la dirección llega intacto sin tocar una línea del servidor**, que hoy solo lee `Host`
  (`TenantResolver.swift`).
- **Coste total del backoffice: unos 3 $/mes** (máquina y certificado), muy por debajo del tope de 20 $.

**Lo que no se puede comprobar hasta publicar:** que la entrada de Fly.io entrega el nombre intacto a Caddy.
La documentación de cabeceras no lo dice ni en un sentido ni en otro. Lo mide la prueba de humo de la nota
de CORS (sección 5, cuatro `curl`), y es **lo primero que se ejecuta al publicar**. Si fallara, las opciones
A o D evitan el problema.

## 8. Decisión 6 — Cómo se prueba

*Pendiente.*

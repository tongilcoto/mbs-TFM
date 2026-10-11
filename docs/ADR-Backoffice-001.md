# ADR-Backoffice-001 · Cómo se construye la web del backoffice

- **Estado:** En curso. Decididas 2 de 6 (ver §2).
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
| 3 | Cómo sabe la web qué datos manda y recibe | ⏳ En discusión | — |
| 4 | El aspecto visual | ⏳ Pendiente | — |
| 5 | Dónde se publica y cuánto cuesta | ⏳ Pendiente | — |
| 6 | Cómo se prueba | ⏳ Pendiente | — |

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

*En discusión.*

## 6. Decisión 4 — El aspecto visual

*Pendiente.*

## 7. Decisión 5 — Dónde se publica y cuánto cuesta

*Pendiente.*

## 8. Decisión 6 — Cómo se prueba

*Pendiente.*

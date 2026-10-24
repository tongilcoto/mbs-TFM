# Backoffice · la web del club

La web con la que el club gestiona sus equipos. Se construye pantalla a pantalla siguiendo su
[plan](../docs/Plan%20de%20desarrollo%20backoffice-001.md); cómo está hecha por dentro, en el
[LLD del backoffice](../docs/Backoffice%20LLD-001.md).

Hecha con Vue y TypeScript, con las piezas de PrimeVue. Los datos se los pide al servidor del backend
(`backend/`), y las descripciones de esos datos se fabrican solas del catálogo
`backend/Sources/APIContract/openapi.yaml`.

**Lo que enseña hoy** (rebanada 1, cerrada el 2026-10-20): la **portada**, con los equipos del club en una
temporada, la competición en la que juega cada uno, cómo va su ingesta y cuándo se sincronizó por última vez, en
tu hora. La temporada se elige arriba a la derecha y queda en la dirección (`/?temporada=2025-26`). Alrededor, la
cabecera con el club, el menú (de momento solo «Equipos») y el botón de modo claro u oscuro.

**En construcción** (rebanada 2): el **alta de equipo**, en `/equipos/nuevo`. Ya se rellena, comprueba todos los
campos a la vez antes de enviar y avisa si se sale con cambios sin guardar. Al lado del selector de
temporada, **«Crear nueva temporada»** la crea en ese momento, solo con su etiqueta (`2027/28`). Todavía se llega
escribiendo la dirección: el botón de la portada llega en el paso siguiente. **Ojo: guardar da de alta el equipo
de verdad en tu club, y «Crear» crea la temporada de verdad**; borrar un equipo no se podrá hasta la rebanada 13,
ni una temporada hasta la 11.

## Antes de empezar

- **Node 22.** La versión está fijada en `.nvmrc`; con nvm, basta con `nvm use` dentro de esta carpeta.
- **Las herramientas instaladas**, una vez y cada vez que cambie `package.json`:

  ```sh
  cd backoffice
  npm install
  ```

Todas las órdenes de abajo se escriben **dentro de `backoffice/`**.

## Las órdenes del día a día

| Para qué | Orden | Qué hace |
|---|---|---|
| **Arrancar** la web | `npm run dev` | La sirve en **`http://celtic-castilla.localhost:5173`**. Se recarga sola al guardar un cambio. `Ctrl+C` la para |
| **Probar** las piezas | `npm test` | Pasa todas las pruebas de Vitest una vez y dice cuántas pasan y cuáles fallan |
| Probar mientras se escribe | `npm run test:watch` | Igual, pero se queda atento y repite las pruebas al guardar. `q` lo para |
| **Probar los escenarios** de punta a punta | `npm run e2e` | Compila el servidor, arranca su propia copia de todo y pasa los escenarios en Chromium. Ver [abajo](#los-escenarios-de-punta-a-punta) |
| **Comprobar los tipos** | `npm run typecheck` | Comprueba que cada petición y cada dato encajan con el catálogo. No ejecuta nada |
| **Revisar** el código | `npm run lint` | El revisor de código: avisa si una pieza de `components/` usa `api/` y de los fallos de accesibilidad que se ven sin ejecutar (imagen sin texto alternativo, campo sin etiqueta…) |
| **Fabricar** la web para publicarla | `npm run build` | Comprueba los tipos y deja la web lista en `dist/` |

**Los tipos y las reglas del catálogo se fabrican solos** antes de `dev`, `test`, `typecheck` y `build`, con
`npm run gen:api`, en dos ficheros:

| Fichero | Qué tiene | Para qué |
|---|---|---|
| `src/api/schema.d.ts` | La forma de cada dato | Que cada petición encaje con el catálogo al compilar |
| `src/api/schemas.json` | Las reglas de cada dato (obligatorio, formato, lista cerrada…) y el nombre en español de cada valor de las listas cerradas («Alevín», «Fútbol 7») | Que los formularios las comprueben antes de enviar, con Ajv; y que la web enseñe los valores con su nombre y en el orden del catálogo |

**Si a una lista del catálogo le falta el nombre de algún valor, o le sobra uno, `gen:api` se para y dice
cuál**: los nombres se escriben en el catálogo, junto a la lista (`x-enum-names`), no en la web.

Ninguno de los dos se toca a mano ni se guarda en git: si el catálogo cambia, la próxima orden los vuelve a
fabricar, y los dos salen siempre del mismo catálogo a la vez. Para fabricarlos, `npm run gen:api` lee
`../backend/`: la web se compila con el repositorio entero a la vista, no solo con esta carpeta.

Lo que se ha añadido para eso: **`ajv`** (el comprobador de reglas) y **`ajv-formats`** (los formatos, como el
de los identificadores), que viajan con la web; y **`yaml`**, que solo usa `gen:api` para leer el catálogo.

Dos cosas a tener en cuenta el día que se publique (están en los pendientes de la rebanada 16 del
[plan](../docs/Plan%20de%20desarrollo%20backoffice-001.md)): Ajv fabrica sus comprobadores en el navegador, así que una
política de seguridad estricta en la página tendría que permitirlo; y `schemas.json` lleva también las
descripciones del catálogo, unos 157 KB, que se pueden quitar si el tamaño importa.

## Los escenarios de punta a punta

`npm run e2e` pasa los escenarios de `e2e/features/` en un navegador de verdad (Chromium), contra un servidor y
una base de verdad. **Arranca su propia copia de todo** y la para al terminar; lo tuyo no se toca:

| Pieza | Dónde | La tuya, que no se toca |
|---|---|---|
| El servidor de pruebas | puerto **8081**, base `tfm_test` | el 8080 y la base `tfm` |
| La web de pruebas | puerto **5174** | el 5173 |
| La federación falsa, con respuestas grabadas y competiciones inventadas | puerto **8090**, en el lugar de rffm.es | — |

- **Antes, una vez:** `npx playwright install chromium`, que descarga el navegador de los escenarios. Docker
  tiene que estar en marcha, porque la base de pruebas vive en el mismo Postgres.
- **Si una pieza no arranca, la pasada falla enseguida diciendo cuál**, por ejemplo si el 8081 está ocupado.
  Lo que escribe cada pieza queda en `e2e-results/` (`servidor.log`, `web.log`).
- **Al final de cada escenario, axe revisa la accesibilidad** de la pantalla en modo claro y en oscuro (WCAG 2.2
  AA). Un fallo hace fallar el escenario y dice en qué modo, qué regla y dónde.
- **Cada escenario tiene su propio club**, `bo-…`, que se borra al acabar. Para conservarlos y mirarlos en
  TablePlus (base `tfm_test`): `KEEP_TEST_DATA=1 npm run e2e`. La pasada siguiente los barre.
- **Los datos de cada escenario se eligen al azar** (equipos, competiciones, temporadas, nombre del club), así que
  cada pasada prueba con otros. Al empezar, la pasada escribe su semilla; **para repetir los mismos datos**:
  `SEMILLA=255079 npm run e2e`. Si un escenario falla, el informe dice qué datos le tocaron. La semilla y esos
  datos quedan también en `e2e-results/datos.log`, que se rehace en cada pasada.
- **Compila el servidor antes de empezar** (`swift build`): los escenarios usan el programa ya compilado, y uno
  viejo probaría código que ya no es el tuyo.

## Para ver datos, el servidor tiene que estar en marcha

La web pide los datos en `/api/v1/…`, y Vite se los pasa al servidor quitándoles el `/api` (LLD-B §1.3). Sin
el servidor, la web arranca igual, pero no tiene datos que enseñar. Para arrancarlo, en otra terminal:

```sh
cd backend
swift run Run serve
```

**El puerto del servidor se elige en un fichero, `backend/.env.development`**, y lo leen los dos: el servidor al
arrancar y la web para saber adónde mandar las peticiones. Así no hay que acordarse de ponerlo en dos sitios.
Es de cada Mac (git no lo guarda) y basta con una línea:

```sh
echo "API_PORT=8765" > backend/.env.development
```

Sin el fichero, los dos usan el **8080**. Si cambias el puerto con la web ya arrancada, Vite se reinicia solo al
cambiar su configuración, pero no al cambiar ese fichero: para la web con `Ctrl+C` y vuelve a lanzar
`npm run dev`. Los escenarios no lo leen: usan siempre su propio servidor del 8081.

**Para que la portada tenga equipos**, el club tiene que tenerlos enganchados con su federación. Mientras la web
no sepa dar de alta equipos (rebanada 2), se hace desde el servidor: [README del backend, §4.1](../backend/README.md#enganche).

Una forma rápida de ver que los dos se hablan:

```sh
curl -s http://celtic-castilla.localhost:5173/api/v1/club    # el club, pasando por Vite
```

Si en vez del club sale la página HTML, la web que está en marcha no tiene el recepcionista activo: párala y
vuelve a arrancarla.

## La dirección lleva el nombre del club

El club se saca de la dirección: `celtic-castilla.localhost` es el club `celtic-castilla`. Chrome y Safari
abren las direcciones `*.localhost` sin tocar nada.

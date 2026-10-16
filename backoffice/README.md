# Backoffice · la web del club

La web con la que el club gestiona sus equipos. Se construye pantalla a pantalla siguiendo su
[plan](./Plan%20backoffice-001.md); cómo está hecha por dentro, en el
[LLD del backoffice](../docs/Backoffice%20LLD-001.md).

Hecha con Vue y TypeScript, con las piezas de PrimeVue. Los datos se los pide al servidor del backend
(`backend/`), y las descripciones de esos datos se fabrican solas del catálogo
`backend/Sources/APIContract/openapi.yaml`.

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
| **Comprobar los tipos** | `npm run typecheck` | Comprueba que cada petición y cada dato encajan con el catálogo. No ejecuta nada |
| **Revisar** el código | `npm run lint` | El revisor de código: avisa si una pieza de `components/` usa `api/` y de los fallos de accesibilidad que se ven sin ejecutar (imagen sin texto alternativo, campo sin etiqueta…) |
| **Fabricar** la web para publicarla | `npm run build` | Comprueba los tipos y deja la web lista en `dist/` |

**Los tipos del catálogo se fabrican solos** antes de `dev`, `typecheck` y `build`, en
`src/api/schema.d.ts`. Ese fichero no se toca a mano ni se guarda en git: si el catálogo cambia, la próxima
orden lo vuelve a fabricar.

## Para ver datos, el servidor tiene que estar en marcha

La web pide los datos en `/api/v1/…`, y Vite se los pasa al servidor del puerto **8080** quitándoles el
`/api` (LLD-B §1.3). Sin el servidor, la web arranca igual, pero no tiene datos que enseñar. Para arrancarlo,
en otra terminal:

```sh
cd backend
swift run Run serve
```

Una forma rápida de ver que los dos se hablan:

```sh
curl -s http://celtic-castilla.localhost:5173/api/v1/club    # el club, pasando por Vite
```

## La dirección lleva el nombre del club

El club se saca de la dirección: `celtic-castilla.localhost` es el club `celtic-castilla`. Chrome y Safari
abren las direcciones `*.localhost` sin tocar nada.

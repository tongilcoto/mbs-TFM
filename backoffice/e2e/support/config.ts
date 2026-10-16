// Los datos fijos del arnés de los escenarios (LLD-B §11): puertos, base y dónde está cada cosa.
// Todo es «de las pruebas»: el servidor del 8080 y la base `tfm` del desarrollador no se tocan.
import { fileURLToPath } from 'node:url'

const here = (relative: string) => fileURLToPath(new URL(relative, import.meta.url))

export const config = {
  /** El servidor de las pruebas: otro puerto y otra base que los de trabajo. */
  apiPort: 8081,
  /** La web de las pruebas, con su recepcionista apuntando al 8081. */
  webPort: 5174,
  /** La federación falsa, en el lugar de rffm.es (DW-14). */
  federationPort: 8090,

  /** La base de las pruebas, la misma que usan las del backend. */
  database: {
    host: process.env.DB_HOST ?? 'localhost',
    port: Number(process.env.DB_PORT ?? 5434),
    user: process.env.DB_USER ?? 'tfm',
    password: process.env.DB_PASSWORD ?? 'tfm',
    name: 'tfm_test',
  },

  /** El servidor ya compilado: `swift build --product Run` lo deja aquí. */
  serverBinary: here('../../../backend/.build/debug/Run'),
  /** Las respuestas grabadas de la federación, las mismas que usa el backend. */
  fixtures: here('../../../backend/Tests/FederationTests/Fixtures'),
  /** Dónde deja cada proceso lo que escribe, para mirarlo si algo falla. */
  logs: here('../../e2e-results'),

  /** Cuánto se espera a que un proceso conteste antes de dar el arranque por fallido. */
  startTimeoutMs: 20_000,
}

// El servidor de las pruebas (LLD-B §11.1): el binario ya compilado, en el 8081 y contra `tfm_test`.
// Se usa el binario y no `swift run` porque `swift run` comprueba la compilación cada vez que arranca.
// Detrás, en el lugar de rffm.es, la federación falsa (R0.8, DW-14).
//
// Un escenario puede pararlo y volver a arrancarlo, para ver los errores de verdad (DW-17, LLD-B §11.5). Solo
// es seguro porque los escenarios van de uno en uno. El del desarrollador no se toca nunca.
import { existsSync } from 'node:fs'
import { config } from './config.ts'
import { requireFreePort, startProcess, waitUntilAnswers, type Started } from './processes.ts'

const name = `El servidor de pruebas (${config.apiPort})`

// El que está en marcha ahora; `undefined` si está parado.
let current: Started | undefined
// La primera vez empieza su fichero de mensajes de cero; al volver a arrancarlo, sigue escribiendo detrás.
let startedBefore = false

export async function startApiServer(): Promise<Started> {
  if (current) return current
  if (!existsSync(config.serverBinary)) {
    throw new Error(
      `${name}: no está compilado. Desde backoffice/: swift build --package-path ../backend --product Run`,
    )
  }
  await requireFreePort(name, config.apiPort)

  const server = startProcess(name, config.serverBinary, ['serve'], {
    logName: 'servidor',
    append: startedBefore,
    env: {
      DB_NAME: config.database.name,
      API_PORT: String(config.apiPort),
      RFFM_BASE_URL: `http://127.0.0.1:${config.federationPort}`,
    },
  })
  startedBefore = true
  // Cualquier respuesta vale, también «este club no existe»: lo que se mira es que escucha.
  await waitUntilAnswers(server, config.apiPort, { path: '/v1/club', host: `bo-humo.localhost:${config.apiPort}` })
  current = server
  return server
}

/** Para el servidor de pruebas, y no vuelve hasta que ha soltado su puerto. */
export async function stopApiServer(): Promise<void> {
  await current?.stop()
  current = undefined
}

export function apiServerIsRunning(): boolean {
  return current !== undefined
}

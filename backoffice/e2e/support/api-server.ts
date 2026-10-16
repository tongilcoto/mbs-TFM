// El servidor de las pruebas (LLD-B §11.1): el binario ya compilado, en el 8081 y contra `tfm_test`.
// Se usa el binario y no `swift run` porque `swift run` comprueba la compilación cada vez que arranca.
// Detrás, en el lugar de rffm.es, la federación falsa (R0.8, DW-14).
import { existsSync } from 'node:fs'
import { config } from './config.ts'
import { requireFreePort, startProcess, waitUntilAnswers, type Started } from './processes.ts'

export async function startApiServer(): Promise<Started> {
  const name = `El servidor de pruebas (${config.apiPort})`
  if (!existsSync(config.serverBinary)) {
    throw new Error(
      `${name}: no está compilado. Desde backoffice/: swift build --package-path ../backend --product Run`,
    )
  }
  await requireFreePort(name, config.apiPort)

  const server = startProcess(name, config.serverBinary, ['serve'], {
    logName: 'servidor',
    env: {
      DB_NAME: config.database.name,
      API_PORT: String(config.apiPort),
      RFFM_BASE_URL: `http://localhost:${config.federationPort}`,
    },
  })
  // Cualquier respuesta vale, también «este club no existe»: lo que se mira es que escucha.
  await waitUntilAnswers(server, config.apiPort, { path: '/v1/club', host: `bo-humo.localhost:${config.apiPort}` })
  return server
}

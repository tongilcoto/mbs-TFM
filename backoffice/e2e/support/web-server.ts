// La web de las pruebas (LLD-B §11.1): Vite en el 5174, con su recepcionista apuntando al servidor de
// pruebas del 8081 en vez de al 8080 del desarrollador.
import { fileURLToPath } from 'node:url'
import { config } from './config.ts'
import { requireFreePort, startProcess, waitUntilAnswers, type Started } from './processes.ts'

export async function startWebServer(): Promise<Started> {
  const name = `La web de pruebas (${config.webPort})`
  await requireFreePort(name, config.webPort)

  const vite = fileURLToPath(new URL('../../node_modules/.bin/vite', import.meta.url))
  const web = startProcess(name, vite, ['--host', '127.0.0.1', '--port', String(config.webPort), '--strictPort'], {
    logName: 'web',
    cwd: fileURLToPath(new URL('../..', import.meta.url)),
    env: { BACKOFFICE_API_URL: `http://127.0.0.1:${config.apiPort}` },
  })
  await waitUntilAnswers(web, config.webPort, { host: `bo-humo.localhost:${config.webPort}` })
  return web
}

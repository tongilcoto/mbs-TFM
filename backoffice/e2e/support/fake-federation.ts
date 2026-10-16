// La federación falsa (DW-14): un servidor pequeño que se pone en el lugar de rffm.es y devuelve las
// respuestas grabadas que ya usa el backend (backend/Tests/FederationTests/Fixtures/README.md).
// El servidor de pruebas le pide aquí porque arranca con RFFM_BASE_URL apuntando a ella (R0.8).
//
// Contesta como la RFFM de verdad, también cuando algo no existe: siempre con 200, y con `null` (la
// clasificación y los goleadores) o con un calendario vacío (el calendario). Así la ingesta ve lo mismo
// que vería en producción.
//
// Si un escenario necesita una respuesta que no está grabada, se graba una nueva en
// e2e/federation-recordings/: un `.txt` con la dirección pedida en una línea y la respuesta debajo, como
// los que ya hay. Ojo con el `null` pasajero de la RFFM (H-61): si llega, se vuelve a pedir.
import { readdirSync, readFileSync } from 'node:fs'
import http from 'node:http'
import path from 'node:path'
import { config } from './config.ts'

/** Los calendarios grabados. Son páginas enteras y no llevan dentro la dirección, así que van aquí. */
const calendars: Record<string, string> = {
  // temporada | tipojuego | competicion | grupo
  '21|1|24037548|24037549': 'RFFM-calendario-temporada-jugada.html', // Cadete G1 2025-26, 240 partidos jugados
  '22|1|24037548|24037549': 'RFFM-calendario-temporada-sin-jugar.html', // Preferente G1 2026-27, sin jugar
}
const calendarNotFound = 'RFFM-calendario-coordenada-inexistente.html'

/** Una dirección escrita siempre igual: la ruta y los parámetros en orden alfabético. */
function key(address: string): string {
  const url = new URL(address, 'http://federacion')
  url.searchParams.sort()
  return `${url.pathname}?${url.searchParams}`
}

/**
 * Las respuestas de los `.txt`, por su dirección. Cada fichero puede traer varias: cada una empieza por
 * la línea con su dirección, y acaba en la siguiente dirección o en la línea «HTTP 200».
 */
function readRecordedAnswers(folder: string): Map<string, string> {
  const answers = new Map<string, string>()
  for (const file of readdirSync(folder).filter((name) => name.endsWith('.txt'))) {
    let address: string | undefined
    let body: string[] = []
    const save = () => {
      if (address) answers.set(key(address), body.join('\n').trim())
    }
    for (const line of readFileSync(path.join(folder, file), 'utf8').split('\n')) {
      if (/^https?:\/\//.test(line.trim())) {
        save()
        address = line.trim()
        body = []
      } else if (/^HTTP \d+/.test(line.trim())) {
        save()
        address = undefined
      } else if (address) {
        body.push(line)
      }
    }
    save()
  }
  return answers
}

export interface FakeFederation {
  /** Las direcciones que le han pedido, en orden. */
  requests: string[]
  stop(): Promise<void>
}

export async function startFakeFederation(port = config.federationPort): Promise<FakeFederation> {
  const answers = new Map([...readRecordedAnswers(config.fixtures), ...readRecordedAnswers(config.recordings)])
  const requests: string[] = []

  const server = http.createServer((request, response) => {
    const address = request.url ?? '/'
    requests.push(address)
    const url = new URL(address, 'http://federacion')
    const send = (body: string, type = 'application/json; charset=utf-8') => {
      response.writeHead(200, { 'content-type': type })
      response.end(body)
    }

    if (url.pathname === '/competicion/calendario') {
      const q = url.searchParams
      const coordinate = [q.get('temporada'), q.get('tipojuego'), q.get('competicion'), q.get('grupo')].join('|')
      const file = calendars[coordinate] ?? calendarNotFound
      return send(readFileSync(path.join(config.fixtures, file), 'utf8'), 'text/html; charset=utf-8')
    }
    if (url.pathname === '/api/standings' || url.pathname === '/api/scorers') {
      return send(answers.get(key(address)) ?? 'null')
    }
    response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' })
    response.end(`La federación falsa no conoce ${url.pathname}`)
  })

  await new Promise<void>((resolve, reject) => {
    server.once('error', (error: NodeJS.ErrnoException) =>
      reject(
        error.code === 'EADDRINUSE'
          ? new Error(`La federación falsa (${port}): el puerto ${port} está ocupado. Para ver quién lo usa: lsof -i :${port}`)
          : error,
      ),
    )
    server.listen(port, '127.0.0.1', resolve)
  })

  return {
    requests,
    stop: () => new Promise((resolve) => server.close(() => resolve())),
  }
}

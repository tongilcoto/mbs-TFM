// La API del servidor de pruebas, para preparar los datos de los escenarios por los caminos de la aplicación (la
// skill de escenarios, principio 9). El club va en el nombre del servidor, como desde la web (LLD-B §8): se
// llama a 127.0.0.1 y se dice el club en la cabecera `Host`.
import http from 'node:http'
import type { ScenarioClub } from './clubs.ts'
import { config } from './config.ts'

export interface ApiAnswer<T> {
  status: number
  body: T
}

export function callApi<T = unknown>(
  club: ScenarioClub,
  method: 'GET' | 'POST' | 'PATCH',
  path: string,
  body?: unknown,
): Promise<ApiAnswer<T>> {
  const payload = body === undefined ? undefined : JSON.stringify(body)
  return new Promise((resolve, reject) => {
    const request = http.request(
      {
        host: '127.0.0.1',
        port: config.apiPort,
        path: `/v1${path}`,
        method,
        headers: {
          host: `${club.slug}.localhost:${config.apiPort}`,
          ...(payload ? { 'content-type': 'application/json', 'content-length': Buffer.byteLength(payload) } : {}),
        },
        timeout: 30_000,
      },
      (response) => {
        let text = ''
        response.setEncoding('utf8')
        response.on('data', (chunk) => (text += chunk))
        response.on('end', () => {
          let parsed: unknown = text
          try {
            parsed = text ? JSON.parse(text) : undefined
          } catch {
            // No es JSON: se devuelve el texto tal cual, que es lo que sirve para saber qué pasó.
          }
          resolve({ status: response.statusCode ?? 0, body: parsed as T })
        })
      },
    )
    request.once('timeout', () => request.destroy(new Error(`${method} ${path}: el servidor de pruebas no contestó`)))
    request.once('error', reject)
    if (payload) request.write(payload)
    request.end()
  })
}

/** Como `callApi`, pero falla si el servidor no contesta lo esperado, con lo que contestó. */
export async function expectApi<T = unknown>(
  club: ScenarioClub,
  method: 'GET' | 'POST' | 'PATCH',
  path: string,
  body: unknown,
  expected: number,
): Promise<T> {
  const answer = await callApi<T>(club, method, path, body)
  if (answer.status !== expected) {
    throw new Error(
      `${method} ${path}: el servidor contestó ${answer.status} y se esperaba ${expected}: ${JSON.stringify(answer.body)}`,
    )
  }
  return answer.body
}

import { errorFromResponse, noConnection, type ShownError } from './errors'

// Lo que recibe una pantalla de cada petición: los datos, o el error ya traducido (LLD-B §3, §4).
export type Result<T> = { ok: true; data: T } | { ok: false; error: ShownError }

// Lo que devuelve cada petición de `api` (client.ts): los datos si fue bien, el error si no, y la respuesta.
interface Answer<T> {
  data?: T
  error?: unknown
  response: Response
}

// Espera la petición y la convierte en un Result. Un uso: `await asResult(api.GET('/club'))`.
//
// Si quien pidió la cancela al salir de la pantalla (LLD-B §3.2), no hay nada que enseñar: el error sigue su
// camino y la pantalla, que ya no está, no lo recoge.
export async function asResult<T>(call: Promise<Answer<T>>): Promise<Result<T>> {
  let answer: Answer<T>
  try {
    answer = await call
  } catch (error) {
    if (error instanceof DOMException && error.name === 'AbortError') throw error
    // Sin respuesta: pasaron los 30 s, o no se pudo ni conectar.
    return { ok: false, error: noConnection }
  }

  if (answer.response.ok) return { ok: true, data: answer.data as T }
  return { ok: false, error: errorFromResponse(answer.response.status, answer.error) }
}

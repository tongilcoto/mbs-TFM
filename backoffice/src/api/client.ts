import createClient from 'openapi-fetch'
import type { paths } from './schema'

// La web deja de esperar a los 30 s (LLD-B §3.4): por encima de los 20 s que el servidor espera a la federación.
export const REQUEST_TIMEOUT_MS = 30_000

export class ServerNotRespondingError extends Error {
  constructor() {
    super('El servidor no responde')
    this.name = 'ServerNotRespondingError'
  }
}

// Cada petición pasa por aquí. Busca el fetch del navegador en el momento de pedir, no al cargar el fichero.
// La petición se corta a los 30 s; si el corte es del reloj, se convierte en «el servidor no responde».
function send(request: Request): Promise<Response> {
  const clock = new AbortController()
  const timer = setTimeout(() => clock.abort(), REQUEST_TIMEOUT_MS)
  // Se corta por lo que llegue antes: el reloj, o quien pide al salir de la pantalla (LLD-B §3.2).
  const signal = AbortSignal.any([request.signal, clock.signal])

  return globalThis
    .fetch(new Request(request, { signal }))
    .catch((error: unknown) => {
      throw clock.signal.aborted ? new ServerNotRespondingError() : error
    })
    .finally(() => clearTimeout(timer))
}

// Todo va bajo /api/v1 (LLD-B §1.3). La dirección se completa con la de la página: en el navegador es la
// misma (el club sigue en el nombre), y en las pruebas evita que Node rechace una dirección a medias.
export const api = createClient<paths>({ baseUrl: `${location.origin}/api/v1`, fetch: send })

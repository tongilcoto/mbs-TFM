// Retener una petición de la web (DW-17, LLD-B §11.5): Playwright la para antes de que salga, el escenario mira
// la pantalla mientras espera («Cargando…»), y luego la suelta tal cual. Llega al servidor de verdad y la
// respuesta vuelve sin que nadie la toque: solo cambia cuándo sale. No es un simulacro.
import type { Page, Route } from 'playwright'

export interface HeldRequest {
  /** Se cumple cuando la web ya ha hecho la petición y está retenida. */
  arrived: Promise<void>
  /** La deja salir tal cual, y deja de retener las siguientes. */
  release(): Promise<void>
}

/**
 * Retiene la próxima petición de la web a `/api/v1<path>` (por ejemplo, `/seasons`). Solo esa: las demás, y
 * las que lleven algo detrás, como `/seasons/{id}/registrations`, salen sin esperar.
 */
export async function holdRequest(page: Page, path: string): Promise<HeldRequest> {
  const pattern = new RegExp(`/api/v1${path.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(\\?.*)?$`)
  let alreadyHeld = false
  let markArrived!: () => void
  const arrived = new Promise<void>((resolve) => (markArrived = resolve))
  let letGo!: () => void
  const gate = new Promise<void>((resolve) => (letGo = resolve))
  let markSent!: () => void
  const sent = new Promise<void>((resolve) => (markSent = resolve))

  // La petición retenida espera aquí dentro hasta que se le da paso, y entonces sale tal cual.
  const handler = async (route: Route) => {
    if (alreadyHeld) return route.continue()
    alreadyHeld = true
    markArrived()
    await gate
    // Sale ahora: si el servidor está parado, falla de verdad (el recepcionista contesta 502).
    await route.continue()
    markSent()
  }
  await page.route(pattern, handler)

  return {
    arrived,
    async release() {
      letGo()
      // La regla se quita cuando la petición ya ha salido: si se quitara antes, Playwright la daría por atendida.
      await sent
      await page.unroute(pattern, handler)
    },
  }
}

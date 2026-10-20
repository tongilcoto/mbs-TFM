// Esperar a ver algo en la página, con un límite corto: cuando llega el `Then`, la pantalla ya está en su
// estado, así que si no aparece en unos segundos no va a aparecer.
import type { Locator, Page } from 'playwright'

export const SHORT_WAIT_MS = 5_000

/** Espera a que se vea; si no, el error dice qué se buscaba. */
export async function shows(locator: Locator, what: string): Promise<void> {
  try {
    await locator.first().waitFor({ state: 'visible', timeout: SHORT_WAIT_MS })
  } catch {
    throw new Error(`no se ve ${what}`)
  }
}

/** Comprueba que no hay ninguno. Se llama cuando la pantalla ya está en su estado. */
export async function absent(locator: Locator, what: string): Promise<void> {
  const count = await locator.count()
  if (count > 0) throw new Error(`se ve ${what}, y no debería`)
}

/** Espera a que una condición sobre la página se cumpla; si no, dice lo último que vio. */
export async function becomes<T>(page: Page, read: () => Promise<T>, expected: T, what: string): Promise<void> {
  const deadline = Date.now() + SHORT_WAIT_MS
  let seen = await read()
  while (seen !== expected && Date.now() < deadline) {
    await page.waitForTimeout(100)
    seen = await read()
  }
  if (seen !== expected) throw new Error(`${what} es «${String(seen)}», y se esperaba «${String(expected)}»`)
}

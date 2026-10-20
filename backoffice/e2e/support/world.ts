// Lo que tiene cada escenario: su propia pestaña del navegador, limpia, y el club con el que trabaja.
import { setWorldConstructor, World, type IWorldOptions } from '@cucumber/cucumber'
import type { BrowserContext, Page } from 'playwright'
import type { ScenarioClub } from './clubs.ts'
import type { HeldRequest } from './hold-request.ts'
import { config } from './config.ts'

export class ScenarioWorld extends World {
  context!: BrowserContext
  page!: Page
  /** El club de este escenario, recién creado y solo suyo. */
  club!: ScenarioClub
  /** Lo que ha fallado en los `Then`: se apunta y se sigue, y el escenario falla al final con todo. */
  failures: string[] = []
  /** La petición que el escenario tiene retenida, si tiene alguna (DW-17). */
  held?: HeldRequest

  constructor(options: IWorldOptions) {
    super(options)
  }

  /**
   * Una comprobación de un `Then` que no para el escenario si falla (la skill de escenarios, principio 5):
   * todos los `Then` miran el mismo trozo de pantalla en el mismo estado, y parar en el primero escondería
   * los demás. Lo que falle se apunta, y el escenario falla al final con la lista entera.
   */
  async check(what: string, assertion: () => Promise<void>): Promise<void> {
    try {
      await assertion()
    } catch (error) {
      const reason = error instanceof Error ? error.message.split('\n')[0] : String(error)
      this.failures.push(`${what}: ${reason}`)
    }
  }

  /** La dirección de la web de pruebas para el club del escenario: el club va en el nombre (LLD-B §8). */
  clubUrl(path = '/'): string {
    return `http://${this.club.slug}.localhost:${config.webPort}${path}`
  }
}

setWorldConstructor(ScenarioWorld)

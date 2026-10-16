// Lo que tiene cada escenario: su propia pestaña del navegador, limpia, y el club con el que trabaja.
import { setWorldConstructor, World, type IWorldOptions } from '@cucumber/cucumber'
import type { BrowserContext, Page } from 'playwright'
import type { ScenarioClub } from './clubs.ts'
import { config } from './config.ts'

export class ScenarioWorld extends World {
  context!: BrowserContext
  page!: Page
  /** El club de este escenario, recién creado y solo suyo. */
  club!: ScenarioClub

  constructor(options: IWorldOptions) {
    super(options)
  }

  /** La dirección de la web de pruebas para el club del escenario: el club va en el nombre (LLD-B §8). */
  clubUrl(path = '/'): string {
    return `http://${this.club.slug}.localhost:${config.webPort}${path}`
  }
}

setWorldConstructor(ScenarioWorld)

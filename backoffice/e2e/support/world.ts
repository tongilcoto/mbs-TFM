// Lo que tiene cada escenario: su propia pestaña del navegador, limpia, y el club con el que trabaja.
import { setWorldConstructor, World, type IWorldOptions } from '@cucumber/cucumber'
import type { BrowserContext, Page } from 'playwright'
import { config } from './config.ts'

export class ScenarioWorld extends World {
  context!: BrowserContext
  page!: Page

  constructor(options: IWorldOptions) {
    super(options)
  }

  /** La dirección de la web de pruebas para un club: el club va en el nombre (LLD-B §8). */
  clubUrl(slug: string, path = '/'): string {
    return `http://${slug}.localhost:${config.webPort}${path}`
  }
}

setWorldConstructor(ScenarioWorld)

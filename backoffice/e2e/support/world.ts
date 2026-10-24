// Lo que tiene cada escenario: su propia pestaña del navegador, limpia, y el club con el que trabaja.
import { setWorldConstructor, World, type IWorldOptions } from '@cucumber/cucumber'
import type { BrowserContext, Page } from 'playwright'
import type { ScenarioClub } from './clubs.ts'
import type { HeldRequest } from './hold-request.ts'
import { config } from './config.ts'
import type { Competition, Season, Team } from './invented.ts'
import type { Random } from './random.ts'

/** Lo que los `Given` han dado de alta, para que los pasos siguientes se refieran a ello («el equipo»…). */
export interface ScenarioData {
  /** El nombre corto que se le puso al club. */
  shortName?: string
  /** Los equipos del club, para no inventar dos iguales. */
  teams: Team[]
  /** El equipo del escenario. */
  team?: Team
  /** La competición que juega, si juega alguna. */
  competition?: Competition
  /** Las temporadas pasadas del club, por orden de alta. */
  pastSeasons: Season[]
  /** La temporada que todavía no ha empezado. */
  futureSeason?: Season
  /** La temporada que se pide en la dirección y el club no tiene. */
  missingSeason?: Season
  /** Las competiciones de las que se ha lanzado una ingesta: al acabar, se espera a que acaben. */
  ingesting: string[]
  /** El equipo que el escenario ha escrito en el formulario de alta (plan R2). */
  entered?: Team
  /** La temporada archivada del club. */
  archivedSeason?: Season
  /** Los equipos de la tabla por el estado de su ingesta: «Al día» → el equipo (bloque T). */
  byHealth: Record<string, Team>
  /** Los dos equipos que se llamarían igual (bloque T). */
  twins?: Team[]
  /** Los equipos de la tabla en el orden en que los manda el servidor (bloque T). */
  inServerOrder?: Team[]
}

export class ScenarioWorld extends World {
  context!: BrowserContext
  page!: Page
  /** El club de este escenario, recién creado y solo suyo. */
  club!: ScenarioClub
  /** Lo que ha fallado en los `Then`: se apunta y se sigue, y el escenario falla al final con todo. */
  failures: string[] = []
  /** La petición que el escenario tiene retenida, si tiene alguna (DW-17). */
  held?: HeldRequest
  /** El azar del escenario (random.ts): con la misma semilla, los mismos datos. */
  random!: Random
  data: ScenarioData = { teams: [], pastSeasons: [], ingesting: [], byHealth: {} }
  /** Los datos que le tocaron al escenario, en palabras: salen en el informe si falla. */
  chosen: string[] = []

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

  /** Apunta un dato elegido al azar, para poder repetir el escenario si falla. */
  note(text: string): void {
    this.chosen.push(text)
  }

  /** La dirección de la web de pruebas para el club del escenario: el club va en el nombre (LLD-B §8). */
  clubUrl(path = '/'): string {
    return `http://${this.club.slug}.localhost:${config.webPort}${path}`
  }
}

setWorldConstructor(ScenarioWorld)

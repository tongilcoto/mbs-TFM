// Las acciones de cada fila de la portada (plan R3, §3.1 y decisión 1; LLD-B §3.7), y el refresco de la portada
// mientras algo está en marcha (decisión 5, LLD-B §2.4).
import { Given, Then, When } from '@cucumber/cucumber'
import { addPlayingTeam, ingestionFinished, linkTeam, setIngestion, type PlayingTeam } from '../support/club-data.ts'
import { fakeFederation } from '../support/fake-federation.ts'
import { categories, competition, currentSeason, type Team } from '../support/invented.ts'
import { absent, becomes, shows } from '../support/look.ts'
import type { ScenarioWorld } from '../support/world.ts'
import { tabTo } from './alta.steps.ts'
import { addTeamPlaying, content, row, theTeam } from './portada.steps.ts'

// La acción de sincronizar de la fila del equipo: el enlace cuyo nombre lleva el equipo detrás.
const action = (world: ScenarioWorld) =>
  world.page.getByRole('link', { name: new RegExp(`^Sincronizar .*, ${theTeam(world).name}$`) })
// El texto de la acción: lo que se ve junto al icono (no se lee: va en el nombre del enlace).
const tip = (world: ScenarioWorld) => action(world).locator('xpath=..').locator('.tip')

// ── Los datos ────────────────────────────────────────────────────────────────────────────────────────────────

Given('en la temporada en curso de mi club juega un equipo con dos competiciones', async function (this: ScenarioWorld) {
  await addTeamPlaying(this, currentSeason())
  // La copa: otra competición del mismo equipo, con su propio código (D-12, D-101).
  const cup = competition(this.random, currentSeason(), theTeam(this))
  await linkTeam(this.club, theTeam(this), cup)
  this.note(`y juega ${cup.displayName}`)
})

Given(
  'en la portada de mi club, la acción de la fila de un equipo enseña su texto porque he llegado con el tabulador',
  async function (this: ScenarioWorld) {
    await addTeamPlaying(this, currentSeason())
    await openHome(this)
    await tabTo(this, action(this), 'la acción de la fila')
    await tip(this).waitFor()
  },
)

async function openHome(world: ScenarioWorld, query = '') {
  await world.page.goto(world.clubUrl(`/${query}`))
  await content(world).getByRole('table').waitFor()
}

// ── Lo que se hace ───────────────────────────────────────────────────────────────────────────────────────────

When('llego con el tabulador a la acción de la fila del equipo', async function (this: ScenarioWorld) {
  await tabTo(this, action(this), 'la acción de la fila')
})

When('paso el ratón por la acción de la fila del equipo', async function (this: ScenarioWorld) {
  await action(this).hover()
})

When('pulso la tecla Escape', async function (this: ScenarioWorld) {
  await this.page.keyboard.press('Escape')
})

When('pulso el enlace {string} de la fila del equipo', async function (this: ScenarioWorld, name: string) {
  await row(this, theTeam(this).name).getByRole('link', { name, exact: true }).click()
})

When('pulso la acción {string} de la fila del equipo', async function (this: ScenarioWorld, name: string) {
  await this.page.getByRole('link', { name: `${name}, ${theTeam(this).name}`, exact: true }).click()
})

// ── Lo que se ve ─────────────────────────────────────────────────────────────────────────────────────────────

Then('la fila del equipo en la portada tiene el enlace {string}', async function (this: ScenarioWorld, name: string) {
  await this.check(`el enlace «${name}»`, () =>
    shows(row(this, theTeam(this).name).getByRole('link', { name, exact: true }), `el enlace «${name}» en la fila`),
  )
})

Then(
  'la fila del equipo en la portada tiene la acción {string}, con el nombre del equipo para el lector',
  async function (this: ScenarioWorld, name: string) {
    const full = `${name}, ${theTeam(this).name}`
    await this.check(`la acción «${full}»`, () =>
      shows(row(this, theTeam(this).name).getByRole('link', { name: full, exact: true }), `la acción «${full}» en la fila`),
    )
  },
)

Then('la fila del equipo en la portada tiene una sola acción {string}', async function (this: ScenarioWorld, name: string) {
  const full = `${name}, ${theTeam(this).name}`
  await this.check(`una sola «${full}»`, async () => {
    await shows(this.page.getByRole('link', { name: full, exact: true }), `la acción «${full}»`)
    const count = await this.page.getByRole('link', { name: full, exact: true }).count()
    if (count !== 1) throw new Error(`hay ${count}`)
  })
})

Then('la acción de la fila del equipo enseña el texto {string}', async function (this: ScenarioWorld, text: string) {
  await this.check(`el texto «${text}»`, () => shows(tip(this).getByText(text, { exact: true }), `«${text}» junto al icono`))
})

Then('la acción de la fila del equipo no enseña su texto', async function (this: ScenarioWorld) {
  await this.check('el texto', () => absent(tip(this), 'el texto junto al icono'))
})

Then('la acción de la fila del equipo tiene el foco', async function (this: ScenarioWorld) {
  await this.check('el foco', () =>
    becomes(this.page, () => action(this).evaluate((el) => el === document.activeElement), true, 'el foco en la acción'),
  )
})

// ── El refresco ──────────────────────────────────────────────────────────────────────────────────────────────

/** Deja la ingesta del equipo «En marcha», con el calendario retenido en la Federación hasta que se suelte. */
async function runningAndHeld(world: ScenarioWorld, playing: PlayingTeam) {
  world.data.ingesting.push(playing.competition.id!)
  await setIngestion(world.club, playing, 'En marcha')
}

Given('en la temporada en curso de mi club juega un equipo, con su ingesta en marcha y retenida en la Federación', async function (this: ScenarioWorld) {
  await addTeamPlaying(this, currentSeason())
  await runningAndHeld(this, { team: theTeam(this), competition: this.data.competition! })
})

Given(
  'en la temporada en curso de mi club juegan tres equipos, uno con su ingesta en marcha y retenida en la Federación',
  async function (this: ScenarioWorld) {
    const playing: PlayingTeam[] = []
    for (let i = 0; i < 3; i++) {
      const added = await addPlayingTeam(this.club, this.random, currentSeason(), this.data.teams)
      this.data.teams.push(added.team)
      playing.push(added)
    }
    const running = this.random.pick(playing)
    this.data.team = running.team
    this.data.competition = running.competition
    this.note(`en marcha: ${running.team.name}`)
    await runningAndHeld(this, running)
  },
)

// Por edad y letra, como la regla de la columna «Equipo» (order.ts); al revés, del último al primero.
function byTeam(a: Team, b: Team): number {
  return categories.indexOf(a.category) - categories.indexOf(b.category) || (a.letter ?? '').localeCompare(b.letter ?? '', 'es')
}

Given('la portada de mi club está abierta, ordenada al revés por {string}', async function (this: ScenarioWorld, column: string) {
  if (column !== 'Equipo') throw new Error(`El escenario solo sabe ordenar por «Equipo», no por «${column}»`)
  await openHome(this, '?orden=equipo-inverso')
})

When('la Federación suelta la ingesta retenida', async function (this: ScenarioWorld) {
  fakeFederation().releaseAll()
  await ingestionFinished(this.club, this.data.competition!.id!)
  // La portada se entera en su siguiente refresco, como mucho a los 10 s: se espera a que vuelva a pedir.
  await this.page.waitForResponse((response) => new URL(response.url()).pathname === '/api/v1/competitions', { timeout: 12_000 })
})

Then('la portada no dice {string}', async function (this: ScenarioWorld, text: string) {
  await this.check(`«${text}»`, () => absent(content(this).getByText(text, { exact: true }), `«${text}»`))
})

Then('la tabla de la portada sigue ordenada al revés por {string}', async function (this: ScenarioWorld, column: string) {
  if (column !== 'Equipo') throw new Error(`El escenario solo sabe comprobar el orden por «Equipo», no por «${column}»`)
  const expected = [...this.data.teams].sort(byTeam).reverse().map((t) => t.name)
  await this.check('el orden', () =>
    becomes(this.page, async () => (await content(this).getByRole('rowheader').allTextContents()).map((t) => t.trim()).join(' | '), expected.join(' | '), 'el orden de la tabla'),
  )
})

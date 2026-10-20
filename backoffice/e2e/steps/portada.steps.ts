// La portada: sus datos, la tabla, la temporada y sus estados (plan R1, §3.2 y decisiones 2, 5 y 6).
import { Given, Then, When } from '@cucumber/cucumber'
import { stopApiServer } from '../support/api-server.ts'
import {
  addSeason,
  addTeam,
  currentSeasonLabel,
  setIngestion,
  setLastSynced,
} from '../support/club-data.ts'
import { holdRequest } from '../support/hold-request.ts'
import { absent, becomes, shows } from '../support/look.ts'
import type { ScenarioWorld } from '../support/world.ts'

const content = (world: ScenarioWorld) => world.page.getByRole('main')
const picker = (world: ScenarioWorld) => world.page.getByRole('combobox', { name: 'Temporada' })
// La fila de un equipo: la que tiene su nombre como cabecera (LLD-B §10.4).
const row = (world: ScenarioWorld, team: string) =>
  world.page.getByRole('row').filter({ has: world.page.getByRole('rowheader', { name: team, exact: true }) })

// ── Los datos ────────────────────────────────────────────────────────────────────────────────────────────────

Given('mi club tiene la temporada en curso', async function (this: ScenarioWorld) {
  await addSeason(this.club, currentSeasonLabel())
})

Given('mi club tiene la temporada {string}', async function (this: ScenarioWorld, label: string) {
  await addSeason(this.club, label)
})

Given(
  /^en la temporada en curso(?: de mi club)? el "([^"]+)" juega "([^"]+)"$/,
  async function (this: ScenarioWorld, team: string, competition: string) {
    await addTeam(this.club, team, currentSeasonLabel(), competition)
  },
)

Given(
  'en la temporada {string} el {string} juega {string}',
  async function (this: ScenarioWorld, season: string, team: string, competition: string) {
    await addTeam(this.club, team, season, competition)
  },
)

Given('en la temporada en curso el {string} está inscrito sin competición', async function (this: ScenarioWorld, team: string) {
  await addTeam(this.club, team, currentSeasonLabel())
})

Given('la ingesta del {string} está {string}', async function (this: ScenarioWorld, team: string, state: string) {
  await setIngestion(this.club, team, state as Parameters<typeof setIngestion>[2])
})

Given('el {string} se sincronizó por última vez el {string}', async function (this: ScenarioWorld, team: string, instant: string) {
  await setLastSynced(this.club, team, instant)
})

// ── Retener la petición y parar el servidor (DW-17) ─────────────────────────────────────────────────────────

Given('la petición de las temporadas de mi club está retenida', async function (this: ScenarioWorld) {
  this.held = await holdRequest(this.page, '/seasons')
})

Given('he abierto la portada de mi club con la petición de las temporadas retenida', async function (this: ScenarioWorld) {
  this.held = await holdRequest(this.page, '/seasons')
  await this.page.goto(this.clubUrl())
  await this.held.arrived
})

When('la petición de las temporadas sale', async function (this: ScenarioWorld) {
  await this.held!.release()
})

Given('la portada de mi club enseña que no se ha podido conectar con el servidor', async function (this: ScenarioWorld) {
  this.held = await holdRequest(this.page, '/seasons')
  await this.page.goto(this.clubUrl())
  await this.held.arrived
  await stopApiServer()
  await this.held.release()
  await content(this).getByRole('alert').waitFor()
})

// ── La temporada ─────────────────────────────────────────────────────────────────────────────────────────────

async function chooseSeason(world: ScenarioWorld, label: string) {
  await picker(world).click()
  await world.page.getByRole('option', { name: label }).click()
  // Hasta que la lista de opciones se ha cerrado del todo: a medio cerrar, axe la mediría.
  await world.page.getByRole('listbox').waitFor({ state: 'detached' })
  await world.page.waitForURL((url) => url.searchParams.get('temporada') === label.replace('/', '-'))
}

When('elijo la temporada {string}', async function (this: ScenarioWorld, label: string) {
  await chooseSeason(this, label)
})

Given('he cambiado la portada de mi club a la temporada {string}', async function (this: ScenarioWorld, label: string) {
  await addSeason(this.club, label)
  await this.page.goto(this.clubUrl())
  await chooseSeason(this, label)
})

// ── Lo que se ve ─────────────────────────────────────────────────────────────────────────────────────────────

Then('la fila del {string} tiene la competición {string}', async function (this: ScenarioWorld, team: string, name: string) {
  await this.check(`la competición del ${team}`, () =>
    shows(row(this, team).getByRole('cell', { name, exact: true }), `«${name}» en la fila del ${team}`),
  )
})

Then('la fila del {string} tiene la ingesta {string}', async function (this: ScenarioWorld, team: string, state: string) {
  // El estado va con su icono delante, que el lector de pantalla no lee: se busca la palabra.
  await this.check(`la ingesta del ${team}`, () =>
    shows(row(this, team).getByText(state, { exact: true }), `«${state}» en la fila del ${team}`),
  )
})

Then(
  'la fila del {string} tiene la última sincronización {string}',
  async function (this: ScenarioWorld, team: string, when: string) {
    await this.check(`la última sincronización del ${team}`, () =>
      shows(row(this, team).getByRole('cell', { name: when, exact: true }), `«${when}» en la fila del ${team}`),
    )
  },
)

Then('la fila del {string} dice {string}', async function (this: ScenarioWorld, team: string, text: string) {
  await this.check(`«${text}» en el ${team}`, () => shows(row(this, team).getByText(text), `«${text}» en la fila del ${team}`))
})

Then('la portada tiene la fila del {string}', async function (this: ScenarioWorld, team: string) {
  await this.check(`la fila del ${team}`, () => shows(row(this, team), `la fila del ${team}`))
})

Then('la portada dice {string}', async function (this: ScenarioWorld, text: string) {
  await this.check(`«${text}»`, () => shows(content(this).getByText(text, { exact: true }), `«${text}»`))
})

Then('la portada dice que no hay equipos en la temporada en curso', async function (this: ScenarioWorld) {
  const text = `No hay equipos en la temporada ${currentSeasonLabel()}.`
  await this.check(`«${text}»`, () => shows(content(this).getByText(text, { exact: true }), `«${text}»`))
})

Then('la portada ofrece {string}', async function (this: ScenarioWorld, name: string) {
  await this.check(`«${name}»`, () => shows(content(this).getByRole('button', { name }), `el botón «${name}»`))
})

Then('la portada tiene el enlace {string}', async function (this: ScenarioWorld, name: string) {
  await this.check(`el enlace «${name}»`, () => shows(content(this).getByRole('link', { name }), `el enlace «${name}»`))
})

Then('la portada no tiene selector de temporada', async function (this: ScenarioWorld) {
  await this.check('el selector', () => absent(picker(this), 'el selector de temporada'))
})

Then('el selector de temporada tiene elegida la temporada en curso', async function (this: ScenarioWorld) {
  const expected = currentSeasonLabel()
  await this.check('el selector', () =>
    becomes(this.page, async () => (await picker(this).textContent())?.trim(), expected, 'la temporada del selector'),
  )
})


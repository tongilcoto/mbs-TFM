// La portada: sus datos, la tabla, la temporada y sus estados (plan R1, §3.2 y decisiones 2, 5 y 6).
import { Given, Then, When } from '@cucumber/cucumber'
import { stopApiServer } from '../support/api-server.ts'
import {
  addPlayingTeam,
  addSeason,
  addTeamWithoutCompetition,
  lastSynced,
  setIngestion,
  type HealthWords,
} from '../support/club-data.ts'
import { holdRequest } from '../support/hold-request.ts'
import { currentSeason, futureSeason, pastSeason, type Season } from '../support/invented.ts'
import { absent, becomes, shows } from '../support/look.ts'
import type { ScenarioWorld } from '../support/world.ts'

const content = (world: ScenarioWorld) => world.page.getByRole('main')
const picker = (world: ScenarioWorld) => world.page.getByRole('combobox', { name: 'Temporada' })
// La fila de un equipo: la que tiene su nombre como cabecera (LLD-B §10.4).
const row = (world: ScenarioWorld, team: string) =>
  world.page.getByRole('row').filter({ has: world.page.getByRole('rowheader', { name: team, exact: true }) })
// La fila del equipo del escenario.
const teamRow = (world: ScenarioWorld) => row(world, theTeam(world).name)
// En la dirección, la temporada va con guion: `2025-26` (plan R1, decisión 5).
const inAddress = (season: Season) => season.label.replace('/', '-')

function theTeam(world: ScenarioWorld) {
  if (!world.data.team) throw new Error('El escenario no ha dado de alta ningún equipo')
  return world.data.team
}

function lastPastSeason(world: ScenarioWorld): Season {
  const season = world.data.pastSeasons.at(-1)
  if (!season) throw new Error('El escenario no ha dado de alta ninguna temporada pasada')
  return season
}

/** El instante en hora de Madrid, como lo escribe la web: `17/10/2026 23:40`. */
function inMadrid(instant: Date): string {
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Europe/Madrid',
      day: '2-digit',
      month: '2-digit',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    })
      .formatToParts(instant)
      .map((p) => [p.type, p.value]),
  )
  return `${parts.day}/${parts.month}/${parts.year} ${parts.hour}:${parts.minute}`
}

// ── Los datos ────────────────────────────────────────────────────────────────────────────────────────────────

Given('mi club tiene la temporada en curso', async function (this: ScenarioWorld) {
  await addSeason(this.club, this.random, currentSeason())
})

async function addPastSeason(world: ScenarioWorld): Promise<Season> {
  const season = pastSeason(world.random, world.data.pastSeasons)
  await addSeason(world.club, world.random, season)
  world.data.pastSeasons.push(season)
  world.note(`temporada pasada ${season.label}`)
  return season
}

Given('mi club tiene una temporada pasada', async function (this: ScenarioWorld) {
  await addPastSeason(this)
})

Given('mi club tiene dos temporadas pasadas', async function (this: ScenarioWorld) {
  await addPastSeason(this)
  await addPastSeason(this)
})

Given('mi club tiene una temporada que todavía no ha empezado', async function (this: ScenarioWorld) {
  const season = futureSeason(this.random)
  await addSeason(this.club, this.random, season)
  this.data.futureSeason = season
  this.note(`temporada futura ${season.label}`)
})

async function addTeamPlaying(world: ScenarioWorld, season: Season) {
  const { team, competition } = await addPlayingTeam(world.club, world.random, season, world.data.teams)
  world.data.teams.push(team)
  world.data.team = team
  world.data.competition = competition
  world.note(`${team.name} (${team.gender}, ${team.modality}) juega ${competition.displayName} en ${season.label}`)
}

Given('en la temporada en curso de mi club juega un equipo', async function (this: ScenarioWorld) {
  await addTeamPlaying(this, currentSeason())
})

Given('en una temporada pasada de mi club juega un equipo', async function (this: ScenarioWorld) {
  const season = pastSeason(this.random, this.data.pastSeasons)
  this.data.pastSeasons.push(season)
  await addTeamPlaying(this, season)
})

Given('en la temporada en curso de mi club hay un equipo inscrito sin competición', async function (this: ScenarioWorld) {
  const team = await addTeamWithoutCompetition(this.club, this.random, currentSeason(), this.data.teams)
  this.data.teams.push(team)
  this.data.team = team
  this.note(`${team.name} (${team.gender}, ${team.modality}) inscrito sin competición`)
})

Given('la ingesta de la competición del equipo está {string}', async function (this: ScenarioWorld, state: string) {
  const competition = this.data.competition
  if (!competition) throw new Error('El equipo del escenario no juega ninguna competición')
  // La que se deja en marcha acaba al final del escenario, antes de borrar el club (hooks.ts).
  if (state.startsWith('En marcha')) this.data.ingesting.push(competition.id!)
  await setIngestion(this.club, { team: theTeam(this), competition }, state as HealthWords)
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

When('elijo la temporada pasada', async function (this: ScenarioWorld) {
  await chooseSeason(this, lastPastSeason(this).label)
})

Given('he cambiado la portada de mi club a una temporada pasada', async function (this: ScenarioWorld) {
  const season = await addPastSeason(this)
  await this.page.goto(this.clubUrl())
  await chooseSeason(this, season.label)
})

When('abro la portada de mi club en una temporada pasada que mi club no tiene', async function (this: ScenarioWorld) {
  const season = pastSeason(this.random, this.data.pastSeasons)
  this.data.missingSeason = season
  this.note(`temporada que no tiene ${season.label}`)
  await this.page.goto(this.clubUrl(`/?temporada=${inAddress(season)}`))
  await this.page.locator('h1').first().waitFor()
})

// ── Lo que se ve ─────────────────────────────────────────────────────────────────────────────────────────────

Then('la fila del equipo tiene su competición', async function (this: ScenarioWorld) {
  const name = this.data.competition!.rowName
  await this.check('la competición', () =>
    shows(teamRow(this).getByRole('cell', { name, exact: true }), `«${name}» en la fila del ${theTeam(this).name}`),
  )
})

Then('la fila del equipo tiene la ingesta {string}', async function (this: ScenarioWorld, state: string) {
  // El estado va con su icono delante, que el lector de pantalla no lee: se busca la palabra.
  await this.check('la ingesta', () =>
    shows(teamRow(this).getByText(state, { exact: true }), `«${state}» en la fila del ${theTeam(this).name}`),
  )
})

Then('la fila del equipo tiene su última sincronización, en hora de Madrid', async function (this: ScenarioWorld) {
  const expected = inMadrid(await lastSynced(this.club, this.data.competition!.id!))
  await this.check('la última sincronización', () =>
    shows(teamRow(this).getByRole('cell', { name: expected, exact: true }), `«${expected}» en la fila del ${theTeam(this).name}`),
  )
})

Then('la fila del equipo dice {string}', async function (this: ScenarioWorld, text: string) {
  await this.check(`«${text}»`, () => shows(teamRow(this).getByText(text), `«${text}» en la fila del ${theTeam(this).name}`))
})

Then('la portada tiene la fila del equipo', async function (this: ScenarioWorld) {
  await this.check('la fila del equipo', () => shows(teamRow(this), `la fila del ${theTeam(this).name}`))
})

Then('la portada dice {string}', async function (this: ScenarioWorld, text: string) {
  await this.check(`«${text}»`, () => shows(content(this).getByText(text, { exact: true }), `«${text}»`))
})

Then('la portada dice que no hay equipos en la temporada en curso', async function (this: ScenarioWorld) {
  const text = `No hay equipos en la temporada ${currentSeason().label}.`
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
  const expected = currentSeason().label
  await this.check('el selector', () =>
    becomes(this.page, async () => (await picker(this).textContent())?.trim(), expected, 'la temporada del selector'),
  )
})


Then('la portada dice que enseña la más reciente de las temporadas pasadas, terminada', async function (this: ScenarioWorld) {
  const newest = [...this.data.pastSeasons].sort((a, b) => b.start - a.start)[0]!
  const text = `Temporada ${newest.label} · terminada`
  await this.check(`«${text}»`, () => shows(content(this).getByText(text, { exact: true }), `«${text}»`))
})

Then('la portada dice que enseña la temporada que todavía no ha empezado', async function (this: ScenarioWorld) {
  const text = `Temporada ${this.data.futureSeason!.label} · todavía no ha empezado`
  await this.check(`«${text}»`, () => shows(content(this).getByText(text, { exact: true }), `«${text}»`))
})

Then('la portada dice que no hay esa temporada', async function (this: ScenarioWorld) {
  const text = `No hay ninguna temporada ${this.data.missingSeason!.label}`
  await this.check(`«${text}»`, () => shows(content(this).getByText(text, { exact: true }), `«${text}»`))
})

Then('la dirección lleva la temporada pasada', async function (this: ScenarioWorld) {
  const expected = `/?temporada=${inAddress(lastPastSeason(this))}`
  await this.check('la dirección', () =>
    becomes(
      this.page,
      async () => {
        const url = new URL(this.page.url())
        return url.pathname + url.search
      },
      expected,
      'la dirección',
    ),
  )
})

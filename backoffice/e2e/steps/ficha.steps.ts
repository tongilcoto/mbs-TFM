// La ficha del equipo: cómo se llega y su cabecera (plan R4, §3.1 y §3.2); y volver a traer los datos con ↻, en
// la portada y en la ficha (decisión 7).
import { Given, Then, When } from '@cucumber/cucumber'
import { addPlayingTeam, addTeamWithoutCompetition, linkTeam, rivalTeamId, setIngestion, type HealthWords } from '../support/club-data.ts'
import { playedRounds, positionsAfter } from '../support/expected.ts'
import { fakeFederation } from '../support/fake-federation.ts'
import { holdRequest } from '../support/hold-request.ts'
import { competition, currentSeason, pastSeason, type Season } from '../support/invented.ts'
import { absent, becomes, contains, shows } from '../support/look.ts'
import type { ScenarioWorld } from '../support/world.ts'
import { addTeamPlaying, content, inAddress, lastPastSeason, row, theTeam } from './portada.steps.ts'

const genderLabels: Record<string, string> = { masculino: 'Masculino', femenino: 'Femenino' }
const modalityLabels: Record<string, string> = { futbol_11: 'Fútbol 11', futbol_7: 'Fútbol 7', futbol_sala: 'Fútbol sala', futbol_5: 'Fútbol 5' }

/** La ficha del equipo en una temporada: `/temporadas/2026-27/equipos/<id>/resultados`. */
export const fichaPath = (season: Season, teamId: string) => `/temporadas/${inAddress(season)}/equipos/${teamId}/resultados`

const box = (world: ScenarioWorld, name: 'Competición' | 'Posición') => world.page.getByRole('region', { name })
const seasonPicker = (world: ScenarioWorld) => content(world).getByRole('combobox', { name: 'Temporada' })

export function theCompetition(world: ScenarioWorld) {
  if (!world.data.competition) throw new Error('El equipo del escenario no juega ninguna competición')
  return world.data.competition
}

/** Abre la ficha y espera a que esté entera: la caja de la posición, o el error, o el aviso. */
export async function openFicha(world: ScenarioWorld, season: Season = currentSeason(), id = theTeam(world).id!) {
  await world.page.goto(world.clubUrl(fichaPath(season, id)))
  await world.page.locator('h1').first().waitFor()
}

async function fichaReady(world: ScenarioWorld) {
  await box(world, 'Posición').getByText(/º|—/).first().waitFor()
}

// ── Los datos ────────────────────────────────────────────────────────────────────────────────────────────────

/** El equipo del club que juega una competición con jornadas jugadas (plan R4, R4.3). */
export async function addTeamThatPlayed(world: ScenarioWorld) {
  const { team, competition: plays } = await addPlayingTeam(world.club, world.random, currentSeason(), world.data.teams, true)
  world.data.teams.push(team)
  world.data.team = team
  world.data.competition = plays
  world.note(`${team.name} (${team.gender}, ${team.modality}) ha jugado ${playedRounds(plays).length} jornadas de ${plays.displayName}`)
}

Given('en la temporada en curso de mi club juega un equipo en una competición con jornadas jugadas', async function (this: ScenarioWorld) {
  await addTeamThatPlayed(this)
})

Given('el mismo equipo de mi club juega en la temporada en curso y en una pasada', async function (this: ScenarioWorld) {
  await addTeamPlaying(this, currentSeason())
  const past = pastSeason(this.random, this.data.pastSeasons)
  this.data.pastSeasons.push(past)
  // Sincronizarlo con una competición de la temporada pasada lo inscribe en ella (D-102).
  const plays = competition(this.random, past, theTeam(this))
  await linkTeam(this.club, theTeam(this), plays)
  this.note(`y en ${past.label} juega ${plays.displayName}`)
})

Given('estoy en la ficha del equipo de mi club que ha jugado', async function (this: ScenarioWorld) {
  await addTeamThatPlayed(this)
  await openFicha(this)
  await fichaReady(this)
})

Given(
  'estoy en la ficha del equipo de mi club que ha jugado, con la ingesta de su competición {string}',
  async function (this: ScenarioWorld, state: string) {
    await addTeamThatPlayed(this)
    await setIngestion(this.club, { team: theTeam(this), competition: theCompetition(this) }, state as HealthWords)
    await openFicha(this)
    await fichaReady(this)
  },
)

Given('estoy en la ficha del equipo de mi club inscrito sin competición', async function (this: ScenarioWorld) {
  const team = await addTeamWithoutCompetition(this.club, this.random, currentSeason(), this.data.teams)
  this.data.teams.push(team)
  this.data.team = team
  this.note(`${team.name} (${team.gender}, ${team.modality}) inscrito sin competición`)
  await openFicha(this)
  await fichaReady(this)
})

Given('estoy en la ficha del equipo', async function (this: ScenarioWorld) {
  await openFicha(this)
  await this.page.getByRole('heading', { level: 1, name: theTeam(this).name }).waitFor()
})

Given('la petición del equipo está retenida', async function (this: ScenarioWorld) {
  // `getTeam`, la primera que hace la ficha al abrir (DW-17): sale cuando el escenario acaba.
  this.held = await holdRequest(this.page, `/teams/${theTeam(this).id}`)
})

Given('la Federación ya contesta bien a la competición del equipo', async function (this: ScenarioWorld) {
  fakeFederation().answerCalendar(theCompetition(this))
  fakeFederation().answerScorers(theCompetition(this))
})

Given('la Federación contesta con un error a la competición del equipo', async function (this: ScenarioWorld) {
  fakeFederation().failCalendar(theCompetition(this))
})

Given('la Federación va a retener la próxima petición del calendario de la competición del equipo', async function (this: ScenarioWorld) {
  // La pasada que se lance se queda a medias hasta el final del escenario, que la suelta y espera (hooks.ts).
  fakeFederation().hold(theCompetition(this))
  this.data.ingesting.push(theCompetition(this).id!)
})

// ── Lo que se hace ───────────────────────────────────────────────────────────────────────────────────────────

When('pulso el nombre del equipo en la portada', async function (this: ScenarioWorld) {
  await row(this, theTeam(this).name).getByRole('link', { name: theTeam(this).name, exact: true }).click()
  await headingOf(this)
})

/** Espera al título de la ficha; si no sale, el error dice lo que hay en la página. */
async function headingOf(world: ScenarioWorld) {
  try {
    await world.page.getByRole('heading', { level: 1, name: theTeam(world).name }).waitFor({ timeout: 8_000 })
  } catch {
    const seen = (await content(world).innerText()).replace(/\s+/g, ' ').slice(0, 300)
    throw new Error(`no sale la ficha de ${theTeam(world).name} en ${world.page.url()}: «${seen}»`)
  }
}

When('escribo en el navegador la dirección del equipo, sin temporada', async function (this: ScenarioWorld) {
  await this.page.goto(this.clubUrl(`/equipos/${theTeam(this).id}`))
  await this.page.getByRole('heading', { level: 1, name: theTeam(this).name }).waitFor()
})

When('elijo la temporada pasada en el selector de la ficha', async function (this: ScenarioWorld) {
  await seasonPicker(this).click()
  await this.page.getByRole('option', { name: lastPastSeason(this).label, exact: true }).click()
})

When(/^abro la ficha del equipo(?: de mi club (?:que ha jugado|inscrito sin competición))?$/, async function (this: ScenarioWorld) {
  await openFicha(this)
  await this.page.getByRole('heading', { level: 1, name: theTeam(this).name }).waitFor()
})

When('escribo en el navegador la dirección de la ficha del equipo en la temporada en curso', async function (this: ScenarioWorld) {
  await openFicha(this)
})

When('escribo en el navegador la dirección de la ficha del equipo en la temporada pasada', async function (this: ScenarioWorld) {
  await openFicha(this, lastPastSeason(this))
})

When('escribo en el navegador la dirección de la ficha de un equipo que mi club no tiene', async function (this: ScenarioWorld) {
  await openFicha(this, currentSeason(), crypto.randomUUID())
})

When('abro la ficha del equipo {string} en la temporada en curso', async function (this: ScenarioWorld, id: string) {
  await openFicha(this, currentSeason(), id)
})

When(
  'escribo en el navegador la dirección de la ficha de uno de los rivales del equipo de mi club que juega',
  async function (this: ScenarioWorld) {
    const rival = this.random.pick(theCompetition(this).teams.slice(1))
    this.note(`rival: ${rival.rawName}`)
    await openFicha(this, currentSeason(), await rivalTeamId(this.club, rival.code))
  },
)

When('pulso el enlace {string} de la caja de la competición', async function (this: ScenarioWorld, name: string) {
  await box(this, 'Competición').getByRole('link', { name, exact: true }).click()
})

When('pulso la competición en la caja de la competición', async function (this: ScenarioWorld) {
  await box(this, 'Competición').getByRole('link', { name: theCompetition(this).rowName, exact: true }).click()
})

/** La acción de una competición: el botón con la competición detrás, para el lector. */
const relaunchIn = (scope: ReturnType<ScenarioWorld['page']['getByRole']>, world: ScenarioWorld, name: string) =>
  scope.getByRole('button', { name: `${name}, ${theCompetition(world).rowName}`, exact: true })

When('pulso la acción {string} de la caja de la competición', async function (this: ScenarioWorld, name: string) {
  await relaunchIn(box(this, 'Competición'), this, name).click()
})

When('pulso la acción {string} de la celda de la ingesta del equipo', async function (this: ScenarioWorld, name: string) {
  await relaunchIn(row(this, theTeam(this).name), this, name).click()
})

// ── Lo que se ve ─────────────────────────────────────────────────────────────────────────────────────────────

/** Que la ficha abierta es la del equipo en esa temporada: la dirección y la temporada del selector. */
async function onFicha(world: ScenarioWorld, season: Season) {
  await world.check('la dirección', () =>
    becomes(world.page, async () => new URL(world.page.url()).pathname, fichaPath(season, theTeam(world).id!), 'el camino'),
  )
  await world.check('el equipo', () =>
    shows(world.page.getByRole('heading', { level: 1, name: theTeam(world).name }), `el título «${theTeam(world).name}»`),
  )
  await world.check('la temporada', () => contains(world.page, () => seasonPicker(world).innerText(), season.label, 'el selector de temporada'))
}

Then('estoy en la ficha del equipo, en la temporada pasada', async function (this: ScenarioWorld) {
  await onFicha(this, lastPastSeason(this))
})

// Es un `Given` en un escenario («estoy en la ficha… y elijo otra temporada») y un `Then` en otro (después de
// escribir la dirección sin temporada): si no se está en ella, se abre; y en los dos, se comprueba.
Then('estoy en la ficha del equipo, en la temporada en curso', async function (this: ScenarioWorld) {
  const path = fichaPath(currentSeason(), theTeam(this).id!)
  if (!this.page.url().startsWith('http') || !this.page.url().includes(`/equipos/${theTeam(this).id}`)) {
    await this.page.goto(this.clubUrl(path))
  }
  await onFicha(this, currentSeason())
})

Then('el título de la ficha dice la categoría y la letra del equipo, con su género y su modalidad', async function (this: ScenarioWorld) {
  const team = theTeam(this)
  await this.check('el título', () => shows(this.page.getByRole('heading', { level: 1, name: team.name, exact: true }), `el título «${team.name}»`))
  const below = `${genderLabels[team.gender]} · ${modalityLabels[team.modality]}`
  await this.check('el género y la modalidad', () => shows(content(this).getByText(below, { exact: true }), `«${below}»`))
})

Then('la caja de la temporada dice la temporada en curso', async function (this: ScenarioWorld) {
  await this.check('la temporada', () => contains(this.page, () => seasonPicker(this).innerText(), currentSeason().label, 'el selector'))
})

Then('la caja de la competición dice su división y su grupo, con la ingesta {string}', async function (this: ScenarioWorld, state: string) {
  const name = theCompetition(this).rowName
  await this.check('la competición', () => shows(box(this, 'Competición').getByRole('link', { name, exact: true }), `«${name}»`))
  await this.check('la ingesta', () => shows(box(this, 'Competición').getByText(state, { exact: true }), `«${state}»`))
})

Then('la caja de la competición tiene la ingesta {string}', async function (this: ScenarioWorld, state: string) {
  await this.check('la ingesta', () => shows(box(this, 'Competición').getByText(state, { exact: true }), `«${state}» en la caja`))
})

Then('la caja de la posición dice el puesto del equipo tras la última jornada jugada', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  const last = playedRounds(plays).length
  const positions = positionsAfter(plays, last)
  const expected = [`${positions.get(plays.teams[0]!.code)}º`, `de ${positions.size} · tras la jornada ${last}`]
  this.note(`posición esperada: ${expected.join(' ')}`)
  for (const text of expected) {
    await this.check(`«${text}»`, () => shows(box(this, 'Posición').getByText(text, { exact: true }), `«${text}»`))
  }
})

Then('la caja de la posición dice {string} y {string}', async function (this: ScenarioWorld, first: string, second: string) {
  for (const text of [first, second]) {
    await this.check(`«${text}»`, () => shows(box(this, 'Posición').getByText(text, { exact: true }), `«${text}»`))
  }
})

Then('la caja de la posición dice {string}', async function (this: ScenarioWorld, text: string) {
  await this.check(`«${text}»`, () => shows(box(this, 'Posición').getByText(text, { exact: true }), `«${text}»`))
})

Then('la caja de la competición tiene el enlace {string}', async function (this: ScenarioWorld, name: string) {
  await this.check(`el enlace «${name}»`, () => shows(box(this, 'Competición').getByRole('link', { name, exact: true }), `«${name}»`))
})

Then('la caja de la competición no tiene la acción {string}', async function (this: ScenarioWorld, name: string) {
  await this.check(`la acción «${name}»`, () =>
    absent(box(this, 'Competición').getByRole('button', { name: new RegExp(`^${name}`) }), `la acción «${name}»`),
  )
})

Then('la acción {string} de la caja de la competición está bloqueada', async function (this: ScenarioWorld, name: string) {
  await this.check('bloqueada', () =>
    becomes(this.page, () => relaunchIn(box(this, 'Competición'), this, name).isDisabled(), true, `«${name}» bloqueada`),
  )
})

Then('la ficha dice {string}', async function (this: ScenarioWorld, text: string) {
  await this.check(`«${text}»`, () => shows(content(this).getByText(text, { exact: true }), `«${text}»`))
})

Then('la ficha dice que el equipo no jugó la temporada pasada', async function (this: ScenarioWorld) {
  const text = `Club de pruebas ${theTeam(this).name} no jugó la temporada ${lastPastSeason(this).label}.`
  await this.check('el aviso', () => shows(content(this).getByText(text, { exact: true }), `«${text}»`))
})

Then('la ficha tiene el selector de temporada', async function (this: ScenarioWorld) {
  await this.check('el selector', () => shows(seasonPicker(this), 'el selector de temporada'))
})

// ── ↻ en la portada (acciones-fila.feature) ──────────────────────────────────────────────────────────────────

Then(
  'la celda de la ingesta del equipo tiene la acción {string}, con el nombre de la competición para el lector',
  async function (this: ScenarioWorld, name: string) {
    const action = relaunchIn(row(this, theTeam(this).name), this, name)
    await this.check(`la acción «${name}»`, async () => {
      await shows(action, `«${name}, ${theCompetition(this).rowName}»`)
      // En la celda de la ingesta: la de la columna que se llama así (desde la R5 hay columnas en medio).
      const [cell, ingestion] = await action.evaluate((el) => {
        const td = el.closest('td')!
        const headers = Array.from(td.closest('table')!.querySelectorAll('thead th'))
        return [
          Array.prototype.indexOf.call(td.parentElement!.children, td),
          headers.findIndex((th) => th.textContent!.trim().startsWith('Ingesta')),
        ]
      })
      if (cell !== ingestion) throw new Error(`está en la columna ${cell + 1}, no en la de la ingesta (${ingestion + 1})`)
    })
  },
)

Then('la fila del equipo en la portada no tiene la acción {string}', async function (this: ScenarioWorld, name: string) {
  await this.check(`la acción «${name}»`, () =>
    absent(row(this, theTeam(this).name).getByRole('button', { name: new RegExp(`^${name}`) }), `la acción «${name}»`),
  )
})

Then('la acción {string} de la celda de la ingesta del equipo está bloqueada', async function (this: ScenarioWorld, name: string) {
  await this.check('bloqueada', () =>
    becomes(this.page, () => relaunchIn(row(this, theTeam(this).name), this, name).isDisabled(), true, `«${name}» bloqueada`),
  )
})

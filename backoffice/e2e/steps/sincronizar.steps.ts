// Sincronizar un equipo con la Federación (plan R3, §3.2–§3.4; decisiones 2 a 6). El equipo que se sincroniza es
// `data.team`; la competición que la Federación tiene para él, `data.offer`, inventada y servida por la federación
// falsa (fake-federation.ts). El vocabulario de los pasos está en la cabecera de sincronizar.feature.
import { type DataTable, Given, Then, When } from '@cucumber/cucumber'
import type { Locator } from 'playwright'
import {
  addTeam,
  addTeamWithoutCompetition,
  competitionIdByGroup,
  linkTeam,
  rivalTeamId,
} from '../support/club-data.ts'
import { fakeFederation } from '../support/fake-federation.ts'
import { holdRequest } from '../support/hold-request.ts'
import {
  categories,
  categoryLabels,
  competition,
  currentSeason,
  nextSeason,
  team as inventTeam,
  type Competition,
  type Season,
  type Team,
} from '../support/invented.ts'
import { absent, becomes, contains, sentences, shows } from '../support/look.ts'
import type { ScenarioWorld } from '../support/world.ts'
import { tabTo } from './alta.steps.ts'
import { addTeamPlaying, row, theTeam } from './portada.steps.ts'

const genderLabels = { masculino: 'Masculino', femenino: 'Femenino' }
const modalityLabels = { futbol_11: 'Fútbol 11', futbol_7: 'Fútbol 7', futbol_sala: 'Fútbol sala', futbol_5: 'Fútbol 5' }

// ── Dónde está cada cosa ─────────────────────────────────────────────────────────────────────────────────────

const main = (world: ScenarioWorld) => world.page.getByRole('main')
const currentStep = (world: ScenarioWorld) => main(world).getByRole('list', { name: 'Pasos' }).locator('[aria-current="step"]')
const urlField = (world: ScenarioWorld) => main(world).getByRole('textbox', { name: /^Dirección del calendario/ })
const checkButton = (world: ScenarioWorld) => main(world).getByRole('button', { name: /^Compro/ })
const syncButton = (world: ScenarioWorld) => main(world).getByRole('button', { name: /^Sincronizar/ })
const errorList = (world: ScenarioWorld) => main(world).getByRole('group', { name: /^Revisa est/ })
const teamChoice = (world: ScenarioWorld) => main(world).getByRole('group', { name: /^¿Cuál es tu equipo\?/ })
const radio = (world: ScenarioWorld, rawName: string) => teamChoice(world).getByRole('radio', { name: rawName, exact: true })
const stepTwoHeading = (world: ScenarioWorld) => main(world).getByRole('heading', { name: 'Lo que hay en esa dirección' })
// El botón principal de cada paso: «Comprobar en la Federación» en el 1, «Sincronizar…» en el 2.
const stepButton = (world: ScenarioWorld, step: number) => (step === 1 ? checkButton(world) : syncButton(world))
// Un botón del paso por el principio de su nombre: «Sincronizar» vale para «Sincronizar CLUB 'A'».
const buttonStarting = (world: ScenarioWorld, name: string) =>
  main(world).getByRole('button', { name: new RegExp(`^${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`) })

function offer(world: ScenarioWorld): Competition {
  if (!world.data.offer) throw new Error('La Federación no tiene ninguna competición para el equipo que se sincroniza')
  return world.data.offer
}

/** Lo que el lector dice de un elemento después de su nombre: los textos de su `aria-describedby`. */
function description(locator: Locator): Promise<string> {
  return locator.evaluate((el) =>
    (el.getAttribute('aria-describedby') ?? '')
      .split(' ')
      .filter(Boolean)
      .map((id) => document.getElementById(id)?.textContent?.trim() ?? '')
      .join(' '),
  )
}

/** Los pares del resumen del paso 2: «Competición» → «PRIMERA CADETE · Grupo 4». */
async function summary(world: ScenarioWorld): Promise<Record<string, string>> {
  await stepTwoHeading(world).waitFor()
  return main(world).locator('dl').evaluate((dl) =>
    Object.fromEntries(
      Array.from(dl.querySelectorAll('div')).map((pair) => [
        pair.querySelector('dt')?.textContent?.trim() ?? '',
        pair.querySelector('dd')?.textContent?.trim() ?? '',
      ]),
    ),
  )
}

// ── Llegar a la pantalla ─────────────────────────────────────────────────────────────────────────────────────

/** Espera a que la pantalla tenga su equipo y el paso 1 listo. */
async function stepOneReady(world: ScenarioWorld) {
  await urlField(world).waitFor()
}

/** Abre la portada y pulsa el icono de sincronizar de la fila del equipo, como el usuario. */
async function openFromHome(world: ScenarioWorld, of: Team) {
  await world.page.goto(world.clubUrl())
  await world.page.getByRole('link', { name: new RegExp(`^Sincronizar .*, ${of.name}$`) }).click()
  await stepOneReady(world)
}

/** Antes de actuar en un paso, que la pantalla esté de verdad en él: el escenario lo nombra. */
async function inStep(world: ScenarioWorld, step: number) {
  const expected = step === 1 ? 'La dirección' : 'Tu equipo'
  await currentStep(world).filter({ hasText: expected }).waitFor()
}

async function teamWithoutCompetition(world: ScenarioWorld): Promise<Team> {
  const created = await addTeamWithoutCompetition(world.club, world.random, currentSeason(), world.data.teams)
  world.data.teams.push(created)
  world.data.team = created
  world.note(`${created.name} (${created.gender}, ${created.modality}) inscrito sin competición`)
  return created
}

Given(/^estoy en el paso 1 de sincronizar un equipo de mi club sin competición$/, async function (this: ScenarioWorld) {
  await openFromHome(this, await teamWithoutCompetition(this))
})

When('abro desde la portada la pantalla de sincronizar el equipo de mi club inscrito sin competición', async function (this: ScenarioWorld) {
  await openFromHome(this, theTeam(this))
})

Given('estoy en el paso 1 de sincronizar el equipo de mi club que juega', async function (this: ScenarioWorld) {
  await openFromHome(this, theTeam(this))
})

Given('estoy en el paso 1 de sincronizar el otro equipo', async function (this: ScenarioWorld) {
  const other = this.data.otherTeam!
  this.data.team = other
  await openFromHome(this, other)
})

Given('estoy en el paso 1 de sincronizar un equipo de mi club, con una dirección escrita', async function (this: ScenarioWorld) {
  await openFromHome(this, await teamWithoutCompetition(this))
  this.data.offer = competition(this.random, currentSeason(), theTeam(this))
  await urlField(this).fill(offer(this).calendarUrl)
})

Given('la petición del equipo de mi club inscrito sin competición está retenida', async function (this: ScenarioWorld) {
  // `getTeam`, la que hace la pantalla al abrir (DW-17): sale cuando el escenario acaba.
  this.held = await holdRequest(this.page, `/teams/${theTeam(this).id}`)
})

/** La dirección del equipo en la web: `/equipos/<id>/federacion`. */
const screenPath = (id: string) => `/equipos/${id}/federacion`

When(
  'escribo en el navegador la dirección de la pantalla de sincronizar el equipo de mi club inscrito sin competición',
  async function (this: ScenarioWorld) {
    await this.page.goto(this.clubUrl(screenPath(theTeam(this).id!)))
    await this.page.locator('h1').first().waitFor()
  },
)

When('escribo en el navegador la dirección de la pantalla de sincronizar de un equipo que mi club no tiene', async function (this: ScenarioWorld) {
  await this.page.goto(this.clubUrl(screenPath(crypto.randomUUID())))
  await this.page.locator('h1').first().waitFor()
})

When(
  'escribo en el navegador la dirección de la pantalla de sincronizar de uno de los rivales del equipo de mi club que juega',
  async function (this: ScenarioWorld) {
    const rival = this.random.pick(this.data.competition!.teams.slice(1))
    this.note(`rival: ${rival.rawName}`)
    await this.page.goto(this.clubUrl(screenPath(await rivalTeamId(this.club, rival.code))))
    await this.page.locator('h1').first().waitFor()
  },
)

// ── Lo que tiene la Federación ───────────────────────────────────────────────────────────────────────────────

/** La competición que la Federación tiene para el equipo: la inventa y la sirve. */
function offerFor(world: ScenarioWorld, of: Season, forTeam: Pick<Team, 'category' | 'gender' | 'modality'>, withoutAge = false) {
  const plays = competition(world.random, of, forTeam, withoutAge)
  world.data.offer = plays
  fakeFederation().invent(plays)
  world.note(`la Federación tiene ${plays.displayName} (${plays.season.label})`)
  return plays
}

Given(
  /^la Federación tiene una competición de la temporada en curso para el equipo que se sincroniza(, que tarda en contestar|, que contesta con un error|, sin la edad en su nombre|, con un equipo publicado sin código)?$/,
  async function (this: ScenarioWorld, how?: string) {
    const plays = offerFor(this, currentSeason(), theTeam(this), how === ', sin la edad en su nombre')
    if (how === ', que tarda en contestar') fakeFederation().hold(plays)
    if (how === ', que contesta con un error') fakeFederation().failCalendar(plays)
    // El último del grupo: el del club es el primero.
    if (how === ', con un equipo publicado sin código') plays.teams[3]!.code = ''
  },
)

Given('la Federación tiene una competición de la temporada en curso de otra edad que la del equipo que se sincroniza', async function (this: ScenarioWorld) {
  const mine = theTeam(this)
  const other = this.random.pick(categories.filter((c) => c !== mine.category))
  offerFor(this, currentSeason(), { ...mine, category: other })
})

Given('la Federación tiene una competición para el equipo que se sincroniza de la temporada que viene, que mi club no tiene', async function (this: ScenarioWorld) {
  offerFor(this, nextSeason(), theTeam(this))
})

Given(
  'la Federación tiene una competición para el equipo que se sincroniza de una temporada que mi club no tiene, sin decir cuál es',
  async function (this: ScenarioWorld) {
    const next = nextSeason()
    const plays = competition(this.random, next, theTeam(this))
    // Dos años que no van seguidos: el servidor no lo lee como etiqueta (H-10), y no hay otra.
    plays.calendarSeason = `${next.start}-${next.start + 2}`
    this.data.offer = plays
    fakeFederation().invent(plays)
  },
)

Given('la temporada en curso de mi club ya está sincronizada con un código de la Federación', async function (this: ScenarioWorld) {
  // Un equipo que juega en ella: el enganche le pone a la temporada su código (D-106).
  await addTeamPlaying(this, currentSeason())
})

Given(
  'la Federación tiene una competición para el equipo que se sincroniza con la misma temporada y otro código',
  async function (this: ScenarioWorld) {
    const current = currentSeason()
    offerFor(this, { ...current, federationId: String(Number(current.federationId) + this.random.int(10, 90)) }, theTeam(this))
  },
)

Given('la Federación ya contesta bien a la competición que tiene para el equipo que se sincroniza', async function (this: ScenarioWorld) {
  fakeFederation().answerCalendar(offer(this))
})

Given('la Federación ha quitado del calendario de la competición el equipo elegido en la lista del paso 2', async function (this: ScenarioWorld) {
  // El objeto es el mismo que sirve la federación falsa: cambiarlo es cambiar lo que publica.
  const plays = offer(this)
  plays.teams[0] = { code: String(this.random.int(10_000_000, 19_999_999)), rawName: "OTRO CLUB 'A'" }
})

Given('la primera ingesta de la competición del paso 2 va a tardar', async function (this: ScenarioWorld) {
  // El enganche lee el calendario una vez antes de escribir; la primera ingesta es la segunda petición.
  fakeFederation().hold(offer(this), 1)
})

Given(
  'en la temporada en curso de mi club juega un equipo, en una competición donde el club tiene otro equipo sin sincronizar',
  async function (this: ScenarioWorld) {
    // Dos equipos que solo cambian en la letra: los dos caben en la misma competición (D-110).
    const season = currentSeason()
    const base = inventTeam(this.random, this.data.teams)
    const first = this.random.pick(['A', 'B', 'C', 'D'])
    const second = this.random.pick(['A', 'B', 'C', 'D'].filter((l) => l !== first))
    const withLetter = (letter: string): Team => ({ ...base, id: undefined, letter, name: `${categoryLabels[base.category]} ${letter}` })
    const playing = await addTeam(this.club, season, withLetter(first))
    const other = await addTeam(this.club, season, withLetter(second))
    this.data.teams.push(playing, other)
    const plays = competition(this.random, season, playing)
    await linkTeam(this.club, playing, plays)
    this.data.team = playing
    this.data.competition = plays
    this.data.otherTeam = other
    // La competición que la Federación tiene para el otro es la misma: el que es suyo es el segundo del grupo.
    this.data.offer = plays
    this.note(`${playing.name} juega ${plays.displayName}; ${other.name}, sin sincronizar, es ${plays.teams[1]!.rawName}`)
  },
)

// ── Paso 1 ──────────────────────────────────────────────────────────────────────────────────────────────────

/** Escribe la dirección y pulsa «Comprobar en la Federación». No espera: cada `Then` espera lo suyo. */
async function check(world: ScenarioWorld, address: string) {
  await urlField(world).fill(address)
  await checkButton(world).click()
}

When('compruebo en la Federación la dirección de la competición que tiene para el equipo que se sincroniza', async function (this: ScenarioWorld) {
  await check(this, offer(this).calendarUrl)
})

When('compruebo en la Federación la dirección de la competición en la que juega el equipo que se sincroniza', async function (this: ScenarioWorld) {
  this.data.offer = this.data.competition
  await check(this, offer(this).calendarUrl)
})

When('compruebo en la Federación sin escribir la dirección', async function (this: ScenarioWorld) {
  await checkButton(this).click()
})

When('compruebo en la Federación una dirección que no es la de un calendario', async function (this: ScenarioWorld) {
  // De otra web: el servidor mira el dominio. La página de la clasificación de la RFFM, con los mismos cuatro
  // datos, la acepta, porque lleva al mismo calendario (Anexo RFFM §F.20).
  await check(this, 'https://www.ejemplo.es/competicion/calendario?temporada=22&tipojuego=1&competicion=1&grupo=2')
})

When('compruebo en la Federación la dirección de un calendario que la Federación no tiene', async function (this: ScenarioWorld) {
  const plays = competition(this.random, currentSeason(), theTeam(this))
  // No se inventa: la federación falsa contesta como la RFFM a lo que no tiene, con el calendario a `null`.
  await check(this, plays.calendarUrl)
})

/** Hasta el paso 2 con la dirección de la competición que tiene la Federación. */
async function toStepTwo(world: ScenarioWorld) {
  await check(world, offer(world).calendarUrl)
  await stepTwoHeading(world).waitFor()
}

Given(
  'en el paso 1 de sincronizar un equipo de mi club, la Federación ha respondido con un error al comprobar la competición que tiene para él',
  async function (this: ScenarioWorld) {
    await openFromHome(this, await teamWithoutCompetition(this))
    fakeFederation().failCalendar(offerFor(this, currentSeason(), theTeam(this)))
    await check(this, offer(this).calendarUrl)
    await main(this).getByRole('alert').waitFor()
  },
)

// ── Paso 2 ──────────────────────────────────────────────────────────────────────────────────────────────────

/**
 * El que es del equipo que se sincroniza en la lista: el que se eligió, si ya se eligió (la Federación puede
 * quitarlo después); si no, el primero del grupo, o el segundo si el primero ya juega.
 */
function mineInList(world: ScenarioWorld): string {
  if (world.data.chosen) return world.data.chosen
  const plays = offer(world)
  return world.data.otherTeam && world.data.team === world.data.otherTeam ? plays.teams[1]!.rawName : plays.teams[0]!.rawName
}

async function choose(world: ScenarioWorld) {
  const name = mineInList(world)
  await radio(world, name).check()
  world.data.chosen = name
}

Given(
  /^estoy en el paso 2 de sincronizar un equipo de mi club (con una competición de la temporada en curso|sin competición, con el equipo de la lista que le corresponde ya elegido|con una competición de la temporada que viene, con el equipo de la lista que le corresponde ya elegido)$/,
  async function (this: ScenarioWorld, which: string) {
    const created = await teamWithoutCompetition(this)
    offerFor(this, which.includes('que viene') ? nextSeason() : currentSeason(), created)
    await openFromHome(this, created)
    await toStepTwo(this)
    if (which.includes('ya elegido')) await choose(this)
  },
)

When('elijo en la lista del paso 2 el que es del equipo que se sincroniza', async function (this: ScenarioWorld) {
  await choose(this)
})

/** Pulsa «Sincronizar…»; si lleva a la portada, apunta la competición para esperar su ingesta antes de borrar el club. */
async function pressSync(world: ScenarioWorld) {
  await syncButton(world).click()
  const arrived = await world.page
    .waitForURL((url) => url.pathname === '/', { timeout: 5_000 })
    .then(() => true)
    .catch(() => false)
  if (!arrived) return
  const plays = offer(world)
  const id = await competitionIdByGroup(world.club, plays.season.label, plays.federationGroupId)
  if (id) {
    plays.id = id
    world.data.competition = plays
    world.data.ingesting.push(id)
  }
}

When('pulso el botón {string} del paso {int}', async function (this: ScenarioWorld, name: string, step: number) {
  if (step === 2 && name === 'Sincronizar') return pressSync(this)
  await buttonStarting(this, name).click()
})

When('pulso {string} en el paso {int}', async function (this: ScenarioWorld, name: string, step: number) {
  await inStep(this, step)
  await main(this).getByRole('button', { name, exact: true }).click()
})

Given('he sincronizado desde la portada de mi club un equipo sin competición', async function (this: ScenarioWorld) {
  const created = await teamWithoutCompetition(this)
  offerFor(this, currentSeason(), created)
  await openFromHome(this, created)
  await toStepTwo(this)
  await choose(this)
  await pressSync(this)
})

When(
  'desde la portada, sincronizo el equipo de mi club inscrito sin competición con la competición que la Federación tiene para él, usando solo el teclado',
  async function (this: ScenarioWorld) {
    const mine = theTeam(this)
    await tabTo(this, row(this, mine.name).getByRole('link', { name: 'Sincronizar con la Federación', exact: true }), 'el enlace de la fila')
    await this.page.keyboard.press('Enter')
    await stepOneReady(this)
    await tabTo(this, urlField(this), 'el campo de la dirección')
    await this.page.keyboard.type(offer(this).calendarUrl)
    // Intro en el campo envía el formulario: «Comprobar en la Federación».
    await this.page.keyboard.press('Enter')
    await stepTwoHeading(this).waitFor()
    // Con el tabulador se entra en la lista por su primera opción; con las flechas se cambia de una a otra.
    const target = radio(this, mineInList(this))
    await tabTo(this, teamChoice(this).getByRole('radio').first(), 'la lista de equipos')
    for (let i = 0; i < 10 && !(await target.isChecked()); i++) {
      if (i === 0) await this.page.keyboard.press('Space')
      else await this.page.keyboard.press('ArrowDown')
    }
    if (!(await target.isChecked())) throw new Error('las flechas no llegan al equipo del club')
    await tabTo(this, syncButton(this), 'el botón «Sincronizar…»')
    await this.page.keyboard.press('Enter')
    await this.page.waitForURL((url) => url.pathname === '/')
    const plays = offer(this)
    const id = await competitionIdByGroup(this.club, plays.season.label, plays.federationGroupId)
    if (id) {
      plays.id = id
      this.data.competition = plays
      this.data.ingesting.push(id)
    }
  },
)

// ── Lo que se ve: dónde estoy ────────────────────────────────────────────────────────────────────────────────

async function onStep(world: ScenarioWorld, step: number) {
  const expected = step === 1 ? 'La dirección' : 'Tu equipo'
  await world.check(`el paso ${step}`, () =>
    contains(world.page, async () => (await currentStep(world).textContent()) ?? '', expected, 'el paso en curso'),
  )
  await world.check(`lo del paso ${step}`, () =>
    shows(step === 1 ? urlField(world) : stepTwoHeading(world), step === 1 ? 'el campo de la dirección' : 'el resumen del paso 2'),
  )
}

Then('estoy en el paso {int} de la pantalla de sincronizar', async function (this: ScenarioWorld, step: number) {
  await onStep(this, step)
})

Then('sigo en el paso {int} de la pantalla de sincronizar', async function (this: ScenarioWorld, step: number) {
  await onStep(this, step)
})

Then(
  /^se abre el paso 1 de sincronizar el equipo de mi club (?:inscrito sin competición|que juega)$/,
  async function (this: ScenarioWorld) {
    const mine = theTeam(this)
    await this.check('la dirección', () =>
      becomes(this.page, async () => new URL(this.page.url()).pathname, screenPath(mine.id!), 'el camino'),
    )
    await this.check('el equipo', () => shows(main(this).getByText(new RegExp(`^${mine.name} · `)), `el nombre de ${mine.name}`))
    await onStep(this, 1)
  },
)

Then('la línea de pasos dice que estoy en {string}', async function (this: ScenarioWorld, name: string) {
  await this.check('la línea de pasos', () =>
    contains(this.page, async () => (await currentStep(this).textContent()) ?? '', name, 'el paso en curso'),
  )
})

Then('la pantalla de sincronizar dice el nombre del equipo de mi club inscrito sin competición', async function (this: ScenarioWorld) {
  const mine = theTeam(this)
  const expected = `${mine.name} · ${genderLabels[mine.gender]} · ${modalityLabels[mine.modality]}`
  await this.check('el equipo', () => shows(main(this).getByText(expected, { exact: true }), `«${expected}»`))
})

Then('la pantalla de sincronizar dice {string}', async function (this: ScenarioWorld, text: string) {
  await this.check(`«${text}»`, () => shows(main(this).getByText(text, { exact: true }), `«${text}»`))
})

Then('la pantalla de sincronizar pregunta:', async function (this: ScenarioWorld, table: DataTable) {
  const text = sentences(table)
  await this.check('la pregunta', () =>
    shows(this.page.getByRole('dialog', { name: 'Cambios sin guardar' }).getByText(text, { exact: true }), `«${text}»`),
  )
})

Then('la página dice {string}', async function (this: ScenarioWorld, text: string) {
  await this.check(`«${text}»`, () => shows(main(this).getByText(text, { exact: true }), `«${text}»`))
})

Then('la página tiene un enlace a la portada', async function (this: ScenarioWorld) {
  await this.check('el enlace a la portada', async () => {
    const link = main(this).getByRole('link', { name: 'Ir a la portada' })
    await shows(link, 'el enlace «Ir a la portada»')
    const href = await link.getAttribute('href')
    if (href !== '/') throw new Error(`lleva a «${href}», y no a la portada`)
  })
})

// ── Lo que se ve: el paso 1 ──────────────────────────────────────────────────────────────────────────────────

Then('el campo {string} del paso 1 es obligatorio, con la ayuda:', async function (this: ScenarioWorld, name: string, table: DataTable) {
  const help = sentences(table)
  await this.check(`el campo ${name}`, async () => {
    const field = urlField(this)
    await shows(field, `el campo ${name}`)
    const label = main(this).locator(`label[for="${await field.getAttribute('id')}"]`)
    const visible = (await label.textContent())?.replace(/\s+/g, ' ') ?? ''
    if (!visible.includes('(obligatorio)')) throw new Error(`su etiqueta no dice «obligatorio» al lector: «${visible}»`)
    if ((await label.locator('[aria-hidden="true"]').textContent())?.trim() !== '*') throw new Error('no lleva el asterisco que se ve')
    const said = await description(field)
    if (!said.startsWith(help)) throw new Error(`su ayuda es «${said}», y se esperaba que empezara por «${help}»`)
  })
})

Then('el paso {int} tiene el botón {string}', async function (this: ScenarioWorld, _step: number, name: string) {
  await this.check(`el botón «${name}»`, () => shows(main(this).getByRole('button', { name, exact: true }), `el botón «${name}»`))
})

Then('la lista de errores del paso {int} tiene el foco', async function (this: ScenarioWorld, step: number) {
  await this.check(`la lista de errores del paso ${step}`, () =>
    becomes(this.page, () => errorList(this).evaluate((el) => el === document.activeElement), true, 'el foco en la lista'),
  )
})

Then('la lista de errores del paso {int} nombra {string}', async function (this: ScenarioWorld, _step: number, name: string) {
  await this.check(`«${name}» en la lista de errores`, () =>
    shows(errorList(this).getByRole('link', { name: new RegExp(name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')) }), `el enlace a «${name}»`),
  )
})

Then('el botón del paso {int} dice {string}', async function (this: ScenarioWorld, step: number, text: string) {
  await this.check('el botón', () =>
    becomes(this.page, async () => (await stepButton(this, step).textContent())?.trim(), text, 'el botón'),
  )
})

Then('el botón del paso {int} está bloqueado', async function (this: ScenarioWorld, step: number) {
  await this.check('el botón bloqueado', () => becomes(this.page, () => stepButton(this, step).isDisabled(), true, 'que esté bloqueado'))
})

Then('el campo {string} del paso 1 dice:', async function (this: ScenarioWorld, name: string, table: DataTable) {
  const text = sentences(table)
  await this.check(`el error de ${name}`, () => contains(this.page, () => description(urlField(this)), text, 'lo que se lee junto al campo'))
})

Then('el paso {int} avisa arriba:', async function (this: ScenarioWorld, _step: number, table: DataTable) {
  const text = sentences(table)
  await this.check('el aviso', () => shows(main(this).getByRole('alert').filter({ hasText: text }), `el aviso «${text}»`))
})

Then('el paso {int} ofrece {string}', async function (this: ScenarioWorld, _step: number, name: string) {
  await this.check(`«${name}»`, () => shows(main(this).getByRole('button', { name, exact: true }), `el botón «${name}»`))
})

Then('el paso {int} no ofrece {string}', async function (this: ScenarioWorld, _step: number, name: string) {
  // Cuando llega este paso, el aviso ya está: el anterior lo ha esperado.
  await this.check(`«${name}»`, () => absent(main(this).getByRole('button', { name, exact: true }), `el botón «${name}»`))
})

Then('el campo {string} del paso 1 conserva la dirección de la competición', async function (this: ScenarioWorld, name: string) {
  await this.check(name, () => becomes(this.page, () => urlField(this).inputValue(), offer(this).calendarUrl, `el campo ${name}`))
})

// ── Lo que se ve: el paso 2 ──────────────────────────────────────────────────────────────────────────────────

async function summaryHas(world: ScenarioWorld, term: string, expected: string) {
  await world.check(`${term} en el resumen`, async () => {
    const seen = (await summary(world))[term]
    if (seen !== expected) throw new Error(`dice «${seen}», y se esperaba «${expected}»`)
  })
}

Then('el resumen del paso 2 tiene la división y el grupo de la competición', async function (this: ScenarioWorld) {
  await summaryHas(this, 'Competición', offer(this).rowName)
})

Then('el resumen del paso 2 tiene la edad y la modalidad del equipo que se sincroniza', async function (this: ScenarioWorld) {
  const mine = theTeam(this)
  await summaryHas(this, 'Edad', categoryLabels[mine.category])
  await summaryHas(this, 'Modalidad', modalityLabels[mine.modality])
})

Then('el resumen del paso 2 tiene la temporada en curso', async function (this: ScenarioWorld) {
  await summaryHas(this, 'Temporada', currentSeason().label)
})

Then('el resumen del paso 2 dice que la temporada que viene es nueva', async function (this: ScenarioWorld) {
  await summaryHas(this, 'Temporada', `${nextSeason().label} · nueva`)
})

Then('el paso 2 avisa que la temporada que viene se creará al sincronizar', async function (this: ScenarioWorld) {
  const text = `La temporada ${nextSeason().label} no existe todavía en el club: se creará al sincronizar`
  await this.check('el aviso de la temporada', () => shows(main(this).getByText(text), `«${text}»`))
})

Then('el paso 2 avisa que no cuadra, con la edad del equipo que se sincroniza y la de la competición', async function (this: ScenarioWorld) {
  const text = `Edad: el equipo es ${categoryLabels[theTeam(this).category]} y la competición, ${categoryLabels[offer(this).category]}.`
  await this.check('el aviso de que no cuadra', async () => {
    await shows(main(this).getByText('No cuadra con el equipo.'), '«No cuadra con el equipo.»')
    await shows(main(this).getByText(text, { exact: true }), `«${text}»`)
  })
})

Then(
  'el paso 2 avisa que la Federación no dice la edad de la competición y se usará la del equipo que se sincroniza',
  async function (this: ScenarioWorld) {
    const text = `La Federación no dice la edad de esta competición: se usará la del equipo, ${categoryLabels[theTeam(this).category]}.`
    await this.check('el aviso de la edad', () => shows(main(this).getByText(text), `«${text}»`))
  },
)

Then('el botón {string} del paso 2 está desactivado', async function (this: ScenarioWorld, name: string) {
  await this.check(`«${name}» desactivado`, () => becomes(this.page, () => buttonStarting(this, name).isDisabled(), true, 'que esté desactivado'))
})

Then('el botón {string} del paso 2 está activo', async function (this: ScenarioWorld, name: string) {
  await this.check(`«${name}» activo`, () => becomes(this.page, () => buttonStarting(this, name).isEnabled(), true, 'que esté activo'))
})

Then('la lista de equipos del paso 2 tiene los de la competición, en orden alfabético', async function (this: ScenarioWorld) {
  const spanish = new Intl.Collator('es')
  const expected = offer(this).teams.map((t) => t.rawName).sort(spanish.compare)
  await this.check('la lista de equipos', async () => {
    await shows(teamChoice(this), 'la lista de equipos')
    const seen = (await teamChoice(this).locator('label').allTextContents()).map((t) => t.trim())
    if (seen.join('|') !== expected.join('|')) throw new Error(`es «${seen.join(', ')}», y se esperaba «${expected.join(', ')}»`)
  })
})

Then('la lista de equipos del paso 2 no tiene ninguno elegido', async function (this: ScenarioWorld) {
  await this.check('ninguno elegido', async () => {
    const chosen = await teamChoice(this).getByRole('radio', { checked: true }).count()
    if (chosen > 0) throw new Error(`hay ${chosen} elegido`)
  })
})

Then('la lista de equipos del paso 2 tiene elegido el que es del equipo que se sincroniza', async function (this: ScenarioWorld) {
  const name = mineInList(this)
  await this.check('el elegido', () => becomes(this.page, () => radio(this, name).isChecked(), true, `«${name}» elegido`))
})

Then('el botón del paso 2 dice {string} seguido del nombre elegido en la lista', async function (this: ScenarioWorld, start: string) {
  const expected = `${start} ${mineInList(this)}`
  await this.check('el botón', () => becomes(this.page, async () => (await syncButton(this).textContent())?.trim(), expected, 'el botón'))
})

// En la lista, un equipo: el sin código, el que ya juega o el que se sincroniza.
function listed(world: ScenarioWorld, which: string): string {
  const plays = offer(world)
  if (which === 'el equipo sin código') return plays.teams.find((t) => t.code === '')!.rawName
  if (which === 'el que es del equipo de mi club que ya juega') return plays.teams[0]!.rawName
  if (which === 'el que es del equipo que se sincroniza') return mineInList(world)
  throw new Error(`«${which}» no es un equipo de la lista que el escenario conozca`)
}

const listedTeam = /^en la lista de equipos del paso 2, (el equipo sin código|el que es del equipo de mi club que ya juega|el que es del equipo que se sincroniza)/

Then(new RegExp(`${listedTeam.source} está desactivado$`), async function (this: ScenarioWorld, which: string) {
  const name = listed(this, which)
  await this.check(`«${name}» desactivado`, () => becomes(this.page, () => radio(this, name).isDisabled(), true, 'que esté desactivado'))
})

Then(new RegExp(`${listedTeam.source} dice:$`), async function (this: ScenarioWorld, which: string, table: DataTable) {
  const name = listed(this, which)
  const text = sentences(table)
  await this.check(`el motivo de «${name}»`, () => becomes(this.page, () => description(radio(this, name)), text, 'el motivo'))
})

Then(new RegExp(`${listedTeam.source} dice "([^"]*)"$`), async function (this: ScenarioWorld, which: string, text: string) {
  const name = listed(this, which)
  await this.check(`el motivo de «${name}»`, () => becomes(this.page, () => description(radio(this, name)), text, 'el motivo'))
})

Then(new RegExp(`${listedTeam.source} dice "([^"]*)" y su nombre$`), async function (this: ScenarioWorld, which: string, start: string) {
  const name = listed(this, which)
  // El que ya juega es el otro de los dos que dio de alta el escenario.
  const ownName = this.data.teams.find((t) => t !== this.data.otherTeam)!.name
  await this.check(`el motivo de «${name}»`, async () => {
    const said = await description(radio(this, name))
    if (!said.startsWith(start) || !said.includes(ownName)) throw new Error(`dice «${said}», y se esperaba «${start}» y «${ownName}»`)
  })
})

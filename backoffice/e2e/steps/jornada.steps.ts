// Jornada y clasificación de una competición (plan R4, §3.4; decisión 3): /temporadas/<temporada>/competiciones/<id>
// ?jornada=<número>. Lo que se compara se calcula de la competición que se inventó el escenario (expected.ts).
import { Given, Then, When } from '@cucumber/cucumber'
import {
  currentRound,
  formOf,
  goalDifference,
  matchDay,
  nameIn,
  playedRounds,
  positionsAfter,
  roundLabel,
  roundNumbered,
  rounds,
} from '../support/expected.ts'
import { holdRequest } from '../support/hold-request.ts'
import { currentSeason, standingsAfter, type Round } from '../support/invented.ts'
import { becomes, contains, shows } from '../support/look.ts'
import type { ScenarioWorld } from '../support/world.ts'
import { addTeamThatPlayed, theCompetition } from './ficha.steps.ts'
import { content, inAddress, theTeam } from './portada.steps.ts'

const competitionPath = (id: string) => `/temporadas/${inAddress(currentSeason())}/competiciones/${id}`
const roundPicker = (world: ScenarioWorld) => world.page.getByRole('combobox', { name: 'Jornada' })
const matchesTable = (world: ScenarioWorld) => world.page.getByRole('table', { name: /^Partidos de la jornada / })
const standingTable = (world: ScenarioWorld) => world.page.getByRole('table', { name: /^Clasificación tras la jornada / })

function theRound(world: ScenarioWorld): Round {
  if (world.data.round === undefined) throw new Error('El escenario no ha elegido ninguna jornada')
  return roundNumbered(theCompetition(world), world.data.round)
}

/** Abre la pantalla en una jornada (o sin ella: la última jugada) y espera a que salga. */
async function openCompetition(world: ScenarioWorld, round?: number) {
  world.data.round = round ?? playedRounds(theCompetition(world)).length
  const query = round === undefined ? '' : `?jornada=${round}`
  await world.page.goto(world.clubUrl(`${competitionPath(theCompetition(world).id!)}${query}`))
  await roundShown(world)
}

/** Que la jornada del escenario es la que se enseña: su tabla de partidos ya está. */
async function roundShown(world: ScenarioWorld) {
  await world.page.getByRole('table', { name: `Partidos de la jornada ${world.data.round}` }).waitFor()
}

/** Una jornada jugada, al azar; con `notFirst`, que no sea la primera. */
function aPlayedRound(world: ScenarioWorld, notFirst = false): number {
  const played = playedRounds(theCompetition(world)).filter((r) => !notFirst || r.number > 1)
  const number = world.random.pick(played).number
  world.note(`jornada jugada: ${number}`)
  return number
}

// ── Los datos ────────────────────────────────────────────────────────────────────────────────────────────────

Given('estoy en la pantalla de la competición del equipo de mi club que ha jugado, en una jornada jugada', async function (this: ScenarioWorld) {
  await addTeamThatPlayed(this)
  await openCompetition(this, aPlayedRound(this))
})

Given(
  'estoy en la pantalla de la competición del equipo de mi club que ha jugado, en una jornada jugada que no es la primera',
  async function (this: ScenarioWorld) {
    await addTeamThatPlayed(this)
    await openCompetition(this, aPlayedRound(this, true))
  },
)

Given('estoy en la pantalla de la competición del equipo de mi club que ha jugado, en la jornada en curso', async function (this: ScenarioWorld) {
  await addTeamThatPlayed(this)
  await openCompetition(this, currentRound(theCompetition(this)).number)
})

Given('la petición de las jornadas de la competición del equipo está retenida', async function (this: ScenarioWorld) {
  // `listRounds`, la que trae las jornadas al abrir (DW-17): sale cuando el escenario acaba.
  this.held = await holdRequest(this.page, '/rounds')
})

// ── Lo que se hace ───────────────────────────────────────────────────────────────────────────────────────────

When('abro la pantalla de la competición del equipo, sin jornada', async function (this: ScenarioWorld) {
  this.data.round = playedRounds(theCompetition(this)).length
  await this.page.goto(this.clubUrl(competitionPath(theCompetition(this).id!)))
  await this.page.locator('h1').first().waitFor()
})

When('abro la pantalla de la competición del equipo en una jornada jugada', async function (this: ScenarioWorld) {
  await openCompetition(this, aPlayedRound(this))
})

When('abro la pantalla de la competición del equipo en la última jornada jugada', async function (this: ScenarioWorld) {
  await openCompetition(this, playedRounds(theCompetition(this)).length)
})

When('abro la pantalla de la competición del equipo en la jornada en curso', async function (this: ScenarioWorld) {
  await openCompetition(this, currentRound(theCompetition(this)).number)
})

When('abro la pantalla de la competición del equipo en la primera jornada', async function (this: ScenarioWorld) {
  await openCompetition(this, 1)
})

When('abro la pantalla de la competición del equipo en la última jornada', async function (this: ScenarioWorld) {
  await openCompetition(this, rounds(theCompetition(this)).length)
})

When('escribo en el navegador la dirección de una competición que mi club no tiene', async function (this: ScenarioWorld) {
  await this.page.goto(this.clubUrl(competitionPath(crypto.randomUUID())))
  await this.page.locator('h1').first().waitFor()
})

When('pulso {string} en la pantalla de la competición', async function (this: ScenarioWorld, name: string) {
  const step = name === 'Siguiente' ? 1 : name === 'Anterior' ? -1 : undefined
  if (step === undefined) throw new Error(`La pantalla de la competición no tiene «${name}»`)
  this.data.round = theRound(this).number + step
  await content(this).getByRole('button', { name: new RegExp(name) }).click()
  await roundShown(this)
})

When('elijo una jornada jugada en el selector de jornada', async function (this: ScenarioWorld) {
  const number = aPlayedRound(this)
  this.data.round = number
  await roundPicker(this).click()
  await this.page.getByRole('option', { name: roundLabel(roundNumbered(theCompetition(this), number)), exact: true }).click()
  await this.page.getByRole('listbox').waitFor({ state: 'detached' })
  await roundShown(this)
})

When('recargo la página', async function (this: ScenarioWorld) {
  await this.page.reload()
  await roundShown(this)
})

// ── Lo que se ve ─────────────────────────────────────────────────────────────────────────────────────────────

/** Que la pantalla es la de la competición del equipo, en la jornada del escenario: el camino, `?jornada` y el selector. */
async function onRound(world: ScenarioWorld, withQuery = true) {
  const round = theRound(world)
  await world.check('la dirección', () =>
    becomes(world.page, async () => new URL(world.page.url()).pathname, competitionPath(theCompetition(world).id!), 'el camino'),
  )
  if (withQuery) {
    await world.check('la jornada en la dirección', () =>
      becomes(world.page, async () => new URL(world.page.url()).searchParams.get('jornada'), String(round.number), '?jornada='),
    )
  }
  await world.check('el selector', () => contains(world.page, () => roundPicker(world).innerText(), roundLabel(round), 'el selector'))
}

Then('estoy en la última jornada jugada de la competición del equipo', async function (this: ScenarioWorld) {
  this.data.round = playedRounds(theCompetition(this)).length
  await roundShown(this)
  await onRound(this, false)
})

Then(/^estoy en (?:la jornada (?:siguiente|anterior)|esa jornada) de la competición$/, async function (this: ScenarioWorld) {
  await onRound(this)
})

Then('estoy en la jornada de ese partido, en la pantalla de su competición', async function (this: ScenarioWorld) {
  await roundShown(this)
  await onRound(this)
})

Then('el título de la pantalla de la competición dice su división y su grupo', async function (this: ScenarioWorld) {
  const name = theCompetition(this).rowName
  await this.check('el título', () => shows(this.page.getByRole('heading', { level: 1, name, exact: true }), `el título «${name}»`))
})

Then('el selector de jornada tiene elegida la última jornada jugada, con sus fechas', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  const label = roundLabel(roundNumbered(plays, playedRounds(plays).length))
  await this.check('el selector', () => contains(this.page, () => roundPicker(this).innerText(), label, 'el selector'))
})

Then('la tabla de partidos tiene los de esa jornada, con su fecha, su hora, los dos equipos y el marcador', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  const round = theRound(this)
  const expected = round.matches
    .map((m) => [matchDay(round.date), m.time ?? 'por fijar', nameIn(plays, theTeam(this), m.home), m.score ? `${m.score.home} - ${m.score.away}` : '', nameIn(plays, theTeam(this), m.away)].join(' | '))
    .sort()
  await this.check('los partidos', async () => {
    const rows = await matchesTable(this).locator('tbody tr').all()
    const seen = (await Promise.all(rows.map(async (r) => (await r.getByRole('cell').allInnerTexts()).map((t) => t.trim()).join(' | ')))).sort()
    if (seen.join('\n') !== expected.join('\n')) throw new Error(`son\n${seen.join('\n')}\ny se esperaba\n${expected.join('\n')}`)
  })
})

Then('en la tabla de partidos está resaltado el del equipo de mi club', async function (this: ScenarioWorld) {
  await this.check('el resaltado', async () => {
    const own = matchesTable(this).locator('tbody tr', { hasText: ownTeamName(this) })
    await shows(own, 'el partido del club')
    if (!(await own.getAttribute('class'))?.includes('own')) throw new Error('el partido del club no está resaltado')
    const others = await matchesTable(this).locator('tbody tr.own').count()
    if (others !== 1) throw new Error(`hay ${others} partidos resaltados`)
  })
})

/** La fila de la clasificación de un equipo, por su nombre (la cabecera de la fila). */
const standingRow = (world: ScenarioWorld, name: string) =>
  standingTable(world).getByRole('row').filter({ has: world.page.getByRole('rowheader', { name, exact: true }) })

const ownTeamName = (world: ScenarioWorld) => nameIn(theCompetition(world), theTeam(world), theCompetition(world).teams[0]!)

Then('la clasificación tiene una fila por equipo, en orden de puesto', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  const expected = standingsAfter(plays, theRound(this).number).map((r) => nameIn(plays, theTeam(this), r.team))
  await this.check('el orden', async () => {
    const seen = (await standingTable(this).getByRole('rowheader').allInnerTexts()).map((t) => t.trim())
    if (seen.join(' | ') !== expected.join(' | ')) throw new Error(`es «${seen.join(' | ')}»`)
  })
})

Then(
  'cada fila de la clasificación tiene los jugados, ganados, empatados, perdidos, goles a favor y en contra, diferencia y puntos de la Federación',
  async function (this: ScenarioWorld) {
    const plays = theCompetition(this)
    for (const row of standingsAfter(plays, theRound(this).number)) {
      const name = nameIn(plays, theTeam(this), row.team)
      const expected = [row.played, row.won, row.drawn, row.lost, row.goalsFor, row.goalsAgainst, goalDifference(row.goalsFor - row.goalsAgainst), row.points].map(String)
      await this.check(name, async () => {
        // Las celdas: Pos., (el equipo es la cabecera), J, G, E, P, GF, GC, DG, Pts, Ant., Racha.
        const cells = (await standingRow(this, name).getByRole('cell').allInnerTexts()).map((t) => t.trim())
        const seen = cells.slice(1, 9)
        if (seen.join(' ') !== expected.join(' ')) throw new Error(`dice «${seen.join(' ')}», y la Federación «${expected.join(' ')}»`)
      })
    }
  },
)

Then('cada fila de la clasificación tiene el puesto de la jornada anterior', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  const before = positionsAfter(plays, theRound(this).number - 1)
  for (const row of standingsAfter(plays, theRound(this).number)) {
    const name = nameIn(plays, theTeam(this), row.team)
    const previous = before.get(row.team.code)
    await this.check(name, async () => {
      const cell = (await standingRow(this, name).getByRole('cell').allInnerTexts())[9]!.trim()
      // El puesto anterior va delante; detrás, la flecha. Sin puesto anterior, «–».
      const ok = previous === undefined ? cell === '–' : cell.startsWith(String(previous)) && !/^\d/.test(cell.slice(String(previous).length))
      if (!ok) throw new Error(`dice «${cell}», y se esperaba ${previous ?? '«–»'}`)
    })
  }
})

Then('en la clasificación está resaltada la fila del equipo de mi club', async function (this: ScenarioWorld) {
  await this.check('el resaltado', async () => {
    const own = standingRow(this, ownTeamName(this))
    await shows(own, 'la fila del club')
    if (!(await own.getAttribute('class'))?.includes('own')) throw new Error('la fila del club no está resaltada')
    const count = await standingTable(this).locator('tbody tr.own').count()
    if (count !== 1) throw new Error(`hay ${count} filas resaltadas`)
  })
})

/** La racha de un equipo como la escribe la web, cuadro a cuadro: el número que se ve y lo que oye el lector. */
async function formIn(world: ScenarioWorld, name: string) {
  const boxes = await standingRow(world, name).getByRole('listitem').all()
  return Promise.all(
    boxes.map(async (box) => ({
      seen: (await box.locator('[aria-hidden="true"]').innerText()).trim(),
      heard: (await box.locator('.visually-hidden').innerText()).trim(),
      title: await box.getAttribute('title'),
    })),
  )
}

Then('la racha de cada equipo tiene sus últimos partidos, hasta cinco, del más reciente al más antiguo', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  for (const team of plays.teams) {
    const name = nameIn(plays, theTeam(this), team)
    const expected = formOf(plays, team.code, theRound(this).number).map((f) => String(f.round))
    await this.check(`la racha de ${name}`, async () => {
      const seen = (await formIn(this, name)).map((b) => b.seen)
      if (seen.join(' ') !== expected.join(' ')) throw new Error(`es «${seen.join(' ')}», y se esperaba «${expected.join(' ')}»`)
    })
  }
})

Then('cada partido de la racha dice el número de su jornada', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  for (const team of plays.teams) {
    const name = nameIn(plays, theTeam(this), team)
    await this.check(`los números de ${name}`, async () => {
      const boxes = await formIn(this, name)
      if (boxes.some((b) => !/^\d+$/.test(b.seen))) throw new Error(`hay cuadros sin número: «${boxes.map((b) => b.seen).join(' ')}»`)
    })
  }
})

Then('cada partido de la racha dice al lector si fue victoria, empate o derrota, y en qué jornada', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  for (const team of plays.teams) {
    const name = nameIn(plays, theTeam(this), team)
    const expected = formOf(plays, team.code, theRound(this).number).map((f) => `${f.outcome} en la jornada ${f.round}`)
    await this.check(`lo que oye el lector de ${name}`, async () => {
      const boxes = await formIn(this, name)
      const heard = boxes.map((b) => b.heard)
      if (heard.join(' | ') !== expected.join(' | ')) throw new Error(`oye «${heard.join(' | ')}», y se esperaba «${expected.join(' | ')}»`)
      // Y lo mismo al pasar el ratón.
      if (boxes.some((b) => b.title !== b.heard)) throw new Error('al pasar el ratón no dice lo mismo')
    })
  }
})

Then('la pantalla de la competición dice {string}', async function (this: ScenarioWorld, text: string) {
  await this.check(`«${text}»`, () => shows(content(this).getByText(text, { exact: true }), `«${text}»`))
})

Then(/^el botón "(Anterior|Siguiente)" de la pantalla de la competición está (bloqueado|activo)$/, async function (this: ScenarioWorld, name: string, state: string) {
  await this.check(`«${name}» ${state}`, () =>
    becomes(this.page, () => content(this).getByRole('button', { name: new RegExp(name) }).isDisabled(), state === 'bloqueado', `«${name}» bloqueado`),
  )
})

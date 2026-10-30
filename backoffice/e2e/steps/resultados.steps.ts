// La pestaña Resultados de la ficha del equipo (plan R4, §3.3; decisiones 1, 2 y 6). Lo que se compara se calcula
// de la competición que se inventó el escenario (expected.ts), no se lee de la web.
import { Given, Then, When } from '@cucumber/cucumber'
import { expectApi } from '../support/club-api.ts'
import { addTeamWithoutCompetition } from '../support/club-data.ts'
import {
  currentRound,
  goalDifference,
  matchDay,
  nameIn,
  ownFixture,
  ownName,
  playedRounds,
  positionsAfter,
  rivalName,
  roundNumbered,
  rounds,
} from '../support/expected.ts'
import { fakeFederation } from '../support/fake-federation.ts'
import { competition, currentSeason, standingsAfter, type Round } from '../support/invented.ts'
import { becomes, shows } from '../support/look.ts'
import type { ScenarioWorld } from '../support/world.ts'
import { theCompetition } from './ficha.steps.ts'
import { theTeam } from './portada.steps.ts'

const tab = (world: ScenarioWorld) => world.page.getByRole('region', { name: 'Resultados' })
const table = (world: ScenarioWorld) => tab(world).getByRole('table')
/** La fila de una jornada: la que tiene su número en la primera celda (en otras puede haber el mismo número). */
const rowOf = (world: ScenarioWorld, number: number) =>
  table(world).locator('tbody tr').filter({ has: world.page.locator('td:first-child', { hasText: new RegExp(`^\\s*${number}\\s*$`) }) })
/** Los textos de las celdas de una fila, sin espacios de más. */
const cellsOf = async (world: ScenarioWorld, number: number) =>
  (await rowOf(world, number).getByRole('cell').allInnerTexts()).map((t) => t.replace(/\s+/g, ' ').trim())

function theRound(world: ScenarioWorld): Round {
  if (world.data.round === undefined) throw new Error('El escenario no ha elegido ningún partido')
  return roundNumbered(theCompetition(world), world.data.round)
}

/** Las celdas de la fila, por su columna: J, Fecha, Local, Resultado, Visitante, V/E/D, Pos., Pts, G, E, P, DG. */
const column = { round: 0, date: 1, home: 2, result: 3, away: 4, outcome: 5, position: 6, points: 7, won: 8, drawn: 9, lost: 10, difference: 11 }

// ── Los datos ────────────────────────────────────────────────────────────────────────────────────────────────

Given(
  'en la temporada en curso de mi club juega un equipo recién sincronizado, con su primera ingesta retenida en la Federación',
  async function (this: ScenarioWorld) {
    const team = await addTeamWithoutCompetition(this.club, this.random, currentSeason(), this.data.teams)
    this.data.teams.push(team)
    this.data.team = team
    const plays = competition(this.random, currentSeason(), team)
    fakeFederation().invent(plays)
    // El enganche lee el calendario una vez y la primera ingesta otra: se retiene la segunda.
    fakeFederation().hold(plays, 1)
    const { competitionId } = await expectApi<{ competitionId: string }>(
      this.club,
      'POST',
      `/teams/${team.id}/federation-link`,
      { federationCalendarUrl: plays.calendarUrl, ownTeamFederationId: plays.teams[0]!.code, gender: team.gender },
      202,
    )
    plays.id = competitionId
    this.data.competition = plays
    this.data.ingesting.push(competitionId)
    await fakeFederation().heldArrived(plays)
    this.note(`${team.name} recién sincronizado con ${plays.displayName}, la primera ingesta retenida`)
  },
)

// ── Lo que se hace ───────────────────────────────────────────────────────────────────────────────────────────

When('miro en la tabla de resultados un partido jugado', async function (this: ScenarioWorld) {
  this.data.round = this.random.pick(playedRounds(theCompetition(this))).number
  this.note(`partido jugado: jornada ${this.data.round}`)
  await rowOf(this, this.data.round).waitFor()
})

When('miro en la tabla de resultados un partido por jugar con hora', async function (this: ScenarioWorld) {
  // La jornada en curso es la única por jugar con hora (`playedCompetition`).
  this.data.round = currentRound(theCompetition(this)).number
  await rowOf(this, this.data.round).waitFor()
})

When('miro en la tabla de resultados un partido por jugar sin hora', async function (this: ScenarioWorld) {
  const later = rounds(theCompetition(this)).filter((r) => r.number > currentRound(theCompetition(this)).number)
  this.data.round = this.random.pick(later).number
  this.note(`partido sin hora: jornada ${this.data.round}`)
  await rowOf(this, this.data.round).waitFor()
})

When('pulso el icono {string} de un partido jugado', async function (this: ScenarioWorld, name: string) {
  this.data.round = this.random.pick(playedRounds(theCompetition(this))).number
  this.note(`☰ de la jornada ${this.data.round}`)
  // El texto lleva el número de la jornada: «Ver la jornada 3 y la clasificación».
  await rowOf(this, this.data.round).getByRole('link', { name: name.replace('la jornada', `la jornada ${this.data.round}`) }).click()
})

// ── Lo que se ve ─────────────────────────────────────────────────────────────────────────────────────────────

Then('la tabla de resultados tiene un partido por cada jornada en la que juega el equipo', async function (this: ScenarioWorld) {
  // Sin calendario propio, la federación falsa sirve tres jornadas sin jugar (fake-federation.ts).
  const expected = theCompetition(this).schedule?.length ?? 3
  // Hasta 12 s: si la ingesta acaba de soltarse, la tabla sale en el refresco siguiente (cada 10 s).
  await this.check('las filas', async () => {
    await table(this).waitFor({ timeout: 12_000 })
    await becomes(this.page, async () => (await table(this).getByRole('row').count()) - 1, expected, 'el número de partidos')
  })
})

Then('la tabla de resultados está en orden de jornada', async function (this: ScenarioWorld) {
  const expected = rounds(theCompetition(this)).map((r) => String(r.number)).join(' ')
  await this.check('el orden', async () => {
    const numbers = await table(this).locator('tbody tr td:first-child').allInnerTexts()
    const seen = numbers.map((n) => n.trim()).join(' ')
    if (seen !== expected) throw new Error(`las jornadas van «${seen}»`)
  })
})

Then('el partido tiene su jornada, su fecha y los dos equipos', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  const round = theRound(this)
  const fixture = ownFixture(plays, round)
  const cells = await cellsOf(this, round.number)
  const expected = {
    jornada: String(round.number),
    fecha: matchDay(round.date),
    local: nameIn(plays, theTeam(this), fixture.home),
    visitante: nameIn(plays, theTeam(this), fixture.away),
  }
  await this.check('la jornada', async () => equal(cells[column.round], expected.jornada, 'la jornada'))
  await this.check('la fecha', async () => equal(cells[column.date], expected.fecha, 'la fecha'))
  // Junto al nombre puede ir su puesto, en su óvalo: el nombre va al final de la celda.
  await this.check('el local', async () => endsWith(cells[column.home], expected.local, 'el local'))
  await this.check('el visitante', async () => endsWith(cells[column.away], expected.visitante, 'el visitante'))
})

Then('el partido tiene el marcador de la Federación', async function (this: ScenarioWorld) {
  const { score } = ownFixture(theCompetition(this), theRound(this))
  const cells = await cellsOf(this, theRound(this).number)
  await this.check('el marcador', async () => equal(cells[column.result], `${score!.home} - ${score!.away}`, 'el marcador'))
})

Then('el partido tiene la letra del resultado del equipo: V, E o D', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  const fixture = ownFixture(plays, theRound(this))
  const ownHome = fixture.home.code === plays.teams[0]!.code
  const [mine, theirs] = ownHome ? [fixture.score!.home, fixture.score!.away] : [fixture.score!.away, fixture.score!.home]
  const letter = mine > theirs ? 'V' : mine < theirs ? 'D' : 'E'
  const cells = await cellsOf(this, theRound(this).number)
  await this.check('la letra', async () => equal(cells[column.outcome], letter, 'la letra'))
})

Then(
  'el partido tiene el puesto, los puntos, los ganados, empatados y perdidos, y la diferencia de goles del equipo tras esa jornada',
  async function (this: ScenarioWorld) {
    const plays = theCompetition(this)
    const own = standingsAfter(plays, theRound(this).number).find((r) => r.team.code === plays.teams[0]!.code)!
    const cells = await cellsOf(this, theRound(this).number)
    const expected: [keyof typeof column, string][] = [
      ['position', `${own.position}º`],
      ['points', String(own.points)],
      ['won', String(own.won)],
      ['drawn', String(own.drawn)],
      ['lost', String(own.lost)],
      ['difference', goalDifference(own.goalsFor - own.goalsAgainst)],
    ]
    for (const [name, value] of expected) await this.check(name, async () => equal(cells[column[name]], value, name))
  },
)

/** El puesto que va en el óvalo de cada equipo del partido: el de la tabla de `after`, o ninguno. */
async function badgesAre(world: ScenarioWorld, after: number) {
  const plays = theCompetition(world)
  const round = theRound(world)
  const fixture = ownFixture(plays, round)
  const positions = positionsAfter(plays, after)
  const cells = await cellsOf(world, round.number)
  for (const [side, of] of [['local', fixture.home], ['visitante', fixture.away]] as const) {
    const position = positions.get(of.code)
    const name = nameIn(plays, theTeam(world), of)
    const expected = position ? `${position}º ${name}` : name
    await world.check(`el puesto del ${side}`, async () => equal(cells[side === 'local' ? column.home : column.away], expected, side))
  }
}

Then('cada equipo del partido tiene a su lado el puesto con el que llegó, el de la jornada anterior', async function (this: ScenarioWorld) {
  await badgesAre(this, theRound(this).number - 1)
})

Then('cada equipo del partido tiene a su lado su puesto de hoy', async function (this: ScenarioWorld) {
  await badgesAre(this, playedRounds(theCompetition(this)).length)
})

Then('el partido tiene la hora en lugar del marcador', async function (this: ScenarioWorld) {
  const time = ownFixture(theCompetition(this), theRound(this)).time!
  const cells = await cellsOf(this, theRound(this).number)
  await this.check('la hora', async () => equal(cells[column.result], time, 'el resultado'))
})

Then('el partido no tiene la línea del equipo', async function (this: ScenarioWorld) {
  const cells = await cellsOf(this, theRound(this).number)
  await this.check('la línea', async () => {
    // Sin la letra ni la línea: la celda de la letra y una sola celda vacía que ocupa las seis de la línea.
    const after = cells.slice(column.outcome, -1).filter(Boolean)
    if (after.length > 0) throw new Error(`tiene «${after.join(' | ')}»`)
  })
})

Then('el partido dice {string} en lugar del marcador', async function (this: ScenarioWorld, text: string) {
  const cells = await cellsOf(this, theRound(this).number)
  await this.check(`«${text}»`, async () => equal(cells[column.result], text, 'el resultado'))
})

Then('en la tabla de resultados, el equipo de mi club se llama con el nombre de mi club, no el corto, y su letra', async function (this: ScenarioWorld) {
  const name = ownName(theTeam(this))
  await this.check('el nombre del club', () => shows(table(this).getByText(name, { exact: true }), `«${name}»`))
})

Then('en la tabla de resultados, cada rival se llama con el nombre de su club y su letra', async function (this: ScenarioWorld) {
  for (const rival of theCompetition(this).teams.slice(1)) {
    const name = rivalName(rival)
    await this.check(`«${name}»`, () => shows(table(this).getByText(name, { exact: true }), `«${name}»`))
  }
})

Then('la pestaña Resultados dice {string}', async function (this: ScenarioWorld, text: string) {
  await this.check(`«${text}»`, () => shows(tab(this).getByText(text, { exact: true }), `«${text}» en la pestaña`))
})

Then('la pestaña Resultados tiene el enlace {string}', async function (this: ScenarioWorld, name: string) {
  await this.check(`el enlace «${name}»`, () => shows(tab(this).getByRole('link', { name, exact: true }), `«${name}» en la pestaña`))
})

function equal(seen: string | undefined, expected: string, what: string) {
  if (seen !== expected) throw new Error(`${what} dice «${seen}», y se esperaba «${expected}»`)
}

function endsWith(seen: string | undefined, expected: string, what: string) {
  if (!seen?.endsWith(expected)) throw new Error(`${what} dice «${seen}», y se esperaba que acabara en «${expected}»`)
}

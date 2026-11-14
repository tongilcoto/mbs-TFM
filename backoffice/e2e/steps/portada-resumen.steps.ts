// El resumen de cada equipo en la portada (plan R5, §3; decisiones 2, 3, 5 y 6): la posición, la racha, el último
// partido y el próximo. Lo que se compara se calcula de la competición que se inventó el escenario (expected.ts), no
// se lee de la web.
import { Given, Then, When } from '@cucumber/cucumber'
import type { Locator } from 'playwright'
import { expectApi } from '../support/club-api.ts'
import { addTeam, addTeamWithoutCompetition, linkTeam } from '../support/club-data.ts'
import {
  currentRound,
  matchDay,
  nameIn,
  ownFixture,
  ownRestRound,
  playedRounds,
  positionsAfter,
  rounds,
  streakLabel,
  streakOf,
} from '../support/expected.ts'
import { fakeFederation } from '../support/fake-federation.ts'
import { currentSeason, playedCompetition, standingsAfter, team, type Competition, type Round } from '../support/invented.ts'
import { becomes, shows } from '../support/look.ts'
import type { ScenarioWorld } from '../support/world.ts'
import { addTeamThatPlayed, theCompetition } from './ficha.steps.ts'
import { content, inAddress, row, theTeam } from './portada.steps.ts'

// ── Lo que se calcula ────────────────────────────────────────────────────────────────────────────────────────

const own = (plays: Competition) => plays.teams[0]!.code

/** La última jornada jugada (sin ninguna, 0). */
const lastPlayed = (plays: Competition) => playedRounds(plays).length

/** El puesto del club tras la última jornada jugada. */
function ownPosition(plays: Competition): number | undefined {
  return standingsAfter(plays, lastPlayed(plays)).find((r) => r.team.code === own(plays))?.position
}

/** El último partido jugado del club, sin contar el descanso. */
function lastMatchRound(plays: Competition): Round | undefined {
  return playedRounds(plays)
    .filter((round) => !ownFixture(plays, round).rest)
    .at(-1)
}

/** La jornada del próximo partido del club: la siguiente a la última jugada (`playedCompetition`). */
function nextRound(plays: Competition): Round | undefined {
  return rounds(plays)[lastPlayed(plays)]
}

/** Las piezas de un partido en la fila, como las escribe la web: casa o fuera, el puesto del rival y su nombre. */
function sides(world: ScenarioWorld, plays: Competition, round: Round) {
  const fixture = ownFixture(plays, round)
  const atHome = fixture.home.code === own(plays)
  const rival = atHome ? fixture.away : fixture.home
  return { fixture, atHome, rival, rivalName: nameIn(plays, theTeam(world), rival), venue: atHome ? 'En casa' : 'Fuera' }
}

/** El último, como lo escribe la web: «V En casa 3 - 1 2º C.D. LAS ROZAS A». */
function expectedLast(world: ScenarioWorld, plays: Competition, round: Round): string {
  const { fixture, atHome, rival, rivalName, venue } = sides(world, plays, round)
  const [mine, theirs] = atHome ? [fixture.score!.home, fixture.score!.away] : [fixture.score!.away, fixture.score!.home]
  const letter = mine > theirs ? 'V' : mine < theirs ? 'D' : 'E'
  // Con el que llegó: el de la jornada anterior; en la primera, ninguno.
  const arrived = positionsAfter(plays, round.number - 1).get(rival.code)
  return [letter, venue, `${fixture.score!.home} - ${fixture.score!.away}`, arrived ? `${arrived}º` : '', rivalName].filter(Boolean).join(' ')
}

/** El próximo, como lo escribe la web: «Sáb 21 nov 16:45 Fuera 3º C.D. LAS ROZAS A», o «… , hora por fijar …». */
function expectedNext(world: ScenarioWorld, plays: Competition, round: Round): string {
  const { fixture, rival, rivalName, venue } = sides(world, plays, round)
  if (fixture.rest) return `Descansa · jornada ${round.number}`
  const when = fixture.time ? `${matchDay(round.date)} ${fixture.time}` : `${matchDay(round.date)}, hora por fijar`
  // El de hoy: el de la última clasificación.
  const today = positionsAfter(plays, lastPlayed(plays)).get(rival.code)
  return [when, venue, today ? `${today}º` : '', rivalName].filter(Boolean).join(' ')
}

// ── Lo que se lee ────────────────────────────────────────────────────────────────────────────────────────────

const teamRow = (world: ScenarioWorld) => row(world, theTeam(world).name)

/** El texto de una celda, trozo a trozo y separado por un espacio, como lo lee el lector. */
function words(locator: Locator): Promise<string> {
  return locator.evaluate((element) => {
    const walker = document.createTreeWalker(element, NodeFilter.SHOW_TEXT)
    const pieces: string[] = []
    while (walker.nextNode()) pieces.push(walker.currentNode.textContent!.trim())
    return pieces.filter(Boolean).join(' ')
  })
}

/** La celda de la fila del equipo bajo una cabecera, o nada si la fila no la tiene (sin competición). */
async function cellUnder(world: ScenarioWorld, header: 'Posición' | 'Racha' | 'Último' | 'Próximo'): Promise<Locator | undefined> {
  const headers = (await content(world).locator('thead th').allTextContents()).map((text) => text.trim())
  const index = headers.findIndex((text) => text.startsWith(header))
  if (index < 0) throw new Error(`la tabla de la portada no tiene la columna «${header}»`)
  const cells = teamRow(world).locator('th, td')
  // Sin competición, «Sin competición» ocupa las columnas de la competición: la fila tiene menos celdas.
  if ((await cells.count()) < headers.length) return undefined
  return cells.nth(index)
}

/** Lo que dice una celda; «–» si está vacía, y nada si la fila no la tiene. */
async function cellText(world: ScenarioWorld, header: 'Posición' | 'Racha' | 'Último' | 'Próximo'): Promise<string | undefined> {
  await teamRow(world).waitFor()
  const cell = await cellUnder(world, header)
  return cell ? words(cell) : undefined
}

/** La racha de la fila, cuadro a cuadro: el número que se ve, lo que oye el lector y si es el cuadro vacío. */
async function streakIn(world: ScenarioWorld) {
  await teamRow(world).waitFor()
  const cell = await cellUnder(world, 'Racha')
  if (!cell) return []
  const boxes = await cell.getByRole('listitem').all()
  return Promise.all(
    boxes.map(async (box) => ({
      seen: (await box.locator('[aria-hidden="true"]').first().innerText()).trim(),
      heard: (await box.locator('.visually-hidden').first().innerText()).trim(),
      empty: ((await box.getAttribute('class')) ?? '').includes('descanso'),
    })),
  )
}

/** Comprueba que una celda dice lo esperado, dándole tiempo a cargar. */
function cellSays(world: ScenarioWorld, header: 'Posición' | 'Racha' | 'Último' | 'Próximo', expected: string) {
  return world.check(`«${header}»`, () => becomes(world.page, async () => (await cellText(world, header)) ?? '(sin celda)', expected, `«${header}»`))
}

// ── Los datos ────────────────────────────────────────────────────────────────────────────────────────────────

Given('en la temporada en curso de mi club juega un equipo que descansó en una de las jornadas jugadas', async function (this: ScenarioWorld) {
  await addTeamThatPlayed(this, { ownRests: 'played' })
  this.note(`descansó en la jornada ${ownRestRound(theCompetition(this))?.number}`)
})

Given('en la temporada en curso de mi club juega un equipo que descansó en la última jornada jugada', async function (this: ScenarioWorld) {
  await addTeamThatPlayed(this, { ownRests: 'lastPlayed' })
})

Given('en la temporada en curso de mi club juega un equipo que descansa en la próxima jornada', async function (this: ScenarioWorld) {
  await addTeamThatPlayed(this, { ownRests: 'next' })
})

Given('en la temporada en curso de mi club juega un equipo cuyo próximo partido no tiene hora', async function (this: ScenarioWorld) {
  await addTeamThatPlayed(this, { nextWithoutTime: true })
})

Given('en la temporada en curso de mi club juega un equipo en una competición con todas las jornadas jugadas', async function (this: ScenarioWorld) {
  await addTeamThatPlayed(this, { allPlayed: true })
})

Given('en la temporada en curso de mi club juega un equipo en una competición sin jornadas jugadas', async function (this: ScenarioWorld) {
  // Un calendario como el de `playedCompetition`, sin ningún marcador: así se sabe cuál es la primera jornada, con
  // su fecha y su hora. Se quitan antes de engancharla, para que la ingesta no los vea nunca.
  const invented = team(this.random, this.data.teams)
  const plays = playedCompetition(this.random, currentSeason(), invented)
  plays.schedule = plays.schedule!.map((round) => ({
    ...round,
    matches: round.matches.map((fixture) => ({ home: fixture.home, away: fixture.away, time: fixture.time, rest: fixture.rest })),
  }))
  const added = await addTeam(this.club, currentSeason(), invented)
  await linkTeam(this.club, added, plays)
  this.data.teams.push(added)
  this.data.team = added
  this.data.competition = plays
  this.note(`${added.name} juega ${plays.displayName}, sin jornadas jugadas`)
})

Given('estoy en la portada de mi club, con un equipo que ha jugado', async function (this: ScenarioWorld) {
  await addTeamThatPlayed(this)
  await this.page.goto(this.clubUrl())
  await teamRow(this).waitFor()
})

Given(
  'en la temporada en curso de mi club juegan tres equipos con jornadas jugadas, en puestos distintos, y uno sin competición',
  async function (this: ScenarioWorld) {
    // Con marcadores al azar, dos pueden acabar en el mismo puesto: se inventa otra hasta que no (plan R5, §6).
    const placed: { team: Awaited<ReturnType<typeof addTeam>>; position: number }[] = []
    while (placed.length < 3) {
      const invented = team(this.random, this.data.teams)
      const plays = playedCompetition(this.random, currentSeason(), invented)
      const position = standingsAfter(plays, playedRounds(plays).length).find((r) => r.team.code === plays.teams[0]!.code)!.position
      if (placed.some((p) => p.position === position)) continue
      const added = await addTeam(this.club, currentSeason(), invented)
      await linkTeam(this.club, added, plays)
      this.data.teams.push(added)
      placed.push({ team: added, position })
      this.note(`${added.name}: ${position}º en ${plays.displayName}`)
    }
    const unplaced = await addTeamWithoutCompetition(this.club, this.random, currentSeason(), this.data.teams)
    this.data.teams.push(unplaced)
    this.data.placed = placed
    this.data.unplaced = unplaced
    this.note(`${unplaced.name}, sin competición`)
  },
)

Given(
  'en la temporada en curso de mi club juega un equipo recién sincronizado en una competición con jornadas jugadas, con su primera ingesta retenida en la Federación',
  async function (this: ScenarioWorld) {
    const added = await addTeamWithoutCompetition(this.club, this.random, currentSeason(), this.data.teams)
    this.data.teams.push(added)
    this.data.team = added
    const plays = playedCompetition(this.random, currentSeason(), added)
    fakeFederation().invent(plays)
    // El enganche lee el calendario una vez y la primera ingesta otra: se retiene la segunda.
    fakeFederation().hold(plays, 1)
    const { competitionId } = await expectApi<{ competitionId: string }>(
      this.club,
      'POST',
      `/teams/${added.id}/federation-link`,
      { federationCalendarUrl: plays.calendarUrl, ownTeamFederationId: plays.teams[0]!.code, gender: added.gender },
      202,
    )
    plays.id = competitionId
    this.data.competition = plays
    this.data.ingesting.push(competitionId)
    await fakeFederation().heldArrived(plays)
    this.note(`${added.name} recién sincronizado con ${plays.displayName}, la primera ingesta retenida`)
  },
)

// ── Lo que se hace ───────────────────────────────────────────────────────────────────────────────────────────

When('pulso en la portada un cuadro de la racha del equipo', async function (this: ScenarioWorld) {
  const cell = (await cellUnder(this, 'Racha'))!
  const links = await cell.getByRole('link').all()
  const chosen = this.random.pick(links)
  const name = (await chosen.locator('.visually-hidden').innerText()).trim()
  this.data.round = Number(/jornada (\d+)$/.exec(name)![1])
  this.note(`cuadro de la racha: ${name}`)
  await chosen.click()
})

When('pulso en la portada el próximo partido del equipo', async function (this: ScenarioWorld) {
  this.data.round = nextRound(theCompetition(this))!.number
  await (await cellUnder(this, 'Próximo'))!.getByRole('link').click()
})

// ── Lo que se ve ─────────────────────────────────────────────────────────────────────────────────────────────

Then('la posición del equipo en la portada es su puesto tras la última jornada jugada', async function (this: ScenarioWorld) {
  await cellSays(this, 'Posición', `${ownPosition(theCompetition(this))}º`)
})

Then('la racha del equipo en la portada tiene un cuadro por cada jornada jugada, hasta cinco', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  const expected = Math.min(5, lastPlayed(plays))
  await this.check('cuántos cuadros', () => becomes(this.page, async () => (await streakIn(this)).length, expected, 'el número de cuadros'))
})

Then('la racha del equipo en la portada va de la jornada más reciente a la más antigua', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  const expected = streakOf(plays, own(plays), lastPlayed(plays)).map((e) => String(e.round)).join(' ')
  await this.check('el orden de la racha', () =>
    becomes(this.page, async () => (await streakIn(this)).map((b) => b.seen).join(' '), expected, 'la racha'),
  )
})

Then('cada cuadro de la racha del equipo en la portada dice el número de su jornada', async function (this: ScenarioWorld) {
  await this.check('los números', async () => {
    const boxes = await streakIn(this)
    if (boxes.length === 0 || boxes.some((b) => !/^\d+$/.test(b.seen))) throw new Error(`hay cuadros sin número: «${boxes.map((b) => b.seen).join(' ')}»`)
  })
})

Then(
  'cada cuadro de la racha del equipo en la portada dice al lector si fue victoria, empate o derrota, y en qué jornada',
  async function (this: ScenarioWorld) {
    const plays = theCompetition(this)
    const expected = streakOf(plays, own(plays), lastPlayed(plays)).map(streakLabel).join(' | ')
    await this.check('lo que oye el lector', () =>
      becomes(this.page, async () => (await streakIn(this)).map((b) => b.heard).join(' | '), expected, 'lo que oye el lector'),
    )
  },
)

Then('la racha del equipo en la portada tiene un cuadro vacío en la jornada en la que descansó', async function (this: ScenarioWorld) {
  const rest = ownRestRound(theCompetition(this))!.number
  await this.check('el cuadro vacío', () =>
    becomes(this.page, async () => (await streakIn(this)).filter((b) => b.empty).map((b) => b.seen).join(' '), String(rest), 'los cuadros vacíos'),
  )
})

Then(
  'el cuadro vacío de la racha del equipo en la portada dice al lector {string} y su número',
  async function (this: ScenarioWorld, text: string) {
    const rest = ownRestRound(theCompetition(this))!.number
    await this.check('lo que oye el lector en el cuadro vacío', () =>
      becomes(this.page, async () => (await streakIn(this)).find((b) => b.empty)?.heard ?? '(ninguno)', `${text} ${rest}`, 'el cuadro vacío'),
    )
  },
)

Then('el último partido del equipo en la portada es el de la última jornada jugada', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  await cellSays(this, 'Último', expectedLast(this, plays, lastMatchRound(plays)!))
})

Then('el último partido tiene la letra del resultado del equipo: V, E o D', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  const letter = expectedLast(this, plays, lastMatchRound(plays)!).split(' ')[0]!
  await this.check('la letra', async () => {
    const cell = (await cellUnder(this, 'Último'))!
    await shows(cell.locator('abbr', { hasText: letter }), `la letra «${letter}»`)
  })
})

Then('el último partido dice si el equipo jugó en casa o fuera', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  const { venue } = sides(this, plays, lastMatchRound(plays)!)
  await this.check('casa o fuera', async () => shows((await cellUnder(this, 'Último'))!.getByText(venue, { exact: true }), `«${venue}»`))
})

Then('el último partido tiene el marcador de la Federación, el local primero', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  const { score } = ownFixture(plays, lastMatchRound(plays)!)
  const text = `${score!.home} - ${score!.away}`
  await this.check('el marcador', async () => shows((await cellUnder(this, 'Último'))!.getByText(text, { exact: true }), `«${text}»`))
})

Then('el último partido tiene el rival, con el nombre de su club y su letra', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  const { rivalName } = sides(this, plays, lastMatchRound(plays)!)
  await this.check('el rival', async () => shows((await cellUnder(this, 'Último'))!.getByText(rivalName, { exact: true }), `«${rivalName}»`))
})

Then(
  'el último partido tiene a la izquierda del rival el puesto con el que llegó, el de la jornada anterior',
  async function (this: ScenarioWorld) {
    const plays = theCompetition(this)
    // Todo el texto en orden: el puesto, justo antes del nombre (o nada, si el último fue la primera jornada).
    await cellSays(this, 'Último', expectedLast(this, plays, lastMatchRound(plays)!))
  },
)

Then('el último partido del equipo en la portada es el de la jornada anterior a la del descanso', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  const before = rounds(plays)[lastPlayed(plays) - 2]!
  await cellSays(this, 'Último', expectedLast(this, plays, before))
})

Then('el próximo partido del equipo en la portada es el de la jornada en curso', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  await cellSays(this, 'Próximo', expectedNext(this, plays, currentRound(plays)))
})

Then('el próximo partido tiene el día de la semana, la fecha y la hora', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  const round = currentRound(plays)
  const text = `${matchDay(round.date)} ${ownFixture(plays, round).time}`
  await this.check('el día y la hora', async () => shows((await cellUnder(this, 'Próximo'))!.getByText(text, { exact: true }), `«${text}»`))
})

Then('el próximo partido dice si el equipo juega en casa o fuera', async function (this: ScenarioWorld) {
  const { venue } = sides(this, theCompetition(this), currentRound(theCompetition(this)))
  await this.check('casa o fuera', async () => shows((await cellUnder(this, 'Próximo'))!.getByText(venue, { exact: true }), `«${venue}»`))
})

Then('el próximo partido tiene el rival, con el nombre de su club y su letra', async function (this: ScenarioWorld) {
  const { rivalName } = sides(this, theCompetition(this), currentRound(theCompetition(this)))
  await this.check('el rival', async () => shows((await cellUnder(this, 'Próximo'))!.getByText(rivalName, { exact: true }), `«${rivalName}»`))
})

Then('el próximo partido tiene a la izquierda del rival su puesto de hoy', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  await cellSays(this, 'Próximo', expectedNext(this, plays, currentRound(plays)))
})

Then('el próximo partido del equipo en la portada dice {string}', async function (this: ScenarioWorld, text: string) {
  await this.check(`«${text}»`, () =>
    becomes(this.page, async () => ((await cellText(this, 'Próximo')) ?? '').includes(text), true, `que el próximo diga «${text}»`),
  )
})

Then('el próximo partido del equipo en la portada dice que descansa, y en qué jornada', async function (this: ScenarioWorld) {
  await cellSays(this, 'Próximo', `Descansa · jornada ${currentRound(theCompetition(this)).number}`)
})

Then('la fila del equipo en la portada no tiene posición, racha, último partido ni próximo partido', async function (this: ScenarioWorld) {
  await teamRow(this).waitFor()
  await this.check('las cuatro columnas', async () => {
    for (const header of ['Posición', 'Racha', 'Último', 'Próximo'] as const) {
      const seen = await cellText(this, header)
      if (seen !== undefined && seen !== '–') throw new Error(`«${header}» dice «${seen}»`)
    }
  })
})

Then('la fila del equipo en la portada no tiene posición, racha ni último partido', async function (this: ScenarioWorld) {
  for (const header of ['Posición', 'Racha', 'Último'] as const) await cellSays(this, header, '–')
})

Then('la fila del equipo en la portada tiene el próximo partido, el de la primera jornada', async function (this: ScenarioWorld) {
  await cellSays(this, 'Próximo', expectedNext(this, theCompetition(this), rounds(theCompetition(this))[0]!))
})

Then('la fila del equipo en la portada tiene el último partido, el de la última jornada', async function (this: ScenarioWorld) {
  const plays = theCompetition(this)
  await cellSays(this, 'Último', expectedLast(this, plays, rounds(plays).at(-1)!))
})

Then('la fila del equipo en la portada no tiene próximo partido', async function (this: ScenarioWorld) {
  await cellSays(this, 'Próximo', '–')
})

/** Que la pantalla es la de la competición del equipo, en la jornada del escenario. */
async function onTheRound(world: ScenarioWorld) {
  const path = `/temporadas/${inAddress(currentSeason())}/competiciones/${theCompetition(world).id}`
  await world.check('la dirección', () =>
    becomes(world.page, async () => {
      const url = new URL(world.page.url())
      return `${url.pathname}?${url.searchParams}`
    }, `${path}?jornada=${world.data.round}`, 'la dirección'),
  )
  await world.check('la jornada', () =>
    shows(world.page.getByRole('table', { name: `Partidos de la jornada ${world.data.round}` }), `los partidos de la jornada ${world.data.round}`),
  )
}

Then('estoy en la jornada de ese cuadro, en la pantalla de la competición del equipo', async function (this: ScenarioWorld) {
  await onTheRound(this)
})

Then('estoy en la jornada del próximo partido, en la pantalla de la competición del equipo', async function (this: ScenarioWorld) {
  await onTheRound(this)
})

Then('la tabla de la portada tiene los equipos de mejor a peor puesto', async function (this: ScenarioWorld) {
  const expected = [...this.data.placed!].sort((a, b) => a.position - b.position).map((p) => p.team.name)
  await this.check('el orden', () =>
    becomes(
      this.page,
      async () => (await content(this).getByRole('rowheader').allTextContents()).map((t) => t.trim()).slice(0, 3).join(' | '),
      expected.join(' | '),
      'los tres primeros',
    ),
  )
})

Then('la tabla de la portada tiene al final el equipo sin puesto', async function (this: ScenarioWorld) {
  await this.check('el último', () =>
    becomes(this.page, async () => (await content(this).getByRole('rowheader').allTextContents()).map((t) => t.trim()).at(-1), this.data.unplaced!.name, 'el último'),
  )
})

// La pestaña Plantilla de la ficha del equipo (plan R6, §3; decisiones 5, 7 y 8). Los jugadores se inventan al azar
// y se dan de alta por la API (players.ts); lo que se compara se lee de lo inventado. El dorsal, la demarcación y la
// foto son de la fila de esa temporada; el nombre y el año, de su perfil (D-119).
import { Given, Then, When } from '@cucumber/cucumber'
import { addPlayingTeam, addTeamWithoutCompetition, linkTeam, moveRowToSeason, seasonIdOf } from '../support/club-data.ts'
import { fakeFederation } from '../support/fake-federation.ts'
import {
  competition,
  currentSeason,
  federationPlayerCode,
  futureSeason,
  inventedPerson,
  pastSeason,
  published,
  type InventedPerson,
  type Season,
} from '../support/invented.ts'
import { absent, becomes, contains, shows } from '../support/look.ts'
import {
  addPlayer,
  addRowOfProfile,
  freeShirtNumber,
  initialsOf,
  pathOf,
  positionNames,
  positions,
  rosterOf,
  shownName,
  syncRoster,
  type PlayerShape,
  type ScenarioPlayer,
} from '../support/players.ts'
import type { ScenarioWorld } from '../support/world.ts'
import { theCompetition } from './ficha.steps.ts'
import { inAddress, lastPastSeason, theTeam } from './portada.steps.ts'

// ── Dónde está cada cosa ─────────────────────────────────────────────────────────────────────────────────────

/** La pestaña Plantilla: una zona con su nombre. */
export const rosterTab = (world: ScenarioWorld) => world.page.getByRole('region', { name: 'Plantilla' })
/** La tabla de la plantilla. */
export const rosterTable = (world: ScenarioWorld) => rosterTab(world).getByRole('table')
const bodyRows = (world: ScenarioWorld) => rosterTable(world).locator('tbody tr')
/** La fila de un jugador: la que tiene su nombre como enlace. */
export const rowOfPlayer = (world: ScenarioWorld, player: Pick<ScenarioPlayer, 'fullName'>) =>
  bodyRows(world).filter({ has: world.page.getByRole('link', { name: shownName(player.fullName), exact: true }) })
/** Las celdas de la fila, por su columna: la foto, el dorsal, el nombre, la demarcación, el año y las acciones. */
const column = { photo: 0, shirtNumber: 1, name: 2, position: 3, birthYear: 4 }
export const cellOf = (world: ScenarioWorld, player: Pick<ScenarioPlayer, 'fullName'>, which: keyof typeof column) =>
  rowOfPlayer(world, player).locator('td').nth(column[which])
export const textOf = async (world: ScenarioWorld, player: Pick<ScenarioPlayer, 'fullName'>, which: keyof typeof column) =>
  (await cellOf(world, player, which).innerText()).replace(/\s+/g, ' ').trim()

/** La pestaña Plantilla del equipo en una temporada: `/temporadas/2026-27/equipos/<id>/plantilla`. */
export const rosterPath = (season: Season, teamId: string) => `/temporadas/${inAddress(season)}/equipos/${teamId}/plantilla`
/** La ficha de un jugador en una temporada (plan R6, decisión 6). */
export const playerPath = (season: Season, playerId: string) => `/temporadas/${inAddress(season)}/jugadores/${playerId}`

export function thePlayer(world: ScenarioWorld): ScenarioPlayer {
  if (!world.data.player) throw new Error('El escenario no ha elegido ningún jugador')
  return world.data.player
}

/** Los jugadores del equipo del escenario en una temporada. */
export const playersIn = (world: ScenarioWorld, season: Season) =>
  world.data.players.filter((player) => player.team.id === theTeam(world).id && player.season.label === season.label)

/** Abre la pestaña y espera a que acabe de cargar: la tabla, o el aviso de que no hay jugadores. */
export async function openRoster(world: ScenarioWorld, season: Season) {
  await world.page.goto(world.clubUrl(rosterPath(season, theTeam(world).id!)))
  await rosterLoaded(world)
}

export async function rosterLoaded(world: ScenarioWorld) {
  try {
    await rosterTab(world).waitFor({ timeout: 8_000 })
    await rosterTab(world).getByText('Cargando jugadores…').waitFor({ state: 'detached', timeout: 8_000 })
  } catch {
    const seen = (await world.page.getByRole('main').innerText()).replace(/\s+/g, ' ').slice(0, 300)
    throw new Error(`no sale la pestaña Plantilla en ${world.page.url()}: «${seen}»`)
  }
}

// ── Los datos ────────────────────────────────────────────────────────────────────────────────────────────────

/**
 * Un equipo del club inscrito en la temporada. En la en curso, enganchado a una competición de la Federación: los
 * escenarios dan el enganche por hecho, y sin él no se ofrece sincronizar (R6.16). En una futura no se sincroniza, así
 * que basta con inscribirlo.
 */
export async function addRosterTeam(world: ScenarioWorld, season: Season = currentSeason()) {
  if (season.label === currentSeason().label) {
    const { team, competition: plays } = await addPlayingTeam(world.club, world.random, season, world.data.teams)
    world.data.competition = plays
    world.data.teams.push(team)
    world.data.team = team
    world.note(`${team.name} (${team.gender}, ${team.modality}) en ${season.label}, enganchado a ${plays.displayName}`)
    return team
  }
  const team = await addTeamWithoutCompetition(world.club, world.random, season, world.data.teams)
  world.data.teams.push(team)
  world.data.team = team
  world.note(`${team.name} (${team.gender}, ${team.modality}) en ${season.label}`)
  return team
}

/** Inscribe al equipo del escenario en otra temporada, enganchándolo a una competición de esa temporada (D-102). */
async function registerIn(world: ScenarioWorld, season: Season) {
  await linkTeam(world.club, theTeam(world), competition(world.random, season, theTeam(world)))
}

/** Un jugador ya inventado como persona, para no repetir su nombre. */
const asPerson = (player: ScenarioPlayer): InventedPerson => ({ given: player.fullName, surnames: '' })

/** Da de alta a un jugador en la plantilla del equipo del escenario, y lo apunta. */
export async function addOne(world: ScenarioWorld, season: Season, shape: PlayerShape = {}) {
  const player = await addPlayer(world.club, world.random, theTeam(world), season, world.data.players, shape)
  world.data.players.push(player)
  world.note(
    `${player.fullName} en ${season.label}: dorsal ${player.shirtNumber ?? '—'}, ${player.position ?? 'sin demarcación'}, ` +
      `${player.birthYear ?? 'sin año'}${player.photoPath ? ', con foto' : ''}`,
  )
  return player
}

/** De 2 a 5 jugadores, al azar, en la plantilla del equipo. */
export async function addSome(world: ScenarioWorld, season: Season) {
  const count = world.random.int(2, 5)
  for (let i = 0; i < count; i++) await addOne(world, season)
}

/**
 * Jugadores en la plantilla de una temporada pasada (decisión 1 de R6.18): dados de alta en la temporada en curso,
 * y su fila, movida a la pasada. Así el perfil y la foto salen por la aplicación.
 */
async function addSomeInPast(world: ScenarioWorld, past: Season) {
  const before = world.data.players.length
  await addSome(world, currentSeason())
  for (const player of world.data.players.slice(before)) {
    await moveRowToSeason(world.club, player.id, past)
    player.season = past
  }
}

/** Una temporada pasada del club, nueva, con el equipo del escenario inscrito en ella. */
async function pastWithTeam(world: ScenarioWorld): Promise<Season> {
  const past = pastSeason(world.random, world.data.pastSeasons)
  world.data.pastSeasons.push(past)
  await registerIn(world, past)
  world.note(`y en ${past.label}`)
  return past
}

Given('un equipo de mi club tiene jugadores en la plantilla de la temporada en curso', async function (this: ScenarioWorld) {
  await addRosterTeam(this)
  await addSome(this, currentSeason())
})

Given(
  'un equipo de mi club tiene jugadores en la plantilla de la temporada en curso y en una temporada pasada',
  async function (this: ScenarioWorld) {
    await addRosterTeam(this)
    const past = await pastWithTeam(this)
    await addSome(this, currentSeason())
    await addSomeInPast(this, past)
  },
)

Given('un equipo de mi club tiene jugadores en la plantilla de una temporada pasada', async function (this: ScenarioWorld) {
  await addRosterTeam(this)
  await addSomeInPast(this, await pastWithTeam(this))
})

Given('un equipo de mi club tiene jugadores en la plantilla de una temporada futura', async function (this: ScenarioWorld) {
  const future = futureSeason(this.random)
  this.data.futureSeason = future
  // En una temporada futura sí se escribe (decisión 4 de R6.14): el equipo, inscrito en ella, y sus jugadores.
  await addRosterTeam(this, future)
  await addSome(this, future)
})

Given('un equipo de mi club sin jugadores en la plantilla de la temporada en curso', async function (this: ScenarioWorld) {
  await addRosterTeam(this)
})

Given(
  'un equipo de mi club tiene en la plantilla de la temporada en curso jugadores con dorsal y jugadores sin dorsal',
  async function (this: ScenarioWorld) {
    await addRosterTeam(this)
    const season = currentSeason()
    const withNumber = this.random.int(2, 4)
    const without = this.random.int(2, 4)
    for (let i = 0; i < withNumber; i++) {
      await addOne(this, season, { shirtNumber: freeShirtNumber(this.random, playersIn(this, season)) })
    }
    for (let i = 0; i < without; i++) await addOne(this, season, { shirtNumber: null })
  },
)

/** El jugador del escenario, entre otros de 1 a 3 de la misma plantilla, en un sitio al azar. */
export async function addThePlayer(world: ScenarioWorld, shape: PlayerShape) {
  await addRosterTeam(world)
  const season = currentSeason()
  const others = world.random.int(1, 3)
  const at = world.random.int(0, others)
  for (let i = 0; i <= others; i++) {
    if (i === at) world.data.player = await addOne(world, season, shape)
    else await addOne(world, season)
  }
}

Given(
  'un equipo de mi club tiene en la plantilla de la temporada en curso un jugador con dorsal, demarcación y foto en la plantilla, distintos de los de su perfil, y con año en su perfil',
  async function (this: ScenarioWorld) {
    const position = this.random.pick(positions)
    await addThePlayer(this, { shirtNumber: this.random.int(1, 50), position, photo: 'foto-a.jpg' })
    // El perfil guarda lo de la última fila guardada (D-122): otra fila suya, en otro equipo de una temporada futura,
    // con otro dorsal, otra demarcación y otra foto, se los cambia. La fila de la temporada en curso se queda con
    // los suyos.
    const player = thePlayer(this)
    const future = futureSeason(this.random)
    const other = await addTeamWithoutCompetition(this.club, this.random, future, this.data.teams)
    this.data.teams.push(other)
    const later = await addRowOfProfile(this.club, player, other, future, {
      shirtNumber: player.shirtNumber! + this.random.int(1, 49),
      position: this.random.pick(positions.filter((p) => p !== position)),
      photo: 'foto-b.jpg',
    })
    this.note(`su perfil, desde ${other.name} en ${future.label}: dorsal ${later.shirtNumber}, ${later.position}, otra foto`)
  },
)

Given(
  'un equipo de mi club tiene en la plantilla de la temporada en curso un jugador sin dorsal ni demarcación en la plantilla',
  async function (this: ScenarioWorld) {
    await addThePlayer(this, { shirtNumber: null, position: null })
  },
)

Given(
  'un equipo de mi club tiene en la plantilla de la temporada en curso un jugador sin año en su perfil',
  async function (this: ScenarioWorld) {
    // Solo la sincronización deja un perfil sin año (D-120): el alta a mano lo pide. El equipo, enganchado a una
    // competición de la temporada en curso, y la Federación publica al jugador en su ficha de equipo.
    await addRosterTeam(this)
    const season = currentSeason()
    await addSome(this, season)
    const plays = theCompetition(this)
    const person = inventedPerson(this.random, this.data.players.map(asPerson))
    fakeFederation().publishRoster(plays, [{ code: federationPlayerCode(this.random), published: published(person) }])
    await syncRoster(this.club, theTeam(this), season)
    // Como lo guardó la sincronización: con las tildes del diccionario (D-123).
    const listed = await rosterOf(this.club, theTeam(this), await seasonIdOf(this.club, season))
    // Un nulo puede llegar como clave ausente (DW-21).
    const synced = listed.find((row) => row.birthYear == null)
    if (!synced) throw new Error(`La sincronización no ha dado de alta a ${published(person)}`)
    this.data.player = {
      id: synced.id,
      profileId: synced.profileId,
      fullName: synced.fullName,
      birthYear: null,
      shirtNumber: synced.shirtNumber ?? null,
      position: synced.position ?? null,
      team: theTeam(this),
      season,
    }
    this.data.players.push(this.data.player)
    this.note(`${published(person)}, publicado por la Federación y guardado como ${synced.fullName}`)
  },
)

Given(
  'un equipo de mi club tiene en la plantilla de la temporada en curso un jugador con un apellido con partícula y otro con guion',
  async function (this: ScenarioWorld) {
    const withParticle = this.random.pick(['DE LA FUENTE', 'DEL RÍO', 'DE LOS SANTOS', 'DE LAS HERAS'])
    const withHyphen = this.random.pick(['GARCÍA-PATIÑO', 'LÓPEZ-ARANDA', 'RUIZ-GIMÉNEZ'])
    const person = inventedPerson(this.random)
    const surnames = this.random.chance(0.5) ? `${withParticle} ${withHyphen}` : `${withHyphen} ${withParticle}`
    await addThePlayer(this, { person: { given: person.given, surnames } })
  },
)

Given(
  'un equipo de mi club tiene en la plantilla de la temporada en curso un jugador sin foto en la plantilla',
  async function (this: ScenarioWorld) {
    await addThePlayer(this, {})
  },
)

Given(
  'un equipo de mi club tiene en la plantilla de la temporada en curso un jugador con foto en la plantilla',
  async function (this: ScenarioWorld) {
    await addThePlayer(this, { photo: this.random.pick(['foto-a.jpg', 'foto-b.jpg'] as const) })
  },
)

// ── Lo que se hace ───────────────────────────────────────────────────────────────────────────────────────────

When('pulso la pestaña {string} de la ficha', async function (this: ScenarioWorld, name: string) {
  await this.page.getByRole('navigation', { name: 'Secciones del equipo' }).getByRole('link', { name, exact: true }).click()
  await rosterLoaded(this)
})

/** La temporada de la que habla el paso: «en curso», «futura» o «pasada». */
function seasonNamed(world: ScenarioWorld, which: string): Season {
  if (which === 'en curso') return currentSeason()
  if (which === 'futura') {
    if (!world.data.futureSeason) throw new Error('El escenario no tiene temporada futura')
    return world.data.futureSeason
  }
  return lastPastSeason(world)
}

Given(
  /^(?:estoy en|abro) la pestaña Plantilla de la ficha del equipo, en la temporada (en curso|futura|pasada)$/,
  async function (this: ScenarioWorld, which: string) {
    await openRoster(this, seasonNamed(this, which))
  },
)

When('cambio la ficha a la temporada pasada', async function (this: ScenarioWorld) {
  await this.page.getByRole('main').getByRole('combobox', { name: 'Temporada' }).click()
  await this.page.getByRole('option', { name: lastPastSeason(this).label, exact: true }).click()
  await rosterTab(this).getByRole('table', { name: new RegExp(lastPastSeason(this).label) }).waitFor()
})

When('pulso el nombre de un jugador de la plantilla', async function (this: ScenarioWorld) {
  const player = this.random.pick(playersIn(this, currentSeason()))
  this.data.player = player
  this.note(`el jugador: ${player.fullName}`)
  await rowOfPlayer(this, player).getByRole('link', { name: shownName(player.fullName), exact: true }).click()
})

// ── Lo que se ve ─────────────────────────────────────────────────────────────────────────────────────────────

/** Los nombres de las filas, en el orden de la tabla: la celda del nombre de cada una. */
export async function shownNames(world: ScenarioWorld): Promise<string[]> {
  const rows = await bodyRows(world).all()
  const names: string[] = []
  for (const row of rows) names.push((await row.locator('td').nth(column.name).getByRole('link').innerText()).trim())
  return names
}

Then(
  /^la plantilla tiene a los jugadores del equipo en (la temporada en curso|la temporada pasada|esa temporada)$/,
  async function (this: ScenarioWorld, which: string) {
    const season =
      which === 'la temporada en curso' ? currentSeason() : which === 'la temporada pasada' ? lastPastSeason(this) : seasonOfScenario(this)
    const expected = playersIn(this, season).map((p) => shownName(p.fullName)).sort().join(' · ')
    await this.check('los jugadores', () =>
      becomes(this.page, async () => (await shownNames(this)).sort().join(' · '), expected, 'los nombres de la plantilla'),
    )
    await this.check('la temporada', () =>
      shows(rosterTab(this).getByRole('table', { name: new RegExp(season.label) }), `la plantilla de ${season.label}`),
    )
  },
)

/** «Esa temporada»: la única en la que el escenario ha dado de alta jugadores. */
function seasonOfScenario(world: ScenarioWorld): Season {
  const labels = [...new Set(world.data.players.map((p) => p.season.label))]
  if (labels.length !== 1) throw new Error(`El escenario tiene jugadores en ${labels.length} temporadas`)
  return world.data.players[0]!.season
}

const spanish = new Intl.Collator('es-ES')

Then('la plantilla tiene primero a los jugadores con dorsal, del más bajo al más alto', async function (this: ScenarioWorld) {
  const withNumber = playersIn(this, currentSeason())
    .filter((p) => p.shirtNumber != null)
    .sort((a, b) => a.shirtNumber! - b.shirtNumber!)
  const expected = withNumber.map((p) => shownName(p.fullName)).join(' · ')
  await this.check('los de dorsal', () =>
    becomes(this.page, async () => (await shownNames(this)).slice(0, withNumber.length).join(' · '), expected, 'los primeros de la plantilla'),
  )
})

Then('la plantilla tiene después a los jugadores sin dorsal, por orden de nombre', async function (this: ScenarioWorld) {
  const players = playersIn(this, currentSeason())
  const without = players.filter((p) => p.shirtNumber == null).sort((a, b) => spanish.compare(a.fullName, b.fullName))
  const expected = without.map((p) => shownName(p.fullName)).join(' · ')
  const skip = players.length - without.length
  await this.check('los sin dorsal', () =>
    becomes(this.page, async () => (await shownNames(this)).slice(skip).join(' · '), expected, 'los últimos de la plantilla'),
  )
})

async function cellIs(world: ScenarioWorld, which: keyof typeof column, expected: string, what: string) {
  await world.check(what, () => becomes(world.page, () => textOf(world, thePlayer(world), which), expected, what))
}

Then('la fila del jugador tiene el dorsal de la plantilla', async function (this: ScenarioWorld) {
  await cellIs(this, 'shirtNumber', String(thePlayer(this).shirtNumber), 'el dorsal')
})

Then('la fila del jugador tiene el nombre de su perfil como «Nombre Apellidos»', async function (this: ScenarioWorld) {
  await cellIs(this, 'name', shownName(thePlayer(this).fullName), 'el nombre')
})

Then('la fila del jugador tiene la demarcación de la plantilla', async function (this: ScenarioWorld) {
  await cellIs(this, 'position', positionNames[thePlayer(this).position!], 'la demarcación')
})

Then('la fila del jugador tiene el año de su perfil', async function (this: ScenarioWorld) {
  await cellIs(this, 'birthYear', String(thePlayer(this).birthYear), 'el año')
})

Then('la fila del jugador tiene una raya en el dorsal', async function (this: ScenarioWorld) {
  await cellIs(this, 'shirtNumber', '—', 'el dorsal')
})

Then('la fila del jugador tiene una raya en la demarcación', async function (this: ScenarioWorld) {
  await cellIs(this, 'position', '—', 'la demarcación')
})

Then('la fila del jugador dice {string} en el año de nacimiento', async function (this: ScenarioWorld, text: string) {
  await cellIs(this, 'birthYear', text, 'el año')
})

Then('la fila del jugador tiene la partícula de su apellido en minúscula', async function (this: ScenarioWorld) {
  const particle = thePlayer(this).fullName.match(/ (DE LA|DE LOS|DE LAS|DEL) /)![1]!.toLocaleLowerCase('es-ES')
  await this.check('la partícula', () =>
    contains(this.page, () => textOf(this, thePlayer(this), 'name'), ` ${particle} `, 'el nombre'),
  )
})

Then('la fila del jugador tiene en mayúscula la letra que sigue al guion', async function (this: ScenarioWorld) {
  await this.check('tras el guion', async () => {
    const name = await textOf(this, thePlayer(this), 'name')
    const after = name.match(/-(\p{L})/u)?.[1]
    if (!after) throw new Error(`el nombre «${name}» no tiene guion`)
    if (after !== after.toLocaleUpperCase('es-ES')) throw new Error(`en «${name}», tras el guion va «${after}», en minúscula`)
  })
})

Then('la fila del jugador tiene las iniciales de su nombre en el sitio de la foto', async function (this: ScenarioWorld) {
  await cellIs(this, 'photo', initialsOf(thePlayer(this).fullName), 'el sitio de la foto')
})

/** La foto de la fila, si la tiene. */
const photoOf = (world: ScenarioWorld) => cellOf(world, thePlayer(world), 'photo').getByRole('img')
/** La foto de la fila de un jugador, si la tiene. */
export const rowPhoto = (world: ScenarioWorld, player: Pick<ScenarioPlayer, 'fullName'>) => cellOf(world, player, 'photo').getByRole('img')

Then('la fila del jugador tiene la foto de la plantilla', async function (this: ScenarioWorld) {
  const expected = thePlayer(this).photoPath!
  await this.check('la foto', () =>
    becomes(this.page, async () => {
      const src = (await photoOf(this).count()) > 0 ? await photoOf(this).getAttribute('src') : null
      return src ? pathOf(src) : 'ninguna'
    }, expected, 'la foto'),
  )
  // Que se ve: si no cargara, la web pondría las iniciales en su lugar.
  await this.check('que la foto carga', () =>
    becomes(this.page, () => photoOf(this).evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth > 0), true, 'la foto cargada'),
  )
  // Y que se ve entera: un círculo de 40 × 40. Un estilo de la tabla la dejó una vez en 16 de ancho (R6.21).
  await this.check('el tamaño de la foto', () =>
    becomes(this.page, () => photoOf(this).evaluate((img: HTMLImageElement) => {
      const box = img.getBoundingClientRect()
      return `${Math.round(box.width)} × ${Math.round(box.height)}`
    }), '40 × 40', 'el tamaño de la foto'),
  )
})

Then('la foto de la fila del jugador dice al lector su nombre', async function (this: ScenarioWorld) {
  await this.check('el texto de la foto', () =>
    becomes(this.page, async () => (await photoOf(this).getAttribute('alt')) ?? '', shownName(thePlayer(this).fullName), 'el texto de la foto'),
  )
})

Then('cada fila de la plantilla tiene la acción {string}', async function (this: ScenarioWorld, action: string) {
  await shows(bodyRows(this), 'ninguna fila')
  for (const name of await shownNames(this)) {
    await this.check(`«${action}» de ${name}`, () =>
      shows(rosterTable(this).getByRole('button', { name: `${action}, ${name}`, exact: true }), `«${action}» en la fila de ${name}`),
    )
  }
})

Then('las filas de la plantilla no tienen acciones', async function (this: ScenarioWorld) {
  await shows(bodyRows(this), 'ninguna fila')
  await this.check('las acciones', () => absent(rosterTable(this).getByRole('button'), 'una acción en las filas'))
})

Then('estoy en la ficha de ese jugador, en la temporada en curso', async function (this: ScenarioWorld) {
  const player = thePlayer(this)
  await this.check('la dirección', () =>
    becomes(this.page, async () => new URL(this.page.url()).pathname, playerPath(currentSeason(), player.id), 'el camino'),
  )
  await this.check('el jugador', () =>
    shows(this.page.getByRole('heading', { level: 1, name: shownName(player.fullName), exact: true }), `el título «${shownName(player.fullName)}»`),
  )
})

Then('la pestaña Plantilla dice {string} y la temporada en curso', async function (this: ScenarioWorld, text: string) {
  await this.check('el aviso', () => shows(rosterTab(this).getByText(`${text} ${currentSeason().label}`), `«${text} ${currentSeason().label}»`))
})

Then('la pestaña Plantilla tiene el botón {string}', async function (this: ScenarioWorld, name: string) {
  await this.check(`«${name}»`, () => shows(rosterTab(this).getByRole('button', { name, exact: true }), `el botón «${name}»`))
})

Then('la pestaña Plantilla no tiene el botón {string}', async function (this: ScenarioWorld, name: string) {
  await shows(bodyRows(this), 'ninguna fila')
  await this.check(`sin «${name}»`, () => absent(rosterTab(this).getByRole('button', { name, exact: true }), `el botón «${name}»`))
})

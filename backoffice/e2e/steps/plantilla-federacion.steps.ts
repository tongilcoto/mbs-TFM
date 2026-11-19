// «Sincronizar con la Federación» en la plantilla (plan R6, decisión 9 y parte D; D-120, D-121, D-122 y D-123). La
// federación falsa publica la ficha de equipo de la RFFM; sus jugadores se inventan al azar y, como en la de verdad,
// la mayoría sin tildes ni eñes (decisión 3 de R6.18): el servidor se las pone con su diccionario, así que lo guardado
// es el nombre como se inventó. Los datos del club se dan de alta por la API (players.ts); «el perfil del jugador»
// se lee con el buscador por la API (alta-jugador.steps.ts).
import { After, Given, Then, When } from '@cucumber/cucumber'
import { expectApi } from '../support/club-api.ts'
import { addTeamWithoutCompetition, moveRowToSeason, seasonIdOf } from '../support/club-data.ts'
import { fakeFederation } from '../support/fake-federation.ts'
import {
  asTheRFFM,
  currentSeason,
  federationPlayerCode,
  fullName,
  futureSeason,
  invalidFederationName,
  inventedPerson,
  published,
  sameNameKey,
  withoutAnyMark,
  type InvalidName,
  type InventedPerson,
  type NameMark,
} from '../support/invented.ts'
import { absent, becomes, contains, shows } from '../support/look.ts'
import {
  addPlayer,
  birthYearFor,
  freeShirtNumber,
  pathOf,
  positionNames,
  positions,
  rosterOf,
  searchProfiles,
  shownName,
  syncRoster,
  teamDisplayName,
  type Position,
  type ScenarioPlayer,
} from '../support/players.ts'
import type { PublishedPlayer, ScenarioWorld, SyncData } from '../support/world.ts'
import { openTeamRoster, profileOf } from './alta-jugador.steps.ts'
import { theCompetition } from './ficha.steps.ts'
import { addPastSeason, lastPastSeason, theTeam } from './portada.steps.ts'
import { addOne, addRosterTeam, addSome, playerPath, playersIn, rosterTab, rowOfPlayer, rowPhoto, shownNames, textOf } from './plantilla.steps.ts'

// ── Dónde está cada cosa ─────────────────────────────────────────────────────────────────────────────────────

const syncButton = (world: ScenarioWorld) => rosterTab(world).getByRole('button', { name: /^Sincroniza/ })
/** La caja del resumen: está en una zona que el lector lee al llenarse, con su título «Sincronizada con la Federación». */
const summaryBox = (world: ScenarioWorld) => rosterTab(world).getByRole('status').filter({ hasText: 'Sincronizada con la Federación' })
const failureBox = (world: ScenarioWorld) => rosterTab(world).getByRole('alert')
const summaryText = async (world: ScenarioWorld) => (await summaryBox(world).innerText()).replace(/\s+/g, ' ')

// ── Los datos ────────────────────────────────────────────────────────────────────────────────────────────────

function syncData(world: ScenarioWorld): SyncData {
  world.data.sync ??= { published: [], before: 0, removed: [], duplicates: [], otherTeam: [], invalid: [] }
  return world.data.sync
}

/** El equipo del escenario, enganchado a una competición de la Federación falsa: si no lo hay, se da de alta. */
async function theLinkedTeam(world: ScenarioWorld) {
  if (!world.data.team) await addRosterTeam(world)
  return theTeam(world)
}

/** Todos los nombres que el escenario ya usa, para no inventar otro igual (con «el mismo nombre»). */
function takenPeople(world: ScenarioWorld): InventedPerson[] {
  const names = [...world.data.players.map((p) => p.fullName), ...syncData(world).published.map((p) => p.fullName)]
  return names.filter((name) => name !== '').map((name) => ({ given: name, surnames: '' }))
}

const newPerson = (world: ScenarioWorld, mark?: NameMark) => inventedPerson(world.random, takenPeople(world), mark)

/** Un jugador para la ficha: su código y su nombre como lo pone la RFFM (con `keepMarks`, con sus marcas). */
function federationPlayer(world: ScenarioWorld, person: InventedPerson, keepMarks = false): PublishedPlayer {
  const data = syncData(world)
  return {
    code: federationPlayerCode(world.random, data.published),
    published: asTheRFFM(world.random, person, keepMarks),
    fullName: fullName(person),
  }
}

/** Añade jugadores a la ficha de equipo, y la vuelve a publicar entera. */
function publish(world: ScenarioWorld, ...players: PublishedPlayer[]) {
  const data = syncData(world)
  data.published.push(...players)
  republish(world)
  for (const player of players) world.note(`la Federación publica «${player.published}»`)
}

function republish(world: ScenarioWorld) {
  fakeFederation().publishRoster(theCompetition(world), syncData(world).published)
}

/** De 2 a 4 jugadores que el club no tiene. */
function someNew(world: ScenarioWorld, count = world.random.int(2, 4)): PublishedPlayer[] {
  const players: PublishedPlayer[] = []
  for (let i = 0; i < count; i++) {
    const player = federationPlayer(world, newPerson(world))
    syncData(world).published.push(player)
    players.push(player)
  }
  syncData(world).published.splice(-count, count)
  return players
}

/** Los jugadores de la plantilla en la temporada en curso, leídos por la API tras sincronizar, como del escenario. */
async function readRoster(world: ScenarioWorld) {
  const team = theTeam(world)
  const rows = await rosterOf(world.club, team, await seasonIdOf(world.club, currentSeason()))
  const others = world.data.players.filter((p) => !(p.team.id === team.id && p.season.label === currentSeason().label))
  world.data.players = [
    ...others,
    ...rows.map(
      (row): ScenarioPlayer => ({
        id: row.id,
        profileId: row.profileId,
        fullName: row.fullName,
        birthYear: row.birthYear ?? null,
        shirtNumber: row.shirtNumber ?? null,
        position: row.position ?? null,
        photoPath: row.photoUrl ? pathOf(row.photoUrl) : undefined,
        team,
        season: currentSeason(),
      }),
    ),
  ]
}

/** La plantilla, sincronizada ya una vez con los que publica la Federación (por la API, como el botón). */
async function alreadySynced(world: ScenarioWorld) {
  await theLinkedTeam(world)
  publish(world, ...someNew(world))
  await syncRoster(world.club, theTeam(world), currentSeason())
  await readRoster(world)
  syncData(world).before = playersIn(world, currentSeason()).length
}

/** Da de baja por la API a jugadores de la plantilla que la Federación sigue publicando. */
async function removeSome(world: ScenarioWorld, count: number) {
  for (let i = 0; i < count; i++) {
    const player = world.random.pick(playersIn(world, currentSeason()))
    await expectApi(world.club, 'DELETE', `/players/${player.id}`, undefined, 204)
    world.data.players = world.data.players.filter((p) => p.id !== player.id)
    syncData(world).removed.push(player.fullName)
    world.note(`dado de baja: ${player.fullName}`)
  }
}

/**
 * Un jugador que el club tuvo en una temporada pasada: dado de alta por la API en la temporada en curso, con lo que se
 * diga en su perfil, y su fila movida a una pasada (decisión 1 de R6.18).
 */
async function pastPlayer(
  world: ScenarioWorld,
  shape: { shirtNumber?: number; position?: Position; photo?: 'foto-a.jpg' },
  simple = false,
) {
  const team = await theLinkedTeam(world)
  const past = world.data.pastSeasons.at(-1) ?? (await addPastSeason(world))
  // «Un nombre completo sencillo»: un nombre y dos apellidos, sin partículas ni guion.
  let person: InventedPerson
  do person = inventedPerson(world.random, takenPeople(world))
  while (simple && (/-|\b(DE|DEL|LA|LAS|LOS|SAN)\b/.test(person.surnames) || person.given.includes(' ') || !person.surnames.includes(' ')))
  const player = await addPlayer(world.club, world.random, team, currentSeason(), world.data.players, {
    person,
    shirtNumber: shape.shirtNumber ?? null,
    position: shape.position ?? null,
    photo: shape.photo,
  })
  await moveRowToSeason(world.club, player.id, past)
  player.season = past
  world.data.players.push(player)
  world.note(`tuvo en ${past.label}: ${player.fullName}, ${player.birthYear}, dorsal ${player.shirtNumber ?? '—'}`)
  return { player, person }
}

/** Un jugador del club en otro equipo de la temporada en curso. */
async function inOtherTeam(world: ScenarioWorld) {
  await theLinkedTeam(world)
  const other = await addTeamWithoutCompetition(world.club, world.random, currentSeason(), world.data.teams)
  world.data.teams.push(other)
  const person = newPerson(world)
  const player = await addPlayer(world.club, world.random, other, currentSeason(), world.data.players, { person })
  world.data.players.push(player)
  syncData(world).otherTeam.push({ fullName: player.fullName, teamId: other.id! })
  return person
}

/**
 * Dos perfiles del club con el nombre de alguien que publica la Federación, cada uno con su fila en otro equipo de una
 * temporada futura (allí sí se escribe, y no están en esta temporada). `spellings`, cómo se escribió cada uno.
 */
async function twoWithTheSameName(world: ScenarioWorld, person: InventedPerson, spellings: [string, string]) {
  const future = futureSeason(world.random)
  const team = await addTeamWithoutCompetition(world.club, world.random, future, world.data.teams)
  world.data.teams.push(team)
  for (const spelling of spellings) {
    const [given, ...rest] = spelling.split(' ')
    // Dos «given» de una palabra sí cuentan: lo que importa es el nombre entero.
    const created = await addPlayer(world.club, world.random, team, future, [], { person: { given: given!, surnames: rest.join(' ') } })
    world.data.players.push(created)
    world.note(`en el club, en ${team.name} ${future.label}: ${created.fullName}`)
  }
  const fed = federationPlayer(world, person, true)
  syncData(world).duplicates.push(fed.fullName)
  return fed
}

// ── Los Given: la plantilla entera ───────────────────────────────────────────────────────────────────────────

Given('la Federación publica la plantilla del equipo', async function (this: ScenarioWorld) {
  await theLinkedTeam(this)
  publish(this, ...someNew(this))
})

Given('el equipo no sincronizado tiene jugadores dados de alta a mano en la temporada en curso', async function (this: ScenarioWorld) {
  await theLinkedTeam(this)
  await addSome(this, currentSeason())
})

Given('la Federación contesta con un error a la plantilla del equipo', async function (this: ScenarioWorld) {
  await theLinkedTeam(this)
  await addSome(this, currentSeason())
  publish(this, ...someNew(this))
  fakeFederation().failRoster(theCompetition(this))
})

Given('la Federación va a retener la próxima petición de la plantilla del equipo', async function (this: ScenarioWorld) {
  await theLinkedTeam(this)
  publish(this, ...someNew(this))
  fakeFederation().holdRoster(theCompetition(this))
  // Se suelta al acabar el escenario (hooks.ts, `settleIngestions`).
  syncData(this).held = true
})

Given('estoy en la pestaña Plantilla del equipo, en la temporada en curso', async function (this: ScenarioWorld) {
  await theLinkedTeam(this)
  await openTeamRoster(this)
})

// ── Los Given: cada jugador ──────────────────────────────────────────────────────────────────────────────────

Given('la Federación publica en la plantilla del equipo a un jugador que mi club no tiene', async function (this: ScenarioWorld) {
  await theLinkedTeam(this)
  const [player] = someNew(this, 1)
  syncData(this).player = player
  publish(this, player!)
})

Given(
  /^la Federación publica en la plantilla del equipo a un jugador con un nombre (vacío|de una sola palabra|con un número|con un símbolo|de más de 120 letras)$/,
  async function (this: ScenarioWorld, how: InvalidName) {
    await theLinkedTeam(this)
    const player = { code: federationPlayerCode(this.random, syncData(this).published), published: invalidFederationName(this.random, how), fullName: '' }
    syncData(this).player = player
    syncData(this).invalid.push(player.published)
    publish(this, player)
  },
)

Given('la Federación publica en la plantilla del equipo a un jugador con un nombre que no vale', async function (this: ScenarioWorld) {
  await theLinkedTeam(this)
  const how = this.random.pick(['de una sola palabra', 'con un número', 'con un símbolo', 'de más de 120 letras'] as const)
  const player = { code: federationPlayerCode(this.random, syncData(this).published), published: invalidFederationName(this.random, how), fullName: '' }
  syncData(this).invalid.push(player.published)
  publish(this, player)
})

Given(
  'la Federación publica en la plantilla del equipo a un jugador con un nombre completo sencillo que mi club tuvo en una temporada pasada, con año, dorsal, demarcación y foto en su perfil',
  async function (this: ScenarioWorld) {
    const { player, person } = await pastPlayer(this, {
      shirtNumber: this.random.int(1, 99),
      position: this.random.pick(positions),
      photo: 'foto-a.jpg',
    }, true)
    this.data.present = player
    publish(this, federationPlayer(this, person))
  },
)

Given(
  'la Federación publica en la plantilla del equipo a un jugador que mi club tuvo en una temporada pasada, con un dorsal en su perfil',
  async function (this: ScenarioWorld) {
    const { player, person } = await pastPlayer(this, { shirtNumber: this.random.int(1, 99) })
    this.data.present = player
    publish(this, federationPlayer(this, person))
  },
)

Given('la plantilla del equipo, en la temporada en curso, tiene a otro jugador con ese dorsal', async function (this: ScenarioWorld) {
  await addOne(this, currentSeason(), { shirtNumber: this.data.present!.shirtNumber })
})

Given(
  /^mi club tiene dos jugadores con el mismo nombre que uno que publica la Federación en la plantilla del equipo(?:, (los dos escritos igual que la Federación|uno con la tilde que pone la Federación y otro sin ella|los dos sin la tilde que pone la Federación))?$/,
  async function (this: ScenarioWorld, how?: string) {
    await theLinkedTeam(this)
    const person = newPerson(this, 'tilde')
    const name = fullName(person)
    const plain = withoutAnyMark(name)
    const spellings: [string, string] =
      how === 'uno con la tilde que pone la Federación y otro sin ella' ? [name, plain] : how === 'los dos sin la tilde que pone la Federación' ? [plain, plain] : [name, name]
    publish(this, await twoWithTheSameName(this, person, spellings))
  },
)

Given(
  'la Federación publica en la plantilla del equipo a un jugador que mi club tiene en otro equipo en la temporada en curso',
  async function (this: ScenarioWorld) {
    publish(this, federationPlayer(this, await inOtherTeam(this)))
  },
)

Given('la plantilla del equipo ha dado de baja a un jugador que la Federación publica', async function (this: ScenarioWorld) {
  await alreadySynced(this)
  await removeSome(this, 1)
})

Given('la plantilla del equipo ya se ha sincronizado con la Federación', async function (this: ScenarioWorld) {
  await alreadySynced(this)
})

Given('he puesto dorsal, demarcación y año a un jugador de la plantilla', async function (this: ScenarioWorld) {
  // Corregir por la API (`updatePlayer`, con la ficha entera): lo que se prueba es la sincronización de después.
  const player = this.random.pick(playersIn(this, currentSeason()))
  const shirtNumber = freeShirtNumber(this.random, playersIn(this, currentSeason()))
  const position = this.random.pick(positions)
  const birthYear = birthYearFor(this.random)
  await expectApi(this.club, 'PUT', `/players/${player.id}`, { fullName: player.fullName, birthYear, shirtNumber, position }, 200)
  Object.assign(player, { shirtNumber, position, birthYear })
  this.data.player = player
  this.note(`corregido ${player.fullName}: dorsal ${shirtNumber}, ${position}, ${birthYear}`)
})

/** Cómo escribe el nombre el club y cómo lo publica la Federación, en cada caso del esquema. */
function spellingsFor(person: InventedPerson, inClub: string): { club: string; keepMarks: boolean; fedText?: string } {
  const name = fullName(person)
  switch (inClub) {
    case 'con tilde':
    case 'con diéresis':
      return { club: name, keepMarks: false, fedText: withoutAnyMark(published(person)) }
    case 'sin tilde':
      return { club: withoutAnyMark(name), keepMarks: true }
    case 'en minúsculas':
      return { club: name.toLocaleLowerCase('es-ES'), keepMarks: true }
    default:
      // Con espacios de más: dos entre cada palabra, y alguno delante y detrás.
      return { club: ` ${name.split(' ').join('   ')} `, keepMarks: true }
  }
}

Given(
  /^el equipo tiene dado de alta a mano a un jugador (con tilde|sin tilde|con diéresis|en minúsculas|con espacios de más) que la Federación publica (?:sin ella|con ella|en mayúsculas|con uno entre palabras)$/,
  async function (this: ScenarioWorld, inClub: string) {
    const team = await theLinkedTeam(this)
    const person = newPerson(this, inClub === 'con diéresis' ? 'diéresis' : inClub.includes('tilde') ? 'tilde' : undefined)
    const { club, keepMarks, fedText } = spellingsFor(person, inClub)
    const manual = await addPlayer(this.club, this.random, team, currentSeason(), this.data.players, { person: { given: club, surnames: '' } })
    this.data.players.push(manual)
    this.data.player = manual
    this.note(`a mano: «${club}», guardado ${manual.fullName}`)
    const fed = federationPlayer(this, person, keepMarks)
    publish(this, fedText ? { ...fed, published: fedText } : fed)
  },
)

Given(
  'el equipo tiene dado de alta a mano a un jugador sin la eñe que la Federación pone en su nombre',
  async function (this: ScenarioWorld) {
    const team = await theLinkedTeam(this)
    const person = newPerson(this, 'eñe')
    const withoutEñe = fullName(person).replace(/Ñ/g, 'N')
    const manual = await addPlayer(this.club, this.random, team, currentSeason(), this.data.players, { person: { given: withoutEñe, surnames: '' } })
    this.data.players.push(manual)
    this.data.player = manual
    const fed = federationPlayer(this, person, true)
    syncData(this).player = fed
    publish(this, fed)
  },
)

Given('la Federación ha quitado a un jugador de la plantilla del equipo', async function (this: ScenarioWorld) {
  const data = syncData(this)
  const gone = this.random.pick(data.published)
  data.published = data.published.filter((p) => p !== gone)
  republish(this)
  this.data.player = playersIn(this, currentSeason()).find((p) => sameNameKey(p.fullName) === sameNameKey(gone.fullName))
  this.note(`la Federación deja de publicar a ${gone.fullName}`)
})

Given('el equipo tiene dado de alta a mano a un jugador que la Federación no publica', async function (this: ScenarioWorld) {
  await theLinkedTeam(this)
  this.data.player = await addOne(this, currentSeason())
  publish(this, ...someNew(this))
})

// ── Los Given del resumen ────────────────────────────────────────────────────────────────────────────────────

Given(
  /^estoy en la pestaña Plantilla del equipo, (sin jugadores y sin sincronizar nunca|ya sincronizada|ya sincronizada y con uno dado de baja|ya sincronizada y con dos dados de baja)$/,
  async function (this: ScenarioWorld, start: string) {
    await theLinkedTeam(this)
    if (start.startsWith('ya sincronizada')) await alreadySynced(this)
    if (start.endsWith('con uno dado de baja')) await removeSome(this, 1)
    if (start.endsWith('con dos dados de baja')) await removeSome(this, 2)
    await openTeamRoster(this)
  },
)

/** Uno más para la ficha, según lo que diga la fila del resumen. */
async function oneMore(world: ScenarioWorld, kind: string): Promise<PublishedPlayer> {
  switch (kind) {
    case 'que mi club no tiene':
      return someNew(world, 1)[0]!
    case 'que mi club tuvo en una temporada pasada, con año':
      return federationPlayer(world, (await pastPlayer(world, {})).person)
    case 'que mi club tiene en otro equipo':
      return federationPlayer(world, await inOtherTeam(world))
    case 'con el nombre de dos jugadores de mi club': {
      const person = newPerson(world)
      return twoWithTheSameName(world, person, [fullName(person), fullName(person)])
    }
    default: {
      const how = world.random.pick(['de una sola palabra', 'con un número', 'con un símbolo', 'de más de 120 letras'] as const)
      const published = invalidFederationName(world.random, how)
      syncData(world).invalid.push(published)
      return { code: federationPlayerCode(world.random, syncData(world).published), published, fullName: '' }
    }
  }
}

Given(
  /^la Federación publica en la plantilla del equipo (jugadores que mi club no tiene|los mismos jugadores|los mismos y (?:uno|dos),? .+)$/,
  async function (this: ScenarioWorld, what: string) {
    if (what === 'jugadores que mi club no tiene') publish(this, ...someNew(this))
    const more = /^los mismos y (uno|dos),? (?:cada uno )?(.+)$/.exec(what)
    if (!more) return
    for (let i = 0; i < (more[1] === 'uno' ? 1 : 2); i++) {
      // Uno a uno: el siguiente no puede llamarse como el anterior.
      publish(this, await oneMore(this, more[2]!))
    }
  },
)

// ── Lo que se hace ───────────────────────────────────────────────────────────────────────────────────────────

When('sincronizo la plantilla', async function (this: ScenarioWorld) {
  // Algunos escenarios llegan aquí sin la pestaña abierta: se abre, como lo haría alguien.
  if (!new URL(this.page.url(), 'http://x').pathname.endsWith('/plantilla')) await openTeamRoster(this)
  this.data.rosterBefore = await shownNames(this)
  await syncButton(this).click()
  if (syncData(this).held) {
    await fakeFederation().heldRosterArrived(theCompetition(this))
    return
  }
  // Hasta que acaba: el resumen o el aviso de error; y la tabla, otra vez pedida.
  await becomes(this.page, async () => (await summaryBox(this).count()) + (await failureBox(this).count()) > 0, true, 'el final de la sincronización')
  await becomes(this.page, async () => (await syncButton(this).innerText()).trim(), 'Sincronizar con la Federación', 'el botón')
})

When('abro la pestaña Plantilla del equipo no sincronizado, en la temporada en curso', async function (this: ScenarioWorld) {
  await openTeamRoster(this)
})

When('abro la ficha de un jugador de la plantilla, en la temporada en curso', async function (this: ScenarioWorld) {
  this.data.player = this.random.pick(playersIn(this, currentSeason()))
  await this.page.goto(this.clubUrl(playerPath(currentSeason(), this.data.player.id)))
  await this.page.getByRole('heading', { level: 1, name: shownName(this.data.player.fullName), exact: true }).waitFor()
})

// ── Lo que se ve: la plantilla entera ────────────────────────────────────────────────────────────────────────

/** Un instante en hora de Madrid, como lo escribe la web: «17/11/2026 18:30». */
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

Then('la pestaña Plantilla dice {string} con la fecha y la hora de ahora', async function (this: ScenarioWorld, words: string) {
  // Ahora, o el minuto de antes si ha cambiado mientras tanto.
  const now = new Date()
  const accepted = [inMadrid(now), inMadrid(new Date(now.getTime() - 60_000))].map((when) => `${words}: ${when}`)
  await this.check('la fecha', async () => {
    const text = (await rosterTab(this).locator('.last-sync').innerText()).trim()
    if (!accepted.includes(text)) throw new Error(`dice «${text}», y se esperaba «${accepted[0]}»`)
  })
})

Then('ninguna fila de la plantilla dice "Federado" ni "No federado"', async function (this: ScenarioWorld) {
  await shows(rosterTab(this).getByRole('table'), 'la plantilla')
  await this.check('federado', () => absent(rosterTab(this).getByRole('table').getByText(/Federado|No federado/), '«Federado» o «No federado»'))
})

Then('la plantilla tiene los mismos jugadores que antes de sincronizar', async function (this: ScenarioWorld) {
  const expected = [...this.data.rosterBefore!].sort().join(' · ')
  await this.check('los jugadores', () => becomes(this.page, async () => (await shownNames(this)).sort().join(' · '), expected, 'la plantilla'))
})

Then('la pestaña Plantilla avisa que la Federación no ha contestado y que se puede volver a intentar', async function (this: ScenarioWorld) {
  await this.check('el aviso', () => shows(failureBox(this).filter({ hasText: /Federación/ }).filter({ hasText: /Prueba otra vez/ }), 'el aviso de la Federación'))
  await this.check('volver a intentar', async () => {
    if (!(await syncButton(this).isEnabled())) throw new Error('el botón de sincronizar está bloqueado')
  })
})

Then(
  'el botón "Sincronizar con la Federación" está bloqueado y dice que está sincronizando',
  async function (this: ScenarioWorld) {
    await this.check('el botón', () => becomes(this.page, async () => (await syncButton(this).innerText()).trim(), 'Sincronizando…', 'el botón'))
    await this.check('bloqueado', async () => {
      if (await syncButton(this).isEnabled()) throw new Error('se puede pulsar')
    })
  },
)

// ── Lo que se ve: cada jugador ───────────────────────────────────────────────────────────────────────────────

/** Las filas cuyo nombre es «el mismo nombre» que este (sin tildes ni mayúsculas; la eñe, distinta). */
async function rowsNamed(world: ScenarioWorld, name: string): Promise<number> {
  return (await shownNames(world)).filter((shown) => sameNameKey(shown) === sameNameKey(name)).length
}

const named = (fullName: string) => ({ fullName })

/** El jugador nuevo en el club del escenario: el que publica la Federación, guardado con su nombre bien escrito. */
const theSynced = (world: ScenarioWorld) => named(syncData(world).player!.fullName)

async function federationOf(world: ScenarioWorld, player: { fullName: string }, expected: string) {
  await world.check(`«${expected}»`, async () => {
    await shows(rowOfPlayer(world, player), `la fila de ${shownName(player.fullName)}`)
    const label = rowOfPlayer(world, player).locator('.federation')
    await becomes(world.page, async () => ((await label.count()) > 0 ? (await label.innerText()).trim() : 'nada'), expected, 'lo que dice la fila')
  })
}

Then('la plantilla tiene al jugador nuevo en el club, con su nombre como «Nombre Apellidos»', async function (this: ScenarioWorld) {
  await this.check('el jugador', () => shows(rowOfPlayer(this, theSynced(this)), `la fila de ${shownName(theSynced(this).fullName)}`))
})

Then('la fila del jugador nuevo en el club no tiene dorsal ni demarcación', async function (this: ScenarioWorld) {
  await this.check('el dorsal', () => becomes(this.page, () => textOf(this, theSynced(this), 'shirtNumber'), '—', 'el dorsal'))
  await this.check('la demarcación', () => becomes(this.page, () => textOf(this, theSynced(this), 'position'), '—', 'la demarcación'))
})

Then('la fila del jugador nuevo en el club dice {string}', async function (this: ScenarioWorld, text: string) {
  await federationOf(this, theSynced(this), text)
})

Then('el perfil del jugador nuevo en el club tiene su nombre, sin año', async function (this: ScenarioWorld) {
  await this.check('el perfil', async () => {
    const profile = await profileOf(this, theSynced(this).fullName)
    if (profile.birthYear != null) throw new Error(`tiene el año ${profile.birthYear}`)
  })
})

Then(/^la plantilla no tiene al jugador con el nombre .+$/, async function (this: ScenarioWorld) {
  // Nadie nuevo: la plantilla, como antes. El nombre que no vale puede ser vacío, así que no se busca por él.
  const expected = [...this.data.rosterBefore!].sort().join(' · ')
  await this.check('la plantilla', () => becomes(this.page, async () => (await shownNames(this)).sort().join(' · '), expected, 'la plantilla'))
})

const thePast = (world: ScenarioWorld) => world.data.present!

Then(
  /^la fila del jugador de la temporada pasada tiene (el año|el dorsal|la demarcación|la foto) de su perfil$/,
  async function (this: ScenarioWorld, what: string) {
    const past = thePast(this)
    await this.check(what, async () => {
      await shows(rowOfPlayer(this, past), `la fila de ${shownName(past.fullName)}`)
      if (what === 'el año') await becomes(this.page, () => textOf(this, past, 'birthYear'), String(past.birthYear), what)
      if (what === 'el dorsal') await becomes(this.page, () => textOf(this, past, 'shirtNumber'), String(past.shirtNumber), what)
      if (what === 'la demarcación') await becomes(this.page, () => textOf(this, past, 'position'), positionNames[past.position!], what)
      // La foto de su perfil es la de su fila de la temporada pasada (D-122): el mismo fichero. El buscador no sirve aquí
      // para leer el perfil, porque se pregunta desde esa temporada, y quita a los de su plantilla.
      if (what === 'la foto') {
        await becomes(this.page, async () => {
          const src = (await rowPhoto(this, past).count()) > 0 ? await rowPhoto(this, past).getAttribute('src') : null
          return src ? pathOf(src) : 'ninguna'
        }, past.photoPath!, what)
      }
    })
  },
)

Then('la fila del jugador de la temporada pasada no tiene dorsal', async function (this: ScenarioWorld) {
  const past = thePast(this)
  await this.check('el dorsal', async () => {
    await shows(rowOfPlayer(this, past), `la fila de ${shownName(past.fullName)}`)
    await becomes(this.page, () => textOf(this, past, 'shirtNumber'), '—', 'el dorsal')
  })
})

Then('la plantilla tiene al jugador con nombre repetido', async function (this: ScenarioWorld) {
  const name = syncData(this).duplicates[0]!
  await this.check('el jugador', () => shows(rowOfPlayer(this, named(name)), `la fila de ${shownName(name)}`))
})

Then('mi club tiene ahora tres perfiles con el mismo nombre', async function (this: ScenarioWorld) {
  const name = syncData(this).duplicates[0]!
  await this.check('los perfiles', async () => {
    const found = await searchProfiles(this.club, name, theTeam(this).id!, await seasonIdOf(this.club, lastPastSeason(this)))
    const same = found.filter((p) => sameNameKey(p.fullName) === sameNameKey(name)).length
    if (same !== 3) throw new Error(`hay ${same} con el nombre de ${name}, y se esperaban 3`)
  })
})

Then('la plantilla no tiene al jugador del otro equipo', async function (this: ScenarioWorld) {
  const name = syncData(this).otherTeam[0]!.fullName
  await this.check('el jugador', () => becomes(this.page, () => rowsNamed(this, name), 0, `las filas de ${shownName(name)}`))
})

Then('la plantilla no tiene al jugador dado de baja', async function (this: ScenarioWorld) {
  const name = syncData(this).removed[0]!
  await this.check('el jugador', () => becomes(this.page, () => rowsNamed(this, name), 0, `las filas de ${shownName(name)}`))
})

Then('la plantilla tiene a cada jugador que publica la Federación una sola vez', async function (this: ScenarioWorld) {
  for (const player of syncData(this).published) {
    await this.check(player.fullName, () => becomes(this.page, () => rowsNamed(this, player.fullName), 1, `las filas de ${shownName(player.fullName)}`))
  }
})

Then('el jugador tiene en la plantilla el dorsal, la demarcación y el año que le puse', async function (this: ScenarioWorld) {
  const player = this.data.player!
  await this.check('el dorsal', () => becomes(this.page, () => textOf(this, player, 'shirtNumber'), String(player.shirtNumber), 'el dorsal'))
  await this.check('la demarcación', () => becomes(this.page, () => textOf(this, player, 'position'), positionNames[player.position!], 'la demarcación'))
  await this.check('el año', () => becomes(this.page, () => textOf(this, player, 'birthYear'), String(player.birthYear), 'el año'))
})

Then('la plantilla tiene al jugador una sola vez', async function (this: ScenarioWorld) {
  await this.check('el jugador', () => becomes(this.page, () => rowsNamed(this, this.data.player!.fullName), 1, 'sus filas'))
})

Then('la fila del jugador dice {string}', async function (this: ScenarioWorld, text: string) {
  await federationOf(this, this.data.player!, text)
})

Then('la plantilla tiene al jugador dado de alta a mano', async function (this: ScenarioWorld) {
  await this.check('el jugador', () => shows(rowOfPlayer(this, this.data.player!), `la fila de ${shownName(this.data.player!.fullName)}`))
})

Then('la plantilla tiene al jugador de la Federación, con su eñe, con un perfil nuevo', async function (this: ScenarioWorld) {
  const fed = theSynced(this)
  await this.check('el jugador', () => shows(rowOfPlayer(this, fed), `la fila de ${shownName(fed.fullName)}`))
  await this.check('su perfil', async () => {
    const profile = await profileOf(this, fed.fullName)
    if (profile.profileId === this.data.player!.profileId) throw new Error('es el perfil del dado de alta a mano')
  })
})

Then(/^la fila del jugador (?:quitado|dado de alta a mano) dice "(.+)"$/, async function (this: ScenarioWorld, text: string) {
  await federationOf(this, this.data.player!, text)
})

// ── Lo que se ve: el resumen ─────────────────────────────────────────────────────────────────────────────────

/** Lo que dice cada palabra de la tabla del resumen, en número. */
function countOf(world: ScenarioWorld, word: string): number {
  const data = syncData(world)
  switch (word) {
    case 'todos':
      return data.published.length
    case 'ninguno':
      return 0
    case 'los de antes':
      return data.before
    case 'los demás':
      return data.before - data.removed.length
    default:
      return Number(word)
  }
}

const n = (count: number, one: string, many: string) => `${count} ${count === 1 ? one : many}`

/** Que el resumen dice la línea (con `count` > 0), o que no la dice. */
async function lineSaid(world: ScenarioWorld, what: string, count: number, line: string, prefix: string) {
  await world.check(what, async () => {
    await shows(summaryBox(world), 'el resumen')
    const text = await summaryText(world)
    if (count > 0 && !text.includes(line)) throw new Error(`el resumen dice «${text}», y se esperaba «${line}»`)
    if (count === 0 && text.includes(prefix)) throw new Error(`el resumen dice «${text}», y no debería hablar de ${what}`)
  })
}

Then(
  /^el resumen de la sincronización dice (\S+|los de antes|los demás) añadidos y (\S+|los de antes|los demás) que ya estaban$/,
  async function (this: ScenarioWorld, added: string, already: string) {
    const line = `${n(countOf(this, added), 'añadido', 'añadidos')} y ${n(countOf(this, already), 'que ya estaba', 'que ya estaban')}.`
    await this.check('la primera línea', async () => {
      await shows(summaryBox(this), 'el resumen')
      await contains(this.page, () => summaryText(this), line, 'el resumen')
    })
  },
)

Then(/^el resumen de la sincronización dice (\S+) sin año de nacimiento$/, async function (this: ScenarioWorld, word: string) {
  const count = countOf(this, word)
  await lineSaid(this, 'los sin año', count, `${n(count, 'añadido', 'añadidos')} sin año de nacimiento: se pone desde su ficha.`, 'sin año de nacimiento')
})

Then(
  /^el resumen de la sincronización dice (\S+) dados de baja en el club y (\S+) en otro equipo$/,
  async function (this: ScenarioWorld, removed: string, other: string) {
    const gone = countOf(this, removed)
    const again = gone === 1 ? 'no se vuelve' : 'no se vuelven'
    await lineSaid(this, 'los dados de baja', gone, `${n(gone, 'dado de baja en el club', 'dados de baja en el club')}: ${again} a añadir.`, 'de baja en el club')
    const others = countOf(this, other)
    await lineSaid(this, 'los de otro equipo', others, `En otro equipo del club esta temporada, ${others === 1 ? 'no añadido' : 'no añadidos'}:`, 'En otro equipo')
  },
)

Then(
  /^el resumen de la sincronización dice (\S+) con nombre repetido y (\S+) con un nombre que no vale$/,
  async function (this: ScenarioWorld, repeated: string, invalid: string) {
    const twice = countOf(this, repeated)
    const what = twice === 1 ? 'dado de alta como jugador nuevo; para revisarlo' : 'dados de alta como jugadores nuevos; para revisarlos'
    await lineSaid(this, 'los repetidos', twice, `Con nombre repetido en el club, ${what}:`, 'nombre repetido')
    const bad = countOf(this, invalid)
    await lineSaid(this, 'los que no valen', bad, `Con un nombre que no vale, ${bad === 1 ? 'no añadido; para darlo' : 'no añadidos; para darlos'} de alta a mano:`, 'nombre que no vale')
  },
)

Then('el resumen de la sincronización nombra al jugador con nombre repetido, para revisarlo', async function (this: ScenarioWorld) {
  const line = `Con nombre repetido en el club, dado de alta como jugador nuevo; para revisarlo: ${shownName(syncData(this).duplicates[0]!)}.`
  await this.check('el repetido', () => contains(this.page, () => summaryText(this), line, 'el resumen'))
})

Then('el resumen de la sincronización nombra al jugador del otro equipo, con su equipo', async function (this: ScenarioWorld) {
  const other = syncData(this).otherTeam[0]!
  const team = this.data.teams.find((t) => t.id === other.teamId)!
  const line = `En otro equipo del club esta temporada, no añadido: ${shownName(other.fullName)} (${await teamDisplayName(this.club, team)}).`
  await this.check('el de otro equipo', () => contains(this.page, () => summaryText(this), line, 'el resumen'))
})

Then(
  'el resumen de la sincronización nombra al jugador con un nombre que no vale, para darlo de alta a mano',
  async function (this: ScenarioWorld) {
    const line = `Con un nombre que no vale, no añadido; para darlo de alta a mano: «${syncData(this).invalid[0]!.replace(/\s+/g, ' ')}».`
    await this.check('el que no vale', () => contains(this.page, () => summaryText(this), line, 'el resumen'))
  },
)

// ── La ficha del jugador ─────────────────────────────────────────────────────────────────────────────────────

const federationFact = (world: ScenarioWorld) =>
  world.page.getByRole('main').locator('dl.facts dt').filter({ hasText: /^\s*Federación\s*$/ }).locator('xpath=following-sibling::dd[1]')

Then('la ficha del jugador dice {string}', async function (this: ScenarioWorld, text: string) {
  await this.check('la Federación', () => contains(this.page, async () => (await federationFact(this).innerText()).trim(), text, 'el dato «Federación»'))
})

Then('la ficha del jugador dice la fecha y la hora de la última vez que lo publicó la Federación', async function (this: ScenarioWorld) {
  const row = await expectApi<{ lastListedAt?: string | null }>(this.club, 'GET', `/players/${this.data.player!.id}`, undefined, 200)
  const expected = `publicado el ${inMadrid(new Date(row.lastListedAt!))}`
  await this.check('la fecha', () => contains(this.page, async () => (await federationFact(this).innerText()).trim(), expected, 'el dato «Federación»'))
})

// ── Al acabar ────────────────────────────────────────────────────────────────────────────────────────────────

/**
 * Si el escenario retuvo la ficha de la Federación, se suelta aquí y se espera a que la sincronización acabe (la fecha
 * de la inscripción): si no, escribiría en el club mientras se borra, como pasó con la ingesta en R4.15. Este `After`
 * va antes que los de hooks.ts (Cucumber los pasa del último al primero), con el servidor todavía en marcha.
 */
After({ timeout: 20_000 }, async function (this: ScenarioWorld) {
  if (!this.data.sync?.held) return
  fakeFederation().releaseAll()
  const path = `/teams/${theTeam(this).id}/registrations/${await seasonIdOf(this.club, currentSeason())}`
  const deadline = Date.now() + 15_000
  while (Date.now() < deadline) {
    const registration = await expectApi<{ rosterSyncedAt?: string | null }>(this.club, 'GET', path, undefined, 200)
    if (registration.rosterSyncedAt) return
    await new Promise((resolve) => setTimeout(resolve, 200))
  }
})


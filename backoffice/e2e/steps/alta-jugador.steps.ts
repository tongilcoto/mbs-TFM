// El alta de un jugador, en un diálogo encima de la plantilla (plan R6, decisiones 5, 7, 8, 9 y 10; decisión 2 de
// R6.12). El campo del nombre es también el buscador de los jugadores del club. Los jugadores se inventan al azar y
// se dan de alta por la API (players.ts); lo que el escenario pone en el diálogo se apunta para comparar después.
// «El perfil del jugador» se lee por la API, con el buscador (`searchPlayerProfiles`), preguntando desde una temporada
// pasada del club: el buscador quita a los de la plantilla desde la que se pregunta.
import { Given, Then, When } from '@cucumber/cucumber'
import { addTeamWithoutCompetition, seasonIdOf } from '../support/club-data.ts'
import {
  currentSeason,
  futureSeason,
  fullName,
  inventedPerson,
  sameNameKey,
  type InventedPerson,

} from '../support/invented.ts'
import { absent, becomes, contains, shows } from '../support/look.ts'
import {
  addPlayer,
  badPhoto,
  birthYearFor,
  freeShirtNumber,
  pathOf,
  photoFile,
  positionNames,
  positions,
  searchProfiles,
  shownName,
  teamDisplayName,
  type BadPhoto,
  type PhotoName,
  type Position,
  type ProfileAnswer,
  type ScenarioPlayer,
} from '../support/players.ts'
import type { NewPlayer, ScenarioWorld } from '../support/world.ts'
import { addPastSeason, lastPastSeason, theTeam } from './portada.steps.ts'
import { addOne, addRosterTeam, openRoster, playersIn, rosterTab, rowOfPlayer, rowPhoto, shownNames, textOf } from './plantilla.steps.ts'

// ── Dónde está cada cosa ─────────────────────────────────────────────────────────────────────────────────────

/** El diálogo del alta: su título empieza por «Dar de alta un jugador en». */
const dialog = (world: ScenarioWorld) => world.page.getByRole('dialog', { name: /^Dar de alta un jugador en/ })
/** El buscador del alta: el campo «Nombre y apellidos», que ofrece una lista al escribir. */
const searchBox = (world: ScenarioWorld) => dialog(world).getByRole('combobox', { name: /^Nombre y apellidos/ })
/** Las opciones de la lista del buscador, que sale encima de la página, fuera del diálogo. */
const options = (world: ScenarioWorld) => world.page.getByRole('listbox').getByRole('option')
/** La opción de un jugador del club: su nombre entero, y detrás su año y su equipo. */
const optionOf = (world: ScenarioWorld, player: Pick<ScenarioPlayer, 'fullName'>) =>
  options(world).filter({ hasText: new RegExp(`^\\s*${escaped(shownName(player.fullName))}`) })
const escaped = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

/** Los campos, por su `id` (DialogPlayer): el nombre, el año, el dorsal, la demarcación y la foto. */
const fieldIds: Record<string, string> = {
  'Nombre y apellidos': 'player-search',
  'Año de nacimiento': 'player-year',
  Dorsal: 'player-shirt',
  Demarcación: 'player-position',
  Foto: 'player-photo',
}
function fieldId(name: string): string {
  const id = fieldIds[name]
  if (!id) throw new Error(`El diálogo del alta no tiene el campo «${name}»`)
  return id
}
/** El campo entero: su etiqueta, el control, la ayuda y el error. */
const fieldBox = (world: ScenarioWorld, name: string) =>
  dialog(world).locator('.form-field').filter({ has: world.page.locator(`label[for="${fieldId(name)}"]`) })
const positionPicker = (world: ScenarioWorld) => dialog(world).getByRole('combobox', { name: 'Demarcación' })

function thePresent(world: ScenarioWorld): ScenarioPlayer {
  if (!world.data.present) throw new Error('El escenario no tiene ningún jugador presente en el club')
  return world.data.present
}

function theNew(world: ScenarioWorld): NewPlayer & { fullName: string } {
  const entered = world.data.newPlayer
  if (!entered?.fullName) throw new Error('El escenario no ha rellenado ningún jugador nuevo')
  return entered as NewPlayer & { fullName: string }
}

// ── Los datos ────────────────────────────────────────────────────────────────────────────────────────────────

/**
 * Un jugador presente en el club: con su fila en la plantilla de otro equipo, en una temporada futura (allí sí se
 * escribe, y no está en ninguna de la temporada en curso, así que se puede elegir). Su perfil guarda lo de esa fila
 * (D-122). Su nombre lleva una tilde, para el caso del mismo nombre «sin una tilde que él tiene».
 */
async function addPresent(world: ScenarioWorld, person: InventedPerson, withEverything = false) {
  const future = futureSeason(world.random)
  world.data.futureSeason = future
  const team = await addTeamWithoutCompetition(world.club, world.random, future, world.data.teams)
  world.data.teams.push(team)
  const shape = withEverything
    ? { person, shirtNumber: world.random.int(1, 99), position: world.random.pick(positions), photo: 'foto-a.jpg' as const }
    : { person }
  const present = await addPlayer(world.club, world.random, team, future, world.data.players, shape)
  world.data.players.push(present)
  world.data.present = present
  world.note(
    `presente en el club: ${present.fullName}, ${present.birthYear}, en ${team.name} ${future.label}: dorsal ` +
      `${present.shirtNumber ?? '—'}, ${present.position ?? 'sin demarcación'}${present.photoPath ? ', con foto' : ''}`,
  )
}

/** Alguien que no se llama como ningún jugador del escenario, con una tilde en el nombre o en los apellidos. */
const personWithTilde = (world: ScenarioWorld) =>
  inventedPerson(world.random, world.data.players.map(asPerson), 'tilde')
const asPerson = (player: ScenarioPlayer): InventedPerson => ({ given: player.fullName, surnames: '' })

Given('hay un jugador presente en el club', async function (this: ScenarioWorld) {
  await addPresent(this, personWithTilde(this))
})

Given('hay un jugador presente en el club con una tilde en el apellido', async function (this: ScenarioWorld) {
  let person: InventedPerson
  do person = personWithTilde(this)
  while (!/[ÁÉÍÓÚ]/.test(person.surnames))
  await addPresent(this, person)
})

Given('hay un jugador presente en el club con dorsal, demarcación y foto en su perfil', async function (this: ScenarioWorld) {
  await addPresent(this, personWithTilde(this), true)
})

Given('mi club tiene un jugador en la plantilla de otro equipo en la temporada en curso', async function (this: ScenarioWorld) {
  const team = await addTeamWithoutCompetition(this.club, this.random, currentSeason(), this.data.teams)
  this.data.teams.push(team)
  const present = await addPlayer(this.club, this.random, team, currentSeason(), this.data.players)
  this.data.players.push(present)
  this.data.present = present
  this.note(`en la plantilla de ${team.name}: ${present.fullName}`)
})

Given('un equipo de mi club tiene jugadores con dorsal en la plantilla de la temporada en curso', async function (this: ScenarioWorld) {
  await addRosterTeam(this)
  const count = this.random.int(2, 4)
  for (let i = 0; i < count; i++) {
    await addOne(this, currentSeason(), { shirtNumber: freeShirtNumber(this.random, playersIn(this, currentSeason())) })
  }
})

// ── Abrir el diálogo ─────────────────────────────────────────────────────────────────────────────────────────

/**
 * Abre la pestaña Plantilla del equipo en la temporada en curso. Antes, una temporada pasada del club, vacía, desde la
 * que leer el perfil de un jugador por la API (el buscador quita a los de la plantilla desde la que se pregunta).
 */
export async function openTeamRoster(world: ScenarioWorld) {
  if (world.data.pastSeasons.length === 0) await addPastSeason(world)
  world.data.rosterBefore = playersIn(world, currentSeason()).map((p) => shownName(p.fullName))
  await openRoster(world, currentSeason())
}

export async function openDialog(world: ScenarioWorld) {
  await rosterTab(world).getByRole('button', { name: 'Dar de alta un jugador', exact: true }).click()
  await dialog(world).waitFor()
  // El foco llega al buscador cuando la ventana acaba de aparecer.
  await becomes(world.page, () => world.page.evaluate(() => document.activeElement?.id ?? ''), 'player-search', 'el foco')
}

/** Un equipo de mi club nuevo, con el diálogo del alta abierto en su plantilla de la temporada en curso. */
async function dialogInNewTeam(world: ScenarioWorld) {
  await addRosterTeam(world)
  await openTeamRoster(world)
  await openDialog(world)
}

Given('estoy en la pestaña Plantilla de la ficha de un equipo de mi club, en la temporada en curso', async function (this: ScenarioWorld) {
  await addRosterTeam(this)
  await openTeamRoster(this)
})

Given(
  'tengo abierto el diálogo del alta en la plantilla de un equipo de mi club, en la temporada en curso',
  async function (this: ScenarioWorld) {
    await dialogInNewTeam(this)
  },
)

Given('tengo abierto el diálogo del alta en la plantilla del equipo, en la temporada en curso', async function (this: ScenarioWorld) {
  await openTeamRoster(this)
  await openDialog(this)
})

// ── El buscador ──────────────────────────────────────────────────────────────────────────────────────────────

/** Escribe en el buscador, como lo haría alguien: tecla a tecla. */
async function type(world: ScenarioWorld, text: string) {
  world.data.typed = text
  world.note(`escrito en el buscador: «${text}»`)
  await searchBox(world).fill('')
  await searchBox(world).pressSequentially(text)
}

/** Espera a que el buscador conteste: la lista acaba siempre en la opción del jugador nuevo. */
async function answered(world: ScenarioWorld) {
  await options(world).filter({ hasText: 'como jugador nuevo' }).waitFor()
}

/** Las primeras letras de un nombre, contando solo las letras. */
const firstLetters = (name: string, count: number) => {
  let taken = 0
  let end = 0
  while (taken < count && end < name.length) if (/\p{L}/u.test(name[end++]!)) taken++
  return name.slice(0, end)
}
/** En minúsculas y sin tildes ni diéresis. */
const plain = (text: string) => text.normalize('NFD').replace(/[̀-ͯ]/g, '').normalize('NFC').toLocaleLowerCase('es-ES')

When(
  /^escribo en el buscador del alta las (tres|dos) primeras letras del nombre del jugador presente en el club$/,
  async function (this: ScenarioWorld, howMany: string) {
    await type(this, firstLetters(shownName(thePresent(this).fullName), howMany === 'tres' ? 3 : 2))
  },
)

When(
  'escribo en el buscador del alta, en minúsculas y sin tildes, el comienzo de su nombre y el de su apellido',
  async function (this: ScenarioWorld) {
    // El apellido con la tilde, escrito hasta pasar de ella: así la tilde está en lo que se busca.
    const words = thePresent(this).fullName.split(' ')
    const given = words[0]!
    const surname = words.slice(1).find((word) => /[ÁÉÍÓÚ]/.test(word))!
    const upToTilde = surname.slice(0, Math.max(3, surname.search(/[ÁÉÍÓÚ]/) + 1))
    await type(this, `${plain(firstLetters(given, 3))} ${plain(upToTilde)}`)
  },
)

When(/^escribo en el buscador del alta el nombre entero del jugador (?:presente en el club|de la otra plantilla)$/, async function (this: ScenarioWorld) {
  await type(this, shownName(thePresent(this).fullName))
})

When('escribo en el buscador del alta el nombre entero de un jugador de la plantilla', async function (this: ScenarioWorld) {
  const player = this.random.pick(playersIn(this, currentSeason()))
  this.data.player = player
  await type(this, shownName(player.fullName))
})

/** Un nombre que no tiene ningún jugador del escenario, escrito como «Nombre Apellidos». */
export function newName(world: ScenarioWorld): string {
  return shownName(fullName(inventedPerson(world.random, world.data.players.map(asPerson))))
}

When('escribo en el buscador del alta un nombre que mi club no tiene', async function (this: ScenarioWorld) {
  await type(this, newName(this))
})

When('elijo en el buscador del alta al jugador presente en el club', async function (this: ScenarioWorld) {
  await choosePresent(this)
})

async function choosePresent(world: ScenarioWorld) {
  await type(world, shownName(thePresent(world).fullName))
  await optionOf(world, thePresent(world)).click()
  await dialog(world).getByRole('button', { name: 'Elegir otro jugador' }).waitFor()
}

/** Escribe un nombre nuevo y elige «Dar de alta a «…» como jugador nuevo»: el foco pasa al año. */
async function chooseNew(world: ScenarioWorld, name = newName(world)) {
  await type(world, name)
  await answered(world)
  await options(world).filter({ hasText: 'como jugador nuevo' }).click()
  await becomes(world.page, () => world.page.evaluate(() => document.activeElement?.id ?? ''), 'player-year', 'el foco')
  world.data.newPlayer = { fullName: name.toLocaleUpperCase('es-ES') }
}

When('elijo en el buscador del alta dar de alta lo escrito como jugador nuevo', async function (this: ScenarioWorld) {
  await chooseNew(this)
})

// ── Rellenar ─────────────────────────────────────────────────────────────────────────────────────────────────

async function setYear(world: ScenarioWorld, year: number) {
  await dialog(world).locator('#player-year').fill(String(year))
  world.data.newPlayer = { ...world.data.newPlayer, birthYear: year }
}

async function setShirt(world: ScenarioWorld, shirt: number | null) {
  await dialog(world).locator('#player-shirt').fill(shirt === null ? '' : String(shirt))
  world.data.newPlayer = { ...world.data.newPlayer, shirtNumber: shirt }
}

async function setPosition(world: ScenarioWorld, position: Position | null) {
  if (position === null) {
    // La ✕ del selector, que lo deja en «Sin demarcación».
    await dialog(world).locator('[data-pc-section="clearicon"]').click()
  } else {
    await positionPicker(world).click()
    await world.page.getByRole('option', { name: positionNames[position], exact: true }).click()
  }
  world.data.newPlayer = { ...world.data.newPlayer, position }
}

async function setPhoto(world: ScenarioWorld, photo: PhotoName | null) {
  if (photo === null) await dialog(world).getByRole('button', { name: 'Quitar foto', exact: true }).click()
  else await dialog(world).locator('#player-photo').setInputFiles(photoFile(photo))
  world.data.newPlayer = { ...world.data.newPlayer, photo }
}

type Optional = 'el dorsal' | 'la demarcación' | 'la foto'

/** Un jugador nuevo, con su nombre y su año, y los datos opcionales que se digan. */
export async function fillNew(world: ScenarioWorld, optional: Optional[], shirt?: number) {
  await chooseNew(world)
  await setYear(world, birthYearFor(world.random))
  if (optional.includes('el dorsal')) await setShirt(world, shirt ?? freeShirtNumber(world.random, playersIn(world, currentSeason())))
  if (optional.includes('la demarcación')) await setPosition(world, world.random.pick(positions))
  if (optional.includes('la foto')) await setPhoto(world, world.random.pick(['foto-a.jpg', 'foto-b.jpg'] as const))
  world.note(`jugador nuevo: ${JSON.stringify(world.data.newPlayer)}`)
}

const all: Optional[] = ['el dorsal', 'la demarcación', 'la foto']

Given(
  'en el diálogo del alta de la plantilla de un equipo de mi club he elegido al jugador presente en el club',
  async function (this: ScenarioWorld) {
    await dialogInNewTeam(this)
    await choosePresent(this)
  },
)

Given(
  /^en el diálogo del alta de la plantilla de un equipo de mi club he elegido al jugador presente en el club y he cambiado (el dorsal|la demarcación|la foto)$/,
  async function (this: ScenarioWorld, which: Optional) {
    await dialogInNewTeam(this)
    await choosePresent(this)
    const present = thePresent(this)
    if (which === 'el dorsal') await setShirt(this, 1 + ((present.shirtNumber! + this.random.int(0, 97)) % 99))
    if (which === 'la demarcación') await setPosition(this, this.random.pick(positions.filter((p) => p !== present.position)))
    if (which === 'la foto') await setPhoto(this, 'foto-b.jpg')
    this.note(`cambiado: ${JSON.stringify(this.data.newPlayer)}`)
  },
)

Given(
  'en el diálogo del alta de la plantilla de un equipo de mi club he elegido al jugador presente en el club y he borrado su dorsal, su demarcación y su foto',
  async function (this: ScenarioWorld) {
    await dialogInNewTeam(this)
    await choosePresent(this)
    await setShirt(this, null)
    await setPosition(this, null)
    await setPhoto(this, null)
  },
)

Given(
  'en el diálogo del alta de la plantilla de un equipo de mi club he rellenado un jugador nuevo solo con su nombre y su año',
  async function (this: ScenarioWorld) {
    await dialogInNewTeam(this)
    await fillNew(this, [])
  },
)

Given(
  /^en el diálogo del alta de la plantilla de un equipo de mi club he rellenado un jugador nuevo con su nombre, su año y solo (el dorsal|la demarcación|la foto)$/,
  async function (this: ScenarioWorld, which: Optional) {
    await dialogInNewTeam(this)
    await fillNew(this, [which])
  },
)

Given(
  'en el diálogo del alta de la plantilla de un equipo de mi club he rellenado un jugador nuevo con todos sus datos',
  async function (this: ScenarioWorld) {
    await dialogInNewTeam(this)
    await fillNew(this, all)
  },
)

Given('en el diálogo del alta de la plantilla del equipo he rellenado un jugador nuevo con todos sus datos', async function (this: ScenarioWorld) {
  await openTeamRoster(this)
  await openDialog(this)
  await fillNew(this, all)
})

Given(
  'en el diálogo del alta de la plantilla del equipo he rellenado un jugador nuevo con el dorsal de otro jugador',
  async function (this: ScenarioWorld) {
    await openTeamRoster(this)
    await openDialog(this)
    const other = this.random.pick(playersIn(this, currentSeason()))
    this.data.player = other
    this.note(`el dorsal ${other.shirtNumber}, de ${other.fullName}`)
    await fillNew(this, ['el dorsal'], other.shirtNumber!)
  },
)

Given(
  /^en el diálogo del alta de la plantilla de un equipo de mi club he rellenado como jugador nuevo uno con el nombre del jugador presente en el club, (escrito igual|sin una tilde que él tiene), y otro año$/,
  async function (this: ScenarioWorld, how: string) {
    await dialogInNewTeam(this)
    const present = thePresent(this)
    const name = shownName(how === 'escrito igual' ? present.fullName : withoutOneTilde(present.fullName))
    await chooseNew(this, name)
    let year: number
    do year = birthYearFor(this.random)
    while (year === present.birthYear)
    await setYear(this, year)
    this.note(`jugador nuevo: «${name}», ${year}`)
  },
)

/** El nombre con la primera tilde quitada: «MARTÍN DÍAZ» → «MARTIN DÍAZ». */
function withoutOneTilde(name: string): string {
  const at = name.search(/[ÁÉÍÓÚ]/)
  return name.slice(0, at) + name[at]!.normalize('NFD')[0] + name.slice(at + 1)
}

Given(
  'en el diálogo del alta de la plantilla de un equipo de mi club he elegido dar de alta un jugador nuevo',
  async function (this: ScenarioWorld) {
    await dialogInNewTeam(this)
    await chooseNew(this)
  },
)

Given('he borrado el nombre del diálogo del alta', async function (this: ScenarioWorld) {
  await searchBox(this).fill('')
  this.data.newPlayer = {}
})

/** Un nombre que no vale, como lo escribiría alguien: el caso del escenario. */
function invalidName(world: ScenarioWorld, how: string): string {
  const person = inventedPerson(world.random)
  const name = shownName(fullName(person))
  switch (how) {
    case 'de una sola palabra':
      return shownName(person.given.split(' ')[0]!)
    case 'con un número':
      return `${name} ${world.random.int(2, 9)}`
    case 'con un símbolo':
      // Ni guion ni apóstrofo, que sí valen.
      return `${name}${world.random.pick(['*', '#', '@', '!', '?', '+', '/'])}`
    default: {
      let long = name
      while (long.length <= 120) long += ` ${shownName(inventedPerson(world.random).surnames)}`
      return long
    }
  }
}

Given(
  /^he escrito en el nombre del diálogo del alta un nombre (de una sola palabra|con un número|con un símbolo|de más de 120 letras)$/,
  async function (this: ScenarioWorld, how: string) {
    await type(this, invalidName(this, how))
    // Fuera del buscador, para que su lista se cierre y no tape los botones; y hasta que acaba de irse, que mientras
    // se desvanece sus colores están a medias (y axe los mediría).
    await dialog(this).locator('#player-year').click()
    await this.page.getByRole('listbox').waitFor({ state: 'detached' })
  },
)

Given('he escrito en el dorsal del diálogo del alta {string}', async function (this: ScenarioWorld, shirt: string) {
  await dialog(this).locator('#player-shirt').fill(shirt)
})

Given(
  /^en el diálogo del alta de la plantilla de un equipo de mi club he rellenado un jugador nuevo con una foto (que no es una imagen|de más de 5 MB|en un formato que no es JPEG ni PNG)$/,
  async function (this: ScenarioWorld, how: BadPhoto) {
    await dialogInNewTeam(this)
    await fillNew(this, [])
    await dialog(this).locator('#player-photo').setInputFiles(badPhoto(how))
  },
)

// ── Lo que se hace ───────────────────────────────────────────────────────────────────────────────────────────

When('pulso el botón {string} de la pestaña Plantilla', async function (this: ScenarioWorld, name: string) {
  await rosterTab(this).getByRole('button', { name, exact: true }).click()
})

When('pulso {string} en el diálogo del alta', async function (this: ScenarioWorld, name: string) {
  await dialog(this).getByRole('button', { name, exact: true }).click()
})

// ── Lo que se ve: el diálogo ─────────────────────────────────────────────────────────────────────────────────

Then('el diálogo del alta está abierto', async function (this: ScenarioWorld) {
  await this.check('el diálogo', () => shows(dialog(this), 'el diálogo del alta'))
})

Then('el diálogo del alta sigue abierto', async function (this: ScenarioWorld) {
  await this.check('el diálogo', () => shows(dialog(this), 'el diálogo del alta'))
})

Then('el título del diálogo del alta dice el equipo y la temporada en curso', async function (this: ScenarioWorld) {
  const expected = `Dar de alta un jugador en ${theTeam(this).name}, ${currentSeason().label}`
  await this.check('el título', () => shows(this.page.getByRole('dialog', { name: expected, exact: true }), `el título «${expected}»`))
})

Then('el buscador del alta está vacío y tiene el foco', async function (this: ScenarioWorld) {
  await this.check('vacío', () => becomes(this.page, () => searchBox(this).inputValue(), '', 'el buscador'))
  await this.check('el foco', () =>
    becomes(this.page, () => this.page.evaluate(() => document.activeElement?.id ?? ''), 'player-search', 'el campo con el foco'),
  )
})

Then('el buscador del alta tiene la etiqueta {string}', async function (this: ScenarioWorld, text: string) {
  // Lo que el lector lee al llegar al campo (decisión 2 de R6.12).
  await this.check('el nombre del buscador', () =>
    shows(dialog(this).getByRole('combobox', { name: new RegExp(`^${escaped(text)}`) }), `el buscador «${text}»`),
  )
})

Then('el buscador del alta ofrece al jugador presente en el club', async function (this: ScenarioWorld) {
  await this.check('el jugador', () => shows(optionOf(this, thePresent(this)), `la opción de ${shownName(thePresent(this).fullName)}`))
  await this.check('que se puede elegir', async () => {
    if ((await optionOf(this, thePresent(this)).getAttribute('aria-disabled')) === 'true') throw new Error('está desactivado')
  })
})

Then('el jugador presente en el club sale en el buscador con su año de nacimiento', async function (this: ScenarioWorld) {
  await this.check('el año', () =>
    contains(this.page, () => optionOf(this, thePresent(this)).innerText(), String(thePresent(this).birthYear), 'la opción'),
  )
})

/** «Celtic Cadete A 2027/28»: su último equipo, como lo manda el servidor, y la temporada. */
async function lastTeamText(world: ScenarioWorld) {
  const present = thePresent(world)
  return `${await teamDisplayName(world.club, present.team)} ${present.season.label}`
}

Then('el jugador presente en el club sale en el buscador con su último equipo y su temporada', async function (this: ScenarioWorld) {
  const expected = await lastTeamText(this)
  await this.check('el equipo', () => contains(this.page, () => optionOf(this, thePresent(this)).innerText(), expected, 'la opción'))
})

Then('el buscador del alta ofrece al jugador presente en el club, con su año y su último equipo', async function (this: ScenarioWorld) {
  const expected = `${thePresent(this).birthYear} · ${await lastTeamText(this)}`
  await this.check('el jugador', () => contains(this.page, () => optionOf(this, thePresent(this)).innerText(), expected, 'la opción'))
})

Then('el buscador del alta no ofrece ningún jugador', async function (this: ScenarioWorld) {
  // Con menos de tres letras no pregunta al servidor: se espera lo que tardaría en hacerlo, y no hay lista.
  await this.page.waitForTimeout(1_000)
  await this.check('la lista', () => absent(options(this), 'una opción en el buscador'))
})

Then('el buscador del alta no ofrece a ese jugador', async function (this: ScenarioWorld) {
  await answered(this)
  await this.check('el jugador', () => absent(optionOf(this, this.data.player!), `la opción de ${shownName(this.data.player!.fullName)}`))
})

Then(
  'la última opción del buscador del alta dice {string} lo escrito {string}',
  async function (this: ScenarioWorld, before: string, after: string) {
    await answered(this)
    const expected = `${before} «${this.data.typed}» ${after}`
    await this.check('la última opción', () =>
      becomes(this.page, async () => (await options(this).last().innerText()).trim(), expected, 'la última opción'),
    )
  },
)

Then('el buscador del alta enseña al jugador de la otra plantilla, desactivado', async function (this: ScenarioWorld) {
  await this.check('el jugador', () => shows(optionOf(this, thePresent(this)), `la opción de ${shownName(thePresent(this).fullName)}`))
  await this.check('desactivado', () =>
    becomes(this.page, async () => await optionOf(this, thePresent(this)).getAttribute('aria-disabled'), 'true', 'aria-disabled'),
  )
})

Then(
  'el jugador de la otra plantilla sale en el buscador con {string} y el nombre de su equipo',
  async function (this: ScenarioWorld, words: string) {
    const expected = `${words} ${await teamDisplayName(this.club, thePresent(this).team)}`
    await this.check('su equipo', () => contains(this.page, () => optionOf(this, thePresent(this)).innerText(), expected, 'la opción'))
  },
)

Then('el diálogo del alta tiene el nombre y el año del jugador presente en el club, bloqueados', async function (this: ScenarioWorld) {
  const present = thePresent(this)
  const name = dialog(this).locator('#player-search')
  const year = dialog(this).locator('#player-year')
  await this.check('el nombre', () => becomes(this.page, () => name.inputValue(), shownName(present.fullName), 'el nombre'))
  await this.check('el año', () => becomes(this.page, () => year.inputValue(), String(present.birthYear), 'el año'))
  await this.check('bloqueados', async () => {
    if (!(await name.isDisabled()) || !(await year.isDisabled())) throw new Error('se pueden cambiar')
  })
})

/** Lo que enseña cada campo del bloque de la plantilla: el dorsal, la demarcación o la foto (el camino, sin firma). */
async function fieldValue(world: ScenarioWorld, name: string): Promise<string> {
  if (name === 'Dorsal') return dialog(world).locator('#player-shirt').inputValue()
  if (name === 'Demarcación') return (await positionPicker(world).innerText()).trim()
  const img = fieldBox(world, 'Foto').getByRole('img')
  return (await img.count()) > 0 ? pathOf((await img.getAttribute('src')) ?? '') : 'ninguna'
}

Then(
  /^el campo "(Dorsal|Demarcación|Foto)" del diálogo del alta tiene (?:el dorsal|la demarcación|la foto) de su perfil$/,
  async function (this: ScenarioWorld, name: string) {
    const profile = await profileOf(this, thePresent(this).fullName, thePresent(this).profileId)
    const expected =
      name === 'Dorsal' ? String(profile.lastShirtNumber) : name === 'Demarcación' ? positionNames[profile.lastPosition!] : pathOf(profile.lastPhotoUrl!)
    await this.check(name, () => becomes(this.page, () => fieldValue(this, name), expected, `el campo «${name}»`))
  },
)

/** Si el campo dice «(obligatorio)» en su etiqueta. */
const isRequired = async (world: ScenarioWorld, name: string) =>
  ((await fieldBox(world, name).locator('label').textContent()) ?? '').includes('(obligatorio)')

async function checkRequired(world: ScenarioWorld, name: string, required: boolean) {
  await world.check(`«${name}» ${required ? 'obligatorio' : 'opcional'}`, () =>
    becomes(world.page, () => isRequired(world, name), required, `«${name}» obligatorio`),
  )
}

async function checkHelp(world: ScenarioWorld, name: string, help: string) {
  await world.check(`la ayuda de «${name}»`, () =>
    contains(world.page, async () => (await dialog(world).locator(`#${fieldId(name)}-help`).innerText()).trim(), help, `la ayuda de «${name}»`),
  )
}

Then('el campo {string} del diálogo del alta es obligatorio y tiene lo escrito', async function (this: ScenarioWorld, name: string) {
  await checkRequired(this, name, true)
  await this.check('lo escrito', () => becomes(this.page, () => searchBox(this).inputValue(), this.data.typed!, `el campo «${name}»`))
})

Then('el campo {string} del diálogo del alta es obligatorio', async function (this: ScenarioWorld, name: string) {
  await checkRequired(this, name, true)
})

Then('el campo {string} del diálogo del alta es opcional', async function (this: ScenarioWorld, name: string) {
  await checkRequired(this, name, false)
})

Then(
  'el campo {string} del diálogo del alta es opcional, con la ayuda {string}',
  async function (this: ScenarioWorld, name: string, help: string) {
    await checkRequired(this, name, false)
    await checkHelp(this, name, help)
  },
)

/** El error junto a un campo. */
const errorOf = (world: ScenarioWorld, name: string) => dialog(world).locator(`#${fieldId(name)}-error`)

Then('el campo {string} del diálogo del alta dice {string}', async function (this: ScenarioWorld, name: string, text: string) {
  await this.check(`el error de «${name}»`, () => shows(errorOf(this, name).filter({ hasText: text }), `«${text}» junto a «${name}»`))
})

Then(
  'el campo "Dorsal" del diálogo del alta dice "ya lo tiene" y el nombre del otro jugador',
  async function (this: ScenarioWorld) {
    const expected = `ya lo tiene ${shownName(this.data.player!.fullName)}`
    await this.check('el error del dorsal', () => shows(errorOf(this, 'Dorsal').filter({ hasText: expected }), `«${expected}»`))
  },
)

Then('el diálogo del alta avisa que el jugador nuevo se ha guardado', async function (this: ScenarioWorld) {
  const expected = `${shownName(theNew(this).fullName)}: guardado.`
  await this.check('el aviso', () => shows(dialog(this).getByRole('status').filter({ hasText: expected }), `el aviso «${expected}»`))
})

// ── Lo que se ve: la plantilla ───────────────────────────────────────────────────────────────────────────────

Then('la pestaña Plantilla avisa {string}', async function (this: ScenarioWorld, text: string) {
  await this.check('el aviso', () => shows(this.page.getByRole('status').filter({ hasText: text }), `el aviso «${text}»`))
})

Then('la pestaña Plantilla avisa {string} y {string}', async function (this: ScenarioWorld, first: string, second: string) {
  await this.check('el aviso', () =>
    shows(this.page.getByRole('status').filter({ hasText: first }).filter({ hasText: second }), `el aviso «${first} … ${second}»`),
  )
})

Then('la plantilla tiene los mismos jugadores que antes de abrir el diálogo', async function (this: ScenarioWorld) {
  const expected = [...this.data.rosterBefore!].sort().join(' · ')
  await this.check('los jugadores', () =>
    becomes(this.page, async () => (await shownNames(this)).sort().join(' · '), expected, 'los nombres de la plantilla'),
  )
})

/** El jugador del que habla el `Then`: el presente en el club, o el nuevo. */
function who(world: ScenarioWorld, which: string): { fullName: string } {
  return which === 'presente en el club' ? thePresent(world) : theNew(world)
}

/** Que la fila del jugador está en la plantilla: se espera a que la tabla se vuelva a pedir tras guardar. */
async function rowShown(world: ScenarioWorld, player: { fullName: string }) {
  await shows(rowOfPlayer(world, player), `la fila de ${shownName(player.fullName)}`)
}

async function cellBecomes(world: ScenarioWorld, player: { fullName: string }, which: 'shirtNumber' | 'position' | 'birthYear', expected: string, what: string) {
  await world.check(what, async () => {
    await rowShown(world, player)
    await becomes(world.page, () => textOf(world, player, which), expected, what)
  })
}

Then(/^la fila del jugador (presente en el club|nuevo) tiene su nombre y su año(?: de siempre)?$/, async function (this: ScenarioWorld, which: string) {
  const player = who(this, which)
  const year = which === 'presente en el club' ? thePresent(this).birthYear : theNew(this).birthYear
  await this.check('el nombre', () => rowShown(this, player))
  await cellBecomes(this, player, 'birthYear', String(year), 'el año')
})

Then('la plantilla tiene al jugador nuevo, con su año', async function (this: ScenarioWorld) {
  await cellBecomes(this, theNew(this), 'birthYear', String(theNew(this).birthYear), 'el año')
})

Then(/^la fila del jugador presente en el club tiene (el dorsal|la demarcación|la foto) de su perfil$/, async function (this: ScenarioWorld, which: string) {
  const present = thePresent(this)
  if (which === 'el dorsal') await cellBecomes(this, present, 'shirtNumber', String(present.shirtNumber), 'el dorsal')
  if (which === 'la demarcación') await cellBecomes(this, present, 'position', positionNames[present.position!], 'la demarcación')
  if (which === 'la foto') await photoBecomes(this, present, present.photoPath!)
})

/** El camino de la foto de la fila, sin la firma, o «ninguna». */
async function photoPathOf(world: ScenarioWorld, player: { fullName: string }): Promise<string> {
  const img = rowPhoto(world, player)
  return (await img.count()) > 0 ? pathOf((await img.getAttribute('src')) ?? '') : 'ninguna'
}

async function photoBecomes(world: ScenarioWorld, player: { fullName: string }, expected: string) {
  await world.check('la foto', async () => {
    await rowShown(world, player)
    await becomes(world.page, () => photoPathOf(world, player), expected, 'la foto de la fila')
  })
}

Then(
  /^la fila del jugador (presente en el club|nuevo) tiene (el dorsal|la demarcación|la foto) que he puesto$/,
  async function (this: ScenarioWorld, which: string, what: string) {
    const player = who(this, which)
    const entered = this.data.newPlayer!
    if (what === 'el dorsal') await cellBecomes(this, player, 'shirtNumber', String(entered.shirtNumber), 'el dorsal')
    if (what === 'la demarcación') await cellBecomes(this, player, 'position', positionNames[entered.position!], 'la demarcación')
    if (what === 'la foto') await newPhotoInRow(this, player)
  },
)

/**
 * La foto que se ha puesto: el servidor la limpia y la guarda con una clave nueva (D-115), así que no se compara el
 * fichero. Se mira que la fila tiene una foto que carga, y que no es la que traía el perfil.
 */
async function newPhotoInRow(world: ScenarioWorld, player: { fullName: string }) {
  await world.check('la foto', async () => {
    await rowShown(world, player)
    await becomes(world.page, async () => (await photoPathOf(world, player)) !== 'ninguna', true, 'que la fila tenga foto')
    const before = world.data.present?.fullName === player.fullName ? world.data.present.photoPath : undefined
    if (before && (await photoPathOf(world, player)) === before) throw new Error('la fila tiene la foto de antes')
    await becomes(
      world.page,
      () => rowPhoto(world, player).evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth > 0),
      true,
      'la foto cargada',
    )
  })
}

const nothing: Record<string, 'shirtNumber' | 'position'> = { dorsal: 'shirtNumber', demarcación: 'position' }

Then(/^la fila del jugador (presente en el club|nuevo) no tiene (dorsal|demarcación|foto)$/, async function (this: ScenarioWorld, which: string, what: string) {
  const player = who(this, which)
  if (what === 'foto') await photoBecomes(this, player, 'ninguna')
  else await cellBecomes(this, player, nothing[what]!, '—', what)
})

/** «demarcación, ni foto» → las dos. */
const listed = (text: string) => text.split(/,\s*ni\s+|,\s*/).map((w) => w.trim())

Then(/^la fila del jugador nuevo no tiene (dorsal|demarcación|foto), ni (dorsal|demarcación|foto)$/, async function (this: ScenarioWorld, a: string, b: string) {
  for (const what of [a, b]) {
    if (what === 'foto') await photoBecomes(this, theNew(this), 'ninguna')
    else await cellBecomes(this, theNew(this), nothing[what]!, '—', what)
  }
})

// ── Lo que se ve: el perfil, por la API ──────────────────────────────────────────────────────────────────────

/** El perfil de un jugador, preguntando desde la temporada pasada del club, donde no está en ninguna plantilla. */
export async function profileOf(world: ScenarioWorld, name: string, profileId?: string): Promise<ProfileAnswer> {
  const found = await searchProfiles(world.club, name, theTeam(world).id!, await seasonIdOf(world.club, lastPastSeason(world)))
  const profile = found.find((p) => (profileId ? p.profileId === profileId : p.fullName === name))
  if (!profile) throw new Error(`el buscador no encuentra el perfil de ${name}`)
  return profile
}

/** El perfil del jugador del `Then`, cuando ya está guardado: se espera a que la fila esté en la plantilla. */
async function savedProfile(world: ScenarioWorld, which: string): Promise<ProfileAnswer> {
  const player = who(world, which)
  await rowShown(world, player)
  return profileOf(world, player.fullName, which === 'presente en el club' ? thePresent(world).profileId : undefined)
}

/** Lo que el perfil dice de un dato: el número, el nombre de la demarcación, o si tiene foto. */
function profileSays(profile: ProfileAnswer, what: string): string {
  if (what.includes('dorsal')) return profile.lastShirtNumber == null ? 'ninguno' : String(profile.lastShirtNumber)
  if (what.includes('demarcación')) return profile.lastPosition == null ? 'ninguna' : positionNames[profile.lastPosition]
  return profile.lastPhotoUrl == null ? 'ninguna' : pathOf(profile.lastPhotoUrl)
}

/** Lo puesto en el diálogo, como lo dice `profileSays`; la foto, la que tiene ahora la fila. */
async function enteredSays(world: ScenarioWorld, which: string, what: string): Promise<string> {
  const entered = world.data.newPlayer!
  if (what.includes('dorsal')) return entered.shirtNumber == null ? 'ninguno' : String(entered.shirtNumber)
  if (what.includes('demarcación')) return entered.position == null ? 'ninguna' : positionNames[entered.position]
  return photoPathOf(world, who(world, which))
}

async function profileHas(world: ScenarioWorld, which: string, what: string, expected: () => Promise<string>) {
  await world.check(`el perfil: ${what}`, async () => {
    const profile = await savedProfile(world, which)
    const want = await expected()
    const seen = profileSays(profile, what)
    if (seen !== want) throw new Error(`dice «${seen}», y se esperaba «${want}»`)
  })
}

Then(
  /^el perfil del jugador (presente en el club|nuevo) tiene (el dorsal|la demarcación|la foto) que he puesto$/,
  async function (this: ScenarioWorld, which: string, what: string) {
    await profileHas(this, which, what, () => enteredSays(this, which, what))
  },
)

Then('el perfil del jugador nuevo tiene el dorsal, la demarcación y la foto que he puesto', async function (this: ScenarioWorld) {
  for (const what of all) await profileHas(this, 'nuevo', what, () => enteredSays(this, 'nuevo', what))
})

const empty = (what: string) => async () => (what.includes('dorsal') ? 'ninguno' : 'ninguna')

Then('el perfil del jugador presente en el club no tiene dorsal, ni demarcación, ni foto', async function (this: ScenarioWorld) {
  for (const what of ['dorsal', 'demarcación', 'foto']) await profileHas(this, 'presente en el club', what, empty(what))
})

Then(/^el perfil del jugador nuevo no tiene (.+)$/, async function (this: ScenarioWorld, others: string) {
  for (const what of listed(others)) await profileHas(this, 'nuevo', what, empty(what))
})

Then('el perfil del jugador nuevo tiene su nombre y su año, sin dorsal, ni demarcación, ni foto', async function (this: ScenarioWorld) {
  await this.check('el año del perfil', async () => {
    const profile = await savedProfile(this, 'nuevo')
    if (profile.birthYear !== theNew(this).birthYear) throw new Error(`es ${profile.birthYear}, y se esperaba ${theNew(this).birthYear}`)
  })
  for (const what of ['dorsal', 'demarcación', 'foto']) await profileHas(this, 'nuevo', what, empty(what))
})

Then('mi club tiene ahora dos perfiles con el mismo nombre', async function (this: ScenarioWorld) {
  await this.check('los perfiles', async () => {
    await rowShown(this, theNew(this))
    const found = await searchProfiles(this.club, theNew(this).fullName, theTeam(this).id!, await seasonIdOf(this.club, lastPastSeason(this)))
    const same = found.filter((p) => sameNameKey(p.fullName) === sameNameKey(theNew(this).fullName))
    if (same.length !== 2) throw new Error(`hay ${same.length} con el nombre de ${theNew(this).fullName}, y se esperaban 2`)
  })
})

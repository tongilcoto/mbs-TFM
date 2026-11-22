// La ficha del jugador, corregir y dar de baja (plan R6, decisiones 6, 7, 8 y 10; decisión 1 de R6.12). La ficha es
// la del jugador en una temporada: /temporadas/:temporada/jugadores/:id. Los jugadores se inventan al azar y se dan de
// alta por la API (players.ts); «el perfil del jugador» se lee con el buscador por la API (alta-jugador.steps.ts).
import { Given, Then, When } from '@cucumber/cucumber'
import { expectApi } from '../support/club-api.ts'
import { currentSeason, pastSeason, type Season } from '../support/invented.ts'
import { absent, becomes, shows } from '../support/look.ts'
import {
  birthYearFor,
  freeShirtNumber,
  initialsOf,
  LOCATION_MARK,
  pathOf,
  photoFile,
  photoWithLocation,
  positionNames,
  shownName,
  type ScenarioPlayer,
} from '../support/players.ts'
import type { ScenarioWorld } from '../support/world.ts'
import { fillNew, newName, openDialog, openTeamRoster, profileOf } from './alta-jugador.steps.ts'
import { addPastSeason, lastPastSeason, theTeam } from './portada.steps.ts'
import {
  addOne,
  addRosterTeam,
  addSome,
  addThePlayer,
  playerPath,
  playersIn,
  rosterLoaded,
  rosterPath,
  rosterTab,
  rowOfPlayer,
  shownNames,
  textOf,
  thePlayer,
} from './plantilla.steps.ts'

// ── Dónde está cada cosa ─────────────────────────────────────────────────────────────────────────────────────

/** La ficha del jugador: lo de debajo del título, en la zona principal. */
const sheet = (world: ScenarioWorld) => world.page.getByRole('main')
/** Un dato de la ficha («Dorsal», «Año de nacimiento»…): lo que va junto a su nombre. */
const factOf = (world: ScenarioWorld, label: string) =>
  sheet(world).locator('dl.facts dt').filter({ hasText: new RegExp(`^\\s*${label}\\s*$`) }).locator('xpath=following-sibling::dd[1]')
/** El sitio de la foto de la ficha. */
const sheetPhotoBox = (world: ScenarioWorld) => sheet(world).getByRole('region', { name: 'Foto' })
/** El diálogo de corregir: su título es «Corregir a» y el nombre. */
const editDialog = (world: ScenarioWorld) => world.page.getByRole('dialog', { name: /^Corregir a / })
const yearConfirm = (world: ScenarioWorld) => world.page.getByRole('dialog', { name: 'Poner el año de nacimiento' })
const removeConfirm = (world: ScenarioWorld) => world.page.getByRole('dialog', { name: 'Dar de baja' })

const focusedId = (world: ScenarioWorld) => world.page.evaluate(() => document.activeElement?.id ?? '')

// ── Los datos ────────────────────────────────────────────────────────────────────────────────────────────────

/** El equipo con unos jugadores, todos con dorsal, y uno de ellos, al azar, el del escenario. */
async function teamWithPlayers(world: ScenarioWorld) {
  await addRosterTeam(world)
  const count = world.random.int(2, 4)
  for (let i = 0; i < count; i++) {
    await addOne(world, currentSeason(), { shirtNumber: freeShirtNumber(world.random, playersIn(world, currentSeason())) })
  }
  world.data.player = world.random.pick(playersIn(world, currentSeason()))
  world.note(`el jugador: ${world.data.player.fullName}`)
}

Given('un equipo de mi club tiene en la plantilla de la temporada en curso un jugador con año en su perfil', async function (this: ScenarioWorld) {
  await addThePlayer(this, {})
})

Given('un jugador con dorsal de la plantilla de un equipo de mi club se ha dado de baja', async function (this: ScenarioWorld) {
  await teamWithPlayers(this)
  const player = thePlayer(this)
  // La baja, por la API (`deletePlayer`): lo que se prueba es el alta de después.
  await expectApi(this.club, 'DELETE', `/players/${player.id}`, undefined, 204)
  this.data.players = this.data.players.filter((p) => p.id !== player.id)
  this.note(`dado de baja: ${player.fullName}, con el ${player.shirtNumber}`)
})

// ── Entrar ───────────────────────────────────────────────────────────────────────────────────────────────────

/** Abre la ficha del jugador en una temporada y espera a su título. */
async function openSheet(world: ScenarioWorld, player: ScenarioPlayer, season: Season = player.season) {
  await world.page.goto(world.clubUrl(playerPath(season, player.id)))
  await world.page.locator('h1').first().waitFor()
}

async function sheetLoaded(world: ScenarioWorld) {
  await world.page.getByRole('heading', { level: 1, name: shownName(thePlayer(world).fullName), exact: true }).waitFor()
  await sheet(world).getByText('Cargando jugador…').waitFor({ state: 'detached' })
}

When('abro la ficha del jugador, en la temporada en curso', async function (this: ScenarioWorld) {
  await openSheet(this, thePlayer(this), currentSeason())
  await sheetLoaded(this)
})

When('abro la ficha de un jugador de la plantilla, en la temporada pasada', async function (this: ScenarioWorld) {
  this.data.player = this.random.pick(playersIn(this, lastPastSeason(this)))
  await openSheet(this, thePlayer(this), lastPastSeason(this))
  await sheetLoaded(this)
})

When('abro la ficha de un jugador de la plantilla con una temporada pasada en el camino', async function (this: ScenarioWorld) {
  this.data.player = this.random.pick(playersIn(this, currentSeason()))
  const wrong = pastSeason(this.random, this.data.pastSeasons)
  this.note(`en el camino, ${wrong.label}`)
  await openSheet(this, thePlayer(this), wrong)
})

Given('estoy en la ficha de un jugador de mi club, en la temporada en curso', async function (this: ScenarioWorld) {
  await addRosterTeam(this)
  await addSome(this, currentSeason())
  this.data.player = this.random.pick(playersIn(this, currentSeason()))
  await openSheet(this, thePlayer(this))
  await sheetLoaded(this)
})

Given(
  /^estoy en la ficha de un jugador de mi club (sin|con) foto en la plantilla, en la temporada en curso$/,
  async function (this: ScenarioWorld, how: string) {
    await addThePlayer(this, how === 'con' ? { photo: 'foto-a.jpg' } : {})
    // Una temporada pasada, vacía, desde la que leer su perfil por la API.
    await addPastSeason(this)
    await openSheet(this, thePlayer(this))
    await sheetLoaded(this)
  },
)

Given(
  'estoy en la pestaña Plantilla de la ficha de un equipo de mi club con jugadores, en la temporada en curso',
  async function (this: ScenarioWorld) {
    await teamWithPlayers(this)
    await openTeamRoster(this)
  },
)

// ── Lo que se hace ───────────────────────────────────────────────────────────────────────────────────────────

When('pulso el enlace {string} y su equipo, encima de la ficha del jugador', async function (this: ScenarioWorld, text: string) {
  await this.page.getByRole('link', { name: `${text} ${theTeam(this).name}`, exact: true }).click()
  await rosterLoaded(this)
})

/** La acción de la fila: un icono que el lector nombra con la acción y el jugador («Corregir, Juan García»). */
async function rowAction(world: ScenarioWorld, action: string) {
  await rowOfPlayer(world, thePlayer(world)).getByRole('button', { name: `${action}, ${shownName(thePlayer(world).fullName)}`, exact: true }).click()
}

When(/^pulso la acción "(Corregir|Dar de baja)" de la fila de un jugador$/, async function (this: ScenarioWorld, action: string) {
  await rowAction(this, action)
})

When(/^pulso la acción "(Corregir|Dar de baja)" de la fila del jugador$/, async function (this: ScenarioWorld, action: string) {
  await rowAction(this, action)
})

When('pulso {string} en la ficha del jugador', async function (this: ScenarioWorld, name: string) {
  await sheet(this).getByRole('button', { name, exact: true }).click()
})

/** El diálogo de corregir del jugador del escenario, desde su fila; espera a que el foco llegue al nombre. */
async function openEdit(world: ScenarioWorld) {
  await rowAction(world, 'Corregir')
  await editDialog(world).waitFor()
  await becomes(world.page, () => focusedId(world), 'player-search', 'el foco')
}

Given(
  'tengo abierto el diálogo de corregir de un jugador de mi club desde la plantilla, en la temporada en curso',
  async function (this: ScenarioWorld) {
    await teamWithPlayers(this)
    await openTeamRoster(this)
    await openEdit(this)
  },
)

async function setShirt(world: ScenarioWorld, shirt: number) {
  await editDialog(world).locator('#player-shirt').fill(String(shirt))
  world.data.newPlayer = { ...world.data.newPlayer, shirtNumber: shirt }
  world.note(`dorsal nuevo: ${shirt}`)
}

Given('he cambiado el dorsal por uno libre en el diálogo de corregir', async function (this: ScenarioWorld) {
  await setShirt(this, freeShirtNumber(this.random, playersIn(this, currentSeason())))
})

Given('he cambiado el dorsal por el de otro jugador del equipo en el diálogo de corregir', async function (this: ScenarioWorld) {
  const other = this.random.pick(playersIn(this, currentSeason()).filter((p) => p.id !== thePlayer(this).id))
  this.data.present = other
  await setShirt(this, other.shirtNumber!)
})

async function setName(world: ScenarioWorld) {
  const name = newName(world)
  await editDialog(world).locator('#player-search').fill(name)
  world.data.newPlayer = { ...world.data.newPlayer, fullName: name.toLocaleUpperCase('es-ES') }
  world.note(`nombre nuevo: ${name}`)
}

async function setYear(world: ScenarioWorld) {
  const year = birthYearFor(world.random)
  await editDialog(world).locator('#player-year').fill(String(year))
  world.data.newPlayer = { ...world.data.newPlayer, birthYear: year }
  world.note(`año: ${year}`)
}

Given('he cambiado el nombre en el diálogo de corregir', async function (this: ScenarioWorld) {
  await setName(this)
})

/** El diálogo de corregir del jugador del escenario, desde la plantilla: la abre y lo abre. */
async function editFromRoster(world: ScenarioWorld) {
  await openTeamRoster(world)
  await openEdit(world)
}

Given(
  'en el diálogo de corregir del jugador, desde la plantilla, he puesto su año de nacimiento',
  async function (this: ScenarioWorld) {
    await editFromRoster(this)
    await setYear(this)
  },
)

Given(
  'en el diálogo de corregir del jugador, desde la plantilla, he puesto su año de nacimiento y he pulsado "Guardar"',
  async function (this: ScenarioWorld) {
    await editFromRoster(this)
    await setYear(this)
    await editDialog(this).getByRole('button', { name: 'Guardar', exact: true }).click()
    await yearConfirm(this).waitFor()
  },
)

Given(
  'en el diálogo de corregir del jugador, desde la plantilla, he cambiado su nombre y he puesto su año de nacimiento',
  async function (this: ScenarioWorld) {
    await editFromRoster(this)
    await setName(this)
    await setYear(this)
  },
)

When('pulso {string} en el diálogo de corregir', async function (this: ScenarioWorld, name: string) {
  await editDialog(this).getByRole('button', { name, exact: true }).click()
})

When('confirmo el año', async function (this: ScenarioWorld) {
  await yearConfirm(this).getByRole('button', { name: 'Guardar el año', exact: true }).click()
})

When('cancelo la confirmación del año', async function (this: ScenarioWorld) {
  await yearConfirm(this).getByRole('button', { name: 'Volver', exact: true }).click()
  // Volver deja el diálogo de corregir abierto; se cierra sin guardar, para mirar la plantilla.
  await yearConfirm(this).waitFor({ state: 'detached' })
  await editDialog(this).getByRole('button', { name: 'Cancelar', exact: true }).click()
})

When('pongo una foto al jugador desde su ficha', async function (this: ScenarioWorld) {
  await sheet(this).locator('#sheet-photo').setInputFiles(photoFile('foto-b.jpg'))
})

When('pongo al jugador desde su ficha una foto con la ubicación dentro', async function (this: ScenarioWorld) {
  await sheet(this).locator('#sheet-photo').setInputFiles(photoWithLocation())
})

Given(
  'en la plantilla de un equipo de mi club, en la temporada en curso, he pedido dar de baja a un jugador',
  async function (this: ScenarioWorld) {
    await teamWithPlayers(this)
    await openTeamRoster(this)
    await rowAction(this, 'Dar de baja')
    await removeConfirm(this).waitFor()
  },
)

Given('he pedido dar de baja al jugador desde su ficha', async function (this: ScenarioWorld) {
  await sheet(this).getByRole('button', { name: 'Dar de baja', exact: true }).click()
  await removeConfirm(this).waitFor()
})

When('confirmo la baja', async function (this: ScenarioWorld) {
  await removeConfirm(this).getByRole('button', { name: 'Dar de baja', exact: true }).click()
})

When('cancelo la baja', async function (this: ScenarioWorld) {
  await removeConfirm(this).getByRole('button', { name: 'Cancelar', exact: true }).click()
  await removeConfirm(this).waitFor({ state: 'detached' })
})

Given(
  'en el diálogo del alta de la plantilla del equipo he rellenado un jugador nuevo con el dorsal del dado de baja',
  async function (this: ScenarioWorld) {
    await openTeamRoster(this)
    await openDialog(this)
    await fillNew(this, ['el dorsal'], thePlayer(this).shirtNumber!)
  },
)

// ── Lo que se ve: la ficha ───────────────────────────────────────────────────────────────────────────────────

Then('la ficha del jugador tiene el nombre de su perfil como «Nombre Apellidos»', async function (this: ScenarioWorld) {
  const name = shownName(thePlayer(this).fullName)
  await this.check('el nombre', () => shows(this.page.getByRole('heading', { level: 1, name, exact: true }), `el título «${name}»`))
})

Then('la ficha del jugador tiene su equipo y la temporada en curso', async function (this: ScenarioWorld) {
  const expected = `${theTeam(this).name} · ${currentSeason().label}`
  await this.check('el equipo', () => shows(sheet(this).getByText(expected, { exact: true }), `«${expected}»`))
})

async function factIs(world: ScenarioWorld, label: string, expected: string) {
  await world.check(label, () => becomes(world.page, async () => (await factOf(world, label).innerText()).trim(), expected, label))
}

Then('la ficha del jugador tiene el dorsal de la plantilla', async function (this: ScenarioWorld) {
  await factIs(this, 'Dorsal', String(thePlayer(this).shirtNumber))
})

Then('la ficha del jugador tiene la demarcación de la plantilla', async function (this: ScenarioWorld) {
  await factIs(this, 'Demarcación', positionNames[thePlayer(this).position!])
})

Then('la ficha del jugador tiene el año de su perfil', async function (this: ScenarioWorld) {
  await factIs(this, 'Año de nacimiento', String(thePlayer(this).birthYear))
})

Then('la ficha del jugador dice {string} en el año de nacimiento', async function (this: ScenarioWorld, text: string) {
  await factIs(this, 'Año de nacimiento', text)
})

/** El camino de la foto de la ficha, sin la firma, o «ninguna». */
async function sheetPhotoPath(world: ScenarioWorld): Promise<string> {
  const img = sheetPhotoBox(world).getByRole('img')
  return (await img.count()) > 0 ? pathOf((await img.getAttribute('src')) ?? '') : 'ninguna'
}

Then('la ficha del jugador tiene su foto', async function (this: ScenarioWorld) {
  await this.check('la foto', async () => {
    await becomes(this.page, async () => (await sheetPhotoPath(this)) !== 'ninguna', true, 'que la ficha tenga foto')
    await becomes(
      this.page,
      () => sheetPhotoBox(this).getByRole('img').evaluate((img: HTMLImageElement) => img.complete && img.naturalWidth > 0),
      true,
      'la foto cargada',
    )
  })
})

Then('la ficha del jugador tiene las iniciales de su nombre en el sitio de la foto', async function (this: ScenarioWorld) {
  const initials = initialsOf(thePlayer(this).fullName)
  await this.check('las iniciales', () =>
    becomes(this.page, async () => (await sheetPhotoBox(this).locator('.initials').count()) > 0 ? (await sheetPhotoBox(this).locator('.initials').innerText()).trim() : 'ninguna', initials, 'el sitio de la foto'),
  )
})

Then('la foto de la ficha del jugador no tiene ubicación', async function (this: ScenarioWorld) {
  await this.check('la ubicación', async () => {
    await becomes(this.page, async () => (await sheetPhotoPath(this)) !== 'ninguna', true, 'que la ficha tenga foto')
    // El fichero que sirve el servidor, leído desde la página: ni el bloque Exif ni lo que llevaba dentro.
    const src = (await sheetPhotoBox(this).getByRole('img').getAttribute('src'))!
    const text = await this.page.evaluate(async (url) => {
      const bytes = new Uint8Array(await (await fetch(url)).arrayBuffer())
      return Array.from(bytes, (byte) => String.fromCharCode(byte)).join('')
    }, src)
    // Que lo leído es la foto, un JPEG, y no una página de error, que tampoco llevaría la ubicación.
    if (!text.startsWith('\xff\xd8')) throw new Error('lo que sirve el servidor no es un JPEG')
    if (text.includes(LOCATION_MARK)) throw new Error('la foto lleva la ubicación de la original')
    if (text.includes('Exif\0\0')) throw new Error('la foto lleva un bloque Exif')
  })
})

Then(
  'la ficha del jugador no tiene los botones "Corregir", "Dar de baja" ni los de la foto',
  async function (this: ScenarioWorld) {
    for (const name of ['Corregir', 'Dar de baja', 'Poner foto', 'Cambiar foto', 'Quitar foto']) {
      await this.check(`sin «${name}»`, () => absent(sheet(this).getByRole('button', { name, exact: true }), `el botón «${name}»`))
    }
  },
)

Then('estoy en la pestaña Plantilla de la ficha de su equipo, en la temporada en curso', async function (this: ScenarioWorld) {
  await this.check('la dirección', () =>
    becomes(this.page, async () => new URL(this.page.url()).pathname, rosterPath(currentSeason(), theTeam(this).id!), 'el camino'),
  )
  await this.check('la pestaña', () => shows(rosterTab(this), 'la pestaña Plantilla'))
})

// ── Lo que se ve: el diálogo de corregir ─────────────────────────────────────────────────────────────────────

Then('el diálogo de corregir está abierto', async function (this: ScenarioWorld) {
  const name = `Corregir a ${shownName(thePlayer(this).fullName)}`
  await this.check('el diálogo', () => shows(this.page.getByRole('dialog', { name, exact: true }), `el diálogo «${name}»`))
})

Then('el diálogo de corregir tiene el nombre y el año de su perfil', async function (this: ScenarioWorld) {
  const player = thePlayer(this)
  await this.check('el nombre', () =>
    becomes(this.page, () => editDialog(this).locator('#player-search').inputValue(), shownName(player.fullName), 'el nombre'),
  )
  await this.check('el año', () =>
    becomes(this.page, () => editDialog(this).locator('#player-year').inputValue(), player.birthYear == null ? '' : String(player.birthYear), 'el año'),
  )
})

Then('el diálogo de corregir tiene el dorsal, la demarcación y la foto de la plantilla', async function (this: ScenarioWorld) {
  const player = thePlayer(this)
  await this.check('el dorsal', () =>
    becomes(this.page, () => editDialog(this).locator('#player-shirt').inputValue(), player.shirtNumber == null ? '' : String(player.shirtNumber), 'el dorsal'),
  )
  await this.check('la demarcación', () =>
    becomes(
      this.page,
      async () => (await editDialog(this).getByRole('combobox', { name: 'Demarcación' }).innerText()).trim(),
      player.position == null ? 'Sin demarcación' : positionNames[player.position],
      'la demarcación',
    ),
  )
  await this.check('la foto', () =>
    becomes(
      this.page,
      async () => {
        const img = editDialog(this).locator('.photo-field').getByRole('img')
        return (await img.count()) > 0 ? pathOf((await img.getAttribute('src')) ?? '') : 'ninguna'
      },
      player.photoPath ?? 'ninguna',
      'la foto',
    ),
  )
})

/** Un bloque del diálogo: el grupo de campos con su título. */
const block = (world: ScenarioWorld, legend: string) =>
  editDialog(world).getByRole('group', { name: legend, exact: true })

Then(
  'el diálogo de corregir tiene un bloque {string} con el nombre y el año',
  async function (this: ScenarioWorld, legend: string) {
    for (const id of ['player-search', 'player-year']) {
      await this.check(`«${id}» en «${legend}»`, () => shows(block(this, legend).locator(`#${id}`), `el campo ${id} en «${legend}»`))
    }
  },
)

Then(
  'el diálogo de corregir tiene un bloque con el equipo y la temporada en curso, con el dorsal, la demarcación y la foto',
  async function (this: ScenarioWorld) {
    const legend = `En ${theTeam(this).name}, ${currentSeason().label}`
    for (const id of ['player-shirt', 'player-position', 'player-photo']) {
      await this.check(`«${id}» en «${legend}»`, () =>
        shows(block(this, legend).locator(`[id="${id}"], label[for="${id}"]`), `el campo ${id} en «${legend}»`),
      )
    }
  },
)

Then(
  'el campo "Año de nacimiento" del diálogo de corregir tiene el año de su perfil, bloqueado',
  async function (this: ScenarioWorld) {
    const year = editDialog(this).locator('#player-year')
    await this.check('el año', () => becomes(this.page, () => year.inputValue(), String(thePlayer(this).birthYear), 'el año'))
    await this.check('bloqueado', async () => {
      if (!(await year.isDisabled())) throw new Error('se puede cambiar')
    })
  },
)

Then('la confirmación del año dice que no se podrá cambiar después', async function (this: ScenarioWorld) {
  await this.check('el aviso', () => shows(yearConfirm(this).getByText('El año no se podrá cambiar después.'), 'que no se podrá cambiar'))
})

Then(
  'la confirmación del año dice que, si es un error, hay que dar de baja al jugador y darlo de alta como nuevo',
  async function (this: ScenarioWorld) {
    const text = 'Si te equivocas, tendrás que dar de baja al jugador y darlo de alta como nuevo.'
    await this.check('qué hacer', () => shows(yearConfirm(this).getByText(text), `«${text}»`))
  },
)

Then('el diálogo de corregir dice que no se pueden cambiar a la vez el nombre y el año', async function (this: ScenarioWorld) {
  await this.check('el aviso', () =>
    shows(editDialog(this).getByText(/No se pueden cambiar a la vez el nombre y el año\./), 'que no se pueden cambiar a la vez'),
  )
})

Then(
  'el diálogo de corregir dice que, si es otra persona, hay que dar de baja a este jugador y dar de alta al otro como nuevo',
  async function (this: ScenarioWorld) {
    await this.check('qué hacer', () =>
      shows(
        editDialog(this).getByText(/Si es otra persona, da de baja a este jugador y da de alta al otro como nuevo\./),
        'qué hacer si es otra persona',
      ),
    )
  },
)

Then(
  'el campo "Dorsal" del diálogo de corregir dice "ya lo tiene" y el nombre del otro jugador',
  async function (this: ScenarioWorld) {
    const expected = `ya lo tiene ${shownName(this.data.present!.fullName)}`
    await this.check('el error del dorsal', () => shows(editDialog(this).locator('#player-shirt-error').filter({ hasText: expected }), `«${expected}»`))
  },
)

// ── Lo que se ve: la plantilla y el perfil ───────────────────────────────────────────────────────────────────

/** La fila del jugador del escenario, con el nombre que tenga ahora (el nuevo, si se ha corregido). */
const current = (world: ScenarioWorld) => ({ fullName: world.data.newPlayer?.fullName ?? thePlayer(world).fullName })

async function rowCell(world: ScenarioWorld, which: 'shirtNumber' | 'birthYear', expected: string, what: string) {
  await world.check(what, async () => {
    await shows(rowOfPlayer(world, current(world)), `la fila de ${shownName(current(world).fullName)}`)
    await becomes(world.page, () => textOf(world, current(world), which), expected, what)
  })
}

Then('la fila del jugador en la plantilla tiene el dorsal nuevo', async function (this: ScenarioWorld) {
  await rowCell(this, 'shirtNumber', String(this.data.newPlayer!.shirtNumber), 'el dorsal')
})

Then('la fila del jugador en la plantilla tiene el dorsal de antes', async function (this: ScenarioWorld) {
  await editDialog(this).waitFor({ state: 'detached' })
  await this.check('el dorsal', () => becomes(this.page, () => textOf(this, thePlayer(this), 'shirtNumber'), String(thePlayer(this).shirtNumber), 'el dorsal'))
})

Then('la fila del jugador en la plantilla tiene el nombre nuevo', async function (this: ScenarioWorld) {
  await this.check('el nombre', () => shows(rowOfPlayer(this, current(this)), `la fila de ${shownName(current(this).fullName)}`))
})

Then('la fila del jugador en la plantilla tiene el año que he puesto', async function (this: ScenarioWorld) {
  await rowCell(this, 'birthYear', String(this.data.newPlayer!.birthYear), 'el año')
})

Then('la fila del jugador en la plantilla dice {string} en el año de nacimiento', async function (this: ScenarioWorld, text: string) {
  await editDialog(this).waitFor({ state: 'detached' })
  await this.check('el año', () => becomes(this.page, () => textOf(this, thePlayer(this), 'birthYear'), text, 'el año'))
})

/** El perfil del jugador del escenario, por la API, cuando lo guardado ya se ve. */
async function profile(world: ScenarioWorld) {
  return profileOf(world, current(world).fullName, thePlayer(world).profileId)
}

Then('el perfil del jugador tiene el dorsal nuevo', async function (this: ScenarioWorld) {
  await this.check('el perfil', async () => {
    await shows(rowOfPlayer(this, current(this)), 'la fila')
    await becomes(this.page, async () => String((await profile(this)).lastShirtNumber), String(this.data.newPlayer!.shirtNumber), 'el dorsal del perfil')
  })
})

Then('el perfil del jugador tiene la foto nueva', async function (this: ScenarioWorld) {
  await this.check('el perfil', async () => {
    await becomes(this.page, async () => (await sheetPhotoPath(this)) !== 'ninguna', true, 'que la ficha tenga foto')
    const seen = await sheetPhotoPath(this)
    await becomes(this.page, async () => {
      const url = (await profile(this)).lastPhotoUrl
      return url ? pathOf(url) : 'ninguna'
    }, seen, 'la foto del perfil')
  })
})

Then('el perfil del jugador no tiene foto', async function (this: ScenarioWorld) {
  await this.check('el perfil', () =>
    becomes(this.page, async () => {
      const url = (await profile(this)).lastPhotoUrl
      return url ? pathOf(url) : 'ninguna'
    }, 'ninguna', 'la foto del perfil'),
  )
})

// ── La baja ──────────────────────────────────────────────────────────────────────────────────────────────────

Then(
  'la confirmación de la baja pregunta si dar de baja al jugador, con su nombre y su equipo',
  async function (this: ScenarioWorld) {
    const text = `¿Dar de baja a ${shownName(thePlayer(this).fullName)} del ${theTeam(this).name}?`
    await this.check('la pregunta', () => shows(removeConfirm(this).getByText(text, { exact: true }), `«${text}»`))
  },
)

Then('la confirmación de la baja dice que sus goles y tarjetas siguen contando para el equipo', async function (this: ScenarioWorld) {
  const text = 'Sus goles y tarjetas siguen contando para el equipo.'
  await this.check('los goles', () => shows(removeConfirm(this).getByText(text), `«${text}»`))
})

Then('la confirmación de la baja dice que sincronizar con la Federación no lo volverá a añadir', async function (this: ScenarioWorld) {
  const text = 'Sincronizar con la Federación no lo volverá a añadir.'
  await this.check('sincronizar', () => shows(removeConfirm(this).getByText(text), `«${text}»`))
})

Then('la plantilla ya no tiene al jugador', async function (this: ScenarioWorld) {
  await this.check('el jugador', async () => {
    await rosterLoaded(this)
    await becomes(this.page, async () => (await shownNames(this)).includes(shownName(thePlayer(this).fullName)), false, 'que esté en la plantilla')
  })
})

Then('la plantilla sigue teniendo al jugador', async function (this: ScenarioWorld) {
  await this.check('el jugador', () => shows(rowOfPlayer(this, thePlayer(this)), `la fila de ${shownName(thePlayer(this).fullName)}`))
})

Then('la plantilla tiene al jugador nuevo con ese dorsal', async function (this: ScenarioWorld) {
  const entered = this.data.newPlayer!
  await this.check('el dorsal', async () => {
    await shows(rowOfPlayer(this, { fullName: entered.fullName! }), 'la fila del jugador nuevo')
    await becomes(this.page, () => textOf(this, { fullName: entered.fullName! }, 'shirtNumber'), String(entered.shirtNumber), 'el dorsal')
  })
})


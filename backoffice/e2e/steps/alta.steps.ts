// El alta de equipo y «Crear nueva temporada» (plan R2, §3.2–§3.4). El equipo que se escribe en el formulario se
// inventa al azar (invented.ts) y se guarda en `data.entered`, para que los `Then` busquen en la pantalla siguiente
// lo mismo que se metió.
import { Given, Then, When } from '@cucumber/cucumber'
import type { Locator } from 'playwright'
import { addArchivedSeason, addSeason } from '../support/club-data.ts'
import { categoryLabels, currentSeason, nextSeason, pastSeason, team, type Season, type Team } from '../support/invented.ts'
import { becomes, shows } from '../support/look.ts'
import type { ScenarioWorld } from '../support/world.ts'
import { addPastSeason, addTeamPlaying, content, inAddress, lastPastSeason, row } from './portada.steps.ts'

const genderLabels = { masculino: 'Masculino', femenino: 'Femenino' }
const modalityLabels = { futbol_11: 'Fútbol 11', futbol_7: 'Fútbol 7', futbol_sala: 'Fútbol sala', futbol_5: 'Fútbol 5' }

// ── Dónde está cada cosa ─────────────────────────────────────────────────────────────────────────────────────

// El formulario está en la zona principal; el diálogo de PrimeVue se pinta fuera de ella, encima de todo.
const form = (world: ScenarioWorld) => world.page.getByRole('main')
const dialog = (world: ScenarioWorld) => world.page.getByRole('dialog', { name: 'Crear nueva temporada' })
// Un campo del formulario por su nombre, que empieza por el de su etiqueta: «Categoría (obligatorio)».
const field = (world: ScenarioWorld, name: string) =>
  form(world).getByRole(name === 'Letra' ? 'textbox' : 'combobox', { name: new RegExp(`^${name}`) })
const seasonPicker = (world: ScenarioWorld) => field(world, 'Temporada')
const errorList = (world: ScenarioWorld) => form(world).getByRole('group', { name: /^Revisa est/ })

function seasonByName(world: ScenarioWorld, which: string): Season {
  if (which === 'en curso') return currentSeason()
  if (which === 'siguiente') return nextSeason()
  if (which === 'pasada') return lastPastSeason(world)
  throw new Error(`«${which}» no es una temporada que el escenario conozca`)
}

// ── Llegar al formulario ─────────────────────────────────────────────────────────────────────────────────────

/** Espera a que el formulario esté listo: su título, y su selector de temporada fuera de «Cargando temporadas…». */
async function formReady(world: ScenarioWorld) {
  await world.page.getByRole('heading', { level: 1, name: 'Dar de alta un equipo' }).waitFor()
  await form(world).getByText('Cargando temporadas…').waitFor({ state: 'detached' })
}

/** Abre la portada del club (en esa temporada, si se dice) y pulsa «Dar de alta un equipo», como el usuario. */
async function openFormFromHome(world: ScenarioWorld, season?: Season) {
  await world.page.goto(world.clubUrl(season ? `/?temporada=${inAddress(season)}` : '/'))
  await content(world).getByRole('link', { name: 'Dar de alta un equipo' }).first().click()
  await formReady(world)
}

Given('estoy en el formulario de alta de equipo, abierto desde la portada de mi club', async function (this: ScenarioWorld) {
  await openFormFromHome(this)
})

When('abro el formulario de alta de equipo desde la portada de mi club', async function (this: ScenarioWorld) {
  await openFormFromHome(this)
})

Given(
  'estoy en el formulario de alta de equipo, abierto desde la portada de mi club en una temporada pasada',
  async function (this: ScenarioWorld) {
    await openFormFromHome(this, await addPastSeason(this))
  },
)

Given('estoy en el formulario de alta de equipo de un club sin temporadas', async function (this: ScenarioWorld) {
  // El club de cada escenario nace sin temporadas: basta con no darle ninguna.
  await openFormFromHome(this)
})

Given('estoy en el formulario de alta de equipo con una categoría elegida', async function (this: ScenarioWorld) {
  await openFormFromHome(this)
  const entered = team(this.random, this.data.teams)
  await choose(this, 'Categoría', categoryLabels[entered.category])
  this.note(`categoría elegida: ${categoryLabels[entered.category]}`)
})

// ── Rellenar y guardar ───────────────────────────────────────────────────────────────────────────────────────

/** Elige una opción de un selector del formulario, con el ratón. */
async function choose(world: ScenarioWorld, name: string, option: string) {
  await field(world, name).click()
  await world.page.getByRole('option', { name: option, exact: true }).click()
  await world.page.getByRole('listbox').waitFor({ state: 'detached' })
}

/** Escribe el equipo en el formulario; la temporada, solo si se dice (si no, la que trae). */
async function fillTeam(world: ScenarioWorld, entered: Team, season?: Season) {
  await choose(world, 'Categoría', categoryLabels[entered.category])
  if (entered.letter) await field(world, 'Letra').fill(entered.letter)
  await choose(world, 'Género', genderLabels[entered.gender])
  await choose(world, 'Modalidad', modalityLabels[entered.modality])
  if (season) await choose(world, 'Temporada', season.label)
}

/** Guarda y espera a llegar a la portada. */
async function saveAndArrive(world: ScenarioWorld) {
  await form(world).getByRole('button', { name: 'Guardar' }).click()
  await world.page.waitForURL((url) => url.pathname === '/')
}

/** Da de alta un equipo nuevo, inventado, desde el formulario abierto; lo apunta para los `Then`. */
async function addNewTeam(world: ScenarioWorld, season?: Season) {
  const entered = team(world.random, world.data.teams)
  world.data.entered = entered
  world.data.team = entered
  world.data.teams.push(entered)
  world.note(`equipo dado de alta: ${entered.name} (${entered.gender}, ${entered.modality})`)
  await fillTeam(world, entered, season)
  await saveAndArrive(world)
}

When('en el formulario de alta, doy de alta un equipo nuevo', async function (this: ScenarioWorld) {
  await addNewTeam(this)
})

When('en el formulario de alta, doy de alta un equipo nuevo en la temporada elegida', async function (this: ScenarioWorld) {
  await addNewTeam(this)
})

When('en el formulario de alta, doy de alta un equipo nuevo en la temporada pasada', async function (this: ScenarioWorld) {
  await addNewTeam(this, lastPastSeason(this))
})

/**
 * El equipo del escenario (el que ya juega en otra temporada, o el ya inscrito), escrito otra vez en el formulario y
 * guardado. Espera a lo que pase: llegar a la portada (se inscribe) o el aviso del formulario (ya estaba).
 */
async function addSameTeam(world: ScenarioWorld) {
  const same = world.data.team!
  world.data.entered = same
  await fillTeam(world, same)
  await form(world).getByRole('button', { name: 'Guardar' }).click()
  await Promise.race([
    world.page.waitForURL((url) => url.pathname === '/'),
    form(world).getByRole('alert').waitFor(),
  ])
}

When('en el formulario de alta, doy de alta el mismo equipo en la temporada en curso', async function (this: ScenarioWorld) {
  await addSameTeam(this)
})

When('pulso el enlace {string} de la portada', async function (this: ScenarioWorld, name: string) {
  await content(this).getByRole('link', { name }).first().click()
})

When('envío el formulario de alta sin rellenar', async function (this: ScenarioWorld) {
  await form(this).getByRole('button', { name: 'Guardar' }).click()
})

When('pulso {string} en el formulario de alta', async function (this: ScenarioWorld, name: string) {
  await form(this).getByRole('button', { name, exact: true }).click()
})

When('recargo el formulario de alta', async function (this: ScenarioWorld) {
  await this.page.reload()
  await formReady(this)
})

// ── Con el teclado ───────────────────────────────────────────────────────────────────────────────────────────

/** Pulsa el tabulador hasta que el foco llega a `target` (como mucho, 30 veces). */
async function tabTo(world: ScenarioWorld, target: Locator, what: string) {
  for (let i = 0; i < 30; i++) {
    if (await target.evaluate((el) => el === document.activeElement || el.contains(document.activeElement))) return
    await world.page.keyboard.press('Tab')
  }
  throw new Error(`el tabulador no llega a ${what}`)
}

/** Elige una opción de un selector solo con el teclado: se abre con la flecha y se baja hasta ella. */
async function chooseWithKeyboard(world: ScenarioWorld, name: string, option: string) {
  const select = field(world, name)
  await tabTo(world, select, `el campo ${name}`)
  await world.page.keyboard.press('ArrowDown')
  const listbox = world.page.getByRole('listbox')
  await listbox.waitFor()
  for (let i = 0; i < 20; i++) {
    const focused = await world.page.evaluate(() => {
      const id = document.activeElement?.getAttribute('aria-activedescendant')
      return id ? document.getElementById(id)?.getAttribute('aria-label') : null
    })
    if (focused === option) break
    await world.page.keyboard.press('ArrowDown')
  }
  await world.page.keyboard.press('Enter')
  await listbox.waitFor({ state: 'detached' })
}

When('desde la portada, doy de alta un equipo nuevo usando solo el teclado', async function (this: ScenarioWorld) {
  const entered = team(this.random, this.data.teams)
  this.data.entered = entered
  this.data.team = entered
  this.note(`equipo dado de alta con el teclado: ${entered.name} (${entered.gender}, ${entered.modality})`)
  // El primero: el de junto al selector (con la temporada vacía, hay otro debajo del mensaje).
  await tabTo(this, content(this).getByRole('link', { name: 'Dar de alta un equipo' }).first(), 'el enlace «Dar de alta un equipo»')
  await this.page.keyboard.press('Enter')
  await formReady(this)
  await chooseWithKeyboard(this, 'Categoría', categoryLabels[entered.category])
  if (entered.letter) {
    await tabTo(this, field(this, 'Letra'), 'el campo Letra')
    await this.page.keyboard.type(entered.letter)
  }
  await chooseWithKeyboard(this, 'Género', genderLabels[entered.gender])
  await chooseWithKeyboard(this, 'Modalidad', modalityLabels[entered.modality])
  await tabTo(this, form(this).getByRole('button', { name: 'Guardar' }), 'el botón Guardar')
  await this.page.keyboard.press('Enter')
  await this.page.waitForURL((url) => url.pathname === '/')
})

// ── Lo que ya ha pasado (Given complejos) ────────────────────────────────────────────────────────────────────

Given('he dado de alta un equipo nuevo desde la portada de mi club', async function (this: ScenarioWorld) {
  await addSeason(this.club, currentSeason())
  await openFormFromHome(this)
  await addNewTeam(this)
})

Given(
  'he dado de alta en la temporada en curso el equipo que jugaba en una temporada pasada',
  async function (this: ScenarioWorld) {
    const past = pastSeason(this.random, this.data.pastSeasons)
    this.data.pastSeasons.push(past)
    await addTeamPlaying(this, past)
    await addSeason(this.club, currentSeason())
    await openFormFromHome(this)
    await addSameTeam(this)
  },
)

// ── «Crear nueva temporada» ──────────────────────────────────────────────────────────────────────────────────

async function openDialog(world: ScenarioWorld) {
  await form(world).getByRole('button', { name: 'Crear nueva temporada' }).click()
  await dialog(world).waitFor()
}

const labelField = (world: ScenarioWorld) => dialog(world).getByRole('textbox', { name: /^Temporada/ })

/** Escribe la etiqueta y pulsa «Crear». Si la crea, espera a que el diálogo se cierre. */
async function createSeason(world: ScenarioWorld, label: string, expectClosed: boolean) {
  await labelField(world).fill(label)
  await dialog(world).getByRole('button', { name: 'Crear', exact: true }).click()
  if (expectClosed) await dialog(world).waitFor({ state: 'detached' })
}

Given('tengo abierto «Crear nueva temporada» en el formulario de alta de equipo', async function (this: ScenarioWorld) {
  await openFormFromHome(this)
  await openDialog(this)
})

Given(
  'tengo abierto «Crear nueva temporada» en el formulario de alta, con la temporada siguiente escrita',
  async function (this: ScenarioWorld) {
    await openFormFromHome(this)
    await openDialog(this)
    await labelField(this).fill(nextSeason().label)
  },
)

Given(
  'he creado la temporada en curso desde el formulario de alta de un club sin temporadas',
  async function (this: ScenarioWorld) {
    await openFormFromHome(this)
    await openDialog(this)
    await createSeason(this, currentSeason().label, true)
  },
)

Given('mi club tiene una temporada pasada archivada', async function (this: ScenarioWorld) {
  const season = pastSeason(this.random, this.data.pastSeasons)
  await addArchivedSeason(this.club, season)
  this.data.archivedSeason = season
  this.note(`temporada archivada ${season.label}`)
})

When(
  /^en el formulario de alta, creo la temporada (en curso|siguiente) con «Crear nueva temporada»$/,
  async function (this: ScenarioWorld, which: string) {
    await openDialog(this)
    await createSeason(this, seasonByName(this, which).label, true)
  },
)

When('en el diálogo «Crear nueva temporada», creo la temporada {string}', async function (this: ScenarioWorld, label: string) {
  await createSeason(this, label, false)
})

When('en el diálogo «Crear nueva temporada», creo la temporada archivada', async function (this: ScenarioWorld) {
  await createSeason(this, this.data.archivedSeason!.label, false)
})

When('pulso {string} en el diálogo «Crear nueva temporada»', async function (this: ScenarioWorld, name: string) {
  await dialog(this).getByRole('button', { name, exact: true }).click()
  await dialog(this).waitFor({ state: 'detached' })
})

When('pulso Escape en el diálogo «Crear nueva temporada»', async function (this: ScenarioWorld) {
  await this.page.keyboard.press('Escape')
  await dialog(this).waitFor({ state: 'detached' })
})

// ── Lo que se ve: dónde estoy ────────────────────────────────────────────────────────────────────────────────

async function onForm(world: ScenarioWorld) {
  await world.check('la dirección', () =>
    becomes(world.page, async () => new URL(world.page.url()).pathname, '/equipos/nuevo', 'el camino'),
  )
  await world.check('el título', () =>
    shows(world.page.getByRole('heading', { level: 1, name: 'Dar de alta un equipo' }), 'el título «Dar de alta un equipo»'),
  )
}

Then('estoy en el formulario de alta', async function (this: ScenarioWorld) {
  await onForm(this)
})

Then('sigo en el formulario de alta', async function (this: ScenarioWorld) {
  await onForm(this)
})

Then(/^estoy en la portada, en la temporada (en curso|pasada)$/, async function (this: ScenarioWorld, which: string) {
  const expected = seasonByName(this, which).label
  await this.check('la dirección', () =>
    becomes(this.page, async () => new URL(this.page.url()).pathname, '/', 'el camino'),
  )
  await this.check('el título de la portada', () =>
    shows(this.page.getByRole('heading', { level: 1, name: 'Equipos' }), 'el título «Equipos»'),
  )
  await this.check('la temporada de la portada', () =>
    becomes(
      this.page,
      async () => (await this.page.getByRole('combobox', { name: 'Temporada', exact: true }).textContent())?.trim(),
      expected,
      'la temporada del selector de la portada',
    ),
  )
})

// ── Lo que se ve: el formulario ──────────────────────────────────────────────────────────────────────────────

Then(
  /^el selector de temporada del formulario de alta tiene elegida la temporada (en curso|pasada|siguiente)$/,
  async function (this: ScenarioWorld, which: string) {
    const expected = seasonByName(this, which).label
    await this.check('la temporada del formulario', () =>
      becomes(this.page, async () => (await seasonPicker(this).textContent())?.trim(), expected, 'la temporada elegida'),
    )
  },
)

Then('el selector de temporada del formulario de alta no tiene la temporada siguiente', async function (this: ScenarioWorld) {
  const label = nextSeason().label
  await this.check(`la temporada ${label} en el selector`, async () => {
    // Se abre la lista para leer sus opciones y se cierra igual que estaba.
    await seasonPicker(this).click()
    await this.page.getByRole('listbox').waitFor()
    const options = await this.page.getByRole('option').allTextContents()
    await this.page.keyboard.press('Escape')
    await this.page.getByRole('listbox').waitFor({ state: 'detached' })
    if (options.map((o) => o.trim()).includes(label)) throw new Error(`el selector tiene ${label}, y no debería`)
  })
})

/** El nombre accesible y la descripción de un campo: lo que dice el lector al llegar a él. */
// Sin funciones con nombre dentro: lo que va al navegador no puede llevar las ayudas que añade tsx al compilar.
async function readField(locator: Locator) {
  return locator.evaluate((el) => {
    // La etiqueta: la que le pone nombre (aria-labelledby), o la que apunta a su `id`.
    const labelledBy = el.getAttribute('aria-labelledby')
    const label = labelledBy ? document.getElementById(labelledBy) : document.querySelector(`label[for="${el.id}"]`)
    const visible = label?.textContent?.replace(/\s+/g, ' ').trim() ?? ''
    // Lo que se ve pero no se lee: el asterisco.
    let hidden = ''
    for (const node of Array.from(label?.querySelectorAll('[aria-hidden="true"]') ?? [])) hidden += node.textContent?.trim() ?? ''
    // Lo que se lee después del nombre: la ayuda y el error.
    let description = ''
    for (const id of (el.getAttribute('aria-describedby') ?? '').split(' ').filter(Boolean)) {
      description = `${description} ${document.getElementById(id)?.textContent?.trim() ?? ''}`.trim()
    }
    return { visible, hidden, description }
  })
}

Then('el campo {string} del formulario de alta es obligatorio', async function (this: ScenarioWorld, name: string) {
  await this.check(`el campo ${name}`, async () => {
    const locator = field(this, name)
    await shows(locator, `el campo ${name}`)
    const { visible, hidden } = await readField(locator)
    if (hidden !== '*') throw new Error(`no lleva el asterisco que se ve`)
    if (!visible.includes('(obligatorio)')) throw new Error(`su etiqueta no dice «obligatorio» al lector: «${visible}»`)
  })
})

Then(
  'el campo {string} del formulario de alta es opcional, con la ayuda {string}',
  async function (this: ScenarioWorld, name: string, help: string) {
    await this.check(`el campo ${name}`, async () => {
      const locator = field(this, name)
      await shows(locator, `el campo ${name}`)
      const { visible, hidden, description } = await readField(locator)
      if (hidden || visible.includes('obligatorio')) throw new Error(`se marca como obligatorio: «${visible}»`)
      if (description !== help) throw new Error(`su ayuda es «${description}», y se esperaba «${help}»`)
    })
  },
)

Then('la lista de errores del formulario de alta tiene el foco', async function (this: ScenarioWorld) {
  await this.check('la lista de errores', () =>
    becomes(this.page, () => errorList(this).evaluate((el) => el === document.activeElement), true, 'el foco en la lista'),
  )
})

Then('la lista de errores del formulario de alta nombra {string}', async function (this: ScenarioWorld, name: string) {
  await this.check(`«${name}» en la lista de errores`, () =>
    shows(errorList(this).getByRole('link', { name: new RegExp(`^${name}:`) }), `el enlace a «${name}» en la lista de errores`),
  )
})

Then('el formulario de alta avisa arriba {string}', async function (this: ScenarioWorld, text: string) {
  await this.check('el aviso', () => shows(form(this).getByRole('alert').filter({ hasText: text }), `el aviso «${text}»`))
})

Then('el formulario de alta conserva la categoría del equipo', async function (this: ScenarioWorld) {
  const expected = categoryLabels[this.data.entered!.category]
  await this.check('la categoría', () =>
    becomes(this.page, async () => (await field(this, 'Categoría').textContent())?.trim(), expected, 'la categoría'),
  )
})

Then('el formulario de alta conserva la letra del equipo', async function (this: ScenarioWorld) {
  const expected = this.data.entered!.letter ?? ''
  await this.check('la letra', () => becomes(this.page, () => field(this, 'Letra').inputValue(), expected, 'la letra'))
})

Then('el formulario de alta pregunta {string}', async function (this: ScenarioWorld, text: string) {
  await this.check('la pregunta', () =>
    shows(this.page.getByRole('dialog', { name: 'Cambios sin guardar' }).getByText(text, { exact: true }), `«${text}»`),
  )
})

Then('el foco está en el botón {string} del formulario de alta', async function (this: ScenarioWorld, name: string) {
  await this.check(`el foco en «${name}»`, () =>
    becomes(
      this.page,
      () => form(this).getByRole('button', { name, exact: true }).evaluate((el) => el === document.activeElement),
      true,
      `el foco en el botón «${name}»`,
    ),
  )
})

// ── Lo que se ve: el diálogo ─────────────────────────────────────────────────────────────────────────────────

Then('el campo del diálogo «Crear nueva temporada» dice {string}', async function (this: ScenarioWorld, text: string) {
  await this.check('el error del campo', () =>
    shows(dialog(this).getByText(text, { exact: true }), `«${text}» junto al campo`),
  )
})

Then('el diálogo «Crear nueva temporada» avisa arriba {string}', async function (this: ScenarioWorld, text: string) {
  await this.check('el aviso', () => shows(dialog(this).getByRole('alert').filter({ hasText: text }), `el aviso «${text}»`))
})

// ── Lo que se ve: la portada a la que se llega ───────────────────────────────────────────────────────────────

Then(
  'la tabla de la portada tiene el equipo que he dado de alta, con su categoría y su letra',
  async function (this: ScenarioWorld) {
    const name = this.data.entered!.name
    await this.check(`la fila de ${name}`, () => shows(row(this, name), `la fila de «${name}»`))
  },
)

Then('la portada tiene el aviso {string}', async function (this: ScenarioWorld, text: string) {
  await this.check(`el aviso «${text}»`, () =>
    shows(this.page.getByRole('status').filter({ hasText: text }), `el aviso «${text}»`),
  )
})

Then('el mensaje de la portada vacía tiene debajo el enlace {string}', async function (this: ScenarioWorld, name: string) {
  const message = `No hay equipos en la temporada ${currentSeason().label}.`
  await this.check(`el enlace «${name}» debajo del mensaje`, () =>
    shows(
      content(this).getByText(message, { exact: true }).locator('xpath=following-sibling::*[1]').and(
        this.page.getByRole('link', { name }),
      ),
      `el enlace «${name}» justo debajo de «${message}»`,
    ),
  )
})


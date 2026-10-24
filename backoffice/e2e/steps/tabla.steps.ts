// La tabla de la portada: ordenar por sus columnas, y los equipos que se llamarían igual (bloque T del plan R2).
import { Given, Then, When } from '@cucumber/cucumber'
import { addPlayingTeam, addTeam, setIngestion, type HealthWords, type PlayingTeam } from '../support/club-data.ts'
import { categories, currentSeason, team, twinOf, type Team } from '../support/invented.ts'
import { becomes, shows } from '../support/look.ts'
import type { ScenarioWorld } from '../support/world.ts'
import { content, row } from './portada.steps.ts'

const table = (world: ScenarioWorld) => content(world).getByRole('table')
const genderLabels = { masculino: 'Masculino', femenino: 'Femenino' }

// De peor a mejor: el orden de la columna «Ingesta» en su primer clic (bloque T, decisión 3).
const severity: HealthWords[] = ['Con fallos', 'Desactualizada', 'En marcha', 'Sin datos todavía', 'Al día']

/** El orden en que el servidor manda los equipos: por edad y, dentro, por letra, el que no tiene, delante. */
function serverOrder(a: Team, b: Team): number {
  return categories.indexOf(a.category) - categories.indexOf(b.category) || (a.letter ?? '').localeCompare(b.letter ?? '')
}

/**
 * Equipos que juegan en la temporada en curso, uno por estado de la ingesta. Los estados se reparten por el orden
 * del servidor, en el orden en que se dicen: así, con «Al día», «Con fallos» y «Desactualizada», el orden de
 * siempre, el de peor a mejor y el de mejor a peor salen los tres distintos.
 */
async function teamsPlaying(world: ScenarioWorld, states: string[]) {
  const playing: PlayingTeam[] = []
  for (let i = 0; i < states.length; i++) {
    const added = await addPlayingTeam(world.club, world.random, currentSeason(), world.data.teams)
    world.data.teams.push(added.team)
    playing.push(added)
  }
  playing.sort((a, b) => serverOrder(a.team, b.team))
  for (const [i, state] of states.entries()) {
    await setIngestion(world.club, playing[i]!, state as HealthWords)
    world.data.byHealth[state] = playing[i]!.team
    world.note(`${playing[i]!.team.name}: ingesta «${state}»`)
  }
  world.data.inServerOrder = playing.map((p) => p.team)
}

/** Abre la portada y espera a que tenga la tabla. */
async function openHome(world: ScenarioWorld) {
  await world.page.goto(world.clubUrl())
  await table(world).waitFor()
}

/** Pincha la cabecera de la columna, y espera a que el orden llegue a la dirección. */
async function sortBy(world: ScenarioWorld, column: string) {
  const before = new URL(world.page.url()).search
  await table(world).getByRole('button', { name: column, exact: true }).click()
  await world.page.waitForURL((url) => url.search !== before)
}

Given(
  'en la temporada en curso de mi club juegan tres equipos, con la ingesta {string}, {string} y {string}',
  async function (this: ScenarioWorld, first: string, second: string, third: string) {
    await teamsPlaying(this, [first, second, third])
  },
)

Given(
  /^la portada de mi club está ordenada (al revés )?por "([^"]+)", con tres equipos "([^"]+)", "([^"]+)" y "([^"]+)"$/,
  async function (
    this: ScenarioWorld,
    reversed: string | undefined,
    column: string,
    first: string,
    second: string,
    third: string,
  ) {
    await teamsPlaying(this, [first, second, third])
    await openHome(this)
    await sortBy(this, column)
    if (reversed) await sortBy(this, column)
  },
)

Given(
  'en la temporada en curso de mi club hay dos equipos con la misma categoría y letra y distinto género',
  async function (this: ScenarioWorld) {
    const one = await addTeam(this.club, currentSeason(), team(this.random, this.data.teams))
    const other = await addTeam(this.club, currentSeason(), twinOf(one))
    this.data.twins = [one, other]
    this.note(`dos «${one.name}»: ${one.gender} y ${other.gender} (${one.modality})`)
  },
)

When('ordeno la tabla de la portada por {string}', async function (this: ScenarioWorld, column: string) {
  await sortBy(this, column)
})

When('recargo la portada', async function (this: ScenarioWorld) {
  await this.page.reload()
  await table(this).waitFor()
})

// ── Lo que se ve ─────────────────────────────────────────────────────────────────────────────────────────────

/** Los equipos de la tabla, de arriba abajo, por su nombre. */
async function teamOrder(world: ScenarioWorld): Promise<string> {
  return (await table(world).getByRole('rowheader').allTextContents()).map((t) => t.trim()).join(' · ')
}

async function expectOrder(world: ScenarioWorld, teams: Team[], what: string) {
  const expected = teams.map((t) => t.name).join(' · ')
  await world.check(what, () => becomes(world.page, () => teamOrder(world), expected, 'el orden de la tabla'))
}

const byHealth = (world: ScenarioWorld) =>
  severity.filter((state) => world.data.byHealth[state]).map((state) => world.data.byHealth[state]!)

Then('la tabla de la portada tiene los equipos de peor a mejor ingesta', async function (this: ScenarioWorld) {
  await expectOrder(this, byHealth(this), 'de peor a mejor ingesta')
})

Then('la tabla de la portada tiene los equipos de mejor a peor ingesta', async function (this: ScenarioWorld) {
  await expectOrder(this, byHealth(this).reverse(), 'de mejor a peor ingesta')
})

Then('la tabla de la portada tiene los equipos en el orden del servidor', async function (this: ScenarioWorld) {
  await expectOrder(this, this.data.inServerOrder!, 'el orden del servidor')
})

Then(
  'la cabecera {string} de la tabla de la portada dice que está en orden ascendente',
  async function (this: ScenarioWorld, column: string) {
    await this.check(`la cabecera «${column}»`, () =>
      becomes(
        this.page,
        () => table(this).getByRole('columnheader', { name: column }).getAttribute('aria-sort'),
        'ascending',
        'su aria-sort',
      ),
    )
  },
)

Then('la tabla de la portada tiene la fila de cada uno, con su género', async function (this: ScenarioWorld) {
  for (const twin of this.data.twins!) {
    const name = `${twin.name} · ${genderLabels[twin.gender]}`
    await this.check(`la fila de «${name}»`, () => shows(row(this, name), `la fila de «${name}»`))
  }
})

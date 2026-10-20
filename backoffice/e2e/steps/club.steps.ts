// El club que no se puede cargar: la página entera (plan R1, §3.1; LLD-B §8.3), y el servidor de pruebas parado
// o en marcha (DW-17).
import { Given, Then, When } from '@cucumber/cucumber'
import { startApiServer, stopApiServer } from '../support/api-server.ts'
import { leaveClubHalfProvisioned } from '../support/club-data.ts'
import { config } from '../support/config.ts'
import { absent, shows } from '../support/look.ts'
import type { ScenarioWorld } from '../support/world.ts'

const fullPage = (world: ScenarioWorld) => world.page.getByRole('main')

Given('mi club no tiene preparada su base de datos', async function (this: ScenarioWorld) {
  await leaveClubHalfProvisioned(this.club)
})

Given('el servidor está parado', async () => {
  await stopApiServer()
})

Given('el servidor vuelve a estar en marcha', async () => {
  await startApiServer()
})

Given('la web de mi club no ha podido conectar con el servidor', async function (this: ScenarioWorld) {
  await stopApiServer()
  await this.page.goto(this.clubUrl())
  await this.page.getByRole('heading', { level: 1, name: 'No se ha podido conectar con el servidor' }).waitFor()
})

When('abro la web de un club que no existe', async function (this: ScenarioWorld) {
  await this.page.goto(`http://bo-noexiste.localhost:${config.webPort}/`)
  await this.page.locator('h1').waitFor()
})

When('abro la web sin club en la dirección', async function (this: ScenarioWorld) {
  await this.page.goto(`http://localhost:${config.webPort}/`)
  await this.page.locator('h1').waitFor()
})

Then('la página entera dice {string}', async function (this: ScenarioWorld, text: string) {
  await this.check(`«${text}»`, () => shows(fullPage(this).getByText(text, { exact: true }), `«${text}»`))
})

Then('la página entera no tiene menú', async function (this: ScenarioWorld) {
  await this.check('el menú', () => absent(this.page.getByRole('navigation'), 'el menú'))
})

Then('la página entera ofrece {string}', async function (this: ScenarioWorld, name: string) {
  await this.check(`«${name}»`, () => shows(fullPage(this).getByRole('button', { name }), `el botón «${name}»`))
})

Then('la página entera no ofrece {string}', async function (this: ScenarioWorld, name: string) {
  await this.check(`«${name}»`, () => absent(fullPage(this).getByRole('button', { name }), `el botón «${name}»`))
})

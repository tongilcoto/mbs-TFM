// El marco: la cabecera, el modo, «Saltar al contenido» y «Esta página no existe» (plan R1, §3.1 y §3.3).
import { Given, Then, When } from '@cucumber/cucumber'
import { setShortName } from '../support/club-data.ts'
import { clubName } from '../support/invented.ts'
import { becomes, shows } from '../support/look.ts'
import type { ScenarioWorld } from '../support/world.ts'

const isDark = (world: ScenarioWorld) =>
  world.page.evaluate(() => document.documentElement.classList.contains('app-dark'))

Given('mi club tiene un nombre corto', async function (this: ScenarioWorld) {
  const shortName = clubName(this.random)
  await setShortName(this.club, shortName)
  this.data.shortName = shortName
  this.note(`nombre corto «${shortName}»`)
})

// El sistema del navegador en claro, y nada elegido todavía en la web: así abre en claro.
Given('estoy en la portada de mi club en modo claro', async function (this: ScenarioWorld) {
  await this.page.emulateMedia({ colorScheme: 'light' })
  await this.page.goto(this.clubUrl())
  await this.page.getByRole('button', { name: 'Cambiar a modo oscuro' }).waitFor()
})

Given('he cambiado la web de mi club a modo oscuro', async function (this: ScenarioWorld) {
  await this.page.emulateMedia({ colorScheme: 'light' })
  await this.page.goto(this.clubUrl())
  await this.page.getByRole('button', { name: 'Cambiar a modo oscuro' }).click()
  await this.page.getByRole('button', { name: 'Cambiar a modo claro' }).waitFor()
})

When('salto al contenido con el teclado', async function (this: ScenarioWorld) {
  // «Saltar al contenido» es lo primero que alcanza el tabulador (LLD-B §10.1).
  await this.page.keyboard.press('Tab')
  await this.page.keyboard.press('Enter')
})

Then('la cabecera dice el nombre corto de mi club', async function (this: ScenarioWorld) {
  const text = this.data.shortName!
  await this.check('la cabecera', () => shows(this.page.getByRole('banner').getByText(text), `«${text}» en la cabecera`))
})

Then('la web está en modo oscuro', async function (this: ScenarioWorld) {
  await this.check('el modo', () => becomes(this.page, () => isDark(this), true, 'el modo oscuro'))
})

Then('el foco está en el contenido de la página', async function (this: ScenarioWorld) {
  await this.check('el foco', () =>
    becomes(this.page, () => this.page.evaluate(() => document.activeElement?.tagName ?? ''), 'MAIN', 'lo que tiene el foco'),
  )
})

Then('el contenido de la página tiene el título {string}', async function (this: ScenarioWorld, name: string) {
  await this.check('el título', () =>
    shows(this.page.getByRole('main').getByRole('heading', { level: 1, name }), `el título «${name}»`),
  )
})

Then('el contenido de la página tiene el enlace {string}', async function (this: ScenarioWorld, name: string) {
  await this.check('el enlace', () => shows(this.page.getByRole('main').getByRole('link', { name }), `el enlace «${name}»`))
})

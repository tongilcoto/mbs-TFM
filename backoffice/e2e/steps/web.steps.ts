// Pasos generales de la web: abrir una dirección, pulsar, y comprobar cosas de la página entera.
import { Given, Then, When } from '@cucumber/cucumber'
import { becomes, shows } from '../support/look.ts'
import type { ScenarioWorld } from '../support/world.ts'

// Abre una dirección del club y espera a que la web haya pintado su primer título: la pantalla, la página entera
// de error o «Cargando…» con su título. A partir de ahí, cada `Then` espera lo suyo.
async function open(world: ScenarioWorld, url: string) {
  await world.page.goto(url)
  await world.page.locator('h1').first().waitFor()
}

When('abro la web de mi club', async function (this: ScenarioWorld) {
  await this.page.goto(this.clubUrl())
})

When('abro la portada de mi club', async function (this: ScenarioWorld) {
  await open(this, this.clubUrl())
})

When('vuelvo a abrir la portada de mi club', async function (this: ScenarioWorld) {
  await open(this, this.clubUrl())
})

When('abro {string} en la web de mi club', async function (this: ScenarioWorld, path: string) {
  await open(this, this.clubUrl(path))
})

Given('estoy en la portada de mi club', async function (this: ScenarioWorld) {
  await open(this, this.clubUrl())
  await this.page.locator('main').getByRole('status').waitFor({ state: 'detached' })
})

Given('estoy en {string} en la web de mi club', async function (this: ScenarioWorld, path: string) {
  await open(this, this.clubUrl(path))
})

When('pulso el botón {string}', async function (this: ScenarioWorld, name: string) {
  await this.page.getByRole('button', { name }).click()
})

When('pulso el enlace {string}', async function (this: ScenarioWorld, name: string) {
  await this.page.getByRole('link', { name }).click()
})

When('vuelvo atrás en el navegador', async function (this: ScenarioWorld) {
  await this.page.goBack()
})

Then('veo la zona principal de la página', async function (this: ScenarioWorld) {
  // Buscada por lo que es (LLD-B §11.4): la zona principal, `<main>`. Si está, Vue montó la página.
  await this.page.getByRole('main').waitFor({ state: 'attached' })
})

Then('la página está en español', async function (this: ScenarioWorld) {
  await this.check('el idioma de la página', async () => {
    const lang = await this.page.locator('html').getAttribute('lang')
    if (lang !== 'es') throw new Error(`es «${lang}», y se esperaba «es»`)
  })
})

Then('estoy en la portada', async function (this: ScenarioWorld) {
  await this.check('la dirección', () =>
    becomes(this.page, async () => new URL(this.page.url()).pathname, '/', 'el camino'),
  )
  await this.check('el título de la portada', () =>
    shows(this.page.getByRole('heading', { level: 1, name: 'Equipos' }), 'el título «Equipos»'),
  )
})

Then('la dirección es {string}', async function (this: ScenarioWorld, expected: string) {
  await this.check('la dirección', () =>
    becomes(this.page, async () => {
      const url = new URL(this.page.url())
      return url.pathname + url.search
    }, expected, 'la dirección'),
  )
})

Then('la pestaña del navegador dice {string}', async function (this: ScenarioWorld, expected: string) {
  await this.check('la pestaña', () => becomes(this.page, () => this.page.title(), expected, 'la pestaña'))
})

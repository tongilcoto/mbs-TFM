// Pasos generales de la web: abrir una dirección y comprobar cosas de la página entera.
import { Then, When } from '@cucumber/cucumber'
import assert from 'node:assert/strict'
import type { ScenarioWorld } from '../support/world.ts'

When('abro la web de mi club', async function (this: ScenarioWorld) {
  await this.page.goto(this.clubUrl())
})

Then('veo la zona principal de la página', async function (this: ScenarioWorld) {
  // Buscada por lo que es (LLD-B §11.4): la zona principal, `<main>`. Si está, Vue montó la página.
  await this.page.getByRole('main').waitFor({ state: 'attached' })
})

Then('la página está en español', async function (this: ScenarioWorld) {
  assert.equal(await this.page.locator('html').getAttribute('lang'), 'es')
})

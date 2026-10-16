// El arranque y la parada de los escenarios (LLD-B §11.1).
//
// Antes de todos: la base de pruebas, el barrido de los restos `bo_`, la federación falsa, el servidor de
// pruebas, la web de pruebas y el navegador. Si alguno no arranca, la pasada falla enseguida diciendo
// cuál, y se para lo que ya estuviera en marcha. Nunca se salta un escenario (ADR-B, decisión 6).
import { After, AfterAll, Before, BeforeAll, setDefaultTimeout } from '@cucumber/cucumber'
import { chromium, type Browser } from 'playwright'
import { startApiServer } from './api-server.ts'
import { startFakeFederation } from './fake-federation.ts'
import { sweepScenarioClubs } from './sweep.ts'
import { prepareTestDatabase } from './test-database.ts'
import { startWebServer } from './web-server.ts'
import type { ScenarioWorld } from './world.ts'

setDefaultTimeout(15_000)

let browser: Browser | undefined
const running: { stop(): Promise<void> }[] = []

async function stopAll(): Promise<void> {
  await browser?.close()
  browser = undefined
  while (running.length > 0) await running.pop()!.stop()
}

BeforeAll({ timeout: 90_000 }, async function () {
  try {
    await prepareTestDatabase()
    const swept = await sweepScenarioClubs()
    if (swept > 0) console.log(`Barridos ${swept} clubs bo_ de una pasada anterior.`)
    running.push(await startFakeFederation())
    running.push(await startApiServer())
    running.push(await startWebServer())
    browser = await chromium.launch()
  } catch (error) {
    await stopAll()
    throw error
  }
})

AfterAll({ timeout: 30_000 }, async function () {
  await stopAll()
})

Before(async function (this: ScenarioWorld) {
  this.context = await browser!.newContext({ locale: 'es-ES' })
  this.page = await this.context.newPage()
})

After(async function (this: ScenarioWorld) {
  await this.context?.close()
})

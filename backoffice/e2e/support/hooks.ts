// El arranque y la parada de los escenarios (LLD-B §11.1).
//
// Antes de todos: la base de pruebas, el barrido de los restos `bo_`, la federación falsa, el servidor de
// pruebas, la web de pruebas y el navegador. Si alguno no arranca, la pasada falla enseguida diciendo
// cuál, y se para lo que ya estuviera en marcha. Nunca se salta un escenario (ADR-B, decisión 6).
//
// Antes de cada escenario: su propio club. Después, se borra; con KEEP_TEST_DATA=1 se deja para mirarlo
// en TablePlus sobre `tfm_test`, y lo barre la pasada siguiente.
import { After, AfterAll, Before, BeforeAll, setDefaultTimeout } from '@cucumber/cucumber'
import { chromium, type Browser } from 'playwright'
import { startApiServer } from './api-server.ts'
import { createScenarioClub, dropScenarioClub, type ScenarioClub } from './clubs.ts'
import { startFakeFederation } from './fake-federation.ts'
import { sweepScenarioClubs } from './sweep.ts'
import { prepareTestDatabase } from './test-database.ts'
import { startWebServer } from './web-server.ts'
import type { ScenarioWorld } from './world.ts'

setDefaultTimeout(15_000)

let browser: Browser | undefined
const running: { stop(): Promise<void> }[] = []
const keepTestData = process.env.KEEP_TEST_DATA === '1'
const kept: ScenarioClub[] = []
/** Cuánto tarda en crearse cada club, para saber lo que cuesta (R0.12). */
const clubTimesMs: number[] = []

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
  if (clubTimesMs.length > 0) {
    const average = clubTimesMs.reduce((a, b) => a + b, 0) / clubTimesMs.length
    console.log(`Clubs creados: ${clubTimesMs.length}, ${Math.round(average)} ms de media cada uno.`)
  }
  if (kept.length > 0) {
    console.log(`KEEP_TEST_DATA=1 · clubs conservados en tfm_test: ${kept.map((c) => c.schema).join(', ')}`)
  }
})

Before(async function (this: ScenarioWorld) {
  const start = Date.now()
  this.club = await createScenarioClub()
  clubTimesMs.push(Date.now() - start)
  this.context = await browser!.newContext({ locale: 'es-ES' })
  this.page = await this.context.newPage()
})

After(async function (this: ScenarioWorld) {
  await this.context?.close()
  if (!this.club) return
  if (keepTestData) kept.push(this.club)
  else await dropScenarioClub(this.club)
})

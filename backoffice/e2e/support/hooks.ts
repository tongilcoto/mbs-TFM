// El arranque y la parada de los escenarios (LLD-B §11.1).
//
// Antes de todos: la base de pruebas, el barrido de los restos `bo_`, la federación falsa, el servidor de
// pruebas, la web de pruebas y el navegador. Si alguno no arranca, la pasada falla enseguida diciendo
// cuál, y se para lo que ya estuviera en marcha. Nunca se salta un escenario (ADR-B, decisión 6).
//
// Antes de cada escenario: su propio club. Al final, axe en los dos modos: un fallo de accesibilidad hace
// fallar el escenario como cualquier otro (R0.13). Después, el club se borra; con KEEP_TEST_DATA=1 se deja para mirarlo
// en TablePlus sobre `tfm_test`, y lo barre la pasada siguiente.
import { After, AfterAll, Before, BeforeAll, setDefaultTimeout, Status } from '@cucumber/cucumber'
import { appendFileSync, mkdirSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { chromium, type Browser } from 'playwright'
import { accessibilityProblems } from './accessibility.ts'
import { apiServerIsRunning, startApiServer, stopApiServer } from './api-server.ts'
import { settleIngestions } from './club-data.ts'
import { createScenarioClub, dropScenarioClub, type ScenarioClub } from './clubs.ts'
import { config } from './config.ts'
import { startFakeFederation } from './fake-federation.ts'
import { sweepScenarioClubs } from './sweep.ts'
import { randomFor, runSeed } from './random.ts'
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

// La semilla y los datos de los escenarios que fallan, también en un fichero: la consola se pierde al cerrarla.
// Empieza de cero en cada pasada, como los demás de `e2e-results/`, que no van al repositorio.
const dataLog = path.join(config.logs, 'datos.log')

BeforeAll({ timeout: 90_000 }, async function () {
  const seedLine = `Semilla de los datos: ${runSeed}. Para repetirlos: SEMILLA=${runSeed} npm run e2e`
  console.log(seedLine)
  mkdirSync(config.logs, { recursive: true })
  writeFileSync(dataLog, `${new Date().toISOString()} · ${seedLine}\n`)
  try {
    await prepareTestDatabase()
    const swept = await sweepScenarioClubs()
    if (swept > 0) console.log(`Barridos ${swept} clubs bo_ de una pasada anterior.`)
    running.push(await startFakeFederation())
    await startApiServer()
    running.push({ stop: stopApiServer })
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

Before(async function (this: ScenarioWorld, { pickle }) {
  // Su propio azar, del nombre del escenario: se repite igual lanzándolo solo.
  this.random = randomFor(`${pickle.uri}|${pickle.name}`)
  const start = Date.now()
  this.club = await createScenarioClub()
  clubTimesMs.push(Date.now() - start)
  // La hora de Madrid, para que las fechas que enseña la web sean las mismas en cualquier ordenador.
  this.context = await browser!.newContext({ locale: 'es-ES', timezoneId: 'Europe/Madrid' })
  this.page = await this.context.newPage()
})

// Después de cada escenario: se cierra su pestaña y se borra su club (o se conserva, con KEEP_TEST_DATA=1).
// Y si el escenario paró el servidor de pruebas y no llegó a arrancarlo (falló a medias), se arranca aquí, para
// que el siguiente no herede el fallo.
After({ timeout: 30_000 }, async function (this: ScenarioWorld, { result, pickle }) {
  await this.context?.close()
  if (!apiServerIsRunning()) await startApiServer()
  if (result?.status === Status.FAILED && this.chosen.length > 0) {
    const text = `\nDatos de «${pickle.name}» (SEMILLA=${runSeed}):\n${this.chosen.map((c) => `  · ${c}`).join('\n')}`
    console.log(text)
    appendFileSync(dataLog, `${text}\n`)
  }
  if (!this.club) return
  // Lo que el escenario dejó en marcha en el servidor acaba antes de borrar su club.
  await settleIngestions(this.club, this.data.ingesting)
  if (keepTestData) kept.push(this.club)
  else await dropScenarioClub(this.club)
})

// Y antes de eso, axe en los dos modos. Cucumber pasa los After en orden inverso al escrito, así que este
// va primero, con la página todavía abierta. Si el escenario ya falló, o no abrió ninguna página, no hay
// nada que analizar.
After(async function (this: ScenarioWorld, { result }) {
  if (result?.status !== Status.PASSED || this.page.url() === 'about:blank') return
  const problems = await accessibilityProblems(this.page)
  if (problems.length > 0) {
    throw new Error(`Fallos de accesibilidad (axe, WCAG 2.2 AA):\n${problems.join('\n')}`)
  }
})

// Lo primero al acabar (Cucumber pasa los After del último al primero): si algún `Then` apuntó un fallo, el
// escenario falla aquí con todos (World.check).
After(async function (this: ScenarioWorld) {
  if (this.failures.length > 0) {
    throw new Error(`Comprobaciones que fallaron:\n${this.failures.map((f) => `  · ${f}`).join('\n')}`)
  }
})

// Lo que tienen en común los procesos que arranca el arnés: comprobar que su puerto está libre,
// arrancarlos dejando lo que escriben en un fichero, y esperar a que contesten.
// Si algo no arranca, se dice cuál y por qué, y enseguida: nunca se queda esperando (LLD-B §11.1).
import { spawn, type ChildProcess } from 'node:child_process'
import { createWriteStream, mkdirSync } from 'node:fs'
import http from 'node:http'
import net from 'node:net'
import path from 'node:path'
import { config } from './config.ts'

/** Un proceso arrancado por el arnés, con su nombre para los mensajes. */
export interface Started {
  name: string
  child: ChildProcess
  logFile: string
  stop(): Promise<void>
}

/** ¿Hay algo escuchando ya en ese puerto? */
export function portIsBusy(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = net.connect({ host: '127.0.0.1', port })
    socket.once('connect', () => {
      socket.destroy()
      resolve(true)
    })
    socket.once('error', () => resolve(false))
  })
}

export async function requireFreePort(name: string, port: number): Promise<void> {
  if (await portIsBusy(port)) {
    throw new Error(
      `${name}: el puerto ${port} está ocupado. ¿Quedó en marcha de una pasada anterior? ` +
        `Para ver quién lo usa: lsof -i :${port}`,
    )
  }
}

/** Arranca un proceso y deja lo que escribe en `e2e-results/<fichero>.log`. */
export function startProcess(
  name: string,
  command: string,
  args: string[],
  // `append`: lo que escriba se añade al fichero en vez de empezarlo de cero. Para un proceso que se vuelve a
  // arrancar en la misma pasada, como el servidor de pruebas (R1.16), y que no se pierda lo de antes.
  options: { env?: NodeJS.ProcessEnv; cwd?: string; logName: string; append?: boolean },
): Started {
  mkdirSync(config.logs, { recursive: true })
  const logFile = path.join(config.logs, `${options.logName}.log`)
  const log = createWriteStream(logFile, { flags: options.append ? 'a' : 'w' })
  const child = spawn(command, args, {
    cwd: options.cwd,
    env: { ...process.env, ...options.env },
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  child.stdout?.pipe(log)
  child.stderr?.pipe(log)

  return {
    name,
    child,
    logFile,
    stop: () => stopProcess(child),
  }
}

function stopProcess(child: ChildProcess): Promise<void> {
  if (child.exitCode !== null || child.signalCode !== null) return Promise.resolve()
  return new Promise((resolve) => {
    child.once('exit', () => resolve())
    child.kill('SIGTERM')
    // Si no se para por las buenas en 5 s, por las malas.
    setTimeout(() => child.kill('SIGKILL'), 5_000).unref()
  })
}

/**
 * Espera a que el proceso conteste por HTTP a `path`, con la cabecera Host que se le dé.
 * Cualquier respuesta vale (también un 404): lo que se comprueba es que escucha.
 * Falla enseguida si el proceso termina, y a los `config.startTimeoutMs` si no contesta.
 */
export async function waitUntilAnswers(
  started: Started,
  port: number,
  options: { path?: string; host?: string } = {},
): Promise<void> {
  const deadline = Date.now() + config.startTimeoutMs
  while (Date.now() < deadline) {
    if (started.child.exitCode !== null || started.child.signalCode !== null) {
      throw new Error(
        `${started.name}: se paró al arrancar (código ${started.child.exitCode ?? started.child.signalCode}). ` +
          `Lo que escribió está en ${started.logFile}`,
      )
    }
    if (await answers(port, options.path ?? '/', options.host)) return
    await new Promise((resolve) => setTimeout(resolve, 200))
  }
  await started.stop()
  throw new Error(
    `${started.name}: no contestó en ${config.startTimeoutMs / 1000} s en el puerto ${port}. ` +
      `Lo que escribió está en ${started.logFile}`,
  )
}

function answers(port: number, requestPath: string, host?: string): Promise<boolean> {
  return new Promise((resolve) => {
    const request = http.get(
      { host: '127.0.0.1', port, path: requestPath, headers: host ? { host } : {}, timeout: 1_000 },
      (response) => {
        response.resume()
        resolve(true)
      },
    )
    request.once('timeout', () => request.destroy())
    request.once('error', () => resolve(false))
  })
}

/** Ejecuta una orden hasta que termina; si sale mal, el error lleva lo que escribió. */
export function run(command: string, args: string[], env: NodeJS.ProcessEnv = {}): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { env: { ...process.env, ...env }, stdio: ['ignore', 'pipe', 'pipe'] })
    let output = ''
    child.stdout.on('data', (chunk) => (output += chunk))
    child.stderr.on('data', (chunk) => (output += chunk))
    child.once('error', reject)
    child.once('exit', (code) => {
      if (code === 0) resolve(output)
      else reject(new Error(`«${path.basename(command)} ${args.join(' ')}» salió con ${code}:\n${output}`))
    })
  })
}

// La federación falsa (DW-14): un servidor pequeño que se pone en el lugar de rffm.es y devuelve las
// respuestas grabadas que ya usa el backend (backend/Tests/FederationTests/Fixtures/README.md).
// El servidor de pruebas le pide aquí porque arranca con RFFM_BASE_URL apuntando a ella (R0.8).
//
// Contesta como la RFFM de verdad, también cuando algo no existe: siempre con 200, y con `null` (la
// clasificación y los goleadores) o con un calendario vacío (el calendario). Así la ingesta ve lo mismo
// que vería en producción.
//
// Si un escenario necesita una respuesta que no está grabada, se graba una nueva en
// e2e/federation-recordings/: un `.txt` con la dirección pedida en una línea y la respuesta debajo, como
// los que ya hay. Ojo con el `null` pasajero de la RFFM (H-61): si llega, se vuelve a pedir.
//
// Además de las grabadas, sirve las competiciones que se inventa cada escenario (invented.ts): su calendario
// sin jugar, y sus goleadores, todavía ninguno. Así el servidor las da de alta y las sincroniza por su camino
// de siempre, y los datos no se escriben a mano en la base (la skill de escenarios, principio 9). Y a una
// competición inventada se le puede pedir que falle o que tarde: es lo que hace la RFFM de verdad.
import { readdirSync, readFileSync } from 'node:fs'
import http from 'node:http'
import path from 'node:path'
import { config } from './config.ts'
import type { Competition } from './invented.ts'

/** Los calendarios grabados. Son páginas enteras y no llevan dentro la dirección, así que van aquí. */
const calendars: Record<string, string> = {
  // temporada | tipojuego | competicion | grupo
  '21|1|24037548|24037549': 'RFFM-calendario-temporada-jugada.html', // Cadete G1 2025-26, 240 partidos jugados
  '22|1|24037548|24037549': 'RFFM-calendario-temporada-sin-jugar.html', // Preferente G1 2026-27, sin jugar
}
const calendarNotFound = 'RFFM-calendario-coordenada-inexistente.html'

/** Una dirección escrita siempre igual: la ruta y los parámetros en orden alfabético. */
function key(address: string): string {
  const url = new URL(address, 'http://federacion')
  url.searchParams.sort()
  return `${url.pathname}?${url.searchParams}`
}

/**
 * Las respuestas de los `.txt`, por su dirección. Cada fichero puede traer varias: cada una empieza por
 * la línea con su dirección, y acaba en la siguiente dirección o en la línea «HTTP 200».
 */
function readRecordedAnswers(folder: string): Map<string, string> {
  const answers = new Map<string, string>()
  for (const file of readdirSync(folder).filter((name) => name.endsWith('.txt'))) {
    let address: string | undefined
    let body: string[] = []
    const save = () => {
      if (address) answers.set(key(address), body.join('\n').trim())
    }
    for (const line of readFileSync(path.join(folder, file), 'utf8').split('\n')) {
      if (/^https?:\/\//.test(line.trim())) {
        save()
        address = line.trim()
        body = []
      } else if (/^HTTP \d+/.test(line.trim())) {
        save()
        address = undefined
      } else if (address) {
        body.push(line)
      }
    }
    save()
  }
  return answers
}

/** La página del calendario de una competición inventada: tres jornadas sin jugar, con sus fechas en la temporada. */
function inventedCalendar(competition: Competition): string {
  const [a, b, c, d] = competition.teams
  const pairings = [[[a, b], [c, d]], [[a, c], [b, d]], [[a, d], [b, c]]]
  const rounds = pairings.map((matches, index) => {
    // Domingos de septiembre y octubre del primer año de la temporada.
    const day = new Date(Date.UTC(competition.season.start, 8, 14 + 7 * index))
    const date = `${String(day.getUTCDate()).padStart(2, '0')}-${String(day.getUTCMonth() + 1).padStart(2, '0')}-${day.getUTCFullYear()}`
    return {
      codjornada: String(index + 1),
      jornada: `${index + 1} (${date})`,
      equipos: matches.map(([home, away], m) => ({
        codacta: `${competition.federationGroupId}${index}${m}`,
        codigo_equipo_local: home!.code,
        equipo_local: home!.rawName,
        escudo_equipo_local: '',
        goles_casa: '',
        codigo_equipo_visitante: away!.code,
        equipo_visitante: away!.rawName,
        escudo_equipo_visitante: '',
        goles_visitante: '',
        codigo_campo: '',
        campo: '',
        fecha: date,
        hora: '',
      })),
    }
  })
  const start = competition.season.start
  const data = {
    props: {
      pageProps: {
        calendar: {
          competicion: competition.division,
          grupo: competition.group,
          temporada: `${start}-${start + 1}`,
          host: 'https://appweb.rffm.es/',
          rounds,
        },
        currentRound: '1',
      },
    },
  }
  return `<html><body><script id="__NEXT_DATA__" type="application/json">${JSON.stringify(data)}</script></body></html>`
}

/** Los goleadores de una competición inventada: ninguno todavía, porque no se ha jugado. */
function inventedScorers(competition: Competition): string {
  return JSON.stringify({ estado: '1', sesion_ok: '1', competicion: competition.division, grupo: competition.group, goles: [] })
}

// Una respuesta retenida: la federación tarda hasta que el escenario la suelta.
interface Hold {
  arrived: Promise<void>
  markArrived(): void
  gate: Promise<void>
  release(): void
}

function newHold(): Hold {
  let markArrived!: () => void
  let release!: () => void
  const arrived = new Promise<void>((resolve) => (markArrived = resolve))
  const gate = new Promise<void>((resolve) => (release = resolve))
  return { arrived, markArrived, gate, release }
}

export interface FakeFederation {
  /** Las direcciones que le han pedido, en orden. */
  requests: string[]
  /** Desde ahora sirve esta competición. */
  invent(competition: Competition): void
  /** Desde ahora sus goleadores llegan a `null`, como cuando la RFFM no los encuentra: la pasada falla. */
  failScorers(competition: Competition): void
  /** El próximo calendario que se le pida de esta competición no sale hasta `releaseAll`. */
  hold(competition: Competition): void
  /** Cuando el calendario retenido ya se ha pedido. */
  heldArrived(competition: Competition): Promise<void>
  /**
   * Suelta todo lo retenido. Lo inventado no se olvida: la pasada que se suelta todavía pide sus goleadores,
   * y cada escenario inventa códigos nuevos, así que no se pisan.
   */
  releaseAll(): void
  stop(): Promise<void>
}

// La que está en marcha, para que los pasos le pidan cosas.
let running: FakeFederation | undefined

export function fakeFederation(): FakeFederation {
  if (!running) throw new Error('La federación falsa no está en marcha')
  return running
}

export async function startFakeFederation(port = config.federationPort): Promise<FakeFederation> {
  const answers = new Map([...readRecordedAnswers(config.fixtures), ...readRecordedAnswers(config.recordings)])
  const requests: string[] = []
  // Las inventadas, por su grupo: el código que va en todas sus direcciones.
  const invented = new Map<string, Competition>()
  const failing = new Set<string>()
  const holds = new Map<string, Hold>()
  // Las retenidas que ya se pidieron y esperan a que las suelten.
  const waiting: Hold[] = []

  const server = http.createServer(async (request, response) => {
    const address = request.url ?? '/'
    requests.push(address)
    const url = new URL(address, 'http://federacion')
    const send = (body: string, type = 'application/json; charset=utf-8') => {
      response.writeHead(200, { 'content-type': type })
      response.end(body)
    }

    const ours = invented.get(url.searchParams.get('grupo') ?? url.searchParams.get('idGroup') ?? '')
    if (ours && url.pathname === '/competicion/calendario') {
      const hold = holds.get(ours.federationGroupId)
      if (hold) {
        holds.delete(ours.federationGroupId)
        waiting.push(hold)
        hold.markArrived()
        await hold.gate
      }
      return send(inventedCalendar(ours), 'text/html; charset=utf-8')
    }
    if (ours && url.pathname === '/api/scorers') {
      return send(failing.has(ours.federationGroupId) ? 'null' : inventedScorers(ours))
    }

    if (url.pathname === '/competicion/calendario') {
      const q = url.searchParams
      const coordinate = [q.get('temporada'), q.get('tipojuego'), q.get('competicion'), q.get('grupo')].join('|')
      const file = calendars[coordinate] ?? calendarNotFound
      return send(readFileSync(path.join(config.fixtures, file), 'utf8'), 'text/html; charset=utf-8')
    }
    if (url.pathname === '/api/standings' || url.pathname === '/api/scorers') {
      return send(answers.get(key(address)) ?? 'null')
    }
    response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' })
    response.end(`La federación falsa no conoce ${url.pathname}`)
  })

  await new Promise<void>((resolve, reject) => {
    server.once('error', (error: NodeJS.ErrnoException) =>
      reject(
        error.code === 'EADDRINUSE'
          ? new Error(`La federación falsa (${port}): el puerto ${port} está ocupado. Para ver quién lo usa: lsof -i :${port}`)
          : error,
      ),
    )
    server.listen(port, '127.0.0.1', resolve)
  })

  running = {
    requests,
    invent: (competition) => void invented.set(competition.federationGroupId, competition),
    failScorers: (competition) => void failing.add(competition.federationGroupId),
    hold: (competition) => void holds.set(competition.federationGroupId, newHold()),
    // Si ya no está entre las que esperan su petición, es que ya llegó.
    heldArrived: (competition) => holds.get(competition.federationGroupId)?.arrived ?? Promise.resolve(),
    releaseAll: () => {
      for (const hold of [...holds.values(), ...waiting.splice(0)]) hold.release()
      holds.clear()
    },
    stop: () => {
      running = undefined
      return new Promise((resolve) => server.close(() => resolve()))
    },
  }
  return running
}

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
// Además de las grabadas, sirve las competiciones que se inventa cada escenario (invented.ts): su calendario,
// sin jugar o con jornadas jugadas (plan R4), con sus descansos si el grupo es impar (plan R5); la clasificación de cada jornada jugada, calculada de sus marcadores;
// y sus goleadores, todavía ninguno. Así el servidor las da de alta y las sincroniza por su camino
// de siempre, y los datos no se escriben a mano en la base (la skill de escenarios, principio 9). Y a una
// competición inventada se le puede pedir que falle o que tarde: es lo que hace la RFFM de verdad.
//
// Y la ficha de equipo (`fichaequipo/<código>`, plan R6, R6.15) de cada equipo de una competición inventada, con los
// jugadores que el escenario le hace publicar (`publishRoster`), o ninguno; también se le puede pedir que falle o
// que tarde. A un código que no es de ninguna, `team: null`, como la RFFM.
import { readdirSync, readFileSync } from 'node:fs'
import http from 'node:http'
import path from 'node:path'
import { config } from './config.ts'
import { federationDate, standingsAfter, type Competition, type FederationPlayer, type FederationTeam, type Round } from './invented.ts'

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

/** Las tres jornadas sin jugar de una competición inventada sin calendario propio: domingos de septiembre y octubre. */
function unplayedRounds(competition: Competition): Round[] {
  const [a, b, c, d] = competition.teams
  const pairings = [[[a, b], [c, d]], [[a, c], [b, d]], [[a, d], [b, c]]]
  return pairings.map((matches, index) => ({
    number: index + 1,
    date: new Date(Date.UTC(competition.season.start, 8, 14 + 7 * index)),
    matches: matches.map(([home, away]) => ({ home: home!, away: away! })),
  }))
}

/** La página del calendario de una competición inventada, con su calendario o con tres jornadas sin jugar. */
function inventedCalendar(competition: Competition): string {
  const rounds = (competition.schedule ?? unplayedRounds(competition)).map((round) => {
    const date = federationDate(round.date)
    return {
      codjornada: String(round.number),
      jornada: `${round.number} (${date})`,
      equipos: round.matches.map(({ home, away, time, score, rest }, m) => ({
        codacta: `${competition.federationGroupId}${round.number - 1}${m}`,
        codigo_equipo_local: home.code,
        equipo_local: home.rawName,
        escudo_equipo_local: '',
        // La RFFM manda el marcador como texto, y vacío si no se ha jugado.
        goles_casa: score ? String(score.home) : '',
        codigo_equipo_visitante: away.code,
        equipo_visitante: away.rawName,
        escudo_equipo_visitante: '',
        goles_visitante: score ? String(score.away) : '',
        codigo_campo: '',
        campo: '',
        // El descanso, sin fecha (D-105): el servidor le pone la del primer día de su jornada.
        fecha: rest ? '' : date,
        hora: time ?? '',
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
          // La de la temporada, salvo que el escenario quiera que la federación diga otra cosa (`calendarSeason`).
          temporada: competition.calendarSeason ?? `${start}-${start + 1}`,
          host: 'https://appweb.rffm.es/',
          rounds,
        },
        currentRound: '1',
      },
    },
  }
  return `<html><body><script id="__NEXT_DATA__" type="application/json">${JSON.stringify(data)}</script></body></html>`
}

/**
 * La clasificación de una competición inventada tras una jornada, con los campos que lee el servidor
 * (RFFMStandingsParser); `null` si esa jornada no se ha jugado, como la RFFM cuando no la tiene.
 */
function inventedStandings(competition: Competition, round: number): string {
  const rows = standingsAfter(competition, round)
  if (rows.length === 0) return 'null'
  const text = (n: number) => String(n)
  return JSON.stringify({
    estado: '1',
    sesion_ok: '1',
    competicion: competition.division,
    codigo_competicion: competition.federationCompetitionId,
    grupo: competition.group,
    codigo_grupo: competition.federationGroupId,
    jornada: String(round),
    clasificacion: rows.map((row) => ({
      posicion: text(row.position),
      codequipo: row.team.code,
      nombre: row.team.rawName,
      url_img: '',
      jugados: text(row.played),
      ganados: text(row.won),
      empatados: text(row.drawn),
      perdidos: text(row.lost),
      goles_a_favor: text(row.goalsFor),
      goles_en_contra: text(row.goalsAgainst),
      puntos: text(row.points),
    })),
  })
}

/** Los goleadores de una competición inventada: ninguno todavía. */
function inventedScorers(competition: Competition): string {
  return JSON.stringify({ estado: '1', sesion_ok: '1', competicion: competition.division, grupo: competition.group, goles: [] })
}

/**
 * La ficha de equipo, con la forma de la grabada (backend/Tests/FederationTests/Fixtures/RFFM-fichaequipo.html): los
 * datos en `__NEXT_DATA__`, en `props.pageProps.team`, y cada jugador con `cod_jugador` y `nombre`. Lo demás del
 * equipo va vacío: el servidor solo lee los jugadores. Sin equipo, `team: null`.
 */
function teamSheet(code: string, found?: { team: FederationTeam; competition: Competition; players: FederationPlayer[] }): string {
  const team = found && {
    estado: '1',
    sesion_ok: '1',
    codigo_equipo: code,
    codigo_club: '',
    clave_acceso: '',
    nombre_equipo: found.team.rawName,
    escudo_club: '',
    nombre_club: found.team.rawName.replace(/ '[A-Z]'$/, ''),
    categoria: found.competition.division,
    codigo_categoria: '',
    portal_web: '',
    codigo_campo: '',
    campo: '',
    foto_campo: '',
    campo_entrenamiento: '',
    titular_correspondencia: '',
    tratamiento_correspondencia: '',
    domicilio_correspondencia: '',
    localidad_correspondencia: '',
    provincia_correspondencia: '',
    codigo_postal_correspondencia: '',
    email_correspondencia: '',
    telefonos: '',
    jugar_dia: '',
    jugar_horario: '',
    fax: '',
    delegados_equipo: [],
    auxiliares_equipo: [],
    tecnicos_equipo: [],
    jugadores_equipo: found.players.map((player) => ({ cod_jugador: player.code, nombre: player.published })),
    equipaciones: [],
    equipacion1_diseno: [],
    host: 'https://appweb.rffm.es/',
  }
  const data = { props: { pageProps: { team: team ?? null, query: { codficha: [code] } } }, page: '/fichaequipo/[...codficha]' }
  return `<html><body><script id="__NEXT_DATA__" type="application/json">${JSON.stringify(data)}</script></body></html>`
}

// Una respuesta retenida: la federación tarda hasta que el escenario la suelta. `skip`, cuántas peticiones del
// calendario deja pasar antes de retener una: el enganche lo lee una vez y la primera ingesta otra, así que
// retener la ingesta sin retener el enganche es dejar pasar una.
interface Hold {
  skip: number
  arrived: Promise<void>
  markArrived(): void
  gate: Promise<void>
  release(): void
}

function newHold(skip = 0): Hold {
  let markArrived!: () => void
  let release!: () => void
  const arrived = new Promise<void>((resolve) => (markArrived = resolve))
  const gate = new Promise<void>((resolve) => (release = resolve))
  return { skip, arrived, markArrived, gate, release }
}

export interface FakeFederation {
  /** Las direcciones que le han pedido, en orden. */
  requests: string[]
  /** Desde ahora sirve esta competición. */
  invent(competition: Competition): void
  /** Desde ahora sus goleadores llegan a `null`, como cuando la RFFM no los encuentra: la pasada falla. */
  failScorers(competition: Competition): void
  /**
   * El próximo calendario que se le pida de esta competición no sale hasta `releaseAll`; con `skip`, deja pasar
   * antes ese número de peticiones.
   */
  hold(competition: Competition, skip?: number): void
  /** Desde ahora su calendario contesta 500, como la RFFM cuando falla: el servidor no lo entiende. */
  failCalendar(competition: Competition): void
  /** Desde ahora su calendario vuelve a contestar bien. */
  answerCalendar(competition: Competition): void
  /** Desde ahora sus goleadores vuelven a contestar bien. */
  answerScorers(competition: Competition): void
  /** Cuando el calendario retenido ya se ha pedido. */
  heldArrived(competition: Competition): Promise<void>
  /**
   * Desde ahora la ficha del equipo del club en esta competición (el primero de sus equipos) publica estos
   * jugadores, en este orden, y solo estos. Sin llamarla, la ficha sale sin jugadores.
   */
  publishRoster(competition: Competition, players: FederationPlayer[]): void
  /** Desde ahora la ficha del equipo del club contesta 500, como la RFFM cuando falla. */
  failRoster(competition: Competition): void
  /** Desde ahora la ficha del equipo del club vuelve a contestar bien. */
  answerRoster(competition: Competition): void
  /** La próxima ficha que se pida del equipo del club no sale hasta `releaseAll`. */
  holdRoster(competition: Competition): void
  /** Cuando la ficha retenida ya se ha pedido. */
  heldRosterArrived(competition: Competition): Promise<void>
  /**
   * Suelta todo lo retenido. Lo inventado no se olvida: la pasada que se suelta todavía pide sus goleadores,
   * y cada escenario inventa códigos nuevos, así que no se pisan.
   */
  releaseAll(): void
  stop(): Promise<void>
}

/** El código del equipo del club en una competición inventada: el primero de sus equipos. */
function ownCode(competition: Competition): string {
  return competition.teams[0]!.code
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
  const failingCalendars = new Set<string>()
  // Las fichas de equipo: los jugadores de cada equipo del club, y las que fallan, por su código.
  const rosters = new Map<string, FederationPlayer[]>()
  const failingRosters = new Set<string>()
  // Las retenidas: los calendarios por su grupo, y las fichas por `fichaequipo/<código>`.
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
      if (failingCalendars.has(ours.federationGroupId)) {
        response.writeHead(500, { 'content-type': 'text/plain; charset=utf-8' })
        return response.end('Error interno')
      }
      const hold = holds.get(ours.federationGroupId)
      if (hold && hold.skip > 0) hold.skip--
      else if (hold) {
        holds.delete(ours.federationGroupId)
        waiting.push(hold)
        hold.markArrived()
        await hold.gate
      }
      return send(inventedCalendar(ours), 'text/html; charset=utf-8')
    }
    if (ours && url.pathname === '/api/standings') {
      return send(inventedStandings(ours, Number(url.searchParams.get('round'))))
    }
    if (ours && url.pathname === '/api/scorers') {
      return send(failing.has(ours.federationGroupId) ? 'null' : inventedScorers(ours))
    }

    const sheet = /^\/fichaequipo\/([^/]+)$/.exec(url.pathname)
    if (sheet) {
      const code = decodeURIComponent(sheet[1]!)
      if (failingRosters.has(code)) {
        response.writeHead(500, { 'content-type': 'text/plain; charset=utf-8' })
        return response.end('Error interno')
      }
      const hold = holds.get(`fichaequipo/${code}`)
      if (hold) {
        holds.delete(`fichaequipo/${code}`)
        waiting.push(hold)
        hold.markArrived()
        await hold.gate
      }
      const competition = [...invented.values()].find((c) => c.teams.some((t) => t.code === code))
      const team = competition?.teams.find((t) => t.code === code)
      const found = competition && team && { team, competition, players: rosters.get(code) ?? [] }
      return send(teamSheet(code, found), 'text/html; charset=utf-8')
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
    hold: (competition, skip) => void holds.set(competition.federationGroupId, newHold(skip)),
    failCalendar: (competition) => void failingCalendars.add(competition.federationGroupId),
    answerCalendar: (competition) => void failingCalendars.delete(competition.federationGroupId),
    answerScorers: (competition) => void failing.delete(competition.federationGroupId),
    // Si ya no está entre las que esperan su petición, es que ya llegó.
    heldArrived: (competition) => holds.get(competition.federationGroupId)?.arrived ?? Promise.resolve(),
    publishRoster: (competition, players) => void rosters.set(ownCode(competition), [...players]),
    failRoster: (competition) => void failingRosters.add(ownCode(competition)),
    answerRoster: (competition) => void failingRosters.delete(ownCode(competition)),
    holdRoster: (competition) => void holds.set(`fichaequipo/${ownCode(competition)}`, newHold()),
    heldRosterArrived: (competition) => holds.get(`fichaequipo/${ownCode(competition)}`)?.arrived ?? Promise.resolve(),
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

import { fireEvent, render, screen } from '@testing-library/vue'
import { describe, expect, test } from 'vitest'
import { createMemoryHistory, createRouter } from 'vue-router'
import TeamsTable from './TeamsTable.vue'
import type { CompetitionCell, TeamRow } from './teamRow'

function competition(fields: Partial<CompetitionCell>): CompetitionCell {
  return {
    id: 'liga',
    name: 'Cadete · PRIMERA CADETE · Grupo 4',
    health: 'ok',
    healthName: 'Al día',
    previousFailed: false,
    lastSynced: '17/10/2026 23:40',
    summary: { streak: [] },
    ...fields,
  }
}

// Las acciones son enlaces: hace falta un router, aunque no se vaya a ningún sitio.
function withRouter() {
  const router = createRouter({ history: createMemoryHistory(), routes: [{ path: '/:anything(.*)*', component: {} }] })
  return { global: { plugins: [router] } }
}

function renderTable(rows: TeamRow[], seasonLabel?: string, seasonAddress?: string) {
  return render(TeamsTable, {
    props: { rows, caption: 'Equipos de la temporada 2026/27', seasonLabel, seasonAddress },
    ...withRouter(),
  })
}

// Lo que dice cada fila, celda a celda: cada trozo de texto, separado por un espacio. (Vue quita los espacios
// entre etiquetas, así que el texto tal cual juntaría el icono con su palabra: «✓Al día».)
function rowTexts() {
  return screen
    .getAllByRole('row')
    .slice(1)
    .map((row) => [...row.querySelectorAll('th, td')].map(words))
}

function words(cell: Element): string {
  const walker = document.createTreeWalker(cell, NodeFilter.SHOW_TEXT)
  const pieces: string[] = []
  while (walker.nextNode()) pieces.push(walker.currentNode.textContent!.trim())
  return pieces.filter(Boolean).join(' ')
}

describe('la tabla de equipos', () => {
  test('tiene cabeceras de verdad y un título para el lector de pantalla', () => {
    renderTable([])

    // Por su nombre, el que lee el lector: la flecha de ordenar no se lee.
    for (const name of ['Equipo', 'Competición', 'Posición', 'Racha', 'Último', 'Próximo', 'Ingesta', 'Última sincronización', 'Acciones']) {
      expect(screen.getByRole('columnheader', { name })).toBeInTheDocument()
    }
    expect(screen.getAllByRole('columnheader')).toHaveLength(9)
    expect(screen.getByRole('table', { name: 'Equipos de la temporada 2026/27' })).toBeInTheDocument()
  })

  test('cada equipo con su competición, su ingesta en palabras y su última sincronización', () => {
    renderTable([{ id: '1', team: 'Cadete B', competitions: [competition({})] }])

    // La última celda, la de las acciones: un icono sin texto a la vista.
    // Sin resumen todavía, las cuatro columnas de la R5 con su raya.
    expect(rowTexts()).toEqual([['Cadete B', 'Cadete · PRIMERA CADETE · Grupo 4', '–', '–', '–', '–', '✓ Al día', '17/10/2026 23:40', '']])
    // El nombre del equipo es la cabecera de su fila: el lector dice «Cadete B» al recorrerla.
    expect(screen.getByRole('rowheader')).toHaveTextContent('Cadete B')
  })

  test('el icono no se lee: la palabra ya lo dice', () => {
    renderTable([{ id: '1', team: 'Cadete B', competitions: [competition({ health: 'failing', healthName: 'Con fallos' })] }])

    expect(screen.getByText('✕')).toHaveAttribute('aria-hidden', 'true')
  })

  test('«La anterior tuvo fallos», debajo del estado', () => {
    renderTable([
      {
        id: '1',
        team: 'Cadete B',
        competitions: [competition({ health: 'pending', healthName: 'En marcha', previousFailed: true })],
      },
    ])

    expect(rowTexts()[0]![6]).toBe('↻ En marcha ✕ La anterior tuvo fallos')
  })

  test('un equipo con dos competiciones: su nombre una vez, y una línea por competición', () => {
    renderTable([
      {
        id: '1',
        team: 'Cadete B',
        competitions: [competition({ name: 'Liga' }), competition({ name: 'Copa', health: 'never', healthName: 'Sin datos todavía', lastSynced: 'Nunca' })],
      },
    ])

    expect(rowTexts()).toEqual([
      ['Cadete B', 'Liga', '–', '–', '–', '–', '✓ Al día', '17/10/2026 23:40', ''],
      ['Copa', '–', '–', '–', '–', '○ Sin datos todavía', 'Nunca'],
    ])
    expect(screen.getByRole('rowheader')).toHaveAttribute('rowspan', '2')
  })

  test('un equipo sin competición: «Sin competición» y el enlace para sincronizarlo', () => {
    renderTable([{ id: '1', team: 'Alevín A', competitions: [] }])

    expect(rowTexts()).toEqual([['Alevín A', 'Sin competición Sincronizar con la Federación', '']])
  })
})

describe('las acciones de la fila (plan R3, decisión 1)', () => {
  const syncActions = () => screen.getAllByRole('link', { name: /^Sincronizar .*, / })

  test('sin competición, «Sincronizar con la Federación», con el equipo en el nombre', () => {
    renderTable([{ id: '1', team: 'Alevín A', competitions: [] }])

    expect(screen.getByRole('link', { name: 'Sincronizar con la Federación, Alevín A' })).toBeInTheDocument()
  })

  test('con competición, «Sincronizar otra competición», con el equipo en el nombre', () => {
    renderTable([{ id: '1', team: 'Cadete A', competitions: [competition({})] }])

    expect(screen.getByRole('link', { name: 'Sincronizar otra competición, Cadete A' })).toBeInTheDocument()
  })

  test('una vez por equipo, aunque tenga dos competiciones, y a lo alto de las dos líneas', () => {
    renderTable([{ id: '1', team: 'Infantil A', competitions: [competition({ name: 'Liga' }), competition({ name: 'Copa' })] }])

    expect(syncActions()).toHaveLength(1)
    expect(syncActions()[0]!.closest('td')).toHaveAttribute('rowspan', '2')
  })

  test('una por equipo, cada una con el suyo', () => {
    renderTable([
      { id: '1', team: 'Alevín A', competitions: [] },
      { id: '2', team: 'Cadete A', competitions: [competition({})] },
    ])

    expect(syncActions().map((link) => link.getAttribute('aria-label'))).toEqual([
      'Sincronizar con la Federación, Alevín A',
      'Sincronizar otra competición, Cadete A',
    ])
  })

  test('el icono y el enlace llevan a sincronizar ese equipo', () => {
    renderTable([{ id: 'a1b2', team: 'Alevín A', competitions: [] }])

    expect(screen.getByRole('link', { name: 'Sincronizar con la Federación, Alevín A' })).toHaveAttribute(
      'href',
      '/equipos/a1b2/federacion',
    )
    expect(screen.getByRole('link', { name: 'Sincronizar con la Federación' })).toHaveAttribute('href', '/equipos/a1b2/federacion')
  })

  test('la columna no se ordena: su cabecera no es un botón', () => {
    renderTable([])

    expect(screen.queryByRole('button', { name: 'Acciones' })).not.toBeInTheDocument()
  })
})

describe('ordenar (bloque T)', () => {
  test('cada cabecera es un botón, y al pulsarlo avisa de qué columna', async () => {
    const { emitted } = render(TeamsTable, { props: { rows: [], caption: 'x' }, ...withRouter() })

    for (const name of ['Equipo', 'Competición', 'Ingesta', 'Última sincronización']) {
      await fireEvent.click(screen.getByRole('button', { name }))
    }

    expect(emitted('sort')).toEqual([['equipo'], ['competicion'], ['ingesta'], ['sincronizacion']])
  })

  test('la columna ordenada lo dice, en su sentido; las demás, nada', () => {
    render(TeamsTable, { props: { rows: [], caption: 'x', order: { column: 'ingesta', reversed: true } }, ...withRouter() })

    expect(screen.getByRole('columnheader', { name: 'Ingesta' })).toHaveAttribute('aria-sort', 'descending')
    expect(screen.getByRole('columnheader', { name: 'Equipo' })).not.toHaveAttribute('aria-sort')
  })

  test('en su orden es «ascendente»', () => {
    render(TeamsTable, { props: { rows: [], caption: 'x', order: { column: 'equipo', reversed: false } }, ...withRouter() })

    expect(screen.getByRole('columnheader', { name: 'Equipo' })).toHaveAttribute('aria-sort', 'ascending')
  })
})

describe('el nombre del equipo lleva a su ficha (plan R4, §3.1)', () => {
  test('en la temporada que se ve', () => {
    renderTable([{ id: 'a1b2', team: 'Cadete A', competitions: [competition({})] }], '2025/26', '2025-26')

    expect(screen.getByRole('link', { name: 'Cadete A' })).toHaveAttribute('href', '/temporadas/2025-26/equipos/a1b2/resultados')
  })

  test('también sin competición', () => {
    renderTable([{ id: 'a1b2', team: 'Alevín A', competitions: [] }], '2026/27', '2026-27')

    expect(screen.getByRole('link', { name: 'Alevín A' })).toHaveAttribute('href', '/temporadas/2026-27/equipos/a1b2/resultados')
  })

  test('sigue siendo la cabecera de su fila', () => {
    renderTable([{ id: 'a1b2', team: 'Cadete A', competitions: [competition({})] }], '2026/27', '2026-27')

    expect(screen.getByRole('rowheader')).toContainElement(screen.getByRole('link', { name: 'Cadete A' }))
  })
})

describe('volver a traer los datos de la Federación (plan R4, decisión 7)', () => {
  const relaunch = (name: string) => screen.getByRole('button', { name: `Volver a traer los datos de la Federación, ${name}` })

  test('en la celda de la ingesta de cada competición, con la competición en el nombre', () => {
    renderTable([{ id: '1', team: 'Infantil A', competitions: [competition({ name: 'Liga' }), competition({ id: 'copa', name: 'Copa' })] }])

    expect(relaunch('Liga').closest('td')).toBe(screen.getAllByRole('cell')[5])
    expect(relaunch('Copa')).toBeInTheDocument()
  })

  test('sin competición, no hay', () => {
    renderTable([{ id: '1', team: 'Alevín A', competitions: [] }])

    expect(screen.queryByRole('button', { name: /^Volver a traer/ })).not.toBeInTheDocument()
  })

  test('al pulsarlo, avisa de qué competición', async () => {
    const { emitted } = renderTable([{ id: '1', team: 'Infantil A', competitions: [competition({ id: 'copa', name: 'Copa' })] }])

    await fireEvent.click(relaunch('Copa'))

    expect(emitted('relaunch')).toEqual([['copa']])
  })

  test('«En marcha», bloqueado', () => {
    renderTable([{ id: '1', team: 'Cadete B', competitions: [competition({ name: 'Liga', health: 'pending', healthName: 'En marcha' })] }])

    expect(relaunch('Liga')).toBeDisabled()
  })

  test('con fallos, se puede pulsar', () => {
    renderTable([{ id: '1', team: 'Cadete B', competitions: [competition({ name: 'Liga', health: 'failing', healthName: 'Con fallos' })] }])

    expect(relaunch('Liga')).toBeEnabled()
  })
})

describe('el resumen de cada competición (plan R5, §3)', () => {
  const played: CompetitionCell['summary'] = {
    position: 1,
    streak: [
      { round: 29, outcome: 'victoria', label: 'Victoria en la jornada 29' },
      { round: 28, outcome: 'descanso', label: 'Descansó en la jornada 28' },
    ],
    last: { outcome: 'V', atHome: true, score: '2 - 1', opponent: 'RAYO SUR B', opponentPosition: 3 },
    next: { kind: 'match', round: 30, date: 'Sáb 16 may', time: '18:00', atHome: false, opponent: 'ATLETICO NORTE A', opponentPosition: 18 },
  }
  const cadete = (summary: CompetitionCell['summary']): TeamRow[] => [{ id: '1', team: 'Cadete A', competitions: [competition({ id: 'liga', summary })] }]

  test('la posición, la racha, el último y el próximo, entre la competición y la ingesta', () => {
    renderTable(cadete(played), '2026/27', '2026-27')

    expect(rowTexts()[0]!.slice(2, 6)).toEqual([
      '1º',
      '29 Victoria en la jornada 29 28 Descansó en la jornada 28',
      'V En casa 2 - 1 3º RAYO SUR B',
      'Sáb 16 may 18:00 Fuera 18º ATLETICO NORTE A',
    ])
  })

  test('el último sin puesto del rival, y el próximo sin hora: «hora por fijar»', () => {
    const summary = {
      ...played,
      last: { ...played.last!, opponentPosition: undefined },
      next: { kind: 'match' as const, round: 1, date: 'Dom 20 sept', atHome: true, opponent: 'RACING CENTRO A' },
    }
    renderTable(cadete(summary), '2026/27', '2026-27')

    expect(rowTexts()[0]!.slice(4, 6)).toEqual(['V En casa 2 - 1 RAYO SUR B', 'Dom 20 sept, hora por fijar En casa RACING CENTRO A'])
  })

  test('si el próximo es el descanso, «Descansa · jornada N»', () => {
    renderTable(cadete({ ...played, next: { kind: 'rest', round: 30 } }), '2026/27', '2026-27')

    expect(rowTexts()[0]![5]).toBe('Descansa · jornada 30')
  })

  test('cada cuadro de la racha y el próximo llevan a su jornada, en la temporada que se ve (decisión 6)', () => {
    renderTable(cadete(played), '2026/27', '2026-27')

    expect(screen.getByRole('link', { name: 'Victoria en la jornada 29' })).toHaveAttribute('href', '/temporadas/2026-27/competiciones/liga?jornada=29')
    expect(screen.getByRole('link', { name: 'Descansó en la jornada 28' })).toHaveAttribute('href', '/temporadas/2026-27/competiciones/liga?jornada=28')
    // Su nombre es lo que se ve, con espacios entre las piezas (WCAG 2.5.3).
    expect(screen.getByRole('link', { name: 'Sáb 16 may 18:00 Fuera 18º ATLETICO NORTE A' })).toHaveAttribute(
      'href',
      '/temporadas/2026-27/competiciones/liga?jornada=30',
    )
  })

  test('la posición y el último no llevan a ningún sitio: lo hace el cuadro más reciente de la racha', () => {
    renderTable(cadete(played), '2026/27', '2026-27')
    const cells = screen.getAllByRole('row')[1]!.querySelectorAll('td')

    expect(cells[1]!.querySelector('a')).toBeNull()
    expect(cells[3]!.querySelector('a')).toBeNull()
  })

  test('el nombre del próximo sin hora ni puesto del rival, también lo que se ve', () => {
    const next = { kind: 'match' as const, round: 1, date: 'Dom 20 sept', atHome: true, opponent: 'RACING CENTRO A' }
    renderTable(cadete({ ...played, next }), '2026/27', '2026-27')

    expect(screen.getByRole('link', { name: 'Dom 20 sept, hora por fijar En casa RACING CENTRO A' })).toBeInTheDocument()
  })

  test('el descanso de la próxima jornada también lleva a ella', () => {
    renderTable(cadete({ ...played, next: { kind: 'rest', round: 30 } }), '2026/27', '2026-27')

    expect(screen.getByRole('link', { name: 'Descansa · jornada 30' })).toHaveAttribute('href', '/temporadas/2026-27/competiciones/liga?jornada=30')
  })

  test('un equipo sin competición: «Sin competición» ocupa también las cuatro columnas', () => {
    renderTable([{ id: '1', team: 'Alevín A', competitions: [] }])

    expect(screen.getByText('Sin competición').closest('td')).toHaveAttribute('colspan', '7')
  })
})

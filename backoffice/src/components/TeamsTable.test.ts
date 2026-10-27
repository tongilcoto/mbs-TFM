import { fireEvent, render, screen } from '@testing-library/vue'
import { describe, expect, test } from 'vitest'
import { createMemoryHistory, createRouter } from 'vue-router'
import TeamsTable from './TeamsTable.vue'
import type { CompetitionCell, TeamRow } from './teamRow'

function competition(fields: Partial<CompetitionCell>): CompetitionCell {
  return {
    name: 'Cadete · PRIMERA CADETE · Grupo 4',
    health: 'ok',
    healthName: 'Al día',
    previousFailed: false,
    lastSynced: '17/10/2026 23:40',
    ...fields,
  }
}

// Las acciones son enlaces: hace falta un router, aunque no se vaya a ningún sitio.
function withRouter() {
  const router = createRouter({ history: createMemoryHistory(), routes: [{ path: '/:anything(.*)*', component: {} }] })
  return { global: { plugins: [router] } }
}

function renderTable(rows: TeamRow[], seasonLabel?: string) {
  render(TeamsTable, { props: { rows, caption: 'Equipos de la temporada 2026/27', seasonLabel }, ...withRouter() })
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
    for (const name of ['Equipo', 'Competición', 'Ingesta', 'Última sincronización', 'Acciones']) {
      expect(screen.getByRole('columnheader', { name })).toBeInTheDocument()
    }
    expect(screen.getAllByRole('columnheader')).toHaveLength(5)
    expect(screen.getByRole('table', { name: 'Equipos de la temporada 2026/27' })).toBeInTheDocument()
  })

  test('cada equipo con su competición, su ingesta en palabras y su última sincronización', () => {
    renderTable([{ id: '1', team: 'Cadete B', competitions: [competition({})] }])

    // La última celda, la de las acciones: un icono sin texto a la vista.
    expect(rowTexts()).toEqual([['Cadete B', 'Cadete · PRIMERA CADETE · Grupo 4', '✓ Al día', '17/10/2026 23:40', '']])
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

    expect(rowTexts()[0]![2]).toBe('↻ En marcha ✕ La anterior tuvo fallos')
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
      ['Cadete B', 'Liga', '✓ Al día', '17/10/2026 23:40', ''],
      ['Copa', '○ Sin datos todavía', 'Nunca'],
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

import { fireEvent, render, screen } from '@testing-library/vue'
import { describe, expect, test } from 'vitest'
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

function renderTable(rows: TeamRow[]) {
  render(TeamsTable, { props: { rows, caption: 'Equipos de la temporada 2026/27' } })
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
    for (const name of ['Equipo', 'Competición', 'Ingesta', 'Última sincronización']) {
      expect(screen.getByRole('columnheader', { name })).toBeInTheDocument()
    }
    expect(screen.getAllByRole('columnheader')).toHaveLength(4)
    expect(screen.getByRole('table', { name: 'Equipos de la temporada 2026/27' })).toBeInTheDocument()
  })

  test('cada equipo con su competición, su ingesta en palabras y su última sincronización', () => {
    renderTable([{ id: '1', team: 'Cadete B', competitions: [competition({})] }])

    expect(rowTexts()).toEqual([['Cadete B', 'Cadete · PRIMERA CADETE · Grupo 4', '✓ Al día', '17/10/2026 23:40']])
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
      ['Cadete B', 'Liga', '✓ Al día', '17/10/2026 23:40'],
      ['Copa', '○ Sin datos todavía', 'Nunca'],
    ])
    expect(screen.getByRole('rowheader')).toHaveAttribute('rowspan', '2')
  })

  test('un equipo sin competición: «Sin competición» y cómo se engancha', () => {
    renderTable([{ id: '1', team: 'Alevín A', competitions: [] }])

    expect(rowTexts()).toEqual([['Alevín A', 'Sin competición Se engancha con la federación desde la ficha del equipo']])
  })
})

describe('ordenar (bloque T)', () => {
  test('cada cabecera es un botón, y al pulsarlo avisa de qué columna', async () => {
    const { emitted } = render(TeamsTable, { props: { rows: [], caption: 'x' } })

    for (const name of ['Equipo', 'Competición', 'Ingesta', 'Última sincronización']) {
      await fireEvent.click(screen.getByRole('button', { name }))
    }

    expect(emitted('sort')).toEqual([['equipo'], ['competicion'], ['ingesta'], ['sincronizacion']])
  })

  test('la columna ordenada lo dice, en su sentido; las demás, nada', () => {
    render(TeamsTable, { props: { rows: [], caption: 'x', order: { column: 'ingesta', reversed: true } } })

    expect(screen.getByRole('columnheader', { name: 'Ingesta' })).toHaveAttribute('aria-sort', 'descending')
    expect(screen.getByRole('columnheader', { name: 'Equipo' })).not.toHaveAttribute('aria-sort')
  })

  test('en su orden es «ascendente»', () => {
    render(TeamsTable, { props: { rows: [], caption: 'x', order: { column: 'equipo', reversed: false } } })

    expect(screen.getByRole('columnheader', { name: 'Equipo' })).toHaveAttribute('aria-sort', 'ascending')
  })
})

import { fireEvent, render, screen } from '@testing-library/vue'
import { expect, test } from 'vitest'
import { h } from 'vue'
import SortableHeader from './SortableHeader.vue'

// Cuántas veces ha avisado de que la pinchan.
let calls: number[] = []

// La cabecera, dentro de una tabla de verdad, para que el lector la reconozca como cabecera de columna.
function renderHeader(sort?: 'ascending' | 'descending') {
  render({
    render: () =>
      h('table', [h('thead', [h('tr', [h(SortableHeader, { label: 'Ingesta', sort, onSort: () => calls.push(1) })])])]),
  })
}

test('es una cabecera de columna con un botón que se llama como ella', async () => {
  calls = []
  renderHeader()

  const header = screen.getByRole('columnheader', { name: 'Ingesta' })
  await fireEvent.click(screen.getByRole('button', { name: 'Ingesta' }))

  expect(header).toContainElement(screen.getByRole('button'))
  expect(calls).toEqual([1])
})

test('sin ordenar por ella, no dice nada de orden', () => {
  renderHeader()

  expect(screen.getByRole('columnheader')).not.toHaveAttribute('aria-sort')
})

test.each([['ascending'], ['descending']] as const)('ordenada (%s), el lector lo dice', (sort) => {
  renderHeader(sort)

  expect(screen.getByRole('columnheader')).toHaveAttribute('aria-sort', sort)
})

test('la flecha se ve pero no se lee: el orden lo dice aria-sort', () => {
  renderHeader('descending')

  expect(screen.getByText('▼')).toHaveAttribute('aria-hidden', 'true')
})

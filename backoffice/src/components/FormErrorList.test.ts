import { fireEvent, render, screen } from '@testing-library/vue'
import { expect, test } from 'vitest'
import FormErrorList from './FormErrorList.vue'

const errors = [
  { fieldId: 'team-category', label: 'Categoría', message: 'Este campo es obligatorio' },
  { fieldId: 'team-season', label: 'Temporada', message: 'Este campo es obligatorio' },
]

test('nombra cada campo con su error, y cada enlace lleva el foco a su campo', async () => {
  const field = document.createElement('input')
  field.id = 'team-season'
  document.body.append(field)
  render(FormErrorList, { props: { errors } })

  expect(screen.getByRole('group', { name: 'Revisa estos campos:' })).toBeInTheDocument()
  await fireEvent.click(screen.getByRole('link', { name: 'Temporada: Este campo es obligatorio' }))

  expect(field).toHaveFocus()
  field.remove()
})

test('con un solo error, en singular', () => {
  render(FormErrorList, { props: { errors: errors.slice(0, 1) } })

  expect(screen.getByText('Revisa este campo:')).toBeInTheDocument()
})

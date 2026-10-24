import { render, screen } from '@testing-library/vue'
import { expect, test } from 'vitest'
import { h } from 'vue'
import FormField from './FormField.vue'

// El campo de dentro, como lo pondría la pantalla: con el `id` del FormField y unido a sus textos.
function renderField(props: { required: boolean; help?: string; error?: string }) {
  render(FormField, {
    props: { id: 'team-letter', label: 'Letra', ...props },
    slots: {
      default: ({ describedBy, invalid }: { describedBy?: string; invalid: boolean }) =>
        h('input', { id: 'team-letter', 'aria-describedby': describedBy, 'aria-invalid': invalid || undefined }),
    },
  })
  return screen.getByRole('textbox')
}

test('el obligatorio se ve con el asterisco y se lee con la palabra', () => {
  const field = renderField({ required: true })

  expect(field).toHaveAccessibleName('Letra (obligatorio)')
  expect(screen.getByText('*')).toHaveAttribute('aria-hidden', 'true')
})

test('el opcional, sin asterisco', () => {
  expect(renderField({ required: false })).toHaveAccessibleName('Letra')
})

test('la ayuda y el error se leen al llegar al campo, y el campo queda marcado como no válido', () => {
  const field = renderField({ required: false, help: 'A, B…', error: 'No puede estar vacío' })

  expect(field).toHaveAccessibleDescription('A, B… No puede estar vacío')
  expect(field).toBeInvalid()
})

test('sin error, el campo no está marcado', () => {
  const field = renderField({ required: false, help: 'A, B…' })

  expect(field).toHaveAccessibleDescription('A, B…')
  expect(field).toBeValid()
})

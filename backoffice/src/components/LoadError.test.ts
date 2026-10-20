import { fireEvent, render, screen } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { expect, test } from 'vitest'
import { primeVueOptions } from '../theme/primevue'
import LoadError from './LoadError.vue'

function renderError(props: { message: string; code?: string; retry: boolean }, slot?: string) {
  return render(LoadError, {
    props,
    slots: slot ? { default: slot } : {},
    global: { plugins: [[PrimeVue, primeVueOptions]] },
  })
}

test('el error se anuncia, con su código en pequeño y sin Reintentar si no tiene sentido', () => {
  renderError({ message: 'No se ha encontrado la temporada', code: 'SEASON_NOT_FOUND', retry: false })

  expect(screen.getByRole('alert')).toHaveTextContent('No se ha encontrado la temporada')
  expect(screen.getByText('Código: SEASON_NOT_FOUND')).toBeInTheDocument()
  expect(screen.queryByRole('button')).toBeNull()
})

test('si el fallo puede ser pasajero, Reintentar avisa al pulsarlo', async () => {
  const { emitted } = renderError({ message: 'No se ha podido conectar con el servidor', retry: true })

  await fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))

  expect(emitted('retry')).toHaveLength(1)
})

test('la pantalla puede añadir algo dentro, como un enlace', () => {
  renderError({ message: 'No hay ninguna temporada 2019/20', retry: false }, '<a href="/">Ir a la temporada en curso</a>')

  expect(screen.getByRole('alert')).toHaveTextContent('Ir a la temporada en curso')
})

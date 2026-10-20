import { fireEvent, render, screen } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { describe, expect, test } from 'vitest'
import { primeVueOptions } from '../theme/primevue'
import FullPageError from './FullPageError.vue'

type Props = { message: string; code?: string; hint?: string; retry: boolean }

function renderError(props: Props) {
  return render(FullPageError, { props, global: { plugins: [[PrimeVue, primeVueOptions]] } })
}

describe('la página entera de error', () => {
  test('el mensaje es el título, con el código en pequeño y sin Reintentar si no tiene sentido', () => {
    renderError({ message: 'Este club no existe. Revisa la dirección', code: 'UNKNOWN_TENANT', retry: false })

    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Este club no existe. Revisa la dirección')
    expect(screen.getByText('Código: UNKNOWN_TENANT')).toBeInTheDocument()
    expect(screen.queryByRole('button')).toBeNull()
    expect(screen.queryByRole('navigation')).toBeNull()
  })

  test('con la línea de ayuda, si la hay', () => {
    renderError({ message: 'Falta el club en la dirección', hint: 'Por ejemplo: celtic-castilla.localhost:5173', retry: false })

    expect(screen.getByText('Por ejemplo: celtic-castilla.localhost:5173')).toBeInTheDocument()
  })

  test('si el fallo puede ser pasajero, Reintentar avisa al pulsarlo; sin código, no sale «Código»', async () => {
    const { emitted } = renderError({ message: 'No se ha podido conectar con el servidor', retry: true })

    await fireEvent.click(screen.getByRole('button', { name: 'Reintentar' }))

    expect(emitted('retry')).toHaveLength(1)
    expect(screen.queryByText(/Código/)).toBeNull()
  })
})

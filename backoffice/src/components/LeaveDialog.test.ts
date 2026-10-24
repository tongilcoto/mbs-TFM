import { render, screen, waitFor } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { expect, test } from 'vitest'
import { primeVueOptions } from '../theme/primevue'
import LeaveDialog from './LeaveDialog.vue'

test('al abrirse, el foco va a «Seguir editando», el botón que no pierde nada (LLD-B §10.1)', async () => {
  const { rerender } = render(LeaveDialog, {
    props: { visible: false },
    // Con la animación de verdad: la de mentira de las pruebas no avisa de que la ventana se ha abierto.
    global: { plugins: [[PrimeVue, primeVueOptions]], stubs: { transition: false } },
  })

  await rerender({ visible: true })

  await waitFor(() => expect(screen.getByRole('button', { name: 'Seguir editando' })).toHaveFocus())
})

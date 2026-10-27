import { render, screen } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { afterEach, expect, test, vi } from 'vitest'
import { defineComponent, h } from 'vue'
import { createMemoryHistory, createRouter } from 'vue-router'
import App from './App.vue'
import { announce, notice } from './notice'
import { primeVueOptions } from './theme/primevue'

afterEach(() => {
  vi.unstubAllGlobals()
  notice.value = undefined
})

test('el marco enseña el aviso «Guardado» en una zona que el lector lee sin mover el foco', async () => {
  vi.stubGlobal('fetch', async () => Response.json({ id: 'club', name: 'Celtic Castilla', shortName: 'Celtic' }))
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [{ path: '/', component: defineComponent({ render: () => h('h1', 'Equipos') }), meta: { title: 'Equipos' } }],
  })
  await router.push('/')
  render(App, { global: { plugins: [router, [PrimeVue, primeVueOptions]] } })
  await screen.findByRole('heading', { name: 'Equipos' })
  const status = screen.getAllByRole('status').find((element) => element.classList.contains('notice'))!
  expect(status).toHaveTextContent('')

  announce('Guardado')

  await vi.waitFor(() => expect(status).toHaveTextContent('Guardado'))
})

// Al cambiar de pantalla, el foco va a su título (LLD-B §10.2); si la navegación se cancela —«Seguir editando» al
// salir con cambios—, no se cambia de pantalla, y el foco se queda donde estaba.
test('una navegación cancelada no mueve el foco al título', async () => {
  vi.stubGlobal('fetch', async () => Response.json({ id: 'club', name: 'Celtic Castilla', shortName: 'Celtic' }))
  let stay = true
  const router = createRouter({
    history: createMemoryHistory(),
    routes: [
      {
        path: '/',
        component: defineComponent({ render: () => [h('h1', 'Equipos'), h('button', 'Cancelar')] }),
        meta: { title: 'Equipos' },
        beforeEnter: () => true,
      },
      {
        path: '/otra',
        component: defineComponent({ render: () => h('h1', 'Otra') }),
        meta: { title: 'Otra' },
        beforeEnter: () => !stay,
      },
    ],
  })
  await router.push('/')
  render(App, { global: { plugins: [router, [PrimeVue, primeVueOptions]] } })
  const button = await screen.findByRole('button', { name: 'Cancelar' })
  button.focus()

  await router.push('/otra')
  await new Promise((resolve) => setTimeout(resolve))
  expect(button).toHaveFocus()

  stay = false
  await router.push('/otra')
  await vi.waitFor(() => expect(screen.getByRole('heading', { name: 'Otra' })).toHaveFocus())
})

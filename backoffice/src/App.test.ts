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

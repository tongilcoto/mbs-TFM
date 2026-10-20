import { render, screen } from '@testing-library/vue'
import { expect, test } from 'vitest'
import { createMemoryHistory, createRouter } from 'vue-router'
import SideMenu from './SideMenu.vue'

// El menú lleva enlaces de verdad, así que necesita un mapa de pantallas; aquí, uno mínimo en memoria.
test('el menú tiene solo «Equipos», que lleva a la portada y la marca como abierta', async () => {
  const router = createRouter({ history: createMemoryHistory(), routes: [{ path: '/', component: { render: () => null } }] })
  await router.push('/')

  render(SideMenu, { global: { plugins: [router] } })

  const links = screen.getAllByRole('link')
  expect(links.map((link) => link.textContent?.trim())).toEqual(['Equipos'])
  expect(links[0]).toHaveAttribute('href', '/')
  expect(links[0]).toHaveAttribute('aria-current', 'page')
  expect(screen.getByRole('navigation', { name: 'Menú principal' })).toBeInTheDocument()
})

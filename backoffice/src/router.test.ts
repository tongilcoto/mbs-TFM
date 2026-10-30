import { expect, test } from 'vitest'
import { router } from './router'

test('/equipos lleva a la portada, con la dirección cambiada a /', async () => {
  await router.push('/equipos')

  expect(router.currentRoute.value.path).toBe('/')
  expect(router.currentRoute.value.meta.title).toBe('Equipos')
})

test('un camino que la web no conoce es «Esta página no existe»', async () => {
  await router.push('/equipoz')

  expect(router.currentRoute.value.meta.title).toBe('Esta página no existe')
})

test('la ficha sin pestaña lleva a Resultados (LLD-B §6.4)', async () => {
  await router.push('/temporadas/2026-27/equipos/a1b2/')

  expect(router.currentRoute.value.path).toBe('/temporadas/2026-27/equipos/a1b2/resultados')
  expect(router.currentRoute.value.meta.title).toBe('Resultados')
})

test('/equipos/:id, sin temporada, es la ficha; /equipos/nuevo sigue siendo el alta', async () => {
  await router.push('/equipos/a1b2')
  expect(router.currentRoute.value.meta.title).toBe('Resultados')

  await router.push('/equipos/nuevo')
  expect(router.currentRoute.value.meta.title).toBe('Alta de equipo')
})

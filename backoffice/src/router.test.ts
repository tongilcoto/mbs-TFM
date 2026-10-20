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

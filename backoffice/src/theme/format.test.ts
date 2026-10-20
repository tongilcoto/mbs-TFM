import { describe, expect, test } from 'vitest'
import { formatInstant } from './format'

// Las pruebas fijan la zona horaria, para que den lo mismo en cualquier ordenador.
describe('la fecha y la hora de un instante', () => {
  test('el instante del servidor, en UTC, sale en la hora de Madrid', () => {
    expect(formatInstant('2026-10-17T21:40:00Z', 'Europe/Madrid')).toBe('17/10/2026 23:40')
  })

  test('cerca de medianoche, el día es el de Madrid, no el de UTC', () => {
    expect(formatInstant('2026-10-17T22:30:00Z', 'Europe/Madrid')).toBe('18/10/2026 00:30')
  })

  test('en invierno Madrid va una hora por delante de UTC, no dos; y con ceros delante', () => {
    expect(formatInstant('2026-01-05T08:05:00Z', 'Europe/Madrid')).toBe('05/01/2026 09:05')
  })

  test('en Canarias, su hora', () => {
    expect(formatInstant('2026-10-17T21:40:00Z', 'Atlantic/Canary')).toBe('17/10/2026 22:40')
  })

  test('con décimas de segundo, igual', () => {
    expect(formatInstant('2026-10-17T21:40:59.999Z', 'Europe/Madrid')).toBe('17/10/2026 23:40')
  })

  test('sin zona, la del navegador', () => {
    const browserZone = Intl.DateTimeFormat().resolvedOptions().timeZone

    expect(formatInstant('2026-10-17T21:40:00Z')).toBe(formatInstant('2026-10-17T21:40:00Z', browserZone))
  })
})

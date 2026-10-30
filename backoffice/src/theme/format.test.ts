import { describe, expect, test, vi } from 'vitest'
import { formatGoalDifference, formatInstant, formatKickoff, formatMatchDay } from './format'

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

describe('el día de un partido (plan R4, §3.3)', () => {
  test('con el día de la semana, el día y el mes: «Dom 1 mar»', () => {
    expect(formatMatchDay('2026-03-01')).toBe('Dom 1 mar')
    expect(formatMatchDay('2026-10-31')).toBe('Sáb 31 oct')
    expect(formatMatchDay('2027-09-04')).toBe('Sáb 4 sept')
  })

  // LLD-B §9.7: convertida en la medianoche UTC y enseñada en Honolulu, sería el viernes 28 de febrero.
  test('en un navegador de otra zona horaria, el mismo día', () => {
    try {
      for (const other of ['Pacific/Honolulu', 'Pacific/Kiritimati']) {
        vi.stubEnv('TZ', other)
        expect(formatMatchDay('2026-03-01')).toBe('Dom 1 mar')
      }
    } finally {
      vi.unstubAllEnvs()
    }
  })
})

describe('la hora de un partido', () => {
  test('de 24 horas, sin segundos', () => {
    expect(formatKickoff('12:00')).toBe('12:00')
    expect(formatKickoff('09:30:00')).toBe('09:30')
  })
})

describe('la diferencia de goles', () => {
  test('con su signo; el menos, de verdad', () => {
    expect(formatGoalDifference(3)).toBe('+3')
    expect(formatGoalDifference(-2)).toBe('−2')
    expect(formatGoalDifference(0)).toBe('0')
  })
})

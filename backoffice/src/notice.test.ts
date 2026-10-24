import { afterEach, expect, test, vi } from 'vitest'
import { announce, notice, NOTICE_MS } from './notice'

afterEach(() => vi.useRealTimers())

test('el aviso se ve al pedirlo y desaparece solo', () => {
  vi.useFakeTimers()

  announce('Guardado')
  expect(notice.value).toBe('Guardado')

  vi.advanceTimersByTime(NOTICE_MS - 1)
  expect(notice.value).toBe('Guardado')
  vi.advanceTimersByTime(1)
  expect(notice.value).toBeUndefined()
})

test('otro aviso antes de que acabe el primero empieza la cuenta de nuevo', () => {
  vi.useFakeTimers()

  announce('Guardado')
  vi.advanceTimersByTime(NOTICE_MS - 1)
  announce('Guardado')
  vi.advanceTimersByTime(NOTICE_MS - 1)

  expect(notice.value).toBe('Guardado')
})

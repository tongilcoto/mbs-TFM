import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest'
import { effectScope, nextTick, ref } from 'vue'
import { REFRESH_EVERY_MS, REFRESH_FOR_MS, refreshWhile } from './refresh'

// Con un reloj de mentira (como la espera de 30 s de R0.4): los 10 s y los 5 minutos pasan al momento.
beforeEach(() => vi.useFakeTimers())
afterEach(() => {
  vi.useRealTimers()
  setVisibility('visible')
})

function setVisibility(state: 'visible' | 'hidden') {
  Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => state })
  document.dispatchEvent(new Event('visibilitychange'))
}

// Monta el refresco como lo haría una pantalla; `stop` es salir de ella.
function start(initiallyActive = true) {
  const active = ref(initiallyActive)
  const refresh = vi.fn(async () => {})
  const scope = effectScope()
  scope.run(() => refreshWhile(() => active.value, refresh))
  return { active, refresh, stop: () => scope.stop() }
}

describe('refrescar mientras algo está en marcha (LLD-B §2.4)', () => {
  test('cada 10 s, ni antes ni después', async () => {
    const { refresh } = start()

    await vi.advanceTimersByTimeAsync(REFRESH_EVERY_MS - 1)
    expect(refresh).not.toHaveBeenCalled()
    await vi.advanceTimersByTimeAsync(1)
    expect(refresh).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(REFRESH_EVERY_MS * 2)
    expect(refresh).toHaveBeenCalledTimes(3)
  })

  test('sin nada en marcha, nada', async () => {
    const { refresh } = start(false)

    await vi.advanceTimersByTimeAsync(REFRESH_EVERY_MS * 3)

    expect(refresh).not.toHaveBeenCalled()
  })

  test('para cuando ya no queda nada en marcha, y vuelve si algo se pone en marcha otra vez', async () => {
    const { active, refresh } = start()
    await vi.advanceTimersByTimeAsync(REFRESH_EVERY_MS)

    active.value = false
    await nextTick()
    await vi.advanceTimersByTimeAsync(REFRESH_EVERY_MS * 3)
    expect(refresh).toHaveBeenCalledTimes(1)

    active.value = true
    await nextTick()
    await vi.advanceTimersByTimeAsync(REFRESH_EVERY_MS)
    expect(refresh).toHaveBeenCalledTimes(2)
  })

  test('como mucho 5 minutos seguidos', async () => {
    const { refresh } = start()

    await vi.advanceTimersByTimeAsync(REFRESH_FOR_MS + REFRESH_EVERY_MS * 3)

    expect(refresh).toHaveBeenCalledTimes(REFRESH_FOR_MS / REFRESH_EVERY_MS)
  })

  test('con la pestaña escondida, nada; al volver, lo último ya, y otra vez cada 10 s', async () => {
    const { refresh } = start()

    setVisibility('hidden')
    await vi.advanceTimersByTimeAsync(REFRESH_EVERY_MS * 3)
    expect(refresh).not.toHaveBeenCalled()

    setVisibility('visible')
    await vi.advanceTimersByTimeAsync(0)
    expect(refresh).toHaveBeenCalledTimes(1)
    await vi.advanceTimersByTimeAsync(REFRESH_EVERY_MS)
    expect(refresh).toHaveBeenCalledTimes(2)
  })

  test('si se esconde la pestaña con un refresco a medias, al acabar no programa otro', async () => {
    const { refresh } = start()
    let finish: () => void = () => {}
    refresh.mockImplementationOnce(() => new Promise<void>((resolve) => (finish = resolve)))
    await vi.advanceTimersByTimeAsync(REFRESH_EVERY_MS)

    setVisibility('hidden')
    finish()
    await vi.advanceTimersByTimeAsync(REFRESH_EVERY_MS * 3)

    expect(refresh).toHaveBeenCalledTimes(1)
  })

  test('al volver a la pestaña después de los 5 minutos, otros 5', async () => {
    const { refresh } = start()
    setVisibility('hidden')
    await vi.advanceTimersByTimeAsync(REFRESH_FOR_MS * 2)

    setVisibility('visible')
    await vi.advanceTimersByTimeAsync(REFRESH_EVERY_MS * 2)

    expect(refresh).toHaveBeenCalledTimes(3)
  })

  test('al volver a la pestaña sin nada en marcha, nada', async () => {
    const { refresh } = start(false)
    setVisibility('hidden')

    setVisibility('visible')
    await vi.advanceTimersByTimeAsync(REFRESH_EVERY_MS)

    expect(refresh).not.toHaveBeenCalled()
  })

  test('un refresco lento no se pisa: el siguiente se cuenta desde que acaba', async () => {
    const { refresh } = start()
    let finish: () => void = () => {}
    refresh.mockImplementationOnce(() => new Promise<void>((resolve) => (finish = resolve)))

    await vi.advanceTimersByTimeAsync(REFRESH_EVERY_MS * 3)
    expect(refresh).toHaveBeenCalledTimes(1)
    // Volver a la pestaña con el refresco a medias no lanza otro.
    setVisibility('hidden')
    setVisibility('visible')
    expect(refresh).toHaveBeenCalledTimes(1)

    finish()
    await vi.advanceTimersByTimeAsync(REFRESH_EVERY_MS)
    expect(refresh).toHaveBeenCalledTimes(2)
  })

  test('al salir de la pantalla, se para', async () => {
    const { refresh, stop } = start()

    stop()
    await vi.advanceTimersByTimeAsync(REFRESH_EVERY_MS * 3)
    setVisibility('hidden')
    setVisibility('visible')

    expect(refresh).not.toHaveBeenCalled()
  })
})

// Volver a pedir los datos solos mientras algo esté «en marcha» (LLD-B §2.4, DW-20; plan R3, decisión 5): cada 10 s,
// solo con la pestaña a la vista y como mucho 5 minutos seguidos. Lo usa una pantalla al montarse; se para sola al
// desmontarse.
import { onScopeDispose, watch } from 'vue'

export const REFRESH_EVERY_MS = 10_000
export const REFRESH_FOR_MS = 5 * 60_000

// `active`, si hay algo en marcha: mientras lo haya, `refresh` cada 10 s. `refresh` no lanza errores: un refresco
// que falla se deja estar y se prueba en el siguiente (lo decide quien lo usa).
//
// Los 5 minutos empiezan cuando algo se pone en marcha, y vuelven a empezar al volver a la pestaña: quien vuelve
// a mirar, ve lo último, aunque la pestaña estuviera escondida más de 5 minutos.
export function refreshWhile(active: () => boolean, refresh: () => Promise<void>) {
  let timer: ReturnType<typeof setTimeout> | undefined
  let until = 0
  let running = false

  const visible = () => document.visibilityState !== 'hidden'

  function stop() {
    clearTimeout(timer)
    timer = undefined
  }

  function schedule() {
    stop()
    if (active() && visible() && Date.now() < until) timer = setTimeout(run, REFRESH_EVERY_MS)
  }

  async function run() {
    timer = undefined
    running = true
    try {
      await refresh()
    } finally {
      running = false
      schedule()
    }
  }

  function start() {
    until = Date.now() + REFRESH_FOR_MS
    schedule()
  }

  // Escondida, nada; a la vista otra vez, lo último ya, y otros 5 minutos. Si hay un refresco a medias, al
  // acabar se programa el siguiente.
  function onVisibility() {
    if (!visible()) return stop()
    if (!active() || running) return
    until = Date.now() + REFRESH_FOR_MS
    void run()
  }

  watch(active, (now) => (now ? start() : stop()), { immediate: true })
  document.addEventListener('visibilitychange', onVisibility)
  onScopeDispose(() => {
    stop()
    document.removeEventListener('visibilitychange', onVisibility)
  })
}

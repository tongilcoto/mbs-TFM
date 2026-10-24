// El aviso breve que pone el marco, como «Guardado» (LLD-B §5.4). Lo pide una pantalla y lo enseña App.vue, así
// que sigue a la vista después de cambiar de pantalla. Desaparece solo; los de error no van aquí (LLD-B §10.3).
import { ref } from 'vue'

// Cuánto se ve: lo bastante para leerlo, sin quedarse encima.
export const NOTICE_MS = 5_000

export const notice = ref<string>()

let timer: ReturnType<typeof setTimeout> | undefined

export function announce(message: string) {
  notice.value = message
  clearTimeout(timer)
  timer = setTimeout(() => (notice.value = undefined), NOTICE_MS)
}

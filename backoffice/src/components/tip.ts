// El texto que sale al pasar el ratón y al llegar con el teclado (LLD-B §3.7): se queda mientras el ratón está
// encima, y Escape lo esconde sin mover el foco (WCAG 1.4.13). El `Tooltip` de PrimeVue hace lo uno o lo otro, no los
// dos. Lo usan las acciones con icono (IconAction), los cuadros de la racha (StreakBoxes) y casa o fuera (VenueIcon);
// el texto lo pinta TipBubble.
import { computed, onBeforeUnmount, ref, watch } from 'vue'

export function useTip() {
  const hovered = ref(false)
  const focused = ref(false)
  // Escondido con Escape: vuelve a salir al llegar otra vez, con el ratón o con el teclado.
  const dismissed = ref(false)
  const shown = computed(() => (hovered.value || focused.value) && !dismissed.value)

  // Escape vale también con el foco en otro sitio y el ratón encima: se escucha en todo el documento mientras se ve.
  function onKey(event: KeyboardEvent) {
    if (event.key === 'Escape') dismissed.value = true
  }
  watch(shown, (now) => {
    if (now) document.addEventListener('keydown', onKey)
    else document.removeEventListener('keydown', onKey)
  })
  onBeforeUnmount(() => document.removeEventListener('keydown', onKey))

  return {
    shown,
    hover() {
      hovered.value = true
      dismissed.value = false
    },
    leave() {
      hovered.value = false
    },
    focus() {
      focused.value = true
      dismissed.value = false
    },
    blur() {
      focused.value = false
    },
  }
}

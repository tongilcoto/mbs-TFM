import Aura from '@primeuix/themes/aura'
import { es } from 'primelocale/es.json'
import type { PrimeVueConfiguration } from 'primevue/config'

// PrimeVue con el tema Aura, todavía sin tocar: los colores se miden de los bocetos en la rebanada 1 (LLD-B §9.1).
// Los textos de sus piezas, en español, y la semana desde el lunes (LLD-B §9.5).
export const primeVueOptions: PrimeVueConfiguration = {
  theme: {
    preset: Aura,
    // El modo oscuro se activa con esta clase en <html>; la pone index.html antes de pintar (LLD-B §9.3).
    options: { darkModeSelector: '.app-dark' },
  },
  locale: es,
}

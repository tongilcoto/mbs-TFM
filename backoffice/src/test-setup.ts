// Se ejecuta antes de cada fichero de pruebas de piezas.
import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/vue'
import { afterEach } from 'vitest'

// Cada prueba empieza con la página vacía.
afterEach(() => cleanup())

// jsdom no trae matchMedia, y algunas piezas de PrimeVue lo usan para saber el tamaño de la pantalla.
// Esta versión mínima contesta siempre «no coincide».
if (!window.matchMedia) {
  window.matchMedia = (query: string) =>
    ({
      matches: false,
      media: query,
      onchange: null,
      addEventListener: () => {},
      removeEventListener: () => {},
      addListener: () => {},
      removeListener: () => {},
      dispatchEvent: () => false,
    }) as MediaQueryList
}

import { palette as shadesOf } from '@primeuix/styled'
import { definePreset } from '@primeuix/themes'
import Aura from '@primeuix/themes/aura'
import { es } from 'primelocale/es.json'
import type { PrimeVueConfiguration } from 'primevue/config'
import { DARK_MODE_CLASS } from './mode'
import { palette } from './palette'

// Aura con la paleta encima (plan R1, decisión 7). Lo que la paleta no dice —los colores de los estados, los
// bordes, los campos de los formularios— sigue siendo de Aura.
const preset = definePreset(Aura, {
  semantic: {
    // Los once tonos del principal, del 50 (casi blanco) al 950 (casi negro); el 500 es el de la paleta.
    primary: shadesOf(palette.principal),
    colorScheme: {
      light: {
        // El 800: el 500 sobre blanco se queda en 2,1 de contraste, y el 800 llega a 6.
        primary: { color: '{primary.800}', hoverColor: '{primary.900}', activeColor: '{primary.950}' },
        surface: { 0: palette.claro.superficie, 50: palette.claro.fondo },
        text: { color: palette.claro.texto, mutedColor: palette.claro.textoSuave },
        fondo: palette.claro.fondo,
      },
      dark: {
        primary: { color: '{primary.500}', hoverColor: '{primary.400}', activeColor: '{primary.300}' },
        // Aura usa estos dos tonos para lo que va encima del fondo (tarjetas, menús) y para el fondo de los campos.
        surface: { 900: palette.oscuro.superficie, 950: palette.oscuro.fondo },
        text: { color: palette.oscuro.texto, mutedColor: palette.oscuro.textoSuave },
        // El fondo de la página: no es de ninguna pieza, así que Aura no lo tiene. Sale como --p-fondo (index.html).
        fondo: palette.oscuro.fondo,
      },
    },
  },
})

// Los textos de sus piezas, en español, y la semana desde el lunes (LLD-B §9.5).
export const primeVueOptions: PrimeVueConfiguration = {
  theme: {
    preset,
    // El modo oscuro se activa con esta clase en <html>; la pone index.html antes de pintar (LLD-B §9.3).
    options: { darkModeSelector: `.${DARK_MODE_CLASS}` },
  },
  locale: es,
}

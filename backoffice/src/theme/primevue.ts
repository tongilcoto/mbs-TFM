import { palette as shadesOf } from '@primeuix/styled'
import { definePreset } from '@primeuix/themes'
import Aura from '@primeuix/themes/aura'
import { es } from 'primelocale/es.json'
import type { PrimeVueConfiguration } from 'primevue/config'
import { DARK_MODE_CLASS } from './mode'
import { palette } from './palette'

// Los colores de los estados, que el boceto no tiene: se toman de Aura (plan R1, decisión 7) y se nombran por lo
// que significan (LLD-B §9.2). Salen como --p-estado-bien, --p-estado-fallo… Nunca van solos: siempre con su
// palabra al lado (LLD-B §9.4). En claro, tonos oscuros para que se vean sobre blanco; en oscuro, claros.
const states = {
  claro: { bien: '{green.700}', fallo: '{red.600}', enMarcha: '{sky.700}', aviso: '{amber.700}', sinDatos: '{surface.500}' },
  oscuro: { bien: '{green.400}', fallo: '{red.400}', enMarcha: '{sky.400}', aviso: '{amber.400}', sinDatos: '{surface.400}' },
}

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
        estado: states.claro,
      },
      dark: {
        primary: { color: '{primary.500}', hoverColor: '{primary.400}', activeColor: '{primary.300}' },
        // Aura usa estos dos tonos para lo que va encima del fondo (tarjetas, menús) y para el fondo de los campos.
        surface: { 900: palette.oscuro.superficie, 950: palette.oscuro.fondo },
        text: { color: palette.oscuro.texto, mutedColor: palette.oscuro.textoSuave },
        // El fondo de la página: no es de ninguna pieza, así que Aura no lo tiene. Sale como --p-fondo (index.html).
        fondo: palette.oscuro.fondo,
        estado: states.oscuro,
      },
    },
  },
  components: {
    button: {
      // Un enlace con aspecto de botón («Dar de alta un equipo», que va a otra pantalla) se ve como un botón: sin
      // el subrayado que el navegador pone a todos los enlaces y que Aura solo quita a los botones de verdad.
      css: () => 'a.p-button { text-decoration: none; }',
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

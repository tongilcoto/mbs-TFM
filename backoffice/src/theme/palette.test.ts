import { palette as shadesOf } from '@primeuix/styled'
import { describe, expect, test } from 'vitest'
import { palette } from './palette'

// El contraste entre dos colores, como lo define WCAG 2.2: de 1 (iguales) a 21 (negro sobre blanco).
function contrast(a: string, b: string): number {
  const [lighter, darker] = [luminance(a), luminance(b)].sort((x, y) => y - x)
  return (lighter + 0.05) / (darker + 0.05)
}

function luminance(hex: string): number {
  const [r, g, b] = [1, 3, 5].map((i) => {
    const channel = parseInt(hex.slice(i, i + 2), 16) / 255
    return channel <= 0.03928 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4
  })
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

// Nivel AA para el texto normal (LLD-B §9.4).
const AA = 4.5

// axe lo comprueba en los escenarios, pero solo en lo que sale en pantalla; esto avisa en cuanto se toca la paleta.
describe.each([
  ['claro', palette.claro],
  ['oscuro', palette.oscuro],
])('la paleta en modo %s se lee', (_, mode) => {
  test.each([
    ['el texto sobre el fondo', mode.texto, mode.fondo],
    ['el texto sobre la superficie', mode.texto, mode.superficie],
    ['el texto suave sobre el fondo', mode.textoSuave, mode.fondo],
    ['el texto suave sobre la superficie', mode.textoSuave, mode.superficie],
  ])('%s', (_, text, background) => {
    expect(contrast(text, background)).toBeGreaterThanOrEqual(AA)
  })
})

// El principal en cada modo es el tono que elige primevue.ts: el 800 en claro y el 500 en oscuro.
describe('el principal se lee', () => {
  // PrimeVue declara los tonos como «quizá vacíos»; con un color de entrada, están los once.
  const shades = shadesOf(palette.principal) as Record<number, string>

  test('en modo claro, como texto sobre la superficie y con texto blanco encima', () => {
    expect(contrast(shades[800], palette.claro.superficie)).toBeGreaterThanOrEqual(AA)
    expect(contrast(shades[800], palette.claro.fondo)).toBeGreaterThanOrEqual(AA)
  })

  test('en modo oscuro, como texto sobre el fondo y la superficie, y con la superficie encima', () => {
    expect(contrast(shades[500], palette.oscuro.fondo)).toBeGreaterThanOrEqual(AA)
    expect(contrast(shades[500], palette.oscuro.superficie)).toBeGreaterThanOrEqual(AA)
  })
})

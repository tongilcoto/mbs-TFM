import { render, screen } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import Button from 'primevue/button'
import DatePicker from 'primevue/datepicker'
import { expect, test } from 'vitest'
import { primeVueOptions } from './primevue'

// Las piezas de PrimeVue hablan en español y la semana empieza en lunes (LLD-B §9.5).
test('el calendario de PrimeVue sale en español y empieza en lunes', () => {
  const { container } = render(DatePicker, {
    props: { inline: true, modelValue: new Date(2026, 9, 16) },
    global: { plugins: [[PrimeVue, primeVueOptions]] },
  })

  const weekdays = screen.getAllByRole('columnheader').map((day) => day.textContent?.trim())
  expect(weekdays).toEqual(['L', 'M', 'X', 'J', 'V', 'S', 'D'])
  expect(container).toHaveTextContent('Octubre')
})

// Un enlace con aspecto de botón se ve como un botón, sin el subrayado de los enlaces. El navegador de mentira de
// las pruebas no subraya nada, así que lo que se comprueba es que la regla llega a la página con el tema.
test('el tema quita el subrayado a los enlaces con aspecto de botón', () => {
  render(Button, {
    props: { as: 'a', label: 'Dar de alta un equipo' },
    attrs: { href: '/equipos/nuevo' },
    global: { plugins: [[PrimeVue, primeVueOptions]] },
  })

  const styles = [...document.querySelectorAll('style')].map((style) => style.textContent).join('\n')
  expect(styles).toMatch(/a\.p-button\s*\{\s*text-decoration:\s*none;?\s*\}/)
})

// El botón rojo («Dar de baja»), en claro, con el 700: el 500 de Aura no llega al contraste de WCAG con el texto
// blanco (R6.18). Como antes, se comprueba que el color llega a la página con el tema.
test('el botón rojo, en claro, es del 700: relleno, con borde y de solo texto', () => {
  render(Button, {
    props: { label: 'Dar de baja', severity: 'danger' },
    global: { plugins: [[PrimeVue, primeVueOptions]] },
  })

  const styles = [...document.querySelectorAll('style')].map((style) => style.textContent).join('\n')
  expect(styles).toMatch(/--p-button-danger-background:\s*var\(--p-red-700\)/)
  expect(styles).toMatch(/--p-button-outlined-danger-color:\s*var\(--p-red-700\)/)
  expect(styles).toMatch(/--p-button-text-danger-color:\s*var\(--p-red-700\)/)
})

// El botón gris, elegido en R6.18b: en claro, el 300 con el borde verde del principal; en oscuro, el gris de siempre
// con el borde verde de la paleta de oscuro. Como antes, se comprueba que los colores llegan a la página con el tema.
test('el botón gris, con su relleno y el borde verde en los dos modos', () => {
  render(Button, {
    props: { label: 'Sincronizar con la Federación', severity: 'secondary' },
    global: { plugins: [[PrimeVue, primeVueOptions]] },
  })

  const styles = [...document.querySelectorAll('style')].map((style) => style.textContent).join('\n')
  // Los dos modos, cada uno en su bloque: el claro con el 300 y el borde del 800; el oscuro, el gris de siempre (el 800)
  // con el borde del 500.
  expect(styles).toMatch(/--p-button-secondary-background:var\(--p-surface-300\)[^}]*--p-button-secondary-border-color:var\(--p-primary-800\)/)
  expect(styles).toMatch(/--p-button-secondary-background:var\(--p-surface-800\)[^}]*--p-button-secondary-border-color:var\(--p-primary-500\)/)
})


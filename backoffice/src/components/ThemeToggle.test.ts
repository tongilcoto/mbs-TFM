import { fireEvent, render, screen } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { afterEach, describe, expect, test } from 'vitest'
import { primeVueOptions } from '../theme/primevue'
import ThemeToggle from './ThemeToggle.vue'

function renderToggle() {
  render(ThemeToggle, { global: { plugins: [[PrimeVue, primeVueOptions]] } })
}

function isDark() {
  return document.documentElement.classList.contains('app-dark')
}

// Cada prueba empieza en modo claro y sin nada guardado.
afterEach(() => {
  document.documentElement.classList.remove('app-dark')
  localStorage.clear()
})

describe('el interruptor de modo', () => {
  test('en modo claro ofrece pasar a oscuro, y al pulsarlo cambia y lo recuerda', async () => {
    renderToggle()

    await fireEvent.click(screen.getByRole('button', { name: 'Cambiar a modo oscuro' }))

    expect(isDark()).toBe(true)
    expect(localStorage.getItem('tema')).toBe('oscuro')
    expect(screen.getByRole('button', { name: 'Cambiar a modo claro' })).toBeInTheDocument()
  })

  test('si la web abre en oscuro, ofrece pasar a claro, y al pulsarlo cambia y lo recuerda', async () => {
    document.documentElement.classList.add('app-dark')
    renderToggle()

    await fireEvent.click(screen.getByRole('button', { name: 'Cambiar a modo claro' }))

    expect(isDark()).toBe(false)
    expect(localStorage.getItem('tema')).toBe('claro')
    expect(screen.getByRole('button', { name: 'Cambiar a modo oscuro' })).toBeInTheDocument()
  })
})

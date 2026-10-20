import { render, screen } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { describe, expect, test } from 'vitest'
import { primeVueOptions } from '../theme/primevue'
import AppHeader from './AppHeader.vue'

function renderHeader(props: { shortName?: string; crestUrl?: string | null }) {
  return render(AppHeader, { props, global: { plugins: [[PrimeVue, primeVueOptions]] } })
}

describe('la cabecera', () => {
  test('enseña el escudo y el nombre corto del club, y el interruptor de modo', () => {
    const { container } = renderHeader({ shortName: 'Celtic Castilla', crestUrl: 'https://example.com/escudo.png' })

    expect(screen.getByRole('banner')).toHaveTextContent('Celtic Castilla')
    expect(container.querySelector('img')).toHaveAttribute('src', 'https://example.com/escudo.png')
    expect(screen.getByRole('button', { name: /Cambiar a modo/ })).toBeInTheDocument()
  })

  test('un club sin escudo sale solo con su nombre', () => {
    const { container } = renderHeader({ shortName: 'Celtic Castilla', crestUrl: null })

    expect(screen.getByRole('banner')).toHaveTextContent('Celtic Castilla')
    expect(container.querySelector('img')).toBeNull()
  })

  test('mientras llega el club, solo el interruptor', () => {
    renderHeader({})

    expect(screen.getByRole('banner')).toHaveTextContent(/^Cambiar a modo (claro|oscuro)$/)
  })
})

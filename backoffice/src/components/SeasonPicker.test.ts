import { render, screen } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { expect, test } from 'vitest'
import { primeVueOptions } from '../theme/primevue'
import SeasonPicker from './SeasonPicker.vue'

test('el selector se llama «Temporada» y enseña la elegida', () => {
  render(SeasonPicker, {
    props: { labels: ['2026/27', '2025/26'], modelValue: '2026/27' },
    global: { plugins: [[PrimeVue, primeVueOptions]] },
  })

  expect(screen.getByRole('combobox', { name: 'Temporada' })).toHaveTextContent('2026/27')
})

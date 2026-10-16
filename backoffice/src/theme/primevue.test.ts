import { render, screen } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
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

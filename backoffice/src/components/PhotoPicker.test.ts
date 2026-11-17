import { fireEvent, render, screen } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { describe, expect, test } from 'vitest'
import { primeVueOptions } from '../theme/primevue'
import PhotoPicker from './PhotoPicker.vue'

// Elegir una foto (plan R6): un botón con texto de la web, no el del navegador, que abre el selector de ficheros.

function renderPicker() {
  return render(PhotoPicker, {
    props: { inputId: 'foto', label: 'Elegir foto', accept: 'image/jpeg,image/png' },
    global: { plugins: [[PrimeVue, primeVueOptions]] },
  })
}

describe('elegir una foto', () => {
  test('un botón con su texto; el campo del fichero, escondido, solo acepta lo que se le dice', () => {
    renderPicker()

    expect(screen.getByRole('button', { name: 'Elegir foto' })).toBeInTheDocument()
    const input = document.getElementById('foto') as HTMLInputElement
    expect(input).toHaveAttribute('type', 'file')
    expect(input).toHaveAttribute('accept', 'image/jpeg,image/png')
    expect(input).toHaveAttribute('tabindex', '-1')
  })

  test('el botón abre el selector', async () => {
    renderPicker()
    const input = document.getElementById('foto') as HTMLInputElement
    let opened = false
    input.addEventListener('click', () => (opened = true))

    await fireEvent.click(screen.getByRole('button', { name: 'Elegir foto' }))

    expect(opened).toBe(true)
  })

  test('elegido un fichero, lo entrega, y el campo se vacía para poder elegir el mismo otra vez', async () => {
    const { emitted } = renderPicker()
    const input = document.getElementById('foto') as HTMLInputElement
    const file = new File(['x'], 'ana.png', { type: 'image/png' })

    await fireEvent.change(input, { target: { files: [file] } })

    expect(emitted().pick).toEqual([[file]])
    expect(input.value).toBe('')
  })
})

import { fireEvent, render, screen } from '@testing-library/vue'
import PrimeVue from 'primevue/config'
import { describe, expect, test } from 'vitest'
import { primeVueOptions } from '../theme/primevue'
import PhotoPicker from './PhotoPicker.vue'

// Elegir una foto (plan R6): un botón con texto de la web, no el del navegador, que abre el selector de ficheros.

function renderPicker(extra: { name?: string } = {}) {
  return render(PhotoPicker, {
    props: { inputId: 'foto', label: 'Elegir foto', accept: 'image/jpeg,image/png', ...extra },
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

  // Sin una etiqueta de fuera (la ficha del jugador), el campo no tendría nombre: axe lo pide (R6.18).
  test('con `name`, el campo del fichero se llama así; sin él, lo nombra la etiqueta de fuera', () => {
    renderPicker({ name: 'Foto' })

    expect(screen.getByLabelText('Foto')).toBe(document.getElementById('foto'))
  })

  test('sin `name`, el campo no lleva nombre propio', () => {
    renderPicker()

    expect(document.getElementById('foto')).not.toHaveAttribute('aria-label')
  })
})

import { fireEvent, render, screen } from '@testing-library/vue'
import { describe, expect, test } from 'vitest'
import { createMemoryHistory, createRouter } from 'vue-router'
import RowAction from './RowAction.vue'

function renderAction() {
  const router = createRouter({ history: createMemoryHistory(), routes: [{ path: '/:anything(.*)*', component: {} }] })
  render(RowAction, {
    props: { label: 'Sincronizar otra competición', subject: 'Cadete A', icon: 'link', to: '/equipos/1/federacion' },
    global: { plugins: [router] },
  })
  return screen.getByRole('link', { name: 'Sincronizar otra competición, Cadete A' })
}

// El texto a la vista. No se busca por rol: no lo tiene, porque el nombre del enlace ya lo dice.
const tip = () => screen.queryByText('Sincronizar otra competición')

describe('una acción de fila (LLD-B §3.7)', () => {
  test('el lector lee el nombre con el equipo, y el dibujo no', () => {
    const link = renderAction()

    expect(link).toHaveAttribute('href', '/equipos/1/federacion')
    expect(link.querySelector('svg')).toHaveAttribute('aria-hidden', 'true')
  })

  test('el texto no se ve hasta llegar', () => {
    renderAction()

    expect(tip()).not.toBeInTheDocument()
  })

  test('sale al pasar el ratón, y se va al quitarlo', async () => {
    const link = renderAction()

    await fireEvent.pointerEnter(link.parentElement!)
    expect(tip()).toBeInTheDocument()
    // Para que el lector no lo lea dos veces.
    expect(tip()!.closest('[aria-hidden]')).toHaveAttribute('aria-hidden', 'true')

    await fireEvent.pointerLeave(link.parentElement!)
    expect(tip()).not.toBeInTheDocument()
  })

  test('se queda mientras el ratón está encima del texto (WCAG 1.4.13)', async () => {
    const link = renderAction()
    const action = link.parentElement!

    await fireEvent.pointerEnter(action)
    // El texto está dentro de la acción: pasar del icono al texto no sale de ella.
    expect(action).toContainElement(tip())
  })

  test('sale al llegar con el teclado, y se va al salir', async () => {
    const link = renderAction()

    link.focus()
    await fireEvent.focus(link)
    expect(tip()).toBeInTheDocument()

    await fireEvent.blur(link)
    expect(tip()).not.toBeInTheDocument()
  })

  test('Escape lo esconde y el foco se queda; vuelve a salir al llegar otra vez', async () => {
    const link = renderAction()
    link.focus()
    await fireEvent.focus(link)

    await fireEvent.keyDown(link, { key: 'Escape' })
    expect(tip()).not.toBeInTheDocument()
    expect(link).toHaveFocus()

    await fireEvent.blur(link)
    await fireEvent.focus(link)
    expect(tip()).toBeInTheDocument()
  })

  test('Escape lo esconde también con el ratón encima y el foco en otro sitio', async () => {
    const link = renderAction()
    await fireEvent.pointerEnter(link.parentElement!)

    await fireEvent.keyDown(document.body, { key: 'Escape' })
    expect(tip()).not.toBeInTheDocument()

    await fireEvent.pointerLeave(link.parentElement!)
    await fireEvent.pointerEnter(link.parentElement!)
    expect(tip()).toBeInTheDocument()
  })

  test('otra tecla no lo esconde', async () => {
    const link = renderAction()
    await fireEvent.pointerEnter(link.parentElement!)

    await fireEvent.keyDown(document.body, { key: 'a' })
    expect(tip()).toBeInTheDocument()
  })
})

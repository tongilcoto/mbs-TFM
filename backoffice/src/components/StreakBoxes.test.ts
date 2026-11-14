import { fireEvent, render, screen } from '@testing-library/vue'
import { describe, expect, test } from 'vitest'
import { createMemoryHistory, createRouter } from 'vue-router'
import StreakBoxes from './StreakBoxes.vue'

const boxes = [
  { round: 7, outcome: 'victoria', label: 'Victoria en la jornada 7' },
  { round: 6, outcome: 'descanso', label: 'Descansó en la jornada 6' },
] as const

function renderStreak() {
  render(StreakBoxes, { props: { boxes: [...boxes] } })
  return screen.getAllByRole('listitem')
}

function renderLinked() {
  const router = createRouter({ history: createMemoryHistory(), routes: [{ path: '/:anything(.*)*', component: {} }] })
  render(StreakBoxes, {
    props: { boxes: [...boxes], to: (round: number) => `/temporadas/2026-27/competiciones/liga?jornada=${round}` },
    global: { plugins: [router] },
  })
}

describe('la racha en pantalla (plan R5, decisión 3)', () => {
  test('un cuadro por jornada, con su número a la vista y lo que oye el lector', () => {
    const [won, rest] = renderStreak()

    expect(won!.querySelector('[aria-hidden="true"]')).toHaveTextContent('7')
    expect(won).toHaveTextContent('Victoria en la jornada 7')
    expect(won).toHaveAttribute('title', 'Victoria en la jornada 7')
    expect(rest).toHaveTextContent('Descansó en la jornada 6')
  })

  test('cada cuadro con el color de su resultado; el descanso, vacío', () => {
    const [won, rest] = renderStreak()

    expect(won).toHaveClass('box', 'victoria')
    expect(rest).toHaveClass('box', 'descanso')
  })

  test('sin adónde llevar, ningún enlace', () => {
    renderStreak()

    expect(screen.queryAllByRole('link')).toEqual([])
  })
})

describe('la racha que lleva a cada jornada (plan R5, decisión 6)', () => {
  test('cada cuadro, un enlace a su jornada, que dice al lector lo que es', () => {
    renderLinked()

    expect(screen.getByRole('link', { name: 'Victoria en la jornada 7' })).toHaveAttribute('href', '/temporadas/2026-27/competiciones/liga?jornada=7')
    expect(screen.getByRole('link', { name: 'Descansó en la jornada 6' })).toHaveAttribute('href', '/temporadas/2026-27/competiciones/liga?jornada=6')
  })

  test('el texto sale al llegar con el teclado y al pasar el ratón, sin `title` que lo repita', async () => {
    renderLinked()
    const link = screen.getByRole('link', { name: 'Victoria en la jornada 7' })
    const tip = () => screen.queryByText('Victoria en la jornada 7', { selector: '.bubble' })

    expect(link.closest('li')).not.toHaveAttribute('title')
    expect(tip()).not.toBeInTheDocument()

    await fireEvent.focus(link)
    expect(tip()).toBeInTheDocument()
    await fireEvent.blur(link)
    expect(tip()).not.toBeInTheDocument()

    await fireEvent.pointerEnter(link.parentElement!)
    expect(tip()).toBeInTheDocument()
  })
})

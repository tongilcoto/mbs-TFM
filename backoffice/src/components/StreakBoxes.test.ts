import { render, screen } from '@testing-library/vue'
import { describe, expect, test } from 'vitest'
import StreakBoxes from './StreakBoxes.vue'

function renderStreak() {
  render(StreakBoxes, {
    props: {
      boxes: [
        { round: 7, outcome: 'victoria', label: 'Victoria en la jornada 7' },
        { round: 6, outcome: 'descanso', label: 'Descansó en la jornada 6' },
      ],
    },
  })
  return screen.getAllByRole('listitem')
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
})

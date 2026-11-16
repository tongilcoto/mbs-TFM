import { fireEvent, render, screen } from '@testing-library/vue'
import { describe, expect, test } from 'vitest'
import PlayerPhoto from './PlayerPhoto.vue'

// La foto de un jugador, o sus iniciales (plan R6, §3): en la plantilla y en la ficha.

describe('la foto de un jugador', () => {
  test('con foto, la imagen, que dice al lector el nombre del jugador', () => {
    render(PlayerPhoto, { props: { url: '/api/v1/player-photos/abc.jpg', name: 'Marcos Díaz', initials: 'MD' } })

    expect(screen.getByRole('img', { name: 'Marcos Díaz' })).toHaveAttribute('src', '/api/v1/player-photos/abc.jpg')
    expect(screen.queryByText('MD')).not.toBeInTheDocument()
  })

  test('sin foto, las iniciales, que el lector no lee: el nombre ya está al lado', () => {
    render(PlayerPhoto, { props: { name: 'Marcos Díaz', initials: 'MD' } })

    expect(screen.queryByRole('img')).not.toBeInTheDocument()
    expect(screen.getByText('MD')).toHaveAttribute('aria-hidden', 'true')
  })

  test('si la foto no carga (el enlace caducó, D-117), las iniciales', async () => {
    render(PlayerPhoto, { props: { url: '/api/v1/player-photos/abc.jpg', name: 'Marcos Díaz', initials: 'MD' } })

    await fireEvent.error(screen.getByRole('img'))

    expect(screen.queryByRole('img')).not.toBeInTheDocument()
    expect(screen.getByText('MD')).toBeInTheDocument()
  })

  test('con otra foto, se vuelve a intentar', async () => {
    const { rerender } = render(PlayerPhoto, { props: { url: '/vieja.jpg', name: 'Marcos Díaz', initials: 'MD' } })
    await fireEvent.error(screen.getByRole('img'))

    await rerender({ url: '/nueva.jpg', name: 'Marcos Díaz', initials: 'MD' })

    expect(screen.getByRole('img', { name: 'Marcos Díaz' })).toHaveAttribute('src', '/nueva.jpg')
  })
})

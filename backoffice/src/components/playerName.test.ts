import { describe, expect, test } from 'vitest'
import { initialsOf, shownName } from './playerName'

// El nombre del jugador llega en mayúsculas (D-120) y la web lo enseña como «Nombre Apellidos» (plan R6, decisión 9).

describe('el nombre como «Nombre Apellidos»', () => {
  test('cada palabra con su primera letra en mayúscula y el resto en minúscula', () => {
    expect(shownName('MARCOS DÍAZ')).toBe('Marcos Díaz')
  })

  test('las tildes, la eñe y la diéresis se conservan', () => {
    expect(shownName('ÍÑIGO MUÑOZ ARGÜELLES')).toBe('Íñigo Muñoz Argüelles')
  })

  test('«de», «del», «la», «las», «los» e «y», en minúscula', () => {
    expect(shownName('JUAN CARLOS GARCÍA DE LA FUENTE')).toBe('Juan Carlos García de la Fuente')
    expect(shownName('PEDRO SÁNCHEZ DEL RÍO')).toBe('Pedro Sánchez del Río')
    expect(shownName('LUIS DE LAS HERAS Y LOS SANTOS')).toBe('Luis de las Heras y los Santos')
  })

  test('al principio, la partícula va en mayúscula', () => {
    expect(shownName('DE LA CRUZ PÉREZ')).toBe('De la Cruz Pérez')
  })

  test('tras un guion, mayúscula', () => {
    expect(shownName('ANA PÉREZ-REVERTE')).toBe('Ana Pérez-Reverte')
  })

  test('una partícula pegada a un guion no es partícula: es parte del apellido', () => {
    expect(shownName('ANA DE-LA-TORRE')).toBe('Ana De-La-Torre')
  })

  test('tras un apóstrofo, minúscula: «McDonald» sale «Mcdonald», y se asume (decisión 9)', () => {
    expect(shownName("PEDRO O'NEILL")).toBe("Pedro O'neill")
  })
})

describe('las iniciales, en el sitio de la foto', () => {
  test('las de las dos primeras palabras', () => {
    expect(initialsOf('MARCOS DÍAZ')).toBe('MD')
    expect(initialsOf('JUAN CARLOS GARCÍA')).toBe('JC')
  })

  test('sin las partículas', () => {
    expect(initialsOf('DE LA CRUZ PÉREZ')).toBe('CP')
  })

  test('con tilde y eñe, en mayúscula', () => {
    expect(initialsOf('ÍÑIGO ÑÚÑEZ')).toBe('ÍÑ')
  })
})

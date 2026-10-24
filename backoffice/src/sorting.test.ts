import { describe, expect, test } from 'vitest'
import { nextOrder, orderFromAddress, orderToAddress, sortRows, type SortRule } from './sorting'

interface Row {
  name: string
  value?: number
}

// Por el número; sin número, es una fila vacía.
const byValue: SortRule<Row> = {
  compare: (a, b) => a.value! - b.value!,
  isEmpty: (row) => row.value === undefined,
}

const rows: Row[] = [{ name: 'b', value: 2 }, { name: 'vacía' }, { name: 'a', value: 1 }, { name: 'c', value: 3 }]
const names = (sorted: Row[]) => sorted.map((row) => row.name)

describe('ordenar con una regla', () => {
  test('en el orden de la regla, y las vacías al final', () => {
    expect(names(sortRows(rows, byValue, false))).toEqual(['a', 'b', 'c', 'vacía'])
  })

  test('al revés, y las vacías siguen al final', () => {
    expect(names(sortRows(rows, byValue, true))).toEqual(['c', 'b', 'a', 'vacía'])
  })

  test('los empates conservan el orden en que venían, en los dos sentidos', () => {
    const tied: Row[] = [{ name: 'primero', value: 1 }, { name: 'segundo', value: 1 }, { name: 'cero', value: 0 }]

    expect(names(sortRows(tied, byValue, false))).toEqual(['cero', 'primero', 'segundo'])
    expect(names(sortRows(tied, byValue, true))).toEqual(['primero', 'segundo', 'cero'])
  })

  test('no toca la lista que recibe', () => {
    const copy = [...rows]
    sortRows(rows, byValue, false)

    expect(rows).toEqual(copy)
  })
})

describe('los tres clics', () => {
  test('el primero ordena por esa columna; el segundo, al revés; el tercero vuelve al orden de siempre', () => {
    const first = nextOrder(undefined, 'ingesta')
    const second = nextOrder(first, 'ingesta')
    const third = nextOrder(second, 'ingesta')

    expect(first).toEqual({ column: 'ingesta', reversed: false })
    expect(second).toEqual({ column: 'ingesta', reversed: true })
    expect(third).toBeUndefined()
  })

  test('pinchar en otra columna empieza en ella, en su orden', () => {
    expect(nextOrder({ column: 'ingesta', reversed: true }, 'equipo')).toEqual({ column: 'equipo', reversed: false })
  })
})

describe('el orden en la dirección', () => {
  const columns = ['equipo', 'ingesta'] as const

  test('«ingesta» es en su orden, e «ingesta-inverso», al revés', () => {
    expect(orderToAddress({ column: 'ingesta', reversed: false })).toBe('ingesta')
    expect(orderToAddress({ column: 'ingesta', reversed: true })).toBe('ingesta-inverso')
    expect(orderToAddress(undefined)).toBeUndefined()
  })

  test('se lee lo que se escribe', () => {
    expect(orderFromAddress('ingesta', columns)).toEqual({ column: 'ingesta', reversed: false })
    expect(orderFromAddress('ingesta-inverso', columns)).toEqual({ column: 'ingesta', reversed: true })
  })

  test.each([['otra'], ['otra-inverso'], ['-inverso'], [''], [undefined], [['ingesta']]])(
    'lo que no se entiende (%j) es el orden de siempre, sin error',
    (value) => {
      expect(orderFromAddress(value, columns)).toBeUndefined()
    },
  )
})

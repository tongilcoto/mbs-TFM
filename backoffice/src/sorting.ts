// La forma de ordenar las tablas (bloque T del plan R2), para cualquier tabla de la web. Cada tabla pone sus
// columnas y sus reglas; esto pone lo que es igual en todas: ordenar, los tres clics y el orden en la dirección.

// Cómo se ordena por una columna. `compare`, como el de `Array.sort`, en el orden de la columna (el del primer
// clic). `isEmpty`, las filas que no tienen nada en esa columna: van siempre al final, en los dos sentidos.
export interface SortRule<T> {
  compare(a: T, b: T): number
  isEmpty?(row: T): boolean
}

// Por qué columna se ordena, y si al revés. Sin orden (`undefined`), el de siempre: el del servidor.
export interface Order<C extends string> {
  column: C
  reversed: boolean
}

// Las filas ordenadas, en una lista nueva. Los empates conservan el orden en que venían.
export function sortRows<T>(rows: T[], rule: SortRule<T>, reversed: boolean): T[] {
  const isEmpty = rule.isEmpty ?? (() => false)
  const filled = rows.filter((row) => !isEmpty(row))
  const empty = rows.filter(isEmpty)
  const sign = reversed ? -1 : 1
  return [...filled.sort((a, b) => sign * rule.compare(a, b)), ...empty]
}

// Pinchar en una columna: la primera vez, en su orden; la segunda, al revés; la tercera, el de siempre.
export function nextOrder<C extends string>(current: Order<C> | undefined, column: C): Order<C> | undefined {
  if (current?.column !== column) return { column, reversed: false }
  return current.reversed ? undefined : { column, reversed: true }
}

// En la dirección (LLD-B §2.2): `?orden=ingesta`, y al revés, `?orden=ingesta-inverso`.
const REVERSED = '-inverso'

export function orderToAddress(order: Order<string> | undefined): string | undefined {
  if (order === undefined) return undefined
  return order.reversed ? `${order.column}${REVERSED}` : order.column
}

// Lo que no se entiende es el orden de siempre, sin error: no es un dato que el usuario busque.
export function orderFromAddress<C extends string>(value: unknown, columns: readonly C[]): Order<C> | undefined {
  if (typeof value !== 'string') return undefined
  const reversed = value.endsWith(REVERSED)
  const column = reversed ? value.slice(0, -REVERSED.length) : value
  return columns.includes(column as C) ? { column: column as C, reversed } : undefined
}

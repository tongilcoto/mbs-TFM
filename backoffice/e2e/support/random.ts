// El azar de los escenarios (la skill de escenarios, principio 9): los datos que no deciden una rama se eligen al
// azar, para que cada pasada pruebe con otros y salga lo que con los mismos de siempre no saldría nunca.
//
// Al azar, pero repetible. Cada pasada tiene su semilla, que se escribe al empezar; con `SEMILLA=…` se repite
// con los mismos datos. Cada escenario saca la suya de la semilla y de su nombre, así que también se repite
// lanzándolo solo.

/** La semilla de la pasada: la de `SEMILLA`, o una nueva. */
export const runSeed = process.env.SEMILLA ?? String(Math.floor(Math.random() * 1_000_000))

/** Un número de 32 bits a partir de un texto (el FNV-1a de siempre). */
function hash(text: string): number {
  let h = 0x811c9dc5
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i)
    h = Math.imul(h, 0x01000193)
  }
  return h >>> 0
}

export interface Random {
  /** Un entero entre `min` y `max`, los dos incluidos. */
  int(min: number, max: number): number
  /** Uno de la lista. */
  pick<T>(items: readonly T[]): T
  /** `true` una vez de cada `1 / probability`. */
  chance(probability: number): boolean
}

/** El azar de un escenario: siempre el mismo para la misma semilla y el mismo escenario. */
export function randomFor(scenario: string, seed = runSeed): Random {
  // mulberry32: corto, rápido y suficiente para elegir datos.
  let state = hash(`${seed}|${scenario}`)
  const next = () => {
    state = (state + 0x6d2b79f5) >>> 0
    let t = state
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
  return {
    int: (min, max) => min + Math.floor(next() * (max - min + 1)),
    pick: (items) => items[Math.floor(next() * items.length)]!,
    chance: (probability) => next() < probability,
  }
}

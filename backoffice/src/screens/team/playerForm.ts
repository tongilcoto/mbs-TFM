// Lo que la web comprueba antes de enviar el alta o la corrección de un jugador (plan R6, decisión 9: «el servidor,
// y la web avisa antes de enviar»). Son las reglas del servidor (PlayerName, BirthYear y ShirtNumber del dominio),
// con los textos de los escenarios. El servidor las vuelve a mirar: si un día no cuadran, su 422 sale junto al campo.

const NAME_MAX = 120
const EARLIEST_YEAR = 1900

// Fuera los espacios de los lados y uno solo entre palabras; y la tilde en dos piezas, en una (como el servidor:
// si no, «JOSÉ» serían dos nombres).
export function cleanName(raw: string): string {
  return raw.normalize('NFC').trim().split(/\s+/).filter(Boolean).join(' ')
}

// Letras de cualquier alfabeto, el espacio, el guion y el apóstrofo, recto o curvo.
const allowed = /^[\p{L} '’-]*$/u
const hasLetter = /\p{L}/u

export function nameProblem(raw: string): string | undefined {
  const name = cleanName(raw)
  if (name === '') return 'Escribe el nombre y al menos un apellido'
  // Contado por letras como se ven, no por piezas de memoria: «é» es una.
  if ([...name].length > NAME_MAX) return `Como mucho, ${NAME_MAX} letras`
  if (!allowed.test(name)) return 'Solo letras, espacios, guion y apóstrofo'
  const words = name.split(' ')
  if (!words.every((word) => hasLetter.test(word))) return 'Cada palabra tiene que llevar letras'
  if (words.length < 2) return 'Escribe el nombre y al menos un apellido'
  return undefined
}

// Obligatorio en el alta de un jugador nuevo; de 1900 al año en curso.
export function yearProblem(raw: string, thisYear: number): string | undefined {
  const text = raw.trim()
  if (text === '') return 'Falta el año de nacimiento'
  const year = /^\d+$/.test(text) ? Number(text) : NaN
  if (!(year >= EARLIEST_YEAR && year <= thisYear)) return `Un año entre ${EARLIEST_YEAR} y ${thisYear}`
  return undefined
}

// Opcional; si lo hay, del 1 al 99.
export function shirtProblem(raw: string): string | undefined {
  const text = raw.trim()
  if (text === '') return undefined
  const number = /^\d+$/.test(text) ? Number(text) : NaN
  return number >= 1 && number <= 99 ? undefined : 'Del 1 al 99'
}

// El dorsal que se envía: vacío, ninguno. Solo se llama con uno que ha pasado `shirtProblem`.
export function shirtNumberOf(raw: string): number | null {
  const text = raw.trim()
  return text === '' ? null : Number(text)
}

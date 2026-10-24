// Los nombres en español de los valores que manda el servidor. Ninguna pantalla los escribe por su cuenta, y
// tampoco este fichero: salen del catálogo, de la tabla `x-enum-names` de cada lista (D-108). Que no falte ni
// sobre ninguno lo comprueba `npm run gen:api` al fabricar `schemas.json`.
import catalog from '../api/schemas.json'
import type { components } from '../api/schema'

export type TeamCategory = components['schemas']['TeamCategory']
export type Gender = components['schemas']['Gender']
export type Modality = components['schemas']['Modality']
export type IngestionHealth = components['schemas']['IngestionHealth']

type Schemas = typeof catalog.components.schemas

// Las listas del catálogo que llevan nombres: todas menos ProblemCode.
export type NamedList = {
  [K in keyof Schemas]: Schemas[K] extends { 'x-enum-names': object } ? K : never
}[keyof Schemas]

// Los valores de una lista, con el tipo del catálogo: pedir el nombre de uno que no existe no compila.
type ValueOf<L extends NamedList> = components['schemas'][L & keyof components['schemas']]

interface ListSchema {
  enum: string[]
  'x-enum-names': Record<string, string>
}

function listSchema(list: NamedList): ListSchema {
  return catalog.components.schemas[list] as unknown as ListSchema
}

// A cada valor de la lista, su nombre: `namesOf('TeamCategory').alevin` es «Alevín».
export function namesOf<L extends NamedList>(list: L): Record<ValueOf<L>, string> {
  const schema = listSchema(list)
  return Object.fromEntries(schema.enum.map((value) => [value, schema['x-enum-names'][value]])) as Record<
    ValueOf<L>,
    string
  >
}

// Las opciones de un selector, en el orden del catálogo (las categorías, de menor a mayor edad).
export function optionsOf<L extends NamedList>(list: L): { value: ValueOf<L>; label: string }[] {
  const schema = listSchema(list)
  return schema.enum.map((value) => ({ value: value as ValueOf<L>, label: schema['x-enum-names'][value]! }))
}

export const categoryNames = namesOf('TeamCategory')

// Cómo va la ingesta de una competición (plan R1, decisión 2).
export const healthNames = namesOf('IngestionHealth')

// Un equipo por su categoría y su letra: «Cadete B», o «Cadete» si no tiene letra.
export function teamName(category: TeamCategory, letter?: string | null): string {
  return letter ? `${categoryNames[category]} ${letter}` : categoryNames[category]
}

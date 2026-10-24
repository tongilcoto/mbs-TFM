import Ajv2020, { type ErrorObject } from 'ajv/dist/2020'
import addFormats from 'ajv-formats'
import catalog from './schemas.json'
import type { components } from './schema'

// Las reglas de los formularios salen del catálogo (LLD-B §5.1, DW-07): Ajv lee la descripción de cada dato tal
// cual. `schemas.json` lo fabrica `npm run gen:api` del mismo catálogo que los tipos (Plan R2, decisión 3).
export type SchemaName = keyof components['schemas']

// Lo que falla de un formulario: a cada campo, su mensaje. Los que no salen están bien.
export type FieldErrors<T> = Partial<Record<keyof T & string, string>>

// En modo estricto, para que una regla mal escrita en el catálogo salte en vez de ignorarse. Solo se le declaran
// las palabras de OpenAPI que no son de JSON Schema: `components`, el cajón donde el catálogo guarda los esquemas.
const ajv = new Ajv2020({ strict: true, allErrors: true, verbose: true })
addFormats(ajv)
ajv.addKeyword('components')
ajv.addSchema(catalog, 'catalog')

// El texto de cada tipo de regla, no de cada campo (LLD-B §5.1). El resto de tipos no los puede provocar un
// formulario con la pieza que corresponde a cada dato (§5.2), y salen con el genérico.
const ruleMessages: Partial<Record<string, (rule: ErrorObject) => string>> = {
  required: () => 'Este campo es obligatorio',
  minLength: (rule) => (rule.params.limit === 1 ? 'No puede estar vacío' : `Como mínimo ${rule.params.limit} caracteres`),
  maxLength: (rule) => `Como máximo ${rule.params.limit} caracteres`,
  minimum: (rule) => `Como mínimo ${rule.params.limit}`,
  maximum: (rule) => `Como máximo ${rule.params.limit}`,
  pattern: (rule) => withExample('El formato no es válido', rule),
  format: (rule) => withExample('El formato no es válido', rule),
  enum: () => 'Elige un valor de la lista',
}

// Comprueba lo rellenado contra un esquema del catálogo y devuelve todos los campos que fallan a la vez, cada
// uno con su primer fallo. Un campo sin rellenar se pasa como `undefined`, no como `null`: así sale como
// «obligatorio» si lo es, y `null` queda para los campos que lo admiten (la letra del equipo).
export function checkForm<N extends SchemaName>(
  name: N,
  form: Partial<components['schemas'][N]>,
): FieldErrors<components['schemas'][N]> {
  const check = ajv.getSchema(`catalog#/components/schemas/${name}`)
  if (check === undefined) throw new Error(`El catálogo no tiene el esquema ${name}`)
  if (check(form)) return {}

  const errors: Record<string, string> = {}
  for (const rule of check.errors ?? []) {
    const field = fieldOf(rule)
    errors[field] ??= ruleMessages[rule.keyword]?.(rule) ?? 'El valor no es válido'
  }
  return errors as FieldErrors<components['schemas'][N]>
}

// El campo de un fallo: el que falta, si es un `required`, o el del valor que no cumple (`/letter` → `letter`).
function fieldOf(rule: ErrorObject): string {
  const path = rule.instancePath.slice(1).replaceAll('/', '.')
  if (rule.keyword !== 'required') return path
  const missing = String(rule.params.missingProperty)
  return path === '' ? missing : `${path}.${missing}`
}

// Si el dato trae un ejemplo en el catálogo (`examples`), el mensaje lo enseña: «… Por ejemplo: 2024/25».
function withExample(message: string, rule: ErrorObject): string {
  const examples: unknown = rule.parentSchema?.examples
  const example = Array.isArray(examples) ? examples[0] : undefined
  return typeof example === 'string' ? `${message}. Por ejemplo: ${example}` : message
}

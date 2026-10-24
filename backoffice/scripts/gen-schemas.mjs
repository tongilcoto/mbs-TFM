// Saca del catálogo solo sus esquemas, a src/api/schemas.json, para que Ajv compruebe los formularios con las
// mismas reglas con las que se fabricaron los tipos (Plan R2, decisión 3; DW-07). Lo lanza `npm run gen:api`.
//
// Se guarda con la estructura del catálogo, { components: { schemas } }, para que cada `$ref`
// ('#/components/schemas/SeasonLabel') siga apuntando al mismo sitio. No se toca a mano ni se guarda en git.
import { readFileSync, writeFileSync } from 'node:fs'
import { parse } from 'yaml'

const [catalogPath, outPath] = process.argv.slice(2)
const catalog = parse(readFileSync(catalogPath, 'utf8'))
const schemas = catalog.components.schemas

// Cada lista cerrada lleva el nombre de cada valor en `x-enum-names` (D-108), menos ProblemCode, cuyos mensajes
// escribe la web (errors.ts). Si falta uno o sobra uno, se para aquí, antes de fabricar nada.
const problems = []
for (const [name, schema] of Object.entries(schemas)) {
  if (!Array.isArray(schema.enum) || name === 'ProblemCode') continue
  const names = schema['x-enum-names']
  if (names === undefined) {
    problems.push(`${name}: le falta x-enum-names`)
    continue
  }
  const missing = schema.enum.filter((value) => typeof names[value] !== 'string' || names[value].trim() === '')
  const extra = Object.keys(names).filter((value) => !schema.enum.includes(value))
  if (missing.length > 0) problems.push(`${name}: sin nombre para ${missing.join(', ')}`)
  if (extra.length > 0) problems.push(`${name}: nombres de valores que la lista no tiene: ${extra.join(', ')}`)
}
if (problems.length > 0) {
  console.error(`Los nombres de las listas del catálogo no cuadran (D-108):\n  ${problems.join('\n  ')}`)
  process.exit(1)
}

writeFileSync(outPath, JSON.stringify({ components: { schemas } }, null, 2) + '\n')

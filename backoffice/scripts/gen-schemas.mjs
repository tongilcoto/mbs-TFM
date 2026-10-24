// Saca del catálogo solo sus esquemas, a src/api/schemas.json, para que Ajv compruebe los formularios con las
// mismas reglas con las que se fabricaron los tipos (Plan R2, decisión 3; DW-07). Lo lanza `npm run gen:api`.
//
// Se guarda con la estructura del catálogo, { components: { schemas } }, para que cada `$ref`
// ('#/components/schemas/SeasonLabel') siga apuntando al mismo sitio. No se toca a mano ni se guarda en git.
import { readFileSync, writeFileSync } from 'node:fs'
import { parse } from 'yaml'

const [catalogPath, outPath] = process.argv.slice(2)
const catalog = parse(readFileSync(catalogPath, 'utf8'))

writeFileSync(outPath, JSON.stringify({ components: { schemas: catalog.components.schemas } }, null, 2) + '\n')

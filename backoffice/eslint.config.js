// El revisor de código (ESLint). Las dos reglas que importan están al final:
// la frontera entre piezas y conexión (DW-01) y la accesibilidad (ADR-B, decisión 6).
import js from '@eslint/js'
import pluginVue from 'eslint-plugin-vue'
import vueA11y from 'eslint-plugin-vuejs-accessibility'
import globals from 'globals'
import tseslint from 'typescript-eslint'

export default tseslint.config(
  { ignores: ['dist/', 'src/api/schema.d.ts'] },

  js.configs.recommended,
  ...tseslint.configs.recommended,
  ...pluginVue.configs['flat/recommended'],
  {
    files: ['**/*.vue'],
    languageOptions: { parserOptions: { parser: tseslint.parser } },
  },
  {
    languageOptions: { globals: { ...globals.browser } },
  },

  // La accesibilidad, mientras se escribe: imagen sin texto alternativo, botón sin nombre,
  // campo sin etiqueta… dan error.
  ...vueA11y.configs['flat/recommended'],

  // Las piezas solo pintan: no pueden hablar con el servidor (LLD-B §1.2, DW-01).
  {
    files: ['src/components/**'],
    rules: {
      'no-restricted-imports': [
        'error',
        {
          patterns: [
            {
              group: ['**/api', '**/api/**'],
              message: 'Una pieza de components/ no puede usar api/: los datos se los pasa la pantalla (DW-01).',
            },
          ],
        },
      ],
    },
  },
)

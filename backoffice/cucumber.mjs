// La configuración de los escenarios (Cucumber). Se lanzan con `npm run e2e`.
export default {
  paths: ['e2e/features/**/*.feature'],
  import: ['e2e/support/**/*.ts', 'e2e/steps/**/*.ts'],
  format: ['progress-bar', 'summary'],
  // Un escenario que no pudo ejecutar un paso falla, no se da por bueno.
  strict: true,
}

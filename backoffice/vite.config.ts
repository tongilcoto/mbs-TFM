import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vitest/config'

// https://vite.dev/config/
export default defineConfig({
  plugins: [vue()],
  test: {
    // Las piezas se montan en un navegador de mentira (jsdom), sin abrir uno de verdad.
    environment: 'jsdom',
    include: ['src/**/*.test.ts'],
    setupFiles: ['src/test-setup.ts'],
    // Hasta R0.4 no hay ninguna prueba; sin esto, `npm test` falla por no encontrar ninguna.
    // Se quita en R0.4, con las primeras pruebas de verdad.
    passWithNoTests: true,
  },
})

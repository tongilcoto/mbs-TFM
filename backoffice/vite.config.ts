import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vitest/config'

// https://vite.dev/config/
export default defineConfig({
  plugins: [vue()],
  server: {
    proxy: {
      // El recepcionista (LLD-B §1.3): lo que empiece por /api, al servidor, quitándole el /api.
      // changeOrigin: false → el nombre de la dirección (el club) pasa intacto.
      // BACKOFFICE_API_URL solo la ponen los escenarios, para hablar con el servidor de pruebas (8081).
      '/api': {
        target: process.env.BACKOFFICE_API_URL ?? 'http://localhost:8080',
        changeOrigin: false,
        rewrite: (path) => path.replace(/^\/api/, ''),
      },
    },
  },
  test: {
    // Las piezas se montan en un navegador de mentira (jsdom), sin abrir uno de verdad.
    environment: 'jsdom',
    include: ['src/**/*.test.ts'],
    setupFiles: ['src/test-setup.ts'],
  },
})

import vue from '@vitejs/plugin-vue'
import { loadEnv } from 'vite'
import { defineConfig } from 'vitest/config'

// Adónde manda el recepcionista las peticiones, por orden:
// 1. BACKOFFICE_API_URL, que solo ponen los escenarios, para hablar con el servidor de pruebas (8081).
// 2. El API_PORT de backend/.env.development, el mismo fichero que lee el servidor al arrancar: así la web
//    y el servidor están siempre de acuerdo. Ese fichero es de cada Mac y git no lo guarda.
// 3. El 8080, el puerto por defecto del servidor.
function apiTarget(mode: string): string {
  if (process.env.BACKOFFICE_API_URL) return process.env.BACKOFFICE_API_URL
  const port = loadEnv(mode, '../backend', 'API_PORT').API_PORT ?? '8080'
  return `http://127.0.0.1:${port}`
}

// https://vite.dev/config/
export default defineConfig(({ mode }) => ({
  plugins: [vue()],
  server: {
    proxy: {
      // El recepcionista (LLD-B §1.3): lo que empiece por /api, al servidor, quitándole el /api.
      // changeOrigin: false → el nombre de la dirección (el club) pasa intacto.
      '/api': {
        target: apiTarget(mode),
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
}))

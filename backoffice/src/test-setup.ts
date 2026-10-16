// Se ejecuta antes de cada fichero de pruebas de piezas.
import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/vue'
import { afterEach } from 'vitest'

// Cada prueba empieza con la página vacía.
afterEach(() => cleanup())

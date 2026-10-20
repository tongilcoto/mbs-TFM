// El modo claro u oscuro (LLD-B §9.3). Al abrir, lo pone index.html antes de pintar nada; aquí se lee y se cambia.

export type Mode = 'claro' | 'oscuro'

// La clase de <html> que activa el modo oscuro. index.html y el arnés de los escenarios la escriben tal cual.
export const DARK_MODE_CLASS = 'app-dark'

// Lo único que la web guarda en el navegador (LLD-B §2.3): `tema = claro | oscuro`.
const SAVED_MODE_KEY = 'tema'

export function currentMode(): Mode {
  return document.documentElement.classList.contains(DARK_MODE_CLASS) ? 'oscuro' : 'claro'
}

// Cambia el modo en el momento y lo recuerda: desde ahora manda esta elección, no la del sistema.
export function setMode(mode: Mode): void {
  document.documentElement.classList.toggle(DARK_MODE_CLASS, mode === 'oscuro')
  try {
    localStorage.setItem(SAVED_MODE_KEY, mode)
  } catch {
    // El navegador no deja guardar (una ventana privada, por ejemplo): el modo cambia igual, y no se recuerda.
  }
}

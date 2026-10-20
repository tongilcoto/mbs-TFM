// La accesibilidad al final de cada escenario (ADR-B, decisión 6; LLD-B §9.4): axe mira la pantalla tal como
// la dejó el escenario, una vez en modo claro y otra en oscuro, porque un color que se lee bien en un modo
// puede no leerse en el otro. Objetivo: WCAG 2.2, nivel AA.
import AxeBuilder from '@axe-core/playwright'
import type { Page } from 'playwright'

const wcagAA = ['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa', 'wcag22aa']
const modes = [
  { name: 'claro', dark: false },
  { name: 'oscuro', dark: true },
]

/** Devuelve los fallos de accesibilidad de la página en los dos modos, ya escritos para leerlos. */
export async function accessibilityProblems(page: Page): Promise<string[]> {
  const problems: string[] = []
  const wasDark = await isDark(page)
  // Sin animaciones mientras se mide: las piezas de PrimeVue tardan 0,2 s en pasar al color del otro modo, y axe
  // mediría el color de en medio, que no es ninguno de los dos.
  const noTransitions = await page.addStyleTag({ content: '*, *::before, *::after { transition: none !important; }' })
  for (const mode of modes) {
    // El modo se cambia con la clase de <html>, como hace la web (LLD-B §9.3), sin recargar: así se
    // analiza la pantalla en el estado exacto en que la dejó el escenario.
    await page.evaluate((dark) => document.documentElement.classList.toggle('app-dark', dark), mode.dark)
    const result = await new AxeBuilder({ page }).withTags(wcagAA).analyze()
    for (const violation of result.violations) {
      const where = violation.nodes.map((node) => `      ${node.target.join(' ')}`).join('\n')
      problems.push(`[modo ${mode.name}] ${violation.id}: ${violation.help}\n${where}`)
    }
  }
  await page.evaluate((dark) => document.documentElement.classList.toggle('app-dark', dark), wasDark)
  await noTransitions.evaluate((style) => style.parentNode?.removeChild(style))
  return problems
}

function isDark(page: Page): Promise<boolean> {
  return page.evaluate(() => document.documentElement.classList.contains('app-dark'))
}

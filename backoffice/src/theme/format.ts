// Todo lo que se enseña con un formato fijo sale de aquí; ninguna pantalla formatea por su cuenta (LLD-B §9.6).
// De momento, la fecha y la hora de un instante (plan R1, §3.2). La fecha sin hora de los partidos llega en la
// rebanada 4.

// Un instante, como lo manda el servidor (en UTC: `2026-10-17T21:40:00Z`), con su fecha y su hora en la zona
// de quien mira: `17/10/2026 23:40` en Madrid, `17/10/2026 22:40` en Canarias. Hora de 24 horas.
// `timeZone` es para las pruebas: sin él, la del navegador.
export function formatInstant(instant: string, timeZone?: string): string {
  const parts = new Intl.DateTimeFormat('es-ES', {
    timeZone,
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(new Date(instant))
  const part = (type: Intl.DateTimeFormatPartTypes) => parts.find((p) => p.type === type)?.value

  // Se monta a mano, y no con el texto que da Intl, porque Intl pone una coma entre la fecha y la hora.
  return `${part('day')}/${part('month')}/${part('year')} ${part('hour')}:${part('minute')}`
}

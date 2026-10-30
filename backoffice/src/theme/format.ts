// Todo lo que se enseña con un formato fijo sale de aquí; ninguna pantalla formatea por su cuenta (LLD-B §9.6).
// La fecha y la hora de un instante (plan R1, §3.2); y el día y la hora de un partido (plan R4, §3.3).

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

const weekdays = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb']
const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic']

// El día de un partido, como lo manda el servidor (`2026-03-01`): «Dom 1 mar» (plan R4, §3.3). Se lee del texto y
// el día de la semana se calcula sin pasar por la zona horaria de quien mira, que en otra zona daría el día anterior
// (LLD-B §9.7).
export function formatMatchDay(date: string): string {
  const [year, month, day] = date.split('-').map(Number) as [number, number, number]
  const weekday = new Date(Date.UTC(year, month - 1, day)).getUTCDay()
  return `${weekdays[weekday]} ${day} ${months[month - 1]}`
}

// La hora de un partido, de 24 horas y sin segundos: «12:00», aunque llegue «12:00:00».
export function formatKickoff(time: string): string {
  return time.slice(0, 5)
}

// Una diferencia de goles, con su signo: «+3», «−2» (el signo menos de verdad, no el guion), «0».
export function formatGoalDifference(difference: number): string {
  if (difference > 0) return `+${difference}`
  if (difference < 0) return `−${-difference}`
  return '0'
}

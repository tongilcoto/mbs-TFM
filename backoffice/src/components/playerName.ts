// El nombre de un jugador como se enseña (plan R6, decisión 9). El servidor lo guarda en mayúsculas (D-120) y la web
// lo pinta como «Nombre Apellidos»: en la plantilla, en la ficha y en el diálogo de corregir. El CSS no basta:
// `text-transform: capitalize` no baja el resto de la palabra.

// Las palabras que van en minúscula salvo al principio: «García de la Fuente».
const particles = new Set(['de', 'del', 'la', 'las', 'los', 'y'])

// La primera letra en mayúscula, y lo demás como venga.
function capitalized(word: string): string {
  return word.charAt(0).toLocaleUpperCase('es-ES') + word.slice(1)
}

// Todo a minúsculas; mayúscula la primera letra de cada palabra y tras un guion; y las partículas, en minúscula
// salvo al principio. Una partícula unida por guion es parte del apellido («De-La-Torre»).
export function shownName(fullName: string): string {
  return fullName
    .toLocaleLowerCase('es-ES')
    .split(' ')
    .map((word, index) => (index > 0 && particles.has(word) ? word : word.split('-').map(capitalized).join('-')))
    .join(' ')
}

// Las iniciales, en el sitio de la foto cuando no la hay: las dos primeras palabras que no son partícula. El nombre
// es un solo campo, así que no se sabe dónde empiezan los apellidos: «Juan Carlos García» da «JC».
export function initialsOf(fullName: string): string {
  return fullName
    .toLocaleLowerCase('es-ES')
    .split(' ')
    .filter((word) => word !== '' && !particles.has(word))
    .slice(0, 2)
    .map((word) => word.charAt(0).toLocaleUpperCase('es-ES'))
    .join('')
}

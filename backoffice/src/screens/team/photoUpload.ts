// La foto de un jugador, que va aparte de su ficha (D-35): se sube en crudo con su tipo, o se quita. Y qué se dice
// si no se ha podido poner (plan R6, decisión 7: el jugador queda guardado sin ella, con un aviso).
import { api } from '../../api/client'
import type { ShownError } from '../../api/errors'
import { asResult, type Result } from '../../api/result'

// Lo que acepta el campo: con esto, Safari en el iPhone convierte la foto HEIC a JPEG al elegirla.
export const PHOTO_TYPES = 'image/jpeg,image/png'

export function uploadPhoto(playerId: string, file: Blob): Promise<Result<unknown>> {
  return asResult(
    api.PUT('/players/{playerId}/photo', {
      params: { path: { playerId } },
      // En crudo, con el tipo del fichero: el servidor dice si no es una imagen o no es JPEG ni PNG.
      body: file as never,
      bodySerializer: (body: unknown) => body as Blob,
      headers: { 'Content-Type': file.type || 'application/octet-stream' },
    }),
  )
}

export function removePhoto(playerId: string): Promise<Result<unknown>> {
  return asResult(api.DELETE('/players/{playerId}/photo', { params: { path: { playerId } } }))
}

// El motivo, en minúscula, para «Guardado, sin la foto: …».
export function photoProblem(error: ShownError): string {
  switch (error.code) {
    case 'NOT_AN_IMAGE':
      return 'el fichero no es una imagen'
    case 'IMAGE_TOO_LARGE':
      return 'pesa más de 5 MB, o es demasiado grande'
    case 'UNSUPPORTED_IMAGE_TYPE':
      return 'solo JPEG o PNG'
    default:
      return error.message.charAt(0).toLocaleLowerCase('es-ES') + error.message.slice(1)
  }
}

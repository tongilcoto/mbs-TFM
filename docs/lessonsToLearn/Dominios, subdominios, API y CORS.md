# Dominios, subdominios, API y CORS

> Decisión de reparto de nombres públicos para el tier gestionado: un subdominio por club,
> un solo backend, y por qué el backoffice y la API deben compartir origen.
> Relacionado: [[Multi-tenancy por schema - search_path, SET LOCAL y pooling]].

---

## Punto de partida

El club se identifica por **subdominio**, no por un segmento del path. Comercialmente es mejor:
branding por club, la URL parece "suya", y el aislamiento de origen sale gratis.

Contexto del proyecto que condiciona lo demás:

- Auth = **JWT de Supabase validado por JWKS** (`docs/ADR-API_y_BBDD-001.md:319`). *Bearer*, no
  cookie de sesión.
- Backoffice = TS/React. Apps móviles = nativas (iOS Swift, Android Kotlin).
- El tenant se resuelve por "subdominio / claim `club_id`" (`docs/ADR-API_y_BBDD-001.md:143`).

---

## 1. Un subdominio por club NO significa un backend por club

Un solo backend sirve todos los subdominios. El `Host` viaja en la cabecera de cada petición
HTTP; el middleware lo lee y saca el primer *label*
(`spikes/tenancy/Sources/App/TenantResolutionMiddleware.swift:26`). Un proceso, un puerto,
N clubes.

**Dar de alta un club no toca infraestructura: es una fila en `public.tenants`.**

Lo que sí hay que montar una vez:

### DNS wildcard

Un registro `*.myapp.com` apuntando al mismo sitio. Cubre todos los clubes presentes y futuros
sin tocar DNS al dar de alta a ninguno.

### Certificado TLS wildcard

Para `*.myapp.com`. Único detalle con aristas: **Let's Encrypt emite wildcards solo por el
desafío DNS-01**, no HTTP-01. Necesitas que tu proveedor de DNS tenga API y que el emisor pueda
escribir un registro TXT. Es un rato de configuración, no un problema.

La alternativa es emitir un certificado por subdominio bajo demanda (Caddy lo hace solo), que
evita el DNS-01 pero te ata a que cada club exista en DNS antes de su primera petición.

Dos limitaciones que sorprenden a todo el mundo:

- **Un wildcard cubre un solo nivel.** `*.myapp.com` vale para `atleti.myapp.com` pero no para
  `a.b.myapp.com`.
- **Un wildcard no cubre el ápice.** Hay que añadir `myapp.com` como SAN aparte.

### Preservar el `Host` en el proxy

Si delante del backend hay balanceador, CDN o ingress, tiene que reenviar el `Host` original (o
poblar `X-Forwarded-Host`). Es **el** fallo clásico de este patrón: el proxy reescribe el `Host`
a su nombre interno y de pronto todas las peticiones resuelven al mismo club, o a ninguno.
Merece un test de humo en cuanto haya proxy delante.

### Nombres reservados

Si el slug del club es el subdominio, hace falta una lista negra desde el día uno: `www`, `api`,
`admin`, `app`, `status`, `mail`, `staging`. Un club registrado como "api" secuestra un nombre de
infraestructura.

Y los slugs pasan a ser **públicos e inmutables en la práctica**: cambiar el de un club rompe
enlaces guardados.

---

## 2. CORS: `atleti.myapp.com` y `atleti.api.myapp.com` son orígenes DISTINTOS

El origen es **esquema + host + puerto**, comparado como cadena exacta. Compartir dominio padre
no cuenta para nada. Así que un backoffice en `atleti.myapp.com` llamando a una API en
`atleti.api.myapp.com` **es una petición cross-origin** y le aplica CORS entero.

### La solución no es configurar CORS: es eliminarlo

Colapsar los dos en **un solo origen por club**:

```
atleti.myapp.com/            → bundle React del backoffice
atleti.myapp.com/api/v1/...  → Vapor
```

Mismo esquema, mismo host, mismo puerto → mismo origen → **CORS no existe**. Un proxy inverso
delante parte por path. Siguen siendo dos desplegables independientes; lo único que comparten es
el nombre público.

Esto **no debilita** la decisión de subdominio por club: el tenant lo sigue marcando el
subdominio, el `Host` sigue siendo `atleti.myapp.com`, y el middleware no cambia una línea.

```caddy
*.myapp.com {
    tls {
        dns cloudflare {env.CF_API_TOKEN}   # DNS-01, obligatorio para wildcard
    }
    handle /api/* {
        reverse_proxy vapor:8080
    }
    handle {
        root * /srv/backoffice
        try_files {path} /index.html
        file_server
    }
}
```

En Vapor se agrupan las rutas bajo `app.grouped("api", "v1")`, o el proxy elimina el prefijo.

### Ventaja lateral: arregla un bug del resolutor de tenant

`slug(from:)` hace `guard labels.count >= 3` y devuelve `labels[0]`. Con el esquema de dos
niveles eso colisiona:

| Host | Labels | Devuelve | ¿Correcto? |
|---|---|---|---|
| `atleti.api.myapp.com` | 4 | `atleti` | sí |
| `api.myapp.com` (ápice de la API) | 3 | **`api`** | **no** — trata "api" como slug de club |
| `atleti.myapp.com` | 3 | `atleti` | sí |
| `myapp.com` (ápice) | 2 | `nil` → 400 | sí |

Con un solo nivel el contador deja de colisionar. Aun así, **la resolución debería ser contra un
sufijo de dominio configurado, no contra un contador de puntos** — eso hay que arreglarlo cuando
esto salga del spike.

### Ventaja lateral: un wildcard en vez de dos

Necesitas `*.myapp.com` para el backoffice de todos modos. Quitando el `api.` te ahorras el
segundo wildcard.

---

## 3. El argumento de seguridad, con su alcance honesto

Como la auth es *bearer*, el argumento clásico de las cookies aplica **menos** de lo habitual.
Pero no desaparece:

- **El SDK de Supabase en JS persiste la sesión en `localStorage`, que está aislado por origen.**
  Con un origen por club, la sesión de un club es físicamente inaccesible desde la página de
  otro.
- Si algún día el *refresh token* pasa a una cookie `HttpOnly` (patrón más seguro, migración
  probable), este reparto da **cookies host-only gratis**: sin atributo `Domain`, la cookie de
  `atleti.myapp.com` no viaja jamás a `rayo.myapp.com`.
- El riesgo contrario: compartir estado bajo `.myapp.com` mediante cookies con `Domain` sería un
  vector de fuga entre tenants sobre el que **no manda la API** — decide el navegador.

---

## 4. Si aun así se quieren hosts separados

Es viable, pero paga tres peajes:

1. **Preflight en cada petición autenticada.** Una petición con cabecera `Authorization` no es
   "simple", así que el navegador manda un `OPTIONS` previo. Un *round-trip* extra en **todas**
   las llamadas, mitigable con `Access-Control-Max-Age` pero nunca eliminable del todo.
2. **Lista de orígenes dinámica.** Los clubes se dan de alta en caliente, así que no se puede
   fijar la lista. El `CORSMiddleware` de Vapor ofrece `.originBased`, que devuelve como
   permitido el origen que lo pidió — permitir todo con otro nombre. Habría que escribir un
   middleware que valide el `Origin` contra `public.tenants`: código de seguridad propio para un
   problema que la otra opción no tiene.
3. **Dos certificados wildcard** en vez de uno.

Las apps nativas (iOS, Android) **no se ven afectadas por CORS en ningún caso**: es una política
del navegador. Esto solo condiciona al backoffice web.

---

## 5. Decisión pendiente, valga la que valga

El LLD dice que el tenant se resuelve por "subdominio / claim `club_id`". Son **dos fuentes** y
hay que fijar cuál manda:

> **El claim del JWT es el autoritativo. El `Host` es solo enrutado. Si no coinciden, rechazar.**

Razón: cualquiera puede mandar la cabecera `Host` que quiera; el claim va firmado. Defensa en
profundidad, y ahorra una clase entera de confusiones.

El spike hoy resuelve **solo** por `Host` / `X-Club`, sin JWT — declarado como fuera de alcance
en "Lo que el spike no prueba". Es el siguiente hueco natural si se quiere seguir midiendo en vez
de suponer.

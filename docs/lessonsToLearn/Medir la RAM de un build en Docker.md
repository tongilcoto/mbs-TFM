# Medir la RAM de un build en Docker

> Cómo se midió el pico de memoria de `swift build -c release` en el spike, y por qué el primer
> intento dio un número **tres veces mayor** que el bueno.
> Relacionado: [[Multi-tenancy por schema - search_path, SET LOCAL y pooling]].

---

## El resultado, primero

| Medida | Valor |
|---|---|
| Pico de memoria **anónima** (la que importa) | **1,54 GiB** |
| `memory.peak` del cgroup (incluye *page cache*) | 5,00 GiB |
| `docker stats` (descuenta *page cache* inactivo) | 1,70 GiB |
| Perfil del build | p50 **0,09** · p90 0,72 · p99 1,25 · máx 1,54 GiB |

El ADR estimaba un suelo de **2–4 GB**. El real está **por debajo**, y es un pico **breve**: la mitad
del build transcurre por debajo de 0,1 GiB.

---

## Lección 1 · No todos los "usos de memoria" son el mismo número

Un build lee muchísimos ficheros y escribe muchísimos `.o`. Todo eso entra en el *page cache* del
kernel y **cuenta como memoria del cgroup**, pero es **reclamable**: bajo presión el kernel la
desaloja en vez de matar el proceso.

> **Lo que dispara el OOM killer es la memoria *anónima*** (heap, pilas: lo que no tiene respaldo en
> disco). Ésa es la que hay que medir para responder *"¿cabe en mi CI?"*.

Por eso las tres cifras de arriba difieren tanto, y **ninguna está mal**: miden cosas distintas.

- `memory.peak` → marca de agua de **todo** el cgroup, *page cache* incluido. Sobreestima.
- `docker stats` → resta el *page cache* **inactivo**. Se acerca (1,70 vs 1,54, un 10 %).
- `memory.stat` → campo `anon`. **El bueno.**

Traducción práctica: si alguien te enseña un número de RAM de un build, pregunta **de qué contador
salió** antes de dimensionar nada con él.

---

## Lección 2 · La frecuencia de muestreo puede tirar la medida entera

Con el perfil de arriba —p50 de 0,09 GiB y máximo de 1,54— **el build pasa la mayor parte del tiempo
en niveles irrelevantes**. Un muestreo cada 2 s puede caer entero en los valles y perderse el pico.

Aquí se muestreó a **0,5 s** (498 muestras sobre 285 s). Y como red de seguridad se contrastó con
`memory.peak`, que es una **marca de agua del kernel**: no se pierde nada, aunque mida de más.

> Muestrear + contrastar con un contador de marca de agua es el patrón. Ninguno de los dos solo.

---

## Lección 3 · El instrumental también tiene bugs

El primer script calculaba el pico con `awk` sin fijar el locale. En locale español `awk` parsea
`1.50` como **1**, así que todos los picos salían **truncados a la baja** sin ningún aviso.

> `export LC_ALL=C` en cualquier script que parsee números de una herramienta. Siempre.

El síntoma fue ver un `0,09 GiB` con coma decimal en la salida — una pista tonta que delató el
problema antes de que contaminara el resultado.

---

## Cómo montarlo

BuildKit corre **dentro del demonio** con el driver `docker` por defecto, y los pasos del build **no
aparecen en `docker stats`**. Hay que usar un *builder* en contenedor para tener algo que medir:

```bash
docker buildx create --name meter --driver docker-container
docker buildx inspect meter --bootstrap
```

Todo el trabajo de compilación queda encerrado en `buildx_buildkit_meter0`, así que su consumo **es**
el consumo del build. Muestreo:

```bash
docker exec buildx_buildkit_meter0 \
  sh -c 'awk "/^anon /{print \$2}" /sys/fs/cgroup/memory.stat'
```

Y el build, con `--no-cache` y **contenedor de builder nuevo** en cada pase (los contadores del
cgroup son acumulativos: reutilizarlo contamina la medida del siguiente).

---

## Lección 4 · Una medida vale menos de lo que parece si no dices su alcance

Tres avisos que acompañan a este 1,54 GiB y sin los cuales la cifra engaña:

- **`swift build` paraleliza por núcleos → más CPUs, más pico.** Se midió en 10 núcleos; un *runner*
  de CI con menos pedirá **menos** memoria, no más. Es el sentido contrario al que la intuición
  sugiere ("mi portátil es más potente, en CI irá peor").
- **Es un suelo, no un techo.** El spike compila **una** entidad y **cero** capas. El grueso del
  coste es Vapor + NIO + Fluent, que no van a crecer; el código propio sí.
- **En CI la métrica que aprieta es el tiempo, no la memoria.** ~175 s solo el paso de compilación,
  y eso con las capas base ya descargadas. La palanca es la **caché de capas**, no el tamaño de la
  máquina.

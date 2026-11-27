# Retroalimentación – Bases de Datos

Calificación por sprint según la rúbrica de cada entrega. Los scripts se ejecutaron en PostgreSQL 16 vacío. Lo que venía de un sprint anterior aparece como sugerencia y no descuenta.

## Sprint 1 — 4.7 / 5.0

| Criterio | Nivel | Puntos |
|---|---|---|
| C1 Entidades y relaciones | Excelente | 1.25 / 1.25 |
| C2 Preguntas clave | Excelente | 0.75 / 0.75 |
| C3 Modelo lógico | Aceptable | 0.70 / 1.00 |
| C4 Modelo físico | Excelente | 1.25 / 1.25 |
| C5 Repositorio y documentación | Excelente | 0.75 / 0.75 |

- C3: `programming_languages` y `technologies` son `text[]`; rompen la 1FN. Está declarado como excepción, pero sin catálogo "Java" y "java" cuentan distinto.
- C2: la consulta 3 usa `:'user_id'` (variable de psql) sin aclararlo.
- C4: `projects.status` sin CHECK de dominio.
- C5: dos commits con el mismo mensaje.

## Sprint 2 — 5.0 / 5.0

| Criterio | Nivel | Puntos |
|---|---|---|
| C1 MER refinado | Excelente | 0.60 / 0.60 |
| C2 Modelo físico | Excelente | 0.80 / 0.80 |
| C3 schema.sql | Excelente | 0.80 / 0.80 |
| C4 Consultas | Excelente | 0.70 / 0.70 |
| C5 Volumen | Excelente | 0.50 / 0.50 |
| C6 Roles y seguridad | Excelente | 0.60 / 0.60 |
| C7 Almacenamiento e índices | Excelente | 0.40 / 0.40 |
| C8 Costo de una consulta | Excelente | 0.30 / 0.30 |
| C9 Optimización algebraica | Excelente | 0.30 / 0.30 |

- C1: 15 relaciones = 15 FK, con la opcionalidad correcta en `comments` y `reactions`.
- C3: la comparación de 175 objetos entre V1–V15 y `schema.sql` es una buena forma de probar que coinciden.
- C6: privilegios por columna bien usados (`password_hash` fuera de `db_readonly`).
- Sugerencias: normalizar los `text[]`; agregar un `seed.sql` (las 20 consultas devuelven 0 filas).

## Sprint 3 — 5.0 / 5.0

| Criterio | Nivel | Puntos |
|---|---|---|
| C1 MER refinado | Excelente | 0.70 / 0.70 |
| C2 Script refinado | Excelente | 0.80 / 0.80 |
| C3 Triggers | Excelente | 1.10 / 1.10 |
| C4 Procedimientos | Excelente | 1.10 / 1.10 |
| C5 Consultas | Excelente | 0.60 / 0.60 |
| C6 Roles y seguridad | Excelente | 0.70 / 0.70 |

- C1: 23 relaciones = 23 FK.
- C3: los 7 triggers se probaron como `app_runtime` y se comportan como dice el README. Buen uso de los prefijos `a_` / `b_` para fijar el orden.
- C4: las 7 funciones funcionan (bloqueo idempotente, una conversación por par, contador de no leídas a 0).
- C4: las pruebas de las secciones 9 y 10 no están en un archivo `.sql`; no se pueden reproducir sin reescribirlas.
- C6: EXECUTE revocado a PUBLIC; `db_readonly` no lee `messages.content`.
- Sugerencias: actualizar la sección de normalización (dice "las diez tablas"); agregar seed (30 de 31 consultas devuelven 0 filas).

## Nota final: 4.9

Promedio simple de los tres sprints.

# Análisis de volumen y crecimiento de datos

## 1. Objetivo

Estimar el volumen de registros de las nueve tablas del modelo físico de Fabrica Escuela, considerando un escenario hipotético de uso, su crecimiento mensual y una proyección a doce meses.

Las cantidades presentadas son supuestos de planeación académica. No corresponden a mediciones de producción ni a datos reales de Supabase.

## 2. Supuestos de estimación

- La plataforma es una aplicación universitaria para desarrolladores y comunidades técnicas.
- El escenario inicial representa una plataforma en funcionamiento con usuarios, perfiles, proyectos, publicaciones e interacciones.
- El crecimiento mensual se supone constante durante los doce meses.
- Las sesiones se consideran registros acumulativos mientras no se implemente una política de depuración.
- Los registros de auditoría se conservan para facilitar la trazabilidad.
- Los comentarios, reacciones y reportes dependen de la actividad de los usuarios.
- La proyección cuenta filas; no representa bytes ni espacio real ocupado en disco.
- No se incluyen índices, archivos externos, copias de seguridad, WAL ni sobrecarga interna de PostgreSQL.

## 3. Estimación de registros

| Tabla | Registros iniciales estimados | Crecimiento mensual | Proyección a 12 meses |
|---|---:|---:|---:|
| users.app_users | 500 | 50 | 1.100 |
| authentication.auth_sessions | 1.000 | 600 | 8.200 |
| profiles.developer_profiles | 400 | 40 | 880 |
| admin.audit_logs | 3.000 | 500 | 9.000 |
| projects.projects | 600 | 80 | 1.560 |
| posts.posts | 1.500 | 300 | 5.100 |
| interactions.comments | 8.000 | 1.600 | 27.200 |
| interactions.reactions | 12.000 | 2.400 | 40.800 |
| moderation.reports | 300 | 60 | 1.020 |
| **Total** | **27.300** | **5.630** | **94.860** |

## 4. Fórmula de crecimiento

La proyección se calcula mediante:

N(t) = N inicial + (G mensual × t)

Donde:

- N(t): cantidad estimada de registros después de t meses.
- N inicial: cantidad de registros del escenario inicial.
- G mensual: incremento estimado de registros por mes.
- t: número de meses transcurridos.

Ejemplo para `interactions.comments`:

N(12) = 8.000 + (1.600 × 12) = 27.200 registros.

Para el conjunto de las nueve tablas:

N(12) = 27.300 + (5.630 × 12) = 94.860 registros.

## 5. Interpretación

Las tablas de interacciones concentran el mayor crecimiento estimado. En particular, las reacciones y los comentarios pueden acumular numerosos registros debido a la participación de los usuarios en proyectos y publicaciones.

La tabla de sesiones también puede crecer rápidamente si se conservan los registros expirados o revocados. Por ello, se recomienda evaluar una política de retención y depuración, coordinada con el equipo responsable de la aplicación.

Los registros de auditoría requieren una estrategia de conservación acorde con las necesidades de trazabilidad y seguridad.

## 6. Limitaciones

Esta estimación es preliminar y depende de los supuestos adoptados. El crecimiento real puede variar según el número de usuarios activos, la frecuencia de publicación, las interacciones por usuario y las políticas de retención.

Para calcular el almacenamiento físico en bytes se necesitarían tamaños promedio de fila, índices, páginas de PostgreSQL y factores de ocupación. Estos cálculos se desarrollan en la sección 8 (almacenamiento e índices) y en la sección 10 (costo de consultas).

## 7. Conclusión

Bajo el escenario propuesto, el modelo pasaría de 27.300 a 94.860 registros en doce meses. Esta proyección permite identificar las tablas con mayor crecimiento y sirve como base para estudiar el almacenamiento, los índices y el costo de las consultas. Las cifras deberán ajustarse cuando se disponga de métricas reales de uso.

## 8. Cálculo de almacenamiento e índices

### 8.1. Tabla seleccionada

Se selecciona `interactions.comments`: es una de las tablas de mayor volumen (27.200 filas en la proyección a 12 meses), tiene contenido de longitud variable y concentra los índices parciales del modelo. Supuestos: página P = 8.192 bytes (valor por defecto de PostgreSQL) y TR = 27.200.

### 8.2. Longitud típica de fila (L)

L = 4 · (#campos variables) + Σ tamaño(campos fijos) + tamaño(mapa de bits) + Σ tamaño estimado(campos variables)

- Campos fijos: 6 `uuid` (id, user_id, project_id, post_id, parent_comment_id, target_id) = 96; `created_at` = 8; 2 `boolean` (is_root, parent_must_be_root) = 2. Σ fijos = 106 bytes.
- Campos variables (2): `content`, supuesto de 200 bytes en promedio, y `target_type`, 4 bytes ('POST' en la mayoría). Σ variables = 204 bytes.
- Mapa de bits: 11 campos, ⌈11 / 8⌉ = 2 bytes.

L = 4 · 2 + 106 + 2 + 204 = **320 bytes**

### 8.3. Factor de bloqueo

FR = ⌊(P − 2) / (4 + L)⌋ = ⌊(8.192 − 2) / (4 + 320)⌋ = ⌊8.190 / 324⌋ = ⌊25,28⌋ = **25 registros por página**

### 8.4. Páginas de la tabla

BR = ⌈TR / FR⌉ = ⌈27.200 / 25⌉ = **1.088 páginas**

Espacio: 1.088 × 8.192 = 8.912.896 bytes ≈ 8,5 MiB (sin índices ni espacio libre).

### 8.5. Organización de archivo e índice elegidos

- **Archivo:** heap (registros sin orden físico), que es el que usa PostgreSQL. Los comentarios se insertan al final y se consultan por publicación o proyecto, no por rango de llave primaria.
- **Índice:** B+-tree secundario `ix_comments_post_roots` sobre `(post_id, created_at, id)`, parcial (`post_id IS NOT NULL AND parent_comment_id IS NULL`).
- **Justificación:** la consulta frecuente (HU-07) lista los comentarios raíz de una publicación en orden cronológico. La igualdad sobre `post_id` localiza el grupo y `(created_at, id)` entrega el orden sin ordenar aparte. Al ser parcial, excluye respuestas y comentarios de proyectos (que tienen sus propios índices), ocupa menos espacio y cuesta menos mantenerlo.

### 8.6. Tamaño del índice B+-tree

- Entrada: L_I = 8 (cabecera) + 40 (clave: 16 + 8 + 16) + 4 (puntero) = 52 bytes.
- Entradas por nodo: FR_I = ⌊B / L_I⌋ = ⌊8.192 / 52⌋ = 157.
- Orden: 2d − 1 = 157, entonces d = 79 (cumple d ≥ 3).
- V(a,R) = 27.200 (cota superior: la clave incluye `id`, así que cada entrada es distinta).
- Altura: H ≤ log₇₉(27.200) = 2,34, entonces **H = 3**.
- Nodos por nivel (≈ V / dᵏ): hojas = ⌈27.200 / 79⌉ = 345; nivel 2 = ⌈27.200 / 79²⌉ = 5; raíz = 1.
- Espacio = (345 + 5 + 1) × 8.192 = 2.875.392 bytes ≈ **2,74 MiB**.

Contraste: con una ocupación útil del 90 % y 156 entradas por página resultan 194 páginas hoja (≈ 1,52 MiB). La fórmula de referencia usa el orden mínimo d y da una cota mayor. Como el índice es parcial, el tamaño real será menor.

### 8.7. Consideraciones

Los indices aceleran consultas frecuentes, pero consumen espacio y agregan trabajo a las operaciones de insercion, actualizacion y eliminacion. La estrategia propuesta prioriza los patrones de consulta contemplados en el modelo. La conveniencia de cada indice debe validarse posteriormente con datos representativos y planes de ejecucion.

## 9. Optimización algebraica de una consulta

### 9.1. Consulta seleccionada

Se selecciona la consulta 7 de `queries.sql`, que obtiene el historial de acciones administrativas relacionadas con un usuario. La consulta combina `admin.audit_logs` con `users.app_users`, filtra las acciones por tipo e identificador del objetivo y ordena los resultados por fecha descendente.

SQL original (el identificador del usuario se trata como una constante `c`):

```sql
SELECT l.created_at, l.action, a.username, l.details
FROM admin.audit_logs l
JOIN users.app_users a ON a.id = l.admin_id
WHERE l.target_type = 'USER' AND l.target_id = c
ORDER BY l.created_at DESC;
```

### 9.2. Expresión algebraica original

Con p1: `target_type = 'USER'` y p2: `target_id = c`:

Q = τ_{created_at ↓}( π_{created_at, action, username, details}( σ_{p1 ∧ p2}( audit_logs ⋈_{admin_id = id} app_users ) ) )

La selección queda **después** de la reunión, como en el SQL.

### 9.3. Transformaciones

1. **Ley 2** (selección conjunta): σ_{p1 ∧ p2}(E) ≡ σ_{p1}(σ_{p2}(E)). Se separan las dos condiciones.
2. **Leyes 4 y 5** (selección sobre una reunión): p1 y p2 usan solo atributos de `audit_logs`, así que σ_p(E1 ⋈ E2) ≡ σ_p(E1) ⋈ E2. Ambas selecciones bajan a `audit_logs`, antes de la reunión.
3. **Leyes 9 y 8** (proyecciones): se proyecta temprano lo necesario. De `audit_logs`: created_at, action, details y admin_id. De `app_users`: id y username (se conservan los atributos de la reunión). La proyección final elimina admin_id e id (cascada, Ley 8).

### 9.4. Expresión algebraica optimizada

Q' = τ_{created_at ↓}( π_{created_at, action, username, details}( π_{created_at, action, details, admin_id}( σ_{p1}( σ_{p2}( audit_logs ) ) ) ⋈_{admin_id = id} π_{id, username}( app_users ) ) )

### 9.5. Comparación de tuplas

| Momento | Tuplas intermedias estimadas |
|---|---:|
| Original: reunión de `audit_logs` con `app_users` | Hasta 9.000 |
| Original: después de aplicar los filtros | 30 |
| Optimizada: selección en `audit_logs` antes de la reunión | 30 |
| Optimizada: reunión del resultado filtrado con `app_users` | Hasta 30 |

Para esta comparación se supone que cada registro de auditoría encuentra como máximo un usuario administrador mediante `admin_id`, porque este atributo referencia la llave primaria `users.app_users.id`. También se supone que los filtros seleccionan 30 de las 9.000 acciones de auditoría proyectadas, equivalentes a una selectividad aproximada del 0,33 %. Estos valores son supuestos académicos, no resultados medidos.

En este escenario, el conjunto intermedio previo a la selección pasa de hasta 9.000 a 30 tuplas, una reducción aproximada del 99,67 %. La transformación también permite descartar columnas que no se necesitan antes de la reunión.

### 9.6. Conclusión

La optimización algebraica consiste en adelantar las selecciones para reducir el volumen de datos que participa en operaciones posteriores. En la consulta estudiada, el índice compuesto sobre `(target_type, target_id)` favorece la búsqueda de las acciones pertinentes.

El plan de ejecución local confirmó el uso de dicho índice, pero devolvió cero filas porque la base de prueba no contiene datos representativos. Por ello, la reducción del 99 % es únicamente un ejemplo académico y no un resultado medido. La equivalencia lógica de la transformación se mantiene, aunque una mejora real de tiempo debe verificarse con datos de prueba representativos.

## 10. Análisis de costo de una consulta

### 10.1. Consulta seleccionada

La consulta 7 de `queries.sql` (historial de acciones administrativas sobre un usuario), que incluye una reunión. El identificador del usuario se trata como una constante c.

```sql
SELECT l.created_at, l.action, a.username, l.details
FROM admin.audit_logs l
JOIN users.app_users a ON a.id = l.admin_id
WHERE l.target_type = 'USER' AND l.target_id = c
ORDER BY l.created_at DESC;
```

En esta expresión, `c` representa el identificador del usuario objetivo, obtenido mediante la subconsulta por `username` de la consulta 7 de `queries.sql`. Se trata como una constante para simplificar el análisis del costo. Por tanto, los cálculos presentados se concentran en la selección de los registros de auditoría y en la reunión posterior con la tabla de usuarios administradores.

### 10.2. Estadísticas y de dónde salen

| Dato | Valor | Origen |
|---|---|---|
| TR de `audit_logs` | 9.000 | Proyección a 12 meses (sección 3) |
| TR de `app_users` | 1.100 | Proyección a 12 meses (sección 3) |
| P (página) | 8.192 bytes | Valor por defecto de PostgreSQL |
| M (memoria) | 10 páginas | Supuesto |
| V(target_type, target_id) | 300 | Supuesto: 30 acciones por objetivo |
| L, FR, BR | ver abajo | Calculados con las fórmulas de referencia |

- `audit_logs`: fijos = 3 uuid (48) + 1 timestamptz (8) = 56; variables (3): action 20 + target_type 6 + details 100 = 126; mapa de bits = ⌈7/8⌉ = 1. L = 4·3 + 56 + 1 + 126 = **195**. FR = ⌊8.190 / 199⌋ = **41**. BR = ⌈9.000 / 41⌉ = **220**.
- `app_users`: fijos = 1 uuid (16) + 1 boolean (1) + 1 timestamptz (8) = 25; variables (5): 25 + 12 + 28 + 60 + 9 = 134; mapa de bits = 1. L = 4·5 + 25 + 1 + 134 = **180**. FR = ⌊8.190 / 184⌋ = **44**. BR = ⌈1.100 / 44⌉ = **25**.

### 10.3. Altura de los índices

- `ix_audit_logs_target`: se supone una entrada de índice de 40 bytes, por lo que $FR_I=\lfloor8192/40\rfloor=204$. Para la estimación se adopta un orden mínimo $d=\lfloor204/2\rfloor=102$. Con $V=300$ valores distintos, la altura estimada es $HI=\lceil\log_{102}(300)\rceil=2$ niveles.
- Índice de llave primaria de `users.app_users`: se supone una entrada de 28 bytes, por lo que $FR_I=\lfloor8192/28\rfloor=292$. Se adopta $d=\lfloor292/2\rfloor=146$. Para 1.100 usuarios, la altura estimada es $HI=\lceil\log_{146}(1100)\rceil=2$ niveles.

Estos resultados corresponden a un modelo teórico simplificado. La altura y el número de páginas reales dependen de la estructura, la ocupación y la distribución de las claves en los índices de PostgreSQL.

### 10.4. Selección sobre audit_logs

- S(a,R) = TR / V(a,R) = 9.000 / 300 = 30 tuplas.
- Con índice secundario: HI + S = 2 + 30 = **32 páginas**.
- Con lectura lineal: BR = **220 páginas**.
- El resultado (30 × 195 = 5.850 bytes) cabe en 1 página.

### 10.5. Reunión con app_users: planes comparados

| Plan | Cálculo | Costo (páginas) |
|---|---|---:|
| 1. Selección con índice + nested-loop en bloques (externa = resultado de 1 página) | 32 + [1 + 25·⌈1/(10−2)⌉] = 32 + 26 | **58** |
| 2. Selección con índice + indexed nested-loop | 32 + 30·(2 + 1) | 122 |
| 3. Selección lineal + indexed nested-loop | 220 + 30·(2 + 1) | 310 |
| 4. Reunión completa primero (Grace hash join, M = 10 > √25) | 3·(25 + 220) | 735 |
| 5. Reunión completa primero (nested-loop en bloques, externa = app_users) | 25 + 220·⌈25/(10−2)⌉ = 25 + 220·4 | 905 |

Los costos se calculan bajo los supuestos de la sección 10.2 y representan lecturas estimadas de páginas, no tiempos de ejecución medidos. En el plan 1 se supone que las 30 tuplas obtenidas por la selección caben en una página y que `users.app_users` ocupa 25 páginas. En el plan 2 se estima una búsqueda por índice y acceso a la página del usuario por cada tupla seleccionada. Los planes 4 y 5 consideran la reunión de las tablas completas antes de aplicar el filtro. El optimizador de PostgreSQL podría elegir otro plan según las estadísticas, los índices disponibles y los datos reales.

El ordenamiento final se hace en memoria sobre 30 tuplas y no agrega lecturas.

### 10.6. Conclusión

El plan 1 es el más barato (58 páginas), unas 15,6 veces menos que el plan 5 (905). Adelantar la selección, apoyada en el índice, reduce el costo de 905 a 58 páginas. El indexed nested-loop (plan 2) pierde frente al plan 1 porque `app_users` es pequeña (25 páginas): leerla una vez sale más barato que 30 búsquedas por índice. Son estimaciones sobre supuestos, no mediciones.

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

Para calcular el almacenamiento físico en bytes se necesitarían tamaños promedio de fila, índices, páginas de PostgreSQL y factores de ocupación. Estos cálculos se desarrollarán por separado en el análisis de almacenamiento.

## 7. Conclusión

Bajo el escenario propuesto, el modelo pasaría de 27.300 a 94.860 registros en doce meses. Esta proyección permite identificar las tablas con mayor crecimiento y sirve como base para estudiar el almacenamiento, los índices y el costo de las consultas. Las cifras deberán ajustarse cuando se disponga de métricas reales de uso.

## 8. Calculo de almacenamiento e indices

### 8.1. Tabla seleccionada

Se selecciona `interactions.comments`, debido a sus relaciones con usuarios, proyectos, publicaciones y comentarios padre. La proyeccion anual utilizada es de 27.200 filas, segun los supuestos del apartado de volumen.

### 8.2. Tamano estimado de fila

Para el ejercicio se adopta un tamano promedio estimado de fila (L) de 320 bytes. Este valor contempla los campos UUID, el contenido promedio supuesto, la fecha, las columnas generadas y una sobrecarga aproximada de la tupla. No es una medicion real de PostgreSQL.

### 8.3. Factor de bloqueo

Se supone un tamano de pagina de 8.192 bytes, un encabezado de pagina de 24 bytes y un puntero de linea de 4 bytes por registro.

FR = piso((8192 - 24) / (320 + 4)) = 25 registros por bloque.

### 8.4. Bloques requeridos

B = techo(N / FR)

B = techo(27.200 / 25) = 1.088 bloques.

Espacio estimado de paginas de datos:

1.088 x 8.192 = 8.912.896 bytes, aproximadamente 8,5 MiB.

Esta estimacion no incluye indices, fragmentacion, espacio libre ni otros costos internos.

### 8.5. Estrategia de indices

El esquema define indices para buscar comentarios por usuario, proyecto, publicacion y comentario padre. Tambien define indices parciales para comentarios raiz de proyectos y publicaciones, y para respuestas.

Se analiza `ix_comments_post_roots`, definido sobre `(post_id, created_at, id)` para filas cuyo `post_id` no es nulo y cuyo `parent_comment_id` es nulo.

### 8.6. Estimacion ilustrativa del indice B-tree

Para ilustrar el calculo, se supone una entrada de indice de 52 bytes, una pagina de 8.192 bytes y una ocupacion util del 90 %. Se reservan aproximadamente 40 bytes por pagina para encabezado y espacio especial.

Entradas aproximadas por pagina:

E = piso((8192 - 40) / 52) = 156.

Paginas hoja estimadas, suponiendo que las 27.200 filas califican para el indice:

B_hojas = techo(27.200 / (156 x 0,90)) = 194.

Bajo estos supuestos, se estima una altura aproximada de tres niveles: raiz, nivel interno y hojas. El espacio de las paginas hoja seria del orden de 194 x 8.192 bytes, es decir, aproximadamente 1,52 MiB, sin incluir paginas internas ni otros costos.

Este resultado es ilustrativo, no una medicion del indice real. Como el indice es parcial, el numero real de entradas depende de cuantos comentarios sean raiz de publicaciones. El tamano de las entradas, la ocupacion, la altura y el espacio exactos deben verificarse sobre datos reales.

### 8.7. Consideraciones

Los indices aceleran consultas frecuentes, pero consumen espacio y agregan trabajo a las operaciones de insercion, actualizacion y eliminacion. La estrategia propuesta prioriza los patrones de consulta contemplados en el modelo. La conveniencia de cada indice debe validarse posteriormente con datos representativos y planes de ejecucion.

## 9. Optimización algebraica de una consulta

### 9.1. Consulta seleccionada

Se selecciona la consulta 7 de `queries.sql`, que obtiene el historial de acciones administrativas relacionadas con un usuario. La consulta combina `admin.audit_logs` con `users.app_users`, filtra las acciones por tipo e identificador del objetivo y ordena los resultados por fecha descendente.

### 9.2. Expresión algebraica original

Se utilizan los siguientes símbolos:

- σ: selección de filas.
- ⋈: unión entre relaciones.
- π: proyección de columnas.
- τ: ordenamiento.

La expresión original se representa así:

Q = τ_fecha_descendente (π_campos (σ_condiciones(audit_logs) ⋈ app_users))

Donde las condiciones son `target_type = 'USER'` y `target_id = :user_id`, y la unión se realiza mediante `admin_id = id`.

### 9.3. Aplicación de la ley de selección

La ley de equivalencia permite aplicar una selección antes de una unión cuando las condiciones utilizan únicamente atributos de una de las relaciones:

σ_C(R ⋈ S) ≡ σ_C(R) ⋈ S

En este caso, ambas condiciones de filtrado pertenecen a `admin.audit_logs`. Por tanto, se pueden filtrar primero las acciones administrativas y después unir los registros resultantes con `users.app_users`.

### 9.4. Expresión algebraica optimizada

Q optimizada = τ_fecha_descendente (π_campos (σ_condiciones(audit_logs) ⋈ app_users))

La expresión optimizada adelanta conceptualmente la selección sobre `audit_logs`. Se mantienen la unión con los usuarios, las columnas proyectadas y el ordenamiento final, por lo que el resultado lógico es equivalente al de la consulta original.

### 9.5. Comparación de tuplas

Para ilustrar el efecto de la transformación, se plantea el siguiente escenario hipotético, que no corresponde a mediciones reales:

- Registros iniciales en `admin.audit_logs`: 3.000.
- Registros que cumplen ambos filtros: 30.
- Registros en `users.app_users`: 500.
- Registros candidatos a la unión después del filtrado: 30, en lugar de considerar las 3.000 acciones iniciales.

En este escenario, la selección reduce las filas candidatas provenientes de auditoría de 3.000 a 30, una reducción del 99 % antes de la unión.

Esta comparación ilustra la reducción del conjunto intermedio. No significa que la consulta original necesariamente procese las 3.000 filas: PostgreSQL puede aplicar la selección automáticamente y utilizar el índice compuesto `ix_audit_logs_target`.

### 9.6. Conclusión

La optimización algebraica consiste en adelantar las selecciones para reducir el volumen de datos que participa en operaciones posteriores. En la consulta estudiada, el índice compuesto sobre `(target_type, target_id)` favorece la búsqueda de las acciones pertinentes.

El plan de ejecución local confirmó el uso de dicho índice, pero devolvió cero filas porque la base de prueba no contiene datos representativos. Por ello, la reducción del 99 % es únicamente un ejemplo académico y no un resultado medido. La equivalencia lógica de la transformación se mantiene, aunque una mejora real de tiempo debe verificarse con datos de prueba representativos.

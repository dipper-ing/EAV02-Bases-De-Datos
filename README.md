 Diseño de Base de Datos 
Fábrica Escuela 2026-2 · Facultad de Ingeniería · Rol: Bases de Datos

Documentación del modelo de datos correspondiente al Sprint 1 del proyecto DevConnect (red social para desarrolladores). Este repositorio documenta el esquema realmente implementado en el backend del proyecto conjunto, a partir del repositorio principal.

Repositorio del proyecto (backend/frontend): https://github.com/TheMax1270/EAV02-Fabrica-Escuela

Contenido de este repositorio
./schema.sql — script DDL del modelo físico, ejecutable en PostgreSQL / Supabase.
./queries.sql — consultas SQL 
Este README.md — entidades y relaciones, preguntas clave, modelo lógico y modelo físico.
Alcance del Sprint 1 (rol Bases de Datos)
Este sprint documenta las tres tablas que soportan las historias de usuario de "Cimientos" que el backend tiene implementadas:

Historia de usuario	Tabla(s) asociada(s)
HU-01 — Registro de usuario	app_users
HU-03 — Inicio de sesión	app_users, auth_sessions
HU-05 — Crear/editar perfil técnico	developer_profilesDevConnect — Diseño de Base de Datos (Sprint 1)
Fábrica Escuela 2026-2 · Facultad de Ingeniería · Rol: Bases de Datos

Documentación del modelo de datos correspondiente al Sprint 1 del proyecto DevConnect (red social para desarrolladores). Este repositorio documenta el esquema realmente implementado en el backend del proyecto conjunto, a partir de las migraciones Flyway (V1 a V5) del repositorio principal.

Repositorio del proyecto (backend/frontend): https://github.com/TheMax1270/EAV02-Fabrica-Escuela

Contenido de este repositorio
./schema.sql — script DDL del modelo físico, ejecutable en PostgreSQL / Supabase.
./queries.sql — consultas SQL que resuelven las preguntas de negocio del punto 2.
Este README.md — entidades y relaciones, preguntas clave, modelo lógico y modelo físico.
Alcance del Sprint 1 (rol Bases de Datos)
Este sprint documenta las tres tablas que soportan las historias de usuario de "Cimientos" que el backend tiene implementadas:

Historia de usuario	Tabla(s) asociada(s)
HU-01 — Registro de usuario	app_users
HU-03 — Inicio de sesión	app_users, auth_sessions
HU-05 — Crear/editar perfil técnico	developer_profiles
Nota: HU-02 (verificación de correo), HU-04 (recuperar contraseña) y HU-21 (login con Google) están definidas a nivel de producto pero aún no tienen soporte de datos en el backend (no existen columnas de token de verificación, estado de cuenta pendiente/activa, tabla de recuperación de contraseña, ni provider/google_id). Quedan fuera del alcance de este entregable porque el objetivo es documentar el modelo tal como existe hoy.

1. Entidades y relaciones
erDiagram
    APP_USERS ||--o{ AUTH_SESSIONS : "genera"
    APP_USERS ||--o| DEVELOPER_PROFILES : "tiene"

    APP_USERS {
        uuid id PK
        varchar full_name
        varchar username
        varchar email
        varchar password_hash
        varchar role
        boolean enabled
        timestamptz created_at
    }

    AUTH_SESSIONS {
        uuid id PK
        uuid user_id FK
        varchar refresh_token_hash
        timestamptz created_at
        timestamptz expires_at
        timestamptz revoked_at
    }

    DEVELOPER_PROFILES {
        uuid id PK
        uuid user_id FK
        varchar biography
        text_array programming_languages
        text_array technologies
        varchar experience_level
        varchar github_url
        varchar linkedin_url
        varchar portfolio_url
        timestamptz created_at
        timestamptz updated_at
    }
Descripción de entidades

app_users: cuenta de cada usuario de la plataforma. El campo role distingue entre DEVELOPER y ADMIN (no hay tabla de roles separada; es un valor controlado por CHECK). email y username son únicos de forma case-insensitive (índices sobre lower(...)).
auth_sessions: registra cada sesión (refresh token) emitida al iniciar sesión. Relación 1 a N con app_users: un usuario puede tener varias sesiones activas (por ejemplo, en distintos dispositivos).
developer_profiles: perfil técnico opcional de un usuario. Relación 1 a 1 con app_users (user_id es UNIQUE): un usuario tiene, como máximo, un perfil técnico.
2. Preguntas de negocio clave
¿Cuántos usuarios hay registrados por rol (DEVELOPER vs ADMIN)?
¿Qué usuarios tienen la cuenta deshabilitada (enabled = false)?
¿Cuáles son las sesiones activas (no revocadas y no expiradas) de un usuario específico?
¿Qué desarrolladores de nivel SENIOR dominan un lenguaje de programación determinado (por ejemplo, Java)?
¿Cuántos perfiles técnicos existen por nivel de experiencia (JUNIOR, SEMI_SENIOR, SENIOR)?
¿Cuál es el usuario con más sesiones generadas históricamente (posible señal de uso frecuente o de abuso de tokens)?
Las consultas SQL que resuelven cada pregunta están en ./queries.sql.

3. Modelo lógico
Tabla	Columna	Tipo	Restricciones
app_users	id	uuid	PK
full_name	varchar(150)	NOT NULL
username	varchar(50)	NOT NULL, único (case-insensitive)
email	varchar(254)	NOT NULL, único (case-insensitive)
password_hash	varchar(255)	NOT NULL
role	varchar(30)	NOT NULL, CHECK IN ('DEVELOPER','ADMIN')
enabled	boolean	NOT NULL
created_at	timestamptz	NOT NULL
auth_sessions	id	uuid	PK
user_id	uuid	NOT NULL, FK → app_users(id)
refresh_token_hash	varchar(64)	NOT NULL, único
created_at	timestamptz	NOT NULL
expires_at	timestamptz	NOT NULL, CHECK > created_at
revoked_at	timestamptz	nullable
developer_profiles	id	uuid	PK
user_id	uuid	NOT NULL, FK único → app_users(id)
biography	varchar(500)	NOT NULL
programming_languages	text[]	NOT NULL
technologies	text[]	NOT NULL
experience_level	varchar(20)	NOT NULL, CHECK IN ('JUNIOR','SEMI_SENIOR','SENIOR')
github_url / linkedin_url / portfolio_url	varchar(500)	nullable
created_at / updated_at	timestamptz	NOT NULL, CHECK updated_at >= created_at
Normalización

El modelo cumple 1FN/2FN/3FN para sus claves y dependencias funcionales: todas las tablas tienen clave primaria propia (uuid), no hay dependencias transitivas (los atributos no clave dependen únicamente de la PK) y las relaciones se resuelven con claves foráneas explícitas.

Excepción deliberada: programming_languages y technologies en developer_profiles usan el tipo text[] nativo de PostgreSQL en lugar de tablas de unión (developer_languages, developer_technologies). Esto relaja la atomicidad estricta de 1FN a cambio de simplicidad para el MVP del Sprint 1. Una normalización completa extraería estas colecciones a tablas relacionadas N:M con developer_profiles; se deja como mejora propuesta para un sprint posterior si el negocio necesita filtrar/agregar por lenguaje o tecnología de forma más eficiente que con operadores de array.

4. Modelo físico
El script completo está en ./schema.sql. Incluye:

Tipos de datos específicos por columna (no genéricos).
Claves primarias (uuid) y foráneas (REFERENCES) explícitas.
Restricciones NOT NULL, UNIQUE y CHECK (dominio de role y de experience_level, coherencia de fechas en auth_sessions y developer_profiles).
Índices: únicos case-insensitive en app_users(email) y app_users(username); índices simples en las columnas usadas para búsquedas frecuentes (user_id, expires_at).
Cómo ejecutarlo
psql "postgresql://<usuario>:<password>@<host>:<puerto>/<basededatos>" -f schema.sql
O bien, pegar el contenido de schema.sql en el SQL Editor de Supabase y ejecutarlo sobre un proyecto/base vacío.

5. Trazabilidad con el backend
Este esquema corresponde 1 a 1 con las migraciones Flyway del repositorio principal (backend/src/main/resources/db/migration):

Migración	Contenido
V1__create_app_users.sql	Creación de app_users
V2__create_auth_sessions.sql	Creación de auth_sessions
V3__fix_auth_session_refresh_token_type.sql	Ajuste de tipo de refresh_token_hash
V5__recreate_developer_profiles.sql	Versión vigente de developer_profiles (reemplaza a V4)

Nota: HU-02 (verificación de correo), HU-04 (recuperar contraseña) y HU-21 (login con Google) están definidas a nivel de producto pero aún no tienen soporte de datos en el backend (no existen columnas de token de verificación, estado de cuenta pendiente/activa, tabla de recuperación de contraseña, ni provider/google_id). Quedan fuera del alcance de este entregable porque el objetivo es documentar el modelo tal como existe hoy.

1. Entidades y relaciones
erDiagram
    APP_USERS ||--o{ AUTH_SESSIONS : "genera"
    APP_USERS ||--o| DEVELOPER_PROFILES : "tiene"

    APP_USERS {
        uuid id PK
        varchar full_name
        varchar username
        varchar email
        varchar password_hash
        varchar role
        boolean enabled
        timestamptz created_at
    }

    AUTH_SESSIONS {
        uuid id PK
        uuid user_id FK
        varchar refresh_token_hash
        timestamptz created_at
        timestamptz expires_at
        timestamptz revoked_at
    }

    DEVELOPER_PROFILES {
        uuid id PK
        uuid user_id FK
        varchar biography
        text_array programming_languages
        text_array technologies
        varchar experience_level
        varchar github_url
        varchar linkedin_url
        varchar portfolio_url
        timestamptz created_at
        timestamptz updated_at
    }
Descripción de entidades

app_users: cuenta de cada usuario de la plataforma. El campo role distingue entre DEVELOPER y ADMIN (no hay tabla de roles separada; es un valor controlado por CHECK). email y username son únicos de forma case-insensitive (índices sobre lower(...)).
auth_sessions: registra cada sesión (refresh token) emitida al iniciar sesión. Relación 1 a N con app_users: un usuario puede tener varias sesiones activas (por ejemplo, en distintos dispositivos).
developer_profiles: perfil técnico opcional de un usuario. Relación 1 a 1 con app_users (user_id es UNIQUE): un usuario tiene, como máximo, un perfil técnico.
2. Preguntas de negocio clave
¿Cuántos usuarios hay registrados por rol (DEVELOPER vs ADMIN)?
¿Qué usuarios tienen la cuenta deshabilitada (enabled = false)?
¿Cuáles son las sesiones activas (no revocadas y no expiradas) de un usuario específico?
¿Qué desarrolladores de nivel SENIOR dominan un lenguaje de programación determinado (por ejemplo, Java)?
¿Cuántos perfiles técnicos existen por nivel de experiencia (JUNIOR, SEMI_SENIOR, SENIOR)?
¿Cuál es el usuario con más sesiones generadas históricamente (posible señal de uso frecuente o de abuso de tokens)?
Las consultas SQL que resuelven cada pregunta están en ./queries.sql.

3. Modelo lógico
Tabla	Columna	Tipo	Restricciones
app_users	id	uuid	PK
full_name	varchar(150)	NOT NULL
username	varchar(50)	NOT NULL, único (case-insensitive)
email	varchar(254)	NOT NULL, único (case-insensitive)
password_hash	varchar(255)	NOT NULL
role	varchar(30)	NOT NULL, CHECK IN ('DEVELOPER','ADMIN')
enabled	boolean	NOT NULL
created_at	timestamptz	NOT NULL
auth_sessions	id	uuid	PK
user_id	uuid	NOT NULL, FK → app_users(id)
refresh_token_hash	varchar(64)	NOT NULL, único
created_at	timestamptz	NOT NULL
expires_at	timestamptz	NOT NULL, CHECK > created_at
revoked_at	timestamptz	nullable
developer_profiles	id	uuid	PK
user_id	uuid	NOT NULL, FK único → app_users(id)
biography	varchar(500)	NOT NULL
programming_languages	text[]	NOT NULL
technologies	text[]	NOT NULL
experience_level	varchar(20)	NOT NULL, CHECK IN ('JUNIOR','SEMI_SENIOR','SENIOR')
github_url / linkedin_url / portfolio_url	varchar(500)	nullable
created_at / updated_at	timestamptz	NOT NULL, CHECK updated_at >= created_at
Normalización

El modelo cumple 1FN/2FN/3FN para sus claves y dependencias funcionales: todas las tablas tienen clave primaria propia (uuid), no hay dependencias transitivas (los atributos no clave dependen únicamente de la PK) y las relaciones se resuelven con claves foráneas explícitas.

Excepción deliberada: programming_languages y technologies en developer_profiles usan el tipo text[] nativo de PostgreSQL en lugar de tablas de unión (developer_languages, developer_technologies). Esto relaja la atomicidad estricta de 1FN a cambio de simplicidad para el MVP del Sprint 1. Una normalización completa extraería estas colecciones a tablas relacionadas N:M con developer_profiles; se deja como mejora propuesta para un sprint posterior si el negocio necesita filtrar/agregar por lenguaje o tecnología de forma más eficiente que con operadores de array.

4. Modelo físico
El script completo está en ./schema.sql. Incluye:

Tipos de datos específicos por columna (no genéricos).
Claves primarias (uuid) y foráneas (REFERENCES) explícitas.
Restricciones NOT NULL, UNIQUE y CHECK (dominio de role y de experience_level, coherencia de fechas en auth_sessions y developer_profiles).
Índices: únicos case-insensitive en app_users(email) y app_users(username); índices simples en las columnas usadas para búsquedas frecuentes (user_id, expires_at).
Cómo ejecutarlo
psql "postgresql://<usuario>:<password>@<host>:<puerto>/<basededatos>" -f schema.sql
O bien, pegar el contenido de schema.sql en el SQL Editor de Supabase y ejecutarlo sobre un proyecto/base vacío.

5. Trazabilidad con el backend
Este esquema corresponde 1 a 1 con las migraciones Flyway del repositorio principal (backend/src/main/resources/db/migration):

Migración	Contenido
V1__create_app_users.sql	Creación de app_users
V2__create_auth_sessions.sql	Creación de auth_sessions
V3__fix_auth_session_refresh_token_type.sql	Ajuste de tipo de refresh_token_hash
V5__recreate_developer_profiles.sql	Versión vigente de developer_profiles (reemplaza a V4)

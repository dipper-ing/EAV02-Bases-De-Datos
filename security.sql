
-- ============================================================
-- EAV02 - Fabrica Escuela
-- Sprint 2 | Seguridad y privilegios de la base de datos
-- Alcance: roles y permisos de PostgreSQL
-- Ejecutar despues de schema.sql en una base de datos de prueba.
-- ============================================================

-- 1. Crear roles de grupo sin inicio de sesion propio.
-- Las credenciales de conexion de la aplicacion se definiran
-- posteriormente con el equipo de backend.

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'db_readonly'
    ) THEN
        CREATE ROLE db_readonly NOLOGIN;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime'
    ) THEN
        CREATE ROLE app_runtime NOLOGIN;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'app_moderator'
    ) THEN
        CREATE ROLE app_moderator NOLOGIN;
    END IF;
END
$$;

-- 2. Revocar privilegios de tablas al rol PUBLIC.
-- Los permisos se asignaran explicitamente a los roles definidos.

REVOKE ALL ON ALL TABLES IN SCHEMA users FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA authentication FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA profiles FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA admin FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA projects FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA posts FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA interactions FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA moderation FROM PUBLIC;

-- 3. Permitir el uso de los esquemas a los roles autorizados.

GRANT USAGE ON SCHEMA users, authentication, profiles, admin,
    projects, posts, interactions, moderation
TO db_readonly, app_runtime, app_moderator;

-- 4. Rol de consulta: solamente lectura en las nueve tablas.

GRANT SELECT ON ALL TABLES IN SCHEMA users TO db_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA authentication TO db_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA profiles TO db_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA admin TO db_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA projects TO db_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA posts TO db_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA interactions TO db_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA moderation TO db_readonly;

-- 5. Rol de ejecucion de la aplicacion.
-- Puede operar sobre las tablas funcionales, sin administrar
-- el esquema ni modificar o borrar el registro de auditoria.

GRANT SELECT, INSERT, UPDATE
ON users.app_users TO app_runtime;

GRANT SELECT, INSERT, UPDATE, DELETE
ON authentication.auth_sessions TO app_runtime;

GRANT SELECT, INSERT, UPDATE, DELETE
ON profiles.developer_profiles TO app_runtime;

GRANT SELECT, INSERT, UPDATE, DELETE
ON projects.projects TO app_runtime;

GRANT SELECT, INSERT, UPDATE, DELETE
ON posts.posts TO app_runtime;

GRANT SELECT, INSERT, UPDATE, DELETE
ON interactions.comments TO app_runtime;

GRANT SELECT, INSERT, UPDATE, DELETE
ON interactions.reactions TO app_runtime;

-- La aplicacion puede consultar y registrar reportes,
-- pero no resolverlos ni cambiar su estado con este rol.

GRANT SELECT, INSERT
ON moderation.reports TO app_runtime;

-- La auditoria permite consultar y agregar registros,
-- pero no modificarlos ni eliminarlos.

GRANT SELECT, INSERT
ON admin.audit_logs TO app_runtime;

-- 6. Rol de moderacion.
-- Puede consultar y actualizar reportes, pero no eliminarlos.

GRANT SELECT, UPDATE
ON moderation.reports TO app_moderator;

GRANT SELECT
ON admin.audit_logs TO app_moderator;

-- ============================================================
-- EAV02 - Fabrica Escuela
-- Sprints 2 y 3 | Seguridad y privilegios de la base de datos
-- Alcance: roles, permisos, EXECUTE sobre funciones y RLS
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
REVOKE ALL ON ALL TABLES IN SCHEMA messaging FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA notifications FROM PUBLIC;

-- 3. Permitir el uso de los esquemas a los roles autorizados.

GRANT USAGE ON SCHEMA users, authentication, profiles, admin,
    projects, posts, interactions, moderation
TO db_readonly, app_runtime, app_moderator;

-- Sprint 3: el moderador no necesita acceso a mensajes ni notificaciones.
GRANT USAGE ON SCHEMA messaging, notifications
TO db_readonly, app_runtime;

-- 4. Rol de consulta: solo lectura.
-- No puede ver users.app_users.password_hash (se otorga SELECT solo
-- sobre columnas no sensibles) ni authentication.auth_sessions
-- (refresh_token_hash es un dato sensible de sesion).

GRANT SELECT (id, full_name, username, email, role, enabled, created_at)
ON users.app_users TO db_readonly;

GRANT SELECT ON profiles.developer_profiles TO db_readonly;
GRANT SELECT ON admin.audit_logs TO db_readonly;
GRANT SELECT ON projects.projects TO db_readonly;
GRANT SELECT ON posts.posts TO db_readonly;
GRANT SELECT ON interactions.comments TO db_readonly;
GRANT SELECT ON interactions.reactions TO db_readonly;
GRANT SELECT ON interactions.user_follows TO db_readonly;
GRANT SELECT ON moderation.reports TO db_readonly;

-- Sprint 3: los mensajes son privados, por lo que se otorga SELECT solo sobre
-- las columnas que no contienen el texto (sin content).

GRANT SELECT ON interactions.user_blocks TO db_readonly;
GRANT SELECT ON messaging.conversations TO db_readonly;
GRANT SELECT (id, conversation_id, sender_id, created_at)
ON messaging.messages TO db_readonly;
GRANT SELECT ON notifications.notifications TO db_readonly;

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

-- Seguir y dejar de seguir: se crean y se eliminan relaciones,
-- nunca se modifican.

GRANT SELECT, INSERT, DELETE
ON interactions.user_follows TO app_runtime;

-- Sprint 3. Bloquear y desbloquear crean y eliminan filas, nunca las modifican.

GRANT SELECT, INSERT, DELETE
ON interactions.user_blocks TO app_runtime;

-- Los mensajes no se editan ni se eliminan. De las conversaciones solo se
-- actualiza last_message_at (lo hace el trigger T3).

GRANT SELECT, INSERT
ON messaging.conversations TO app_runtime;

GRANT UPDATE (last_message_at)
ON messaging.conversations TO app_runtime;

GRANT SELECT, INSERT
ON messaging.messages TO app_runtime;

-- La aplicación crea las notificaciones y solo puede cambiar read_at.

GRANT SELECT, INSERT
ON notifications.notifications TO app_runtime;

GRANT UPDATE (read_at)
ON notifications.notifications TO app_runtime;

-- La aplicacion puede consultar y registrar reportes,
-- pero no resolverlos ni cambiar su estado con este rol.

GRANT SELECT, INSERT
ON moderation.reports TO app_runtime;

-- La auditoria permite consultar y agregar registros,
-- pero no modificarlos ni eliminarlos.

GRANT SELECT, INSERT
ON admin.audit_logs TO app_runtime;

-- 6. Rol de moderacion.
-- Puede revisar el contenido (publicaciones, comentarios y perfiles) y
-- cambiar unicamente su estado de moderacion (moderation_status), sin
-- poder editarlo ni eliminarlo. Consulta reportes y cambia unicamente su
-- estado; no puede eliminarlos. Registra sus acciones en la auditoria.

GRANT SELECT ON posts.posts TO app_moderator;
GRANT UPDATE (moderation_status) ON posts.posts TO app_moderator;

GRANT SELECT ON interactions.comments TO app_moderator;
GRANT UPDATE (moderation_status) ON interactions.comments TO app_moderator;

GRANT SELECT ON profiles.developer_profiles TO app_moderator;
GRANT UPDATE (moderation_status) ON profiles.developer_profiles TO app_moderator;

GRANT SELECT ON moderation.reports TO app_moderator;
GRANT UPDATE (status) ON moderation.reports TO app_moderator;

GRANT SELECT, INSERT ON admin.audit_logs TO app_moderator;

-- 7. Funciones y procedimientos (Sprint 3).
-- Por defecto PostgreSQL concede EXECUTE a PUBLIC sobre toda función nueva.
-- Se revoca y se otorga solo a los roles que deben invocarla. Los triggers no
-- necesitan EXECUTE sobre su función, porque PostgreSQL solo lo comprueba al
-- crear el trigger.

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA admin, interactions, messaging, notifications
FROM PUBLIC;

REVOKE ALL ON FUNCTION public.fn_set_updated_at() FROM PUBLIC;

ALTER DEFAULT PRIVILEGES IN SCHEMA admin, interactions, messaging, notifications
REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

-- La aplicación invoca los procedimientos de las HU-11, HU-12, HU-13 y HU-14.
GRANT EXECUTE ON FUNCTION
    interactions.block_user(uuid, uuid),
    interactions.unblock_user(uuid, uuid),
    messaging.send_message(uuid, uuid, text),
    messaging.get_conversation(uuid, uuid, integer),
    notifications.count_unread(uuid),
    notifications.mark_notifications_read(uuid),
    admin.get_growth_stats(date, date, text)
TO app_runtime;

-- Los triggers T2 y T5 llaman a esta función con los privilegios del rol que
-- escribe, por lo que app_runtime necesita EXECUTE (la función es
-- SECURITY DEFINER: comprueba el bloqueo sin dar acceso a user_blocks).
GRANT EXECUTE ON FUNCTION interactions.fn_users_blocked(uuid, uuid) TO app_runtime;

-- El rol de consulta solo ejecuta las estadísticas (HU-14); no puede enviar
-- mensajes ni modificar datos mediante procedimientos.
GRANT EXECUTE ON FUNCTION admin.get_growth_stats(date, date, text) TO db_readonly;

-- 8. Row Level Security en las tablas nuevas (Sprint 3).
-- El backend autentica a sus usuarios con su propio JWT y no con Supabase Auth,
-- por lo que no existe auth.uid() para escribir políticas por usuario. RLS se
-- activa como protección por defecto: sin política, cualquier otro rol (por
-- ejemplo anon o authenticated de Supabase) no ve ni modifica estas tablas.
-- El propietario de las tablas (usado por Flyway) no se ve afectado. Los
-- privilegios concretos de cada rol los siguen limitando los GRANT anteriores.

ALTER TABLE interactions.user_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE messaging.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messaging.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_blocks_app ON interactions.user_blocks;
DROP POLICY IF EXISTS user_blocks_readonly ON interactions.user_blocks;
CREATE POLICY user_blocks_app ON interactions.user_blocks
    FOR ALL TO app_runtime USING (true) WITH CHECK (true);
CREATE POLICY user_blocks_readonly ON interactions.user_blocks
    FOR SELECT TO db_readonly USING (true);

DROP POLICY IF EXISTS conversations_app ON messaging.conversations;
DROP POLICY IF EXISTS conversations_readonly ON messaging.conversations;
CREATE POLICY conversations_app ON messaging.conversations
    FOR ALL TO app_runtime USING (true) WITH CHECK (true);
CREATE POLICY conversations_readonly ON messaging.conversations
    FOR SELECT TO db_readonly USING (true);

DROP POLICY IF EXISTS messages_app ON messaging.messages;
DROP POLICY IF EXISTS messages_readonly ON messaging.messages;
CREATE POLICY messages_app ON messaging.messages
    FOR ALL TO app_runtime USING (true) WITH CHECK (true);
CREATE POLICY messages_readonly ON messaging.messages
    FOR SELECT TO db_readonly USING (true);

DROP POLICY IF EXISTS notifications_app ON notifications.notifications;
DROP POLICY IF EXISTS notifications_readonly ON notifications.notifications;
CREATE POLICY notifications_app ON notifications.notifications
    FOR ALL TO app_runtime USING (true) WITH CHECK (true);
CREATE POLICY notifications_readonly ON notifications.notifications
    FOR SELECT TO db_readonly USING (true);

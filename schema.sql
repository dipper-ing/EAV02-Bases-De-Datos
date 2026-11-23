-- ============================================================
-- DevConnect - Fábrica Escuela 2026-2
-- Modelo físico consolidado (Sprints 1, 2 y 3)
-- Estado equivalente a las migraciones Flyway V1 a V18, más los
-- refinamientos del Sprint 3 marcados con "Sprint 3 (refinamiento)".
-- Ejecutar sobre una base de datos PostgreSQL/Supabase vacía.
-- ============================================================

-- Schemas por dominio: un schema por módulo del backend.
-- En public solo permanece flyway_schema_history (control de migraciones).
CREATE SCHEMA IF NOT EXISTS users;
CREATE SCHEMA IF NOT EXISTS authentication;
CREATE SCHEMA IF NOT EXISTS profiles;
CREATE SCHEMA IF NOT EXISTS admin;
CREATE SCHEMA IF NOT EXISTS projects;
CREATE SCHEMA IF NOT EXISTS posts;
CREATE SCHEMA IF NOT EXISTS interactions;
CREATE SCHEMA IF NOT EXISTS moderation;
-- Sprint 3 (V17, V18): mensajería privada y notificaciones.
CREATE SCHEMA IF NOT EXISTS messaging;
CREATE SCHEMA IF NOT EXISTS notifications;


-- Se crea la tabla de usuarios de la plataforma.
CREATE TABLE users.app_users (
    id uuid PRIMARY KEY,
    full_name varchar(150) NOT NULL,
    username varchar(50) NOT NULL,
    email varchar(254) NOT NULL,
    password_hash varchar(255) NOT NULL,
    role varchar(30) NOT NULL CHECK (role IN ('DEVELOPER', 'ADMIN')),
    enabled boolean NOT NULL,
    created_at timestamptz NOT NULL
);

CREATE UNIQUE INDEX ux_app_users_email_ci ON users.app_users (lower(email));
CREATE UNIQUE INDEX ux_app_users_username_ci ON users.app_users (lower(username));


-- Se crea la tabla de sesiones de autenticación de los usuarios.
CREATE TABLE authentication.auth_sessions (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users.app_users(id),
    refresh_token_hash varchar(64) NOT NULL UNIQUE,
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    CONSTRAINT ck_auth_sessions_expiry CHECK (expires_at > created_at)
);

CREATE INDEX ix_auth_sessions_user_id ON authentication.auth_sessions (user_id);
CREATE INDEX ix_auth_sessions_expires_at ON authentication.auth_sessions (expires_at);


-- Se crea la tabla de perfiles técnicos de los desarrolladores.
CREATE TABLE profiles.developer_profiles (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL UNIQUE REFERENCES users.app_users(id),
    biography varchar(500) NOT NULL,
    programming_languages text[] NOT NULL,
    technologies text[] NOT NULL,
    experience_level varchar(20) NOT NULL CHECK (experience_level IN ('JUNIOR', 'SEMI_SENIOR', 'SENIOR')),
    github_url varchar(500),
    linkedin_url varchar(500),
    portfolio_url varchar(500),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    moderation_status varchar(20) NOT NULL DEFAULT 'VISIBLE',
    CONSTRAINT ck_developer_profiles_dates CHECK (updated_at >= created_at),
    CONSTRAINT ck_profiles_moderation_status CHECK (moderation_status IN ('VISIBLE', 'IN_REVIEW', 'REMOVED'))
);

CREATE INDEX ix_developer_profiles_user_id ON profiles.developer_profiles (user_id);
CREATE INDEX ix_profiles_moderation_status ON profiles.developer_profiles (moderation_status);


-- Se crea la tabla de auditoría de acciones administrativas.
CREATE TABLE admin.audit_logs (
    id uuid PRIMARY KEY,
    admin_id uuid NOT NULL REFERENCES users.app_users(id),
    action varchar(100) NOT NULL,
    target_type varchar(50) NOT NULL,
    target_id uuid NOT NULL,
    details jsonb,
    created_at timestamptz NOT NULL
);

CREATE INDEX ix_audit_logs_admin_id ON admin.audit_logs (admin_id);
CREATE INDEX ix_audit_logs_target ON admin.audit_logs (target_type, target_id);
CREATE INDEX ix_audit_logs_created_at ON admin.audit_logs (created_at DESC);


-- Se crea la tabla de proyectos publicados por los desarrolladores.
CREATE TABLE projects.projects (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users.app_users(id),
    title varchar(150) NOT NULL,
    description varchar(2000) NOT NULL,
    technologies text[] NOT NULL,
    status varchar(30) NOT NULL,
    repository_url varchar(500),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,

    -- Sprint 3 (refinamiento): el dominio de status se valida en la BD
    -- con los valores del enum ProjectStatus del backend.
    CONSTRAINT ck_projects_status
        CHECK (status IN ('IN_PROGRESS', 'COMPLETED', 'LOOKING_FOR_COLLABORATORS')),

    -- Sprint 3 (refinamiento): misma regla de fechas que developer_profiles.
    CONSTRAINT ck_projects_dates CHECK (updated_at >= created_at)
);

CREATE INDEX ix_projects_user_id ON projects.projects (user_id);

-- Publicaciones generales y discusiones técnicas.
CREATE TABLE posts.posts (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL,
    title varchar(150),
    content varchar(5000) NOT NULL,
    created_at timestamptz NOT NULL,
    type varchar(30) NOT NULL DEFAULT 'GENERAL',
    link varchar(500),
    categories text[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    resolved boolean NOT NULL DEFAULT FALSE,
    moderation_status varchar(20) NOT NULL DEFAULT 'VISIBLE',

    CONSTRAINT fk_posts_user FOREIGN KEY (user_id) REFERENCES users.app_users(id),

    CONSTRAINT ck_posts_title_not_blank
        CHECK (title ~ '[^[:space:]]'),

    CONSTRAINT ck_posts_content_not_blank
        CHECK (content ~ '[^[:space:]]'),

    CONSTRAINT ck_posts_type
        CHECK (type IN ('GENERAL', 'TECHNICAL_DISCUSSION')),

    CONSTRAINT ck_posts_discussion_title
        CHECK (
            type <> 'TECHNICAL_DISCUSSION'
            OR (title IS NOT NULL AND title ~ '[^[:space:]]')
        ),

    CONSTRAINT ck_posts_discussion_categories
        CHECK (
            type <> 'TECHNICAL_DISCUSSION'
            OR (
                cardinality(categories) >= 1
                AND array_to_string(categories, '') ~ '[^[:space:]]'
            )
        ),

    CONSTRAINT ck_posts_categories
        CHECK (
            cardinality(categories) <= 20
            AND array_position(categories, NULL) IS NULL
            AND array_position(categories, '') IS NULL
        ),

    CONSTRAINT ck_posts_general_unresolved
        CHECK (type <> 'GENERAL' OR resolved = FALSE),

    CONSTRAINT ck_posts_link
        CHECK (link IS NULL OR link ~ '^https?://[^[:space:]]+$'),

    CONSTRAINT ck_posts_moderation_status
        CHECK (moderation_status IN ('VISIBLE', 'IN_REVIEW', 'REMOVED'))
);

CREATE INDEX ix_posts_user_id ON posts.posts (user_id);
CREATE INDEX ix_posts_created_at_id ON posts.posts (created_at DESC, id DESC);
CREATE INDEX ix_posts_moderation_status ON posts.posts (moderation_status);

-- Comentarios sobre proyectos y publicaciones.
CREATE TABLE interactions.comments (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users.app_users(id) ON DELETE NO ACTION,
    project_id uuid REFERENCES projects.projects(id) ON DELETE NO ACTION,
    post_id uuid REFERENCES posts.posts(id) ON DELETE NO ACTION,
    parent_comment_id uuid,
    content varchar(2000) NOT NULL,
    created_at timestamptz NOT NULL,

    target_type text GENERATED ALWAYS AS (
        CASE WHEN project_id IS NOT NULL THEN 'PROJECT' ELSE 'POST' END
    ) STORED,

    target_id uuid GENERATED ALWAYS AS (
        COALESCE(project_id, post_id)
    ) STORED,

    is_root boolean GENERATED ALWAYS AS (
        parent_comment_id IS NULL
    ) STORED,

    moderation_status varchar(20) NOT NULL DEFAULT 'VISIBLE',

    CONSTRAINT ck_comments_target CHECK (
        (project_id IS NOT NULL AND post_id IS NULL)
        OR
        (project_id IS NULL AND post_id IS NOT NULL)
    ),

    CONSTRAINT ck_comments_content_not_blank
        CHECK (content ~ '[^[:space:]]'),

    CONSTRAINT ck_comments_parent_not_self
        CHECK (parent_comment_id IS NULL OR parent_comment_id <> id),

    CONSTRAINT uq_comments_identity_target_root
        UNIQUE (id, target_type, target_id, is_root),

    CONSTRAINT fk_comments_parent
        FOREIGN KEY (parent_comment_id)
        REFERENCES interactions.comments (id)
        ON DELETE NO ACTION,

    CONSTRAINT ck_comments_moderation_status
        CHECK (moderation_status IN ('VISIBLE', 'IN_REVIEW', 'REMOVED'))
);

CREATE INDEX ix_comments_user_id
    ON interactions.comments (user_id);

CREATE INDEX ix_comments_project_id
    ON interactions.comments (project_id)
    WHERE project_id IS NOT NULL;

CREATE INDEX ix_comments_post_id
    ON interactions.comments (post_id)
    WHERE post_id IS NOT NULL;

CREATE INDEX ix_comments_project_roots
    ON interactions.comments (project_id, created_at, id)
    WHERE project_id IS NOT NULL AND parent_comment_id IS NULL;

CREATE INDEX ix_comments_post_roots
    ON interactions.comments (post_id, created_at, id)
    WHERE post_id IS NOT NULL AND parent_comment_id IS NULL;

CREATE INDEX ix_comments_parent_created
    ON interactions.comments (parent_comment_id, created_at, id)
    WHERE parent_comment_id IS NOT NULL;

CREATE INDEX ix_comments_moderation_status
    ON interactions.comments (moderation_status);


CREATE TABLE interactions.reactions (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users.app_users(id) ON DELETE NO ACTION,
    project_id uuid REFERENCES projects.projects(id) ON DELETE NO ACTION,
    post_id uuid REFERENCES posts.posts(id) ON DELETE NO ACTION,
    type varchar(10) NOT NULL DEFAULT 'LIKE',
    created_at timestamptz NOT NULL,

    CONSTRAINT ck_reactions_type
        CHECK (type = 'LIKE'),

    CONSTRAINT ck_reactions_target
        CHECK (
            (project_id IS NOT NULL AND post_id IS NULL)
            OR
            (project_id IS NULL AND post_id IS NOT NULL)
        )
);

CREATE UNIQUE INDEX ux_reactions_project_user_type
    ON interactions.reactions (project_id, user_id, type)
    WHERE project_id IS NOT NULL;

CREATE UNIQUE INDEX ux_reactions_post_user_type
    ON interactions.reactions (post_id, user_id, type)
    WHERE post_id IS NOT NULL;

CREATE INDEX ix_reactions_user_id
    ON interactions.reactions (user_id);

-- Relaciones de seguimiento entre usuarios.
CREATE TABLE interactions.user_follows (
    id uuid PRIMARY KEY,
    follower_id uuid NOT NULL REFERENCES users.app_users(id) ON DELETE CASCADE,
    followed_id uuid NOT NULL REFERENCES users.app_users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL,

    CONSTRAINT ck_user_follows_not_self CHECK (follower_id <> followed_id),
    CONSTRAINT ux_user_follows_pair UNIQUE (follower_id, followed_id)
);

CREATE INDEX ix_user_follows_followed
    ON interactions.user_follows (followed_id, created_at);


-- Reportes de contenido para revisión por moderación.
CREATE TABLE moderation.reports (
    id uuid PRIMARY KEY,
    reporter_id uuid NOT NULL REFERENCES users.app_users(id),
    target_type varchar(20) NOT NULL,
    target_id uuid NOT NULL,
    reason varchar(30) NOT NULL,
    details varchar(500),
    status varchar(20) NOT NULL,
    created_at timestamptz NOT NULL,

    -- Sprint 3 (refinamiento): los dominios de target_type, reason y status
    -- se validan en la BD con los valores de los enums ReportTargetType,
    -- ReportReason y ReportStatus del backend.
    CONSTRAINT ck_reports_target_type
        CHECK (target_type IN ('POST', 'COMMENT', 'PROFILE')),

    CONSTRAINT ck_reports_reason
        CHECK (reason IN ('SPAM', 'HARASSMENT', 'INAPPROPRIATE_CONTENT', 'MISINFORMATION', 'OTHER')),

    CONSTRAINT ck_reports_status
        CHECK (status IN ('PENDING', 'RESOLVED', 'DISMISSED')),

    CONSTRAINT ck_reports_details_not_blank
        CHECK (details IS NULL OR details ~ '[^[:space:]]')
);

-- Evita que un usuario tenga reportes pendientes duplicados
-- para el mismo contenido.
CREATE UNIQUE INDEX ux_reports_pending_per_reporter
    ON moderation.reports (reporter_id, target_type, target_id)
    WHERE status = 'PENDING';

-- Facilita localizar reportes asociados a un contenido.
CREATE INDEX ix_reports_target
    ON moderation.reports (target_type, target_id);

-- Sprint 3 (refinamiento): apoya la bandeja de moderación (HU-10), que
-- filtra por estado y prioriza los reportes más antiguos (consulta 17).
CREATE INDEX ix_reports_status_created
    ON moderation.reports (status, created_at);


-- ============================================================
-- SPRINT 3
-- ============================================================

-- HU-11 (V16): bloqueos entre usuarios.
-- El bloqueo es dirigido (blocker -> blocked); sus efectos se aplican
-- en ambos sentidos (mensajes y seguimiento).
CREATE TABLE interactions.user_blocks (
    id uuid PRIMARY KEY,
    blocker_id uuid NOT NULL REFERENCES users.app_users(id) ON DELETE CASCADE,
    blocked_id uuid NOT NULL REFERENCES users.app_users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL,

    CONSTRAINT ck_user_blocks_not_self CHECK (blocker_id <> blocked_id),
    CONSTRAINT ux_user_blocks_pair UNIQUE (blocker_id, blocked_id)
);

-- La UNIQUE (blocker_id, blocked_id) ya indexa las búsquedas por bloqueador;
-- este índice cubre las búsquedas por usuario bloqueado.
CREATE INDEX ix_user_blocks_blocked
    ON interactions.user_blocks (blocked_id, created_at);


-- HU-12 (V17): conversaciones privadas uno a uno.
-- Una conversación por par de usuarios: el par se guarda ordenado
-- (user_one_id < user_two_id) para que (A, B) y (B, A) sean la misma fila.
CREATE TABLE messaging.conversations (
    id uuid PRIMARY KEY,
    user_one_id uuid NOT NULL REFERENCES users.app_users(id) ON DELETE CASCADE,
    user_two_id uuid NOT NULL REFERENCES users.app_users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL,
    last_message_at timestamptz NOT NULL,

    CONSTRAINT ck_conversations_ordered_pair CHECK (user_one_id < user_two_id),
    CONSTRAINT ux_conversations_pair UNIQUE (user_one_id, user_two_id)
);

-- Bandeja de conversaciones de un usuario, ordenada por actividad,
-- sin importar en qué posición del par se encuentre.
CREATE INDEX ix_conversations_user_one
    ON messaging.conversations (user_one_id, last_message_at DESC);

CREATE INDEX ix_conversations_user_two
    ON messaging.conversations (user_two_id, last_message_at DESC);


-- HU-12 (V17): mensajes de una conversación.
-- El destinatario no se almacena: es el otro participante de la conversación.
CREATE TABLE messaging.messages (
    id uuid PRIMARY KEY,
    conversation_id uuid NOT NULL REFERENCES messaging.conversations(id) ON DELETE CASCADE,
    sender_id uuid NOT NULL REFERENCES users.app_users(id) ON DELETE CASCADE,
    content text NOT NULL,
    created_at timestamptz NOT NULL,

    CONSTRAINT ck_messages_content_not_blank CHECK (content ~ '[^[:space:]]'),
    CONSTRAINT ck_messages_content_length CHECK (char_length(content) <= 2000)
);

-- Historial paginado de una conversación (más recientes primero).
CREATE INDEX ix_messages_conversation_created
    ON messaging.messages (conversation_id, created_at DESC, id DESC);


-- HU-13 (V18): notificaciones in-app.
-- target_type + target_id es una referencia polimórfica (sin FK).
-- read_at NULL significa "no leída".
CREATE TABLE notifications.notifications (
    id uuid PRIMARY KEY,
    recipient_id uuid NOT NULL REFERENCES users.app_users(id) ON DELETE CASCADE,
    actor_id uuid NOT NULL REFERENCES users.app_users(id) ON DELETE CASCADE,
    type varchar(20) NOT NULL,
    target_type varchar(20) NOT NULL,
    target_id uuid NOT NULL,
    target_label varchar(150),
    created_at timestamptz NOT NULL,
    read_at timestamptz,

    CONSTRAINT ck_notifications_type
        CHECK (type IN ('COMMENT', 'LIKE', 'FOLLOWER', 'MESSAGE')),

    CONSTRAINT ck_notifications_target_type
        CHECK (target_type IN ('POST', 'PROJECT', 'USER')),

    CONSTRAINT ck_notifications_not_self
        CHECK (recipient_id <> actor_id)
);

-- Listado paginado de notificaciones de un usuario.
CREATE INDEX ix_notifications_recipient_created
    ON notifications.notifications (recipient_id, created_at DESC, id DESC);

-- Contador de no leídas: índice parcial, solo filas con read_at NULL.
CREATE INDEX ix_notifications_recipient_unread
    ON notifications.notifications (recipient_id)
    WHERE read_at IS NULL;

-- Un "me gusta" o un seguidor sin leer no se duplica aunque el usuario
-- repita la acción.
CREATE UNIQUE INDEX ux_notifications_unread_dedupe
    ON notifications.notifications (recipient_id, actor_id, type, target_type, target_id)
    WHERE read_at IS NULL AND type IN ('LIKE', 'FOLLOWER');


-- ============================================================
-- TRIGGERS (Sprint 3)
-- Automatizan reglas de las HU en la base de datos. Son compatibles con
-- el backend: si la aplicación ya aplicó la regla, el trigger no cambia
-- nada (no duplica datos ni sobrescribe valores informados).
-- ============================================================

-- Función auxiliar: ¿existe un bloqueo entre dos usuarios, en cualquier
-- sentido? La usan los triggers de mensajes y de seguimiento (HU-11).
-- SECURITY DEFINER para que el rol de la aplicación pueda comprobar el
-- bloqueo sin necesitar permisos de lectura directa sobre user_blocks.
CREATE OR REPLACE FUNCTION interactions.fn_users_blocked(p_user_a uuid, p_user_b uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM interactions.user_blocks b
        WHERE (b.blocker_id = p_user_a AND b.blocked_id = p_user_b)
           OR (b.blocker_id = p_user_b AND b.blocked_id = p_user_a)
    );
$$;


-- T1 · HU-12 · BEFORE INSERT ON messaging.messages
-- El remitente debe ser uno de los dos participantes de la conversación.
-- (Los triggers del mismo evento se ejecutan en orden alfabético: el
-- prefijo "a_" garantiza que esta validación ocurra antes que T2.)
CREATE OR REPLACE FUNCTION messaging.fn_messages_check_participant()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM messaging.conversations c
        WHERE c.id = NEW.conversation_id
          AND NEW.sender_id IN (c.user_one_id, c.user_two_id)
    ) THEN
        RAISE EXCEPTION 'El remitente % no participa en la conversación %',
            NEW.sender_id, NEW.conversation_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_messages_a_check_participant
    BEFORE INSERT ON messaging.messages
    FOR EACH ROW
    EXECUTE FUNCTION messaging.fn_messages_check_participant();


-- T2 · HU-12 / HU-11 · BEFORE INSERT ON messaging.messages
-- No se puede enviar un mensaje si existe un bloqueo entre el remitente
-- y el otro participante, en cualquier sentido.
CREATE OR REPLACE FUNCTION messaging.fn_messages_check_block()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_recipient uuid;
BEGIN
    SELECT CASE WHEN c.user_one_id = NEW.sender_id THEN c.user_two_id
                ELSE c.user_one_id END
      INTO v_recipient
      FROM messaging.conversations c
     WHERE c.id = NEW.conversation_id;

    IF interactions.fn_users_blocked(NEW.sender_id, v_recipient) THEN
        RAISE EXCEPTION 'No se puede enviar el mensaje: existe un bloqueo entre % y %',
            NEW.sender_id, v_recipient
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_messages_b_check_block
    BEFORE INSERT ON messaging.messages
    FOR EACH ROW
    EXECUTE FUNCTION messaging.fn_messages_check_block();


-- T3 · HU-12 · AFTER INSERT ON messaging.messages
-- Mantiene conversations.last_message_at con la fecha del mensaje más
-- reciente, para ordenar la bandeja por actividad. Nunca retrocede la fecha.
CREATE OR REPLACE FUNCTION messaging.fn_messages_touch_conversation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE messaging.conversations
       SET last_message_at = NEW.created_at
     WHERE id = NEW.conversation_id
       AND last_message_at < NEW.created_at;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_messages_touch_conversation
    AFTER INSERT ON messaging.messages
    FOR EACH ROW
    EXECUTE FUNCTION messaging.fn_messages_touch_conversation();


-- T4 · HU-11 · AFTER INSERT ON interactions.user_blocks
-- Al bloquear, se eliminan los seguimientos entre ambos usuarios en los
-- dos sentidos.
CREATE OR REPLACE FUNCTION interactions.fn_user_blocks_remove_follows()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM interactions.user_follows f
     WHERE (f.follower_id = NEW.blocker_id AND f.followed_id = NEW.blocked_id)
        OR (f.follower_id = NEW.blocked_id AND f.followed_id = NEW.blocker_id);
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_user_blocks_remove_follows
    AFTER INSERT ON interactions.user_blocks
    FOR EACH ROW
    EXECUTE FUNCTION interactions.fn_user_blocks_remove_follows();


-- T5 · HU-11 / HU-08 · BEFORE INSERT ON interactions.user_follows
-- No se puede seguir a un usuario si existe un bloqueo entre ambos.
CREATE OR REPLACE FUNCTION interactions.fn_user_follows_check_block()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF interactions.fn_users_blocked(NEW.follower_id, NEW.followed_id) THEN
        RAISE EXCEPTION 'No se puede seguir: existe un bloqueo entre % y %',
            NEW.follower_id, NEW.followed_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_user_follows_check_block
    BEFORE INSERT ON interactions.user_follows
    FOR EACH ROW
    EXECUTE FUNCTION interactions.fn_user_follows_check_block();


-- T6 · HU-03 / HU-04 · BEFORE UPDATE ON developer_profiles y projects
-- Función genérica: si el contenido de la fila cambió y la aplicación no
-- actualizó updated_at, la BD lo asigna. Los argumentos del trigger son
-- columnas que no cuentan como edición (por ejemplo, moderation_status:
-- ocultar un perfil no es una edición de su dueño).
-- Se ubica en public por ser una utilidad compartida entre schemas.
CREATE OR REPLACE FUNCTION public.fn_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_ignored text[] := array_append(coalesce(TG_ARGV::text[], '{}'), 'updated_at');
BEGIN
    IF NEW.updated_at IS NOT DISTINCT FROM OLD.updated_at
       AND (to_jsonb(NEW) - v_ignored) IS DISTINCT FROM (to_jsonb(OLD) - v_ignored) THEN
        NEW.updated_at := greatest(now(), OLD.updated_at);
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_developer_profiles_set_updated_at
    BEFORE UPDATE ON profiles.developer_profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_set_updated_at('moderation_status');

CREATE TRIGGER trg_projects_set_updated_at
    BEFORE UPDATE ON projects.projects
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_set_updated_at();


-- ============================================================
-- PROCEDIMIENTOS Y FUNCIONES ALMACENADAS (Sprint 3)
-- Implementan en la base de datos la lógica de las HU del sprint.
-- Se invocan con SELECT (devuelven un resultado) y se ejecutan con
-- los privilegios de quien las llama (SECURITY INVOKER): el rol de
-- la aplicación solo necesita EXECUTE y los permisos de tabla que
-- ya tiene (ver security.sql). Los triggers T1 a T5 siguen
-- aplicando las validaciones de bloqueo y de participantes.
-- ============================================================

-- PR1 · HU-11 · Bloquear usuario.
-- Parámetros: p_blocker (quien bloquea), p_blocked (quien es bloqueado).
-- Resultado: id del bloqueo. Si ya existía, devuelve el existente
-- (la operación es idempotente). El trigger T4 elimina los seguimientos
-- entre ambos usuarios.
CREATE OR REPLACE FUNCTION interactions.block_user(p_blocker uuid, p_blocked uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_id uuid;
BEGIN
    IF p_blocker = p_blocked THEN
        RAISE EXCEPTION 'Un usuario no puede bloquearse a sí mismo'
            USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO interactions.user_blocks (id, blocker_id, blocked_id, created_at)
    VALUES (gen_random_uuid(), p_blocker, p_blocked, now())
    ON CONFLICT (blocker_id, blocked_id) DO NOTHING
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
        SELECT b.id
          INTO v_id
          FROM interactions.user_blocks b
         WHERE b.blocker_id = p_blocker
           AND b.blocked_id = p_blocked;
    END IF;

    RETURN v_id;
END;
$$;

-- PR2 · HU-11 · Desbloquear usuario.
-- Parámetros: p_blocker, p_blocked.
-- Resultado: TRUE si el bloqueo existía y se eliminó; FALSE si no existía.
CREATE OR REPLACE FUNCTION interactions.unblock_user(p_blocker uuid, p_blocked uuid)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM interactions.user_blocks b
     WHERE b.blocker_id = p_blocker
       AND b.blocked_id = p_blocked;

    RETURN FOUND;
END;
$$;

-- PR3 · HU-12 · Enviar mensaje privado.
-- Parámetros: p_sender, p_recipient, p_content (máximo 2000 caracteres).
-- Resultado: id del mensaje creado. Crea la conversación del par si no
-- existe. Los triggers T1 y T2 rechazan el envío si el remitente no
-- participa o si hay un bloqueo entre ambos; T3 actualiza la actividad.
CREATE OR REPLACE FUNCTION messaging.send_message(p_sender uuid, p_recipient uuid, p_content text)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
    v_one uuid := LEAST(p_sender, p_recipient);
    v_two uuid := GREATEST(p_sender, p_recipient);
    v_conversation uuid;
    v_message uuid := gen_random_uuid();
BEGIN
    IF p_sender = p_recipient THEN
        RAISE EXCEPTION 'No puede enviarse mensajes a sí mismo'
            USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO messaging.conversations (id, user_one_id, user_two_id, created_at, last_message_at)
    VALUES (gen_random_uuid(), v_one, v_two, now(), now())
    ON CONFLICT (user_one_id, user_two_id) DO NOTHING;

    SELECT c.id
      INTO v_conversation
      FROM messaging.conversations c
     WHERE c.user_one_id = v_one
       AND c.user_two_id = v_two;

    INSERT INTO messaging.messages (id, conversation_id, sender_id, content, created_at)
    VALUES (v_message, v_conversation, p_sender, p_content, now());

    RETURN v_message;
END;
$$;

-- PR4 · HU-12 · Historial de una conversación.
-- Parámetros: p_user, p_other, p_limit (por defecto, 50 mensajes).
-- Resultado: los últimos p_limit mensajes de la conversación entre ambos
-- usuarios, en orden cronológico (del más antiguo al más reciente).
CREATE OR REPLACE FUNCTION messaging.get_conversation(
    p_user uuid,
    p_other uuid,
    p_limit integer DEFAULT 50
)
RETURNS TABLE (message_id uuid, sender_id uuid, content text, created_at timestamptz)
LANGUAGE sql
STABLE
AS $$
    SELECT m.id, m.sender_id, m.content, m.created_at
      FROM (
            SELECT msg.id, msg.sender_id, msg.content, msg.created_at
              FROM messaging.messages msg
              JOIN messaging.conversations c ON c.id = msg.conversation_id
             WHERE c.user_one_id = LEAST(p_user, p_other)
               AND c.user_two_id = GREATEST(p_user, p_other)
             ORDER BY msg.created_at DESC, msg.id DESC
             LIMIT p_limit
           ) m
     ORDER BY m.created_at ASC, m.id ASC;
$$;

-- PR5 · HU-13 · Contador de notificaciones sin leer.
-- Parámetros: p_user.
-- Resultado: cantidad de notificaciones del usuario con read_at NULL.
CREATE OR REPLACE FUNCTION notifications.count_unread(p_user uuid)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
    SELECT count(*)::integer
      FROM notifications.notifications n
     WHERE n.recipient_id = p_user
       AND n.read_at IS NULL;
$$;

-- PR6 · HU-13 · Marcar notificaciones como leídas.
-- Parámetros: p_user.
-- Resultado: cantidad de notificaciones que pasaron de no leídas a leídas;
-- después de la llamada, el contador de no leídas queda en cero.
CREATE OR REPLACE FUNCTION notifications.mark_notifications_read(p_user uuid)
RETURNS integer
LANGUAGE plpgsql
AS $$
DECLARE
    v_count integer;
BEGIN
    UPDATE notifications.notifications n
       SET read_at = now()
     WHERE n.recipient_id = p_user
       AND n.read_at IS NULL;

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RETURN v_count;
END;
$$;

-- PR7 · HU-14 · Estadísticas de crecimiento y actividad.
-- Parámetros: p_from y p_to (rango de fechas, ambos incluidos) y
-- p_period ('week' o 'month', por defecto 'month').
-- Resultado: una fila por periodo del rango, con los usuarios registrados,
-- los proyectos publicados, las discusiones técnicas creadas y los
-- comentarios escritos en ese periodo (0 si no hubo actividad). Los
-- periodos se calculan en la zona horaria de la sesión.
CREATE OR REPLACE FUNCTION admin.get_growth_stats(
    p_from date,
    p_to date,
    p_period text DEFAULT 'month'
)
RETURNS TABLE (
    period_start date,
    new_users bigint,
    new_projects bigint,
    new_discussions bigint,
    new_comments bigint
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_t0 timestamptz;
    v_t1 timestamptz;
BEGIN
    IF p_period IS NULL OR p_period NOT IN ('week', 'month') THEN
        RAISE EXCEPTION 'Periodo no válido: % (use week o month)', p_period
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    IF p_from IS NULL OR p_to IS NULL OR p_from > p_to THEN
        RAISE EXCEPTION 'Rango de fechas no válido'
            USING ERRCODE = 'invalid_parameter_value';
    END IF;

    v_t0 := p_from::timestamptz;
    v_t1 := (p_to + 1)::timestamptz;

    RETURN QUERY
    WITH periods AS (
        SELECT g AS ps
          FROM generate_series(
                   date_trunc(p_period, v_t0),
                   date_trunc(p_period, v_t1 - interval '1 second'),
                   ('1 ' || p_period)::interval
               ) AS g
    ),
    u AS (
        SELECT date_trunc(p_period, x.created_at) AS ps, count(*) AS n
          FROM users.app_users x
         WHERE x.created_at >= v_t0 AND x.created_at < v_t1
         GROUP BY 1
    ),
    pr AS (
        SELECT date_trunc(p_period, x.created_at) AS ps, count(*) AS n
          FROM projects.projects x
         WHERE x.created_at >= v_t0 AND x.created_at < v_t1
         GROUP BY 1
    ),
    d AS (
        SELECT date_trunc(p_period, x.created_at) AS ps, count(*) AS n
          FROM posts.posts x
         WHERE x.type = 'TECHNICAL_DISCUSSION'
           AND x.created_at >= v_t0 AND x.created_at < v_t1
         GROUP BY 1
    ),
    c AS (
        SELECT date_trunc(p_period, x.created_at) AS ps, count(*) AS n
          FROM interactions.comments x
         WHERE x.created_at >= v_t0 AND x.created_at < v_t1
         GROUP BY 1
    )
    SELECT pe.ps::date,
           COALESCE(u.n, 0),
           COALESCE(pr.n, 0),
           COALESCE(d.n, 0),
           COALESCE(c.n, 0)
      FROM periods pe
      LEFT JOIN u ON u.ps = pe.ps
      LEFT JOIN pr ON pr.ps = pe.ps
      LEFT JOIN d ON d.ps = pe.ps
      LEFT JOIN c ON c.ps = pe.ps
     ORDER BY pe.ps;
END;
$$;

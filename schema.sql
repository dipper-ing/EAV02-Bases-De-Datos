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

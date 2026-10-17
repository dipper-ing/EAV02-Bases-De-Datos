
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
    CONSTRAINT ck_developer_profiles_dates CHECK (updated_at >= created_at)
);

CREATE INDEX ix_developer_profiles_user_id ON profiles.developer_profiles (user_id);


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
    updated_at timestamptz NOT NULL
);

CREATE INDEX ix_projects_user_id ON projects.projects (user_id);

-- Publicaciones generales y discusiones técnicas.
CREATE TABLE posts.posts (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users.app_users(id),
    title varchar(150),
    content varchar(5000) NOT NULL,
    created_at timestamptz NOT NULL,
    type varchar(30) NOT NULL DEFAULT 'GENERAL',
    link varchar(500),
    categories text[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    resolved boolean NOT NULL DEFAULT FALSE,

    CONSTRAINT ck_posts_title_not_blank
        CHECK (title IS NULL OR title ~ '[^[:space:]]'),

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
        CHECK (link IS NULL OR link ~ '^https?://[^[:space:]]+$')
);

CREATE INDEX ix_posts_user_id ON posts.posts (user_id);
CREATE INDEX ix_posts_created_at_id ON posts.posts (created_at DESC, id DESC);

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

    parent_must_be_root boolean GENERATED ALWAYS AS (TRUE) STORED,

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

    CONSTRAINT fk_comments_parent_same_target_root
        FOREIGN KEY (
            parent_comment_id,
            target_type,
            target_id,
            parent_must_be_root
        )
        REFERENCES interactions.comments (
            id,
            target_type,
            target_id,
            is_root
        )
        ON DELETE NO ACTION
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


-- Reportes de contenido para revisión por moderación.
CREATE TABLE moderation.reports (
    id uuid PRIMARY KEY,
    reporter_id uuid NOT NULL REFERENCES users.app_users(id),
    target_type varchar(20) NOT NULL,
    target_id uuid NOT NULL,
    reason varchar(30) NOT NULL,
    details varchar(500),
    status varchar(20) NOT NULL,
    created_at timestamptz NOT NULL
);

-- Evita que un usuario tenga reportes pendientes duplicados
-- para el mismo contenido.
CREATE UNIQUE INDEX ux_reports_pending_per_reporter
    ON moderation.reports (reporter_id, target_type, target_id)
    WHERE status = 'PENDING';

-- Facilita localizar reportes asociados a un contenido.
CREATE INDEX ix_reports_target
    ON moderation.reports (target_type, target_id);

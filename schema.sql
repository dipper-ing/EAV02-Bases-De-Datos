-- Schemas por dominio: un schema por módulo del backend.
-- En public solo permanece flyway_schema_history (control de migraciones).
CREATE SCHEMA users;
CREATE SCHEMA authentication;
CREATE SCHEMA profiles;
CREATE SCHEMA admin;
CREATE SCHEMA projects;


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

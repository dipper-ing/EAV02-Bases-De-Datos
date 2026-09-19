
CREATE TABLE app_users (
    id uuid PRIMARY KEY,
    full_name varchar(150) NOT NULL,
    username varchar(50) NOT NULL,
    email varchar(254) NOT NULL,
    password_hash varchar(255) NOT NULL,
    role varchar(30) NOT NULL CHECK (role IN ('DEVELOPER', 'ADMIN')),
    enabled boolean NOT NULL,
    created_at timestamptz NOT NULL
);

CREATE UNIQUE INDEX ux_app_users_email_ci ON app_users (lower(email));
CREATE UNIQUE INDEX ux_app_users_username_ci ON app_users (lower(username));


CREATE TABLE auth_sessions (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES app_users(id),
    refresh_token_hash varchar(64) NOT NULL UNIQUE,
    created_at timestamptz NOT NULL,
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    CONSTRAINT ck_auth_sessions_expiry CHECK (expires_at > created_at)
);

CREATE INDEX ix_auth_sessions_user_id ON auth_sessions (user_id);
CREATE INDEX ix_auth_sessions_expires_at ON auth_sessions (expires_at);


CREATE TABLE developer_profiles (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL UNIQUE REFERENCES app_users(id),
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

CREATE INDEX ix_developer_profiles_user_id ON developer_profiles (user_id);

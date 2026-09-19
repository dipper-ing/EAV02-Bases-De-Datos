-- 1. Usuarios registrados por rol
SELECT role, COUNT(*) AS total_usuarios
FROM users.app_users
GROUP BY role;

-- 2. Usuarios con la cuenta suspendida (enabled = false)
SELECT id, full_name, username, email
FROM users.app_users
WHERE enabled = false;

-- 3. Sesiones activas (no revocadas y no expiradas) de un usuario
--    Reemplazar :user_id por el uuid real.
SELECT s.id, s.created_at, s.expires_at
FROM authentication.auth_sessions s
WHERE s.user_id = :'user_id'
  AND s.revoked_at IS NULL
  AND s.expires_at > now();

-- 4. Desarrolladores SENIOR que dominan un lenguaje específico (ej. Java)
SELECT u.full_name, u.username, dp.experience_level
FROM profiles.developer_profiles dp
JOIN users.app_users u ON u.id = dp.user_id
WHERE dp.experience_level = 'SENIOR'
  AND 'Java' = ANY (dp.programming_languages);

-- 5. Cantidad de perfiles técnicos por nivel de experiencia
SELECT experience_level, COUNT(*) AS total_perfiles
FROM profiles.developer_profiles
GROUP BY experience_level
ORDER BY total_perfiles DESC;

-- 6. Usuario con más sesiones generadas históricamente
SELECT u.username, COUNT(s.id) AS total_sesiones
FROM users.app_users u
JOIN authentication.auth_sessions s ON s.user_id = u.id
GROUP BY u.username
ORDER BY total_sesiones DESC
LIMIT 1;

-- 7. Historial de acciones administrativas sobre un usuario
--    Reemplazar :user_id por el uuid real.
SELECT l.created_at, l.action, a.username AS administrador, l.details
FROM admin.audit_logs l
JOIN users.app_users a ON a.id = l.admin_id
WHERE l.target_type = 'USER'
  AND l.target_id = :'user_id'
ORDER BY l.created_at DESC;

-- 8. Cantidad de suspensiones y reactivaciones ejecutadas por cada administrador
SELECT a.username AS administrador, l.action, COUNT(*) AS total
FROM admin.audit_logs l
JOIN users.app_users a ON a.id = l.admin_id
WHERE l.action IN ('USER_SUSPENDED', 'USER_REACTIVATED')
GROUP BY a.username, l.action
ORDER BY a.username, l.action;

-- 9. Cuentas actualmente suspendidas, con fecha y responsable de su última suspensión
SELECT u.username, u.email, ultima.created_at AS suspendida_en, a.username AS suspendida_por
FROM users.app_users u
JOIN LATERAL (
    SELECT l.admin_id, l.created_at
    FROM admin.audit_logs l
    WHERE l.target_type = 'USER'
      AND l.target_id = u.id
      AND l.action = 'USER_SUSPENDED'
    ORDER BY l.created_at DESC
    LIMIT 1
) ultima ON true
JOIN users.app_users a ON a.id = ultima.admin_id
WHERE u.enabled = false
ORDER BY ultima.created_at DESC;

-- 10. Acciones administrativas de los últimos 7 días
SELECT l.created_at, a.username AS administrador, l.action, l.target_type, l.target_id
FROM admin.audit_logs l
JOIN users.app_users a ON a.id = l.admin_id
WHERE l.created_at >= now() - interval '7 days'
ORDER BY l.created_at DESC;

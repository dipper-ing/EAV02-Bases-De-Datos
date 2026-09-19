-- 1. Usuarios registrados por rol
SELECT role, COUNT(*) AS total_usuarios
FROM app_users
GROUP BY role;

-- 2. Usuarios con la cuenta deshabilitada
SELECT id, full_name, username, email
FROM app_users
WHERE enabled = false;

-- 3. Sesiones activas (no revocadas y no expiradas) de un usuario
--    Reemplazar :user_id por el uuid real.
SELECT s.id, s.created_at, s.expires_at
FROM auth_sessions s
WHERE s.user_id = :'user_id'
  AND s.revoked_at IS NULL
  AND s.expires_at > now();

-- 4. Desarrolladores SENIOR que dominan un lenguaje específico (ej. Java)
SELECT u.full_name, u.username, dp.experience_level
FROM developer_profiles dp
JOIN app_users u ON u.id = dp.user_id
WHERE dp.experience_level = 'SENIOR'
  AND 'Java' = ANY (dp.programming_languages);

-- 5. Cantidad de perfiles técnicos por nivel de experiencia
SELECT experience_level, COUNT(*) AS total_perfiles
FROM developer_profiles
GROUP BY experience_level
ORDER BY total_perfiles DESC;

-- 6. Usuario con más sesiones generadas históricamente
SELECT u.username, COUNT(s.id) AS total_sesiones
FROM app_users u
JOIN auth_sessions s ON s.user_id = u.id
GROUP BY u.username
ORDER BY total_sesiones DESC
LIMIT 1;

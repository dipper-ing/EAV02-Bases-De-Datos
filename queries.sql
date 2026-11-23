-- ============================================================
-- DevConnect - Consultas de los Sprints 1, 2 y 3
-- Cada consulta responde una pregunta de negocio del README
-- (seccion 2) y se ejecuta sobre las tablas de schema.sql.
-- Las consultas que filtran por usuario usan el nombre de usuario
-- de ejemplo 'usuario_demo' (y 'otro_usuario' cuando intervienen dos);
-- se cambian por los reales. Las consultas 1 a 20 se ejecutaron sin cambios
-- sobre el esquema refinado del Sprint 3; las 21 a 31 son nuevas.
-- ============================================================

-- ------------------------------------------------------------
-- SPRINT 1
-- ------------------------------------------------------------

-- Consulta 1. ¿Cuántos usuarios hay registrados por rol?
SELECT role, COUNT(*) AS total_usuarios
FROM users.app_users
GROUP BY role;

-- Consulta 2. ¿Qué usuarios tienen la cuenta suspendida?
SELECT id, full_name, username, email
FROM users.app_users
WHERE enabled = false;

-- Consulta 3. ¿Cuáles son las sesiones activas de un usuario?
SELECT s.id, s.created_at, s.expires_at
FROM authentication.auth_sessions s
WHERE s.user_id = (SELECT id FROM users.app_users WHERE username = 'usuario_demo')
  AND s.revoked_at IS NULL
  AND s.expires_at > now();

-- Consulta 4. ¿Qué desarrolladores SENIOR dominan un lenguaje (ej. Java)?
SELECT u.full_name, u.username, dp.experience_level
FROM profiles.developer_profiles dp
JOIN users.app_users u ON u.id = dp.user_id
WHERE dp.experience_level = 'SENIOR'
  AND 'Java' = ANY (dp.programming_languages);

-- Consulta 5. ¿Cuántos perfiles técnicos hay por nivel de experiencia?
SELECT experience_level, COUNT(*) AS total_perfiles
FROM profiles.developer_profiles
GROUP BY experience_level
ORDER BY total_perfiles DESC;

-- Consulta 6. ¿Qué usuario ha generado más sesiones?
SELECT u.username, COUNT(s.id) AS total_sesiones
FROM users.app_users u
JOIN authentication.auth_sessions s ON s.user_id = u.id
GROUP BY u.username
ORDER BY total_sesiones DESC
LIMIT 1;

-- Consulta 7. ¿Cuál es el historial de acciones administrativas sobre un usuario?
SELECT l.created_at, l.action, a.username AS administrador, l.details
FROM admin.audit_logs l
JOIN users.app_users a ON a.id = l.admin_id
WHERE l.target_type = 'USER'
  AND l.target_id = (SELECT id FROM users.app_users WHERE username = 'usuario_demo')
ORDER BY l.created_at DESC;

-- Consulta 8. ¿Cuántas suspensiones y reactivaciones ha ejecutado cada administrador?
SELECT a.username AS administrador, l.action, COUNT(*) AS total
FROM admin.audit_logs l
JOIN users.app_users a ON a.id = l.admin_id
WHERE l.action IN ('USER_SUSPENDED', 'USER_REACTIVATED')
GROUP BY a.username, l.action
ORDER BY a.username, l.action;

-- Consulta 9. ¿Qué cuentas están suspendidas, desde cuándo y quién las suspendió?
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

-- Consulta 10. ¿Qué acciones administrativas se realizaron en los últimos 7 días?
SELECT l.created_at, a.username AS administrador, l.action, l.target_type, l.target_id
FROM admin.audit_logs l
JOIN users.app_users a ON a.id = l.admin_id
WHERE l.created_at >= now() - interval '7 days'
ORDER BY l.created_at DESC;

-- ------------------------------------------------------------
-- SPRINT 2
-- ------------------------------------------------------------

-- Consulta 11 (HU-06). ¿Cuántas publicaciones hay por tipo y cuántas están resueltas?
SELECT type,
       COUNT(*) AS total_publicaciones,
       COUNT(*) FILTER (WHERE resolved = TRUE) AS resueltas
FROM posts.posts
GROUP BY type
ORDER BY total_publicaciones DESC;

-- Consulta 12 (HU-06). ¿Qué discusiones técnicas siguen abiertas para una tecnología?
SELECT p.id, p.title, p.created_at, u.username AS autor
FROM posts.posts p
JOIN users.app_users u ON u.id = p.user_id
WHERE p.type = 'TECHNICAL_DISCUSSION'
  AND p.resolved = FALSE
  AND 'flyway' = ANY (p.categories)
ORDER BY p.created_at DESC;

-- Consulta 13 (HU-07). ¿Cuántos comentarios y respuestas tiene cada publicación?
SELECT p.id AS post_id,
       p.title,
       COUNT(c.id) AS total_comentarios,
       COUNT(c.id) FILTER (WHERE c.is_root = TRUE) AS comentarios_raiz,
       COUNT(c.id) FILTER (WHERE c.is_root = FALSE) AS respuestas
FROM posts.posts AS p
LEFT JOIN interactions.comments AS c ON c.post_id = p.id
GROUP BY p.id, p.title
ORDER BY total_comentarios DESC;

-- Consulta 14 (HU-07). ¿Cuántas reacciones tiene cada publicación?
SELECT p.id AS post_id,
       p.title,
       COUNT(r.id) AS total_reacciones
FROM posts.posts AS p
LEFT JOIN interactions.reactions AS r ON r.post_id = p.id
GROUP BY p.id, p.title
ORDER BY total_reacciones DESC;

-- Consulta 15 (HU-09). ¿Qué tipos de contenido o perfiles acumulan más reportes pendientes?
SELECT target_type,
       COUNT(*) AS total_reportes_pendientes
FROM moderation.reports
WHERE status = 'PENDING'
GROUP BY target_type
ORDER BY total_reportes_pendientes DESC;

-- Consulta 16 (HU-09). ¿Qué reportes ha enviado un usuario y en qué estado están?
SELECT id AS report_id, target_type, target_id, reason, details, status, created_at
FROM moderation.reports
WHERE reporter_id = (SELECT id FROM users.app_users WHERE username = 'usuario_demo')
ORDER BY created_at DESC;

-- Consulta 17 (HU-10). ¿Cómo se priorizan los reportes, empezando por los pendientes más antiguos?
SELECT status, reason, target_type,
       COUNT(*) AS total_reportes,
       MIN(created_at) AS reporte_mas_antiguo
FROM moderation.reports
GROUP BY status, reason, target_type
ORDER BY CASE WHEN status = 'PENDING' THEN 0 ELSE 1 END,
         reporte_mas_antiguo ASC;

-- Consulta 18 (HU-08). ¿Cuántos seguidores y cuántos seguidos tiene cada usuario?
SELECT u.username,
       COUNT(DISTINCT fr.id) AS seguidores,
       COUNT(DISTINCT fg.id) AS siguiendo
FROM users.app_users u
LEFT JOIN interactions.user_follows fr ON fr.followed_id = u.id
LEFT JOIN interactions.user_follows fg ON fg.follower_id = u.id
GROUP BY u.id, u.username
ORDER BY seguidores DESC, u.username;

-- Consulta 19 (HU-08). ¿Quiénes siguen a un usuario y desde cuándo?
SELECT seguidor.username AS seguidor, f.created_at AS siguiendo_desde
FROM interactions.user_follows f
JOIN users.app_users seguidor ON seguidor.id = f.follower_id
WHERE f.followed_id = (SELECT id FROM users.app_users WHERE username = 'usuario_demo')
ORDER BY f.created_at DESC;

-- Consulta 20 (HU-10). ¿Cuánto contenido está en revisión o removido, por tipo de contenido?
SELECT 'POST' AS tipo_contenido, moderation_status, COUNT(*) AS total
FROM posts.posts
WHERE moderation_status <> 'VISIBLE'
GROUP BY moderation_status
UNION ALL
SELECT 'COMMENT', moderation_status, COUNT(*)
FROM interactions.comments
WHERE moderation_status <> 'VISIBLE'
GROUP BY moderation_status
UNION ALL
SELECT 'PROFILE', moderation_status, COUNT(*)
FROM profiles.developer_profiles
WHERE moderation_status <> 'VISIBLE'
GROUP BY moderation_status
ORDER BY tipo_contenido, moderation_status;

-- ------------------------------------------------------------
-- SPRINT 3
-- ------------------------------------------------------------

-- Consulta 21 (HU-11). ¿A quiénes ha bloqueado un usuario y desde cuándo?
SELECT bloqueado.username AS bloqueado, b.created_at AS bloqueado_desde
FROM interactions.user_blocks b
JOIN users.app_users bloqueado ON bloqueado.id = b.blocked_id
WHERE b.blocker_id = (SELECT id FROM users.app_users WHERE username = 'usuario_demo')
ORDER BY b.created_at DESC;

-- Consulta 22 (HU-11). ¿Qué usuarios han sido bloqueados por más personas?
SELECT u.username, COUNT(*) AS veces_bloqueado
FROM interactions.user_blocks b
JOIN users.app_users u ON u.id = b.blocked_id
GROUP BY u.id, u.username
ORDER BY veces_bloqueado DESC, u.username
LIMIT 10;

-- Consulta 23 (HU-11). ¿Existe un bloqueo, en cualquier sentido, entre dos usuarios?
SELECT interactions.fn_users_blocked(a.id, b.id) AS hay_bloqueo
FROM users.app_users a
CROSS JOIN users.app_users b
WHERE a.username = 'usuario_demo'
  AND b.username = 'otro_usuario';

-- Consulta 24 (HU-12). ¿Cuáles son las conversaciones de un usuario, ordenadas por actividad, con el otro participante y el último mensaje?
SELECT otro.username AS con_usuario, c.last_message_at, ultimo.content AS ultimo_mensaje
FROM messaging.conversations c
JOIN users.app_users yo
  ON yo.username = 'usuario_demo'
 AND yo.id IN (c.user_one_id, c.user_two_id)
JOIN users.app_users otro
  ON otro.id = CASE WHEN c.user_one_id = yo.id THEN c.user_two_id ELSE c.user_one_id END
JOIN LATERAL (
    SELECT m.content
    FROM messaging.messages m
    WHERE m.conversation_id = c.id
    ORDER BY m.created_at DESC, m.id DESC
    LIMIT 1
) ultimo ON true
ORDER BY c.last_message_at DESC;

-- Consulta 25 (HU-12). ¿Cuál es el historial de mensajes entre dos usuarios, en orden cronológico?
SELECT h.created_at, emisor.username AS remitente, h.content
FROM messaging.get_conversation(
         (SELECT id FROM users.app_users WHERE username = 'usuario_demo'),
         (SELECT id FROM users.app_users WHERE username = 'otro_usuario')
     ) h
JOIN users.app_users emisor ON emisor.id = h.sender_id
ORDER BY h.created_at;

-- Consulta 26 (HU-12). ¿Cuántos mensajes ha enviado cada usuario y cuándo envió el último?
SELECT u.username, COUNT(m.id) AS mensajes_enviados, MAX(m.created_at) AS ultimo_mensaje
FROM users.app_users u
JOIN messaging.messages m ON m.sender_id = u.id
GROUP BY u.id, u.username
ORDER BY mensajes_enviados DESC, u.username;

-- Consulta 27 (HU-13). ¿Cuántas notificaciones sin leer tiene cada usuario?
SELECT u.username, COUNT(*) AS sin_leer
FROM notifications.notifications n
JOIN users.app_users u ON u.id = n.recipient_id
WHERE n.read_at IS NULL
GROUP BY u.id, u.username
ORDER BY sin_leer DESC, u.username;

-- Consulta 28 (HU-13). ¿Cuáles son las notificaciones más recientes de un usuario y quién las originó?
SELECT n.created_at, n.type, actor.username AS actor, n.target_type, n.target_label,
       (n.read_at IS NOT NULL) AS leida
FROM notifications.notifications n
JOIN users.app_users actor ON actor.id = n.actor_id
WHERE n.recipient_id = (SELECT id FROM users.app_users WHERE username = 'usuario_demo')
ORDER BY n.created_at DESC, n.id DESC
LIMIT 20;

-- Consulta 29 (HU-13). ¿Qué tipo de notificación genera más actividad y cuántas siguen sin leer?
SELECT type, COUNT(*) AS total, COUNT(*) FILTER (WHERE read_at IS NULL) AS sin_leer
FROM notifications.notifications
GROUP BY type
ORDER BY total DESC;

-- Consulta 30 (HU-14). ¿Cuántos usuarios nuevos se registraron por mes en un rango de fechas?
SELECT date_trunc('month', created_at)::date AS mes, COUNT(*) AS usuarios_nuevos
FROM users.app_users
WHERE created_at >= DATE '2026-01-01'
  AND created_at < DATE '2026-04-01'
GROUP BY 1
ORDER BY 1;

-- Consulta 31 (HU-14). ¿Cuántos usuarios, proyectos, discusiones y comentarios hubo por periodo (semana o mes)?
SELECT * FROM admin.get_growth_stats(DATE '2026-01-01', DATE '2026-03-31', 'month');
-- Variante semanal:
-- SELECT * FROM admin.get_growth_stats(DATE '2026-02-01', DATE '2026-02-28', 'week');

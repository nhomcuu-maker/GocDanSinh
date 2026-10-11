-- GocDanSinh: RECONCILE EXISTING USERS AND ROLES. READ ONLY.
-- Run before generating accounts. Never send emails/passwords to public chats.
USE [GocDanSinh];
GO
SELECT r.role_code, r.role_name,
 COUNT(DISTINCT CASE WHEN u.account_status=N'active' AND c.user_id IS NOT NULL THEN u.id END) AS active_login_accounts
FROM dbo.role r
LEFT JOIN dbo.user_role ur ON ur.role_id=r.id
LEFT JOIN dbo.app_user u ON u.id=ur.user_id
LEFT JOIN dbo.auth_credential c ON c.user_id=u.id
WHERE r.role_code IN (N'admin',N'author',N'editor',N'reviewer',N'publisher')
GROUP BY r.role_code,r.role_name
ORDER BY r.role_code;
-- Optional: list actual existing staff accounts for LOCAL ONLY identity checks.
SELECT u.id,u.display_name,u.email,u.account_status,r.role_code,
 CASE WHEN c.user_id IS NOT NULL AND DATALENGTH(c.password_salt)=32 AND DATALENGTH(c.password_hash)=64
   THEN N'HAS_SCRYPT_CREDENTIAL' ELSE N'NO_VALID_LOGIN' END AS login_state
FROM dbo.app_user u
JOIN dbo.user_role ur ON ur.user_id=u.id
JOIN dbo.role r ON r.id=ur.role_id
LEFT JOIN dbo.auth_credential c ON c.user_id=u.id
WHERE r.role_code IN (N'admin',N'author',N'editor',N'reviewer',N'publisher')
ORDER BY r.role_code,u.id;
GO

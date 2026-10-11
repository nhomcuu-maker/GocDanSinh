USE [GocDanSinh];
GO

SELECT
    DB_NAME() AS DatabaseName,
    name AS TableName
FROM sys.tables
WHERE name IN (
    'app_user',
    'auth_credential',
    'auth_session',
    'knowledge_item',
    'knowledge_version',
    'knowledge_item_link',
    'knowledge_source_candidate',
    'assistant_feedback'
)
ORDER BY name;



USE [GocDanSinh];
GO

SELECT
    (SELECT COUNT(*)
     FROM dbo.app_user
     WHERE account_status = N'active')
       AS TaiKhoanDangHoatDong,

    (SELECT COUNT(*)
     FROM dbo.auth_credential)
       AS TaiKhoanCoMatKhau,

    (SELECT COUNT(*)
     FROM dbo.app_user u
     JOIN dbo.auth_credential c
       ON c.user_id = u.id
     WHERE u.account_status = N'active')
       AS TaiKhoanHopLe,

    (SELECT COUNT(DISTINCT u.id)
     FROM dbo.app_user u
     JOIN dbo.auth_credential c
       ON c.user_id = u.id
     JOIN dbo.user_role ur
       ON ur.user_id = u.id
     JOIN dbo.[role] r
       ON r.id = ur.role_id
     WHERE u.account_status = N'active'
       AND r.role_code = N'admin')
       AS AdminHopLe;



USE [GocDanSinh];
GO

SELECT
    (SELECT COUNT(*) FROM dbo.app_user)
        AS TongTaiKhoan,

    (SELECT COUNT(*) FROM dbo.auth_credential)
        AS TaiKhoanCoMatKhau;



-- Cấp quyền Admin --


USE [GocDanSinh];
GO

SELECT
    u.id,
    u.email,
    u.account_status
FROM dbo.app_user u
INNER JOIN dbo.auth_credential c
    ON c.user_id = u.id;
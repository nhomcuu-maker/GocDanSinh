-- GOC DAN SINH: ONE-TIME STAFF ACCOUNT PROVISIONING.
-- Generated locally; contains scrypt salt/hash, NEVER cleartext passwords.
-- CAUTION: hash material is sensitive. Do not share this SQL file. Delete it after use.
-- NO automated verification, approval, publication, admin grant or role escalation.
-- New users only. If a matching email already exists, entire batch fails and rolls back.
USE [GocDanSinh];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @Apply BIT = 1; -- 0=PREVIEW/ROLLBACK; 1=COMMIT after full database backup
IF DB_NAME() <> N'GocDanSinh' THROW 59410,N'Wrong database',1;
IF @@TRANCOUNT <> 0 THROW 59411,N'Close existing SSMS transactions first',1;
IF OBJECT_ID(N'dbo.app_user',N'U') IS NULL OR OBJECT_ID(N'dbo.auth_credential',N'U') IS NULL OR
   OBJECT_ID(N'dbo.user_role',N'U') IS NULL OR OBJECT_ID(N'dbo.role',N'U') IS NULL
   THROW 59412,N'Authentication tables missing',1;
DECLARE @Accounts TABLE(
  role_code NVARCHAR(30) NOT NULL PRIMARY KEY,
  display_name NVARCHAR(180) NOT NULL,
  email NVARCHAR(254) NOT NULL UNIQUE,
  salt VARBINARY(32) NOT NULL,
  [hash] VARBINARY(64) NOT NULL
);
INSERT @Accounts(role_code,display_name,email,salt,[hash]) VALUES
(CONVERT(NVARCHAR(30), 0x65006400690074006f007200, 0), CONVERT(NVARCHAR(180), 0x65006400690074006f007200, 0), CONVERT(NVARCHAR(254), 0x65006400690074006f007200400067006d00610069006c002e0063006f006d00, 0), 0x5b8bfcbd7adfd2e9c79b5fe3ee2452f001813b36f8e0b729cba0dec7c8aca8f7, 0xa02ad1baaa62d58cafbc4f54f668c35dccb625ad5b041c1437fcdf159c579252904689f2bc8c273fd42557efe2ffa1c76b3bf7f677519d21eb12f485dec216a2),
(CONVERT(NVARCHAR(30), 0x72006500760069006500770065007200, 0), CONVERT(NVARCHAR(180), 0x72006500760069006500770065007200, 0), CONVERT(NVARCHAR(254), 0x72006500760069006500770065007200400067006d00610069006c002e0063006f006d00, 0), 0x480649d3913996e79cd0bd6b1e1e05d537d5615b50441655ccc7f83d1324d141, 0x985fd5557445d5a00242931130d7444694e10bba81cb7a63ed22016d860f45f7611e522b5ba6feb9a3aa95cb74f50dfa93288c7bc0e5ed44d77b00c99170b1b1),
(CONVERT(NVARCHAR(30), 0x7000750062006c0069007300680065007200, 0), CONVERT(NVARCHAR(180), 0x7000750062006c0069007300680065007200, 0), CONVERT(NVARCHAR(254), 0x7000750062006c0069007300680065007200400067006d00610069006c002e0063006f006d00, 0), 0x65d4115c877d3d3083b012cb1e0c336eaae01e492a11c12f0bc78cff442b4a32, 0xb9dc36e79fcb896b0c2816d36a4911e8b9e9b3bce275cc31bc6492c4a7d2a4b61d7a099e6ce942168a8cc17314e18362662a7f94cc4ff680f6386b620e77ca39);
IF EXISTS(SELECT 1 FROM @Accounts a WHERE a.role_code NOT IN (N'editor',N'reviewer',N'publisher')
    OR DATALENGTH(a.salt)<>32 OR DATALENGTH(a.[hash])<>64)
   THROW 59413,N'Invalid role or scrypt data',1;
IF EXISTS(SELECT 1 FROM @Accounts a LEFT JOIN dbo.role r ON r.role_code=a.role_code WHERE r.id IS NULL)
   THROW 59414,N'A required role is missing from dbo.role',1;
IF EXISTS(SELECT 1 FROM @Accounts a JOIN dbo.app_user u ON u.email=a.email)
   THROW 59415,N'Email already exists. Do not create a duplicate; review roles first',1;
DECLARE @Created TABLE(user_id BIGINT NOT NULL, email NVARCHAR(254), role_code NVARCHAR(30), display_name NVARCHAR(180));
DECLARE @email NVARCHAR(254), @displayName NVARCHAR(180), @role NVARCHAR(30),
        @salt VARBINARY(32), @hash VARBINARY(64), @newId BIGINT, @roleId BIGINT;
BEGIN TRY
  BEGIN TRAN;
  DECLARE staff_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT email,display_name,role_code,salt,[hash] FROM @Accounts ORDER BY role_code;
  OPEN staff_cursor;
  FETCH NEXT FROM staff_cursor INTO @email,@displayName,@role,@salt,@hash;
  WHILE @@FETCH_STATUS=0
  BEGIN
    IF EXISTS(SELECT 1 FROM dbo.app_user WITH(UPDLOCK,HOLDLOCK) WHERE email=@email)
      THROW 59416,N'Email became occupied concurrently; whole batch rolls back',1;
    SELECT @roleId=id FROM dbo.role WHERE role_code=@role;
    IF @roleId IS NULL THROW 59417,N'Role missing',1;
    INSERT dbo.app_user(display_name,email,account_status,created_at)
      VALUES(@displayName,@email,N'active',SYSUTCDATETIME());
    SET @newId=CONVERT(BIGINT,SCOPE_IDENTITY());
    INSERT dbo.auth_credential(user_id,password_salt,password_hash) VALUES(@newId,@salt,@hash);
    INSERT dbo.user_role(user_id,role_id,granted_at) VALUES(@newId,@roleId,SYSUTCDATETIME());
    INSERT @Created(user_id,email,role_code,display_name) VALUES(@newId,@email,@role,@displayName);
    FETCH NEXT FROM staff_cursor INTO @email,@displayName,@role,@salt,@hash;
  END;
  CLOSE staff_cursor;
  DEALLOCATE staff_cursor;
  SELECT @Apply AS ApplyMode,user_id AS NewUserId,display_name AS DisplayName,
         email AS Email,role_code AS AssignedRole,
         CASE WHEN @Apply=1 THEN N'WILL_COMMIT' ELSE N'PREVIEW_WILL_ROLLBACK' END AS TransactionOutcome
  FROM @Created ORDER BY role_code;
  IF @Apply=1
  BEGIN
    COMMIT;
    PRINT N'APPLIED: new staff accounts created with isolated roles. No content changed.';
  END
  ELSE
  BEGIN
    ROLLBACK;
    PRINT N'PREVIEW: all staff account changes ROLLED BACK.';
  END;
END TRY
BEGIN CATCH
  IF CURSOR_STATUS('local','staff_cursor') >= -1
  BEGIN
    IF CURSOR_STATUS('local','staff_cursor') > -1 CLOSE staff_cursor;
    DEALLOCATE staff_cursor;
  END;
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
END CATCH;
GO

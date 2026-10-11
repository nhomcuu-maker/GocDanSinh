-- GOC DAN SINH: NEW REVIEWER ACCOUNT (scrypt N=16384,r=8,p=1)
-- Generated on local PC; never contains the plaintext password.
-- Open SSMS, check database backup, run @Apply=0 first; then set @Apply=1.
-- It creates only ONE new reviewer user and login credentials; no admin/publisher role.
USE [GocDanSinh];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @Apply BIT = 1;
DECLARE @Email NVARCHAR(254) = CONVERT(NVARCHAR(254), 0x6c006500760061006e006100400067006d00610069006c002e0063006f006d00, 0);
DECLARE @DisplayName NVARCHAR(180) = CONVERT(NVARCHAR(180), 0x4c0065002000560061006e0020004100, 0);
DECLARE @Salt VARBINARY(32) = 0xa8246611fcfe8731560e6719b19786e1db0e6e907d4a706c4d59f04405f69644;
DECLARE @PasswordHash VARBINARY(64) = 0xaa17166d3ac9b57e5307e4734df56821f25e33c940799034c69a0928034976a5c1a3201e760bc2c8c003f2c12049848a447e88e0704890129b7987b5ce22d7e6;
DECLARE @ReviewerRoleId BIGINT;
DECLARE @NewUserId BIGINT;
IF DB_NAME() <> N'GocDanSinh' THROW 59300, N'Incorrect database', 1;
IF OBJECT_ID(N'dbo.app_user',N'U') IS NULL OR OBJECT_ID(N'dbo.auth_credential',N'U') IS NULL OR
   OBJECT_ID(N'dbo.[role]',N'U') IS NULL OR OBJECT_ID(N'dbo.user_role',N'U') IS NULL
   THROW 59301, N'Application authentication tables are missing', 1;
IF DATALENGTH(@Salt)<>32 OR DATALENGTH(@PasswordHash)<>64
   THROW 59302, N'Invalid scrypt salt/hash byte lengths', 1;
IF EXISTS (SELECT 1 FROM dbo.app_user WHERE email=@Email)
   THROW 59303, N'Account email already exists: use a DIFFERENT real email; no existing user is modified', 1;
SELECT @ReviewerRoleId=id FROM dbo.[role] WHERE role_code=N'reviewer';
IF @ReviewerRoleId IS NULL THROW 59304, N'Reviewer role not found', 1;
BEGIN TRY
  BEGIN TRAN;
  IF EXISTS (SELECT 1 FROM dbo.app_user WITH(UPDLOCK,HOLDLOCK) WHERE email=@Email)
      THROW 59305, N'Email became occupied concurrently', 1;
  INSERT dbo.app_user(display_name,email,account_status,created_at)
      VALUES(@DisplayName,@Email,N'active',SYSUTCDATETIME());
  SET @NewUserId=CONVERT(BIGINT,SCOPE_IDENTITY());
  INSERT dbo.auth_credential(user_id,password_salt,password_hash)
      VALUES(@NewUserId,@Salt,@PasswordHash);
  INSERT dbo.user_role(user_id,role_id,granted_at)
      VALUES(@NewUserId,@ReviewerRoleId,SYSUTCDATETIME());
  SELECT @Apply AS ApplyMode, @NewUserId AS NewUserId, @DisplayName AS DisplayName,
         @Email AS Email, N'reviewer' AS AssignedRole,
         CASE WHEN @Apply=1 THEN N'WILL_COMMIT' ELSE N'PREVIEW_WILL_ROLLBACK' END AS TransactionOutcome;
  IF @Apply=1 BEGIN
      COMMIT;
      PRINT N'APPLIED: reviewer account and scrypt credential saved.';
  END ELSE BEGIN
      ROLLBACK;
      PRINT N'PREVIEW: reviewer account creation ROLLED BACK.';
  END;
END TRY
BEGIN CATCH
  IF @@TRANCOUNT>0 ROLLBACK;
  THROW;
END CATCH;
GO

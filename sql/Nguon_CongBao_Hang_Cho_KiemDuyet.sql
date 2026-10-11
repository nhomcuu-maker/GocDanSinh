/* GOCDANSINH - SQL INBOX ONLY, never updates accepted evidence or public content.
   Execute in SSMS AFTER backing up the database. @Apply=0 means ROLLBACK preview. */
USE [GocDanSinh];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @Apply BIT = 0;
IF DB_NAME() <> N'GocDanSinh' THROW 59101,N'Wrong database.',1;
BEGIN TRY
 BEGIN TRANSACTION;
 IF OBJECT_ID(N'dbo.official_feed_entry',N'U') IS NULL
 BEGIN
  CREATE TABLE dbo.official_feed_entry(
   id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
   source_key NVARCHAR(80) NOT NULL,
   entry_uid BINARY(32) NOT NULL,
   canonical_url NVARCHAR(1200) NOT NULL,
   first_seen_at DATETIME2(3) NOT NULL,
   last_seen_at DATETIME2(3) NOT NULL,
   CONSTRAINT UX_gds_official_feed_entry UNIQUE(source_key,entry_uid)
  );
 END;
 IF OBJECT_ID(N'dbo.official_feed_snapshot',N'U') IS NULL
 BEGIN
  CREATE TABLE dbo.official_feed_snapshot(
   id BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
   entry_id BIGINT NOT NULL,
   metadata_sha256 BINARY(32) NOT NULL,
   title NVARCHAR(450) NOT NULL,
   description NVARCHAR(1200) NULL,
   published_at DATETIME2(3) NULL,
   captured_at DATETIME2(3) NOT NULL,
   review_status NVARCHAR(20) NOT NULL CONSTRAINT DF_gds_feed_pending DEFAULT N'pending_review',
   CONSTRAINT FK_gds_feed_snapshot_entry FOREIGN KEY(entry_id) REFERENCES dbo.official_feed_entry(id),
   CONSTRAINT CK_gds_feed_review_pending CHECK(review_status=N'pending_review'),
   CONSTRAINT UX_gds_feed_snapshot_unique UNIQUE(entry_id,metadata_sha256)
  );
 END;
 SELECT @Apply AS ApplyMode,
        N'official_feed_entry and official_feed_snapshot' AS Objects,
        N'Pending-only. No joins to knowledge_version_source; no automatic publishing.' AS SafetyPolicy;
 IF @Apply=1 BEGIN COMMIT TRANSACTION; PRINT N'APPLIED: official RSS inbox tables created if missing.'; END
 ELSE BEGIN ROLLBACK TRANSACTION; PRINT N'PREVIEW: ALL DDL ROLLED BACK. Set @Apply=1 only after backup.'; END
END TRY
BEGIN CATCH
 IF XACT_STATE()<>0 ROLLBACK TRANSACTION;
 THROW;
END CATCH;

/*
GOC DAN SINH - SAFELY REMOVE INCORRECT EVIDENCE LINK (VERSION 4 / SNAPSHOT 9)
Run ONLY after registering the SAME PDF to source_id=13 through Admin.
No verification or publication is performed here.
@Apply=0: preview and rollback; @Apply=1: commit after backup and review.
The original file_asset, source_snapshot 9, source and moderation history are preserved.
*/
USE [GocDanSinh];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
DECLARE @Apply BIT = 1;
DECLARE @VersionId BIGINT = 4;
DECLARE @WrongSnapshotId BIGINT = 9;
DECLARE @WrongSourceId BIGINT = 12;
DECLARE @CorrectSourceId BIGINT = 13;
DECLARE @CorrectSnapshotId BIGINT;
DECLARE @WrongHash VARBINARY(32);
DECLARE @WrongAsset BIGINT;

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (
        SELECT 1 FROM dbo.knowledge_version WITH (UPDLOCK, HOLDLOCK)
        WHERE id = @VersionId AND editorial_status IN (N'draft', N'rejected')
    ) THROW 59401, N'Bai viet khong con o trang thai draft/rejected. Dung lai.', 1;

    SELECT @WrongHash = ss.content_sha256, @WrongAsset = ss.file_asset_id
    FROM dbo.knowledge_version_source AS kvs WITH (UPDLOCK, HOLDLOCK)
    JOIN dbo.source_snapshot AS ss ON ss.id = kvs.snapshot_id
    WHERE kvs.version_id = @VersionId
      AND kvs.snapshot_id = @WrongSnapshotId
      AND ss.source_id = @WrongSourceId;

    IF @WrongHash IS NULL OR @WrongAsset IS NULL
        THROW 59402, N'Khong con lien ket sai version=4, snapshot=9, source=12 hoac thieu tai san. Dung lai.', 1;

    IF @WrongHash <> 0x275EE8C277AD2AC2FCEEC3F17374224C56BA0CCA9290A93DB3BAECDA2853E8C9
        THROW 59403, N'SHA-256 cua snapshot sai khong trung PDF da doi chieu. Dung lai.', 1;

    SELECT TOP (1) @CorrectSnapshotId = ss.id
    FROM dbo.knowledge_version_source AS kvs WITH (UPDLOCK, HOLDLOCK)
    JOIN dbo.source_snapshot AS ss ON ss.id = kvs.snapshot_id
    JOIN dbo.[source] AS s ON s.id = ss.source_id
    WHERE kvs.version_id = @VersionId
      AND ss.source_id = @CorrectSourceId
      AND ss.content_sha256 = @WrongHash
      AND ss.file_asset_id = @WrongAsset
      AND s.canonical_url LIKE N'%24971%'
    ORDER BY ss.id;

    IF @CorrectSnapshotId IS NULL
        THROW 59404, N'Chua co snapshot moi cua cung file lien ket voi source=13, URL 24971. Dung lai.', 1;

    IF EXISTS (SELECT 1 FROM dbo.source_verification WHERE source_snapshot_id = @WrongSnapshotId)
        THROW 59405, N'Snapshot sai da co lich su xac minh: can xu ly theo quy trinh kiem duyet.', 1;

    IF EXISTS (SELECT 1 FROM dbo.scam_indicator
               WHERE version_id = @VersionId AND evidence_snapshot_id = @WrongSnapshotId)
        THROW 59406, N'Mot scam_indicator dang su dung snapshot sai. Can doi chieu truoc.', 1;

    IF EXISTS (SELECT 1 FROM dbo.knowledge_version_chunk
               WHERE version_id = @VersionId AND snapshot_id = @WrongSnapshotId)
        THROW 59407, N'Mot content chunk dang su dung snapshot sai. Can doi chieu truoc.', 1;

    SELECT N'BEFORE' AS phase, kvs.version_id, kvs.snapshot_id, ss.source_id,
           s.title AS source_title, CONVERT(VARCHAR(64), ss.content_sha256, 2) AS sha256
    FROM dbo.knowledge_version_source AS kvs
    JOIN dbo.source_snapshot AS ss ON ss.id = kvs.snapshot_id
    JOIN dbo.[source] AS s ON s.id = ss.source_id
    WHERE kvs.version_id = @VersionId ORDER BY kvs.snapshot_id;

    DELETE FROM dbo.knowledge_version_source
    WHERE version_id = @VersionId AND snapshot_id = @WrongSnapshotId;
    IF @@ROWCOUNT <> 1
        THROW 59408, N'Khong xoa duoc dung mot lien ket sai. Dung lai.', 1;

    SELECT @Apply AS ApplyMode,
           @CorrectSnapshotId AS CorrectSnapshotId,
           @WrongSnapshotId AS WrongLinkRemovedInTransaction,
           N'Original snapshot, file, source and moderation history remain untouched' AS Safety;

    SELECT N'AFTER_IN_TRANSACTION' AS phase, kvs.version_id, kvs.snapshot_id,
           ss.source_id, s.title AS source_title,
           CONVERT(VARCHAR(64), ss.content_sha256, 2) AS sha256
    FROM dbo.knowledge_version_source AS kvs
    JOIN dbo.source_snapshot AS ss ON ss.id = kvs.snapshot_id
    JOIN dbo.[source] AS s ON s.id = ss.source_id
    WHERE kvs.version_id = @VersionId ORDER BY kvs.snapshot_id;

    IF @Apply = 1
    BEGIN
        COMMIT TRANSACTION;
        PRINT N'APPLIED: removed ONLY version=4 / snapshot=9 evidence link. Did not verify or publish.';
    END
    ELSE
    BEGIN
        ROLLBACK TRANSACTION;
        PRINT N'PREVIEW: rolled back. Check results, backup DB, then change @Apply=1 to commit.';
    END
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

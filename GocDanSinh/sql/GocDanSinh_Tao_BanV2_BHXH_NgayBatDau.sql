/*
 GOC DAN SINH - CREATE A SAFE SUCCESSOR DRAFT FOR SCAM ARTICLE #4.
 The existing approved version is IMMUTABLE by trigger 53005.
 This script DOES NOT publish or approve. It creates a successor draft
 with the same reviewed evidence snapshot #10 and an explicit display-start date.

 HOW TO USE:
   1. Keep @Apply=0. Run in SSMS and inspect Results/Messages (ROLLBACK).
   2. Back up database, confirm the original article, date and source.
   3. Set @Apply=1 and run once; keep the new version ID from output.
   4. Open NEW draft in Admin as the original editor; review/correct statements,
      submit; a different real reviewer must approve, and a different publisher
      must publish. Do not change the original approved version #4.

 @NewEffectiveFrom = today in Viet Nam; this is the ARTICLE'S DISPLAY/USAGE
 START DATE for SCAM, NOT the legal effective date of any law.
*/
USE [GocDanSinh];
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @Apply BIT = 1; -- 0 PREVIEW ROLLBACK, 1 APPLY
DECLARE @OriginalVersionId BIGINT = 4;
DECLARE @ExpectedSnapshotId BIGINT = 10;
DECLARE @ExpectedSourceId BIGINT = 13;
DECLARE @NewEffectiveFrom DATE = CONVERT(DATE, DATEADD(HOUR, 7, SYSUTCDATETIME()));

DECLARE @ItemId BIGINT, @CreatorId BIGINT, @OldStatus NVARCHAR(24),
        @OldEffectiveFrom DATE, @OldEffectiveTo DATE, @Kind NVARCHAR(20), @DomainCode NVARCHAR(24),
        @NewVersionId BIGINT, @NewVersionNo INT, @LockResult INT,
        @Now DATETIME2(3) = SYSUTCDATETIME(), @LockName NVARCHAR(255);

BEGIN TRY
    BEGIN TRANSACTION;

    SELECT @ItemId=v.item_id, @CreatorId=v.created_by,
           @OldStatus=v.editorial_status, @OldEffectiveFrom=v.effective_from, @OldEffectiveTo=v.effective_to,
           @Kind=i.kind, @DomainCode=d.code
    FROM dbo.knowledge_version v WITH (UPDLOCK, HOLDLOCK)
    JOIN dbo.knowledge_item i ON i.id=v.item_id
    JOIN dbo.domain d ON d.id=i.domain_id
    WHERE v.id=@OriginalVersionId AND i.business_code=N'GDS-MVP-SCAM-MAODANH-BHXH'
      AND i.deleted_at IS NULL;

    IF @ItemId IS NULL OR @Kind<>N'scam' OR @DomainCode<>N'SCAM'
        THROW 59601, N'Original article #4 or SCAM business code does not match; stop.', 1;
    IF @OldStatus<>N'approved' OR @OldEffectiveFrom IS NOT NULL
        THROW 59602, N'Expected original approved article with NULL effective_from; stop.', 1;
    IF @NewEffectiveFrom IS NULL OR @NewEffectiveFrom>CONVERT(DATE, DATEADD(HOUR,7,SYSUTCDATETIME()))
        THROW 59603, N'Invalid or future display-start date.', 1;

    IF @OldEffectiveTo IS NOT NULL AND @NewEffectiveFrom>=@OldEffectiveTo
        THROW 59609, N'Original version end date conflicts with new start date.', 1;

    SET @LockName=CONCAT(N'gocdansinh:item:',CONVERT(NVARCHAR(30),@ItemId));
    EXEC @LockResult=sys.sp_getapplock @Resource=@LockName,
        @LockMode='Exclusive', @LockOwner='Transaction', @LockTimeout=15000;
    IF @LockResult<0 THROW 59604, N'Could not lock article for version creation.', 1;

    IF EXISTS(SELECT 1 FROM dbo.knowledge_version WHERE item_id=@ItemId AND supersedes_version_id=@OriginalVersionId)
        THROW 59605, N'A successor version already exists; inspect it instead of duplicating.', 1;

    IF (SELECT COUNT(*) FROM dbo.knowledge_version_source WHERE version_id=@OriginalVersionId)<>1
       OR NOT EXISTS (
          SELECT 1 FROM dbo.knowledge_version_source kvs
          JOIN dbo.source_snapshot ss ON ss.id=kvs.snapshot_id
          JOIN dbo.source s ON s.id=ss.source_id
          OUTER APPLY (
              SELECT TOP(1) decision,valid_until FROM dbo.source_verification v
              WHERE v.source_snapshot_id=ss.id AND v.verified_at<=SYSUTCDATETIME()
              ORDER BY v.verified_at DESC,v.id DESC
          ) verification
          WHERE kvs.version_id=@OriginalVersionId AND kvs.snapshot_id=@ExpectedSnapshotId
            AND ss.source_id=@ExpectedSourceId
            AND CONVERT(VARCHAR(64),ss.content_sha256,2)='275EE8C277AD2AC2FCEEC3F17374224C56BA0CCA9290A93DB3BAECDA2853E8C9'
            AND s.canonical_url LIKE N'%itemID=24971%'
            AND verification.decision=N'accepted'
            AND (verification.valid_until IS NULL OR verification.valid_until>SYSUTCDATETIME())
       ) THROW 59606, N'Snapshot #10 is not the sole, currently accepted evidence of source #13.', 1;

    IF NOT EXISTS(SELECT 1 FROM dbo.item_scope WHERE version_id=@OriginalVersionId)
       OR NOT EXISTS(SELECT 1 FROM dbo.scam_detail WHERE version_id=@OriginalVersionId)
       OR NOT EXISTS(SELECT 1 FROM dbo.scam_indicator WHERE version_id=@OriginalVersionId)
        THROW 59607, N'Original article lacks subtype or scope; stop.', 1;

    IF EXISTS (
       SELECT 1 FROM dbo.scam_indicator si
       WHERE si.version_id=@OriginalVersionId AND si.evidence_snapshot_id IS NOT NULL
         AND NOT EXISTS(SELECT 1 FROM dbo.knowledge_version_source kvs
           WHERE kvs.version_id=@OriginalVersionId AND kvs.snapshot_id=si.evidence_snapshot_id)
    ) THROW 59608, N'Indicator cites a nonlinked snapshot; review before cloning.', 1;

    SELECT @NewVersionNo=ISNULL(MAX(version_no),0)+1
    FROM dbo.knowledge_version WITH (UPDLOCK,HOLDLOCK) WHERE item_id=@ItemId;

    INSERT INTO dbo.knowledge_version
      (item_id,version_no,title,summary,body_markdown,editorial_status,
       effective_from,effective_to,approved_at,approved_by,published_at,
       withdrawn_at,supersedes_version_id,content_sha256,created_by,created_at)
    SELECT item_id,@NewVersionNo,title,summary,body_markdown,N'draft',
           @NewEffectiveFrom,effective_to,NULL,NULL,NULL,NULL,
           @OriginalVersionId,content_sha256,created_by,@Now
    FROM dbo.knowledge_version WHERE id=@OriginalVersionId;
    SET @NewVersionId=CONVERT(BIGINT,SCOPE_IDENTITY());

    INSERT INTO dbo.item_scope(version_id,scope_kind,admin_unit_id,scope_note)
      SELECT @NewVersionId,scope_kind,admin_unit_id,scope_note
      FROM dbo.item_scope WHERE version_id=@OriginalVersionId;

    INSERT INTO dbo.knowledge_version_source(version_id,snapshot_id,evidence_role,locator)
      SELECT @NewVersionId,snapshot_id,evidence_role,locator
      FROM dbo.knowledge_version_source WHERE version_id=@OriginalVersionId;

    INSERT INTO dbo.scam_detail(version_id,severity,mechanism,warning_signs,immediate_actions,reporting_guidance)
      SELECT @NewVersionId,severity,mechanism,warning_signs,immediate_actions,reporting_guidance
      FROM dbo.scam_detail WHERE version_id=@OriginalVersionId;

    INSERT INTO dbo.scam_indicator(version_id,indicator_no,indicator_kind,description,evidence_snapshot_id)
      SELECT @NewVersionId,indicator_no,indicator_kind,description,evidence_snapshot_id
      FROM dbo.scam_indicator WHERE version_id=@OriginalVersionId;

    -- Audit this privileged maintenance action as a database operation, NOT as a
    -- forged editorial/reviewer decision. The creator attribution of the copied
    -- content remains unchanged, but approval of the new version must be fresh.
    DECLARE @AuditJson NVARCHAR(MAX) = (
        SELECT @OriginalVersionId AS original_version_id,
               @NewVersionId AS new_version_id,
               CONVERT(VARCHAR(10),@NewEffectiveFrom,23) AS display_start_date,
               ORIGINAL_LOGIN() AS database_login,
               N'approved source had no start date; successor created as draft; no approval or publication' AS reason
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    );
    INSERT dbo.audit_log(actor_id,entity_name,entity_id,action,change_json,occurred_at,entry_sha256)
    VALUES(NULL,N'knowledge_version',@NewVersionId,N'clone_approved_to_draft',@AuditJson,@Now,
           HASHBYTES('SHA2_256',CONVERT(VARBINARY(MAX),@AuditJson)));

    SELECT @Apply AS ApplyMode, @OriginalVersionId AS OriginalApprovedVersionId,
           @NewVersionId AS NewDraftVersionId, @NewVersionNo AS NewVersionNo,
           @NewEffectiveFrom AS DisplayStartDate, N'draft' AS NewStatus,
           (SELECT COUNT(*) FROM dbo.knowledge_version_source WHERE version_id=@NewVersionId) AS LinkedSnapshots,
           (SELECT COUNT(*) FROM dbo.scam_indicator WHERE version_id=@NewVersionId) AS Indicators,
           N'No approval or publication. Original approved version unchanged.' AS Safety;

    IF @Apply=1
    BEGIN
      COMMIT TRANSACTION;
      PRINT 'APPLIED: new SCAM draft created; author/editor must review, submit and obtain fresh independent approval.';
    END
    ELSE
    BEGIN
      ROLLBACK TRANSACTION;
      PRINT 'PREVIEW ONLY: all changes rolled back. Backup DB, set @Apply=1 to create the draft.';
    END
END TRY
BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO



USE [GocDanSinh];
GO

SELECT
    id,
    editorial_status,
    effective_from,
    approved_by,
    published_at
FROM dbo.knowledge_version
WHERE id IN (4, 6);

SELECT
    version_id,
    snapshot_id,
    evidence_role
FROM dbo.knowledge_version_source
WHERE version_id = 6;
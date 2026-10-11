USE [GocDanSinh];
GO

SELECT
    t.name AS TableName,
    COUNT(c.column_id) AS ColumnCount
FROM sys.tables AS t
JOIN sys.columns AS c
    ON c.object_id = t.object_id
WHERE t.name IN (
    'official_feed_entry',
    'official_feed_snapshot'
)
GROUP BY t.name
ORDER BY t.name;



USE [GocDanSinh];
GO

SELECT
    (SELECT COUNT(*) FROM dbo.official_feed_entry)
        AS TotalEntries,
    (SELECT COUNT(*) FROM dbo.official_feed_snapshot)
        AS TotalSnapshots,
    (SELECT COUNT(*)
     FROM dbo.official_feed_snapshot
     WHERE review_status = N'pending_review')
        AS PendingReview;

SELECT TOP (5)
    s.title,
    s.published_at,
    s.review_status,
    e.canonical_url
FROM dbo.official_feed_snapshot AS s
JOIN dbo.official_feed_entry AS e
    ON e.id = s.entry_id
ORDER BY s.id DESC;



USE [GocDanSinh];
GO

SELECT
    t.name AS TenBang,
    c.column_id AS STT,
    c.name AS TenCot,
    TYPE_NAME(c.user_type_id) AS KieuDuLieu
FROM sys.tables AS t
JOIN sys.columns AS c
    ON c.object_id = t.object_id
WHERE
    (
        t.name LIKE '%source%'
        OR t.name LIKE '%evidence%'
        OR t.name LIKE '%snapshot%'
        OR t.name LIKE '%link%'
    )
    AND t.name NOT IN (
        'official_feed_entry',
        'official_feed_snapshot'
    )
ORDER BY
    t.name,
    c.column_id;



	USE [GocDanSinh];
GO

-- A. Nguon BHXH hien co
SELECT
    id AS source_id,
    title,
    canonical_url,
    source_kind,
    trust_tier
FROM dbo.source
WHERE canonical_url LIKE N'%baohiemxahoi.gov.vn%'
ORDER BY id;

-- B. Nguon da gan vao danh sach ung vien
SELECT
    k.item_id,
    k.source_id,
    s.title,
    s.canonical_url,
    k.review_status,
    k.review_note
FROM dbo.knowledge_source_candidate AS k
JOIN dbo.source AS s
    ON s.id = k.source_id
ORDER BY k.item_id, k.source_id;

-- C. Snapshot va ket qua xac minh nguon BHXH
SELECT
    s.id AS source_id,
    ss.id AS snapshot_id,
    ss.captured_at,
    ss.capture_method,
    ss.file_asset_id,
    CONVERT(VARCHAR(64), ss.content_sha256, 2)
        AS content_sha256,
    sv.decision,
    sv.verified_at,
    sv.valid_until
FROM dbo.source AS s
LEFT JOIN dbo.source_snapshot AS ss
    ON ss.source_id = s.id
LEFT JOIN dbo.source_verification AS sv
    ON sv.source_snapshot_id = ss.id
WHERE s.canonical_url LIKE N'%baohiemxahoi.gov.vn%'
ORDER BY s.id, ss.id;



USE [GocDanSinh];
GO

SELECT
    ss.id AS snapshot_id,
    s.id AS source_id,
    s.title,
    s.canonical_url,
    CONVERT(VARCHAR(64), ss.content_sha256, 2) AS sha256,
    kvs.version_id,
    kvs.evidence_role,
    kvs.locator
FROM dbo.source_snapshot AS ss
JOIN dbo.source AS s
    ON s.id = ss.source_id
LEFT JOIN dbo.knowledge_version_source AS kvs
    ON kvs.snapshot_id = ss.id
WHERE ss.id = 9;


USE [GocDanSinh];
GO

SELECT
    ss.id AS snapshot_id,
    s.id AS source_id,
    s.title,
    s.canonical_url,
    CONVERT(VARCHAR(64), ss.content_sha256, 2) AS sha256,
    kvs.version_id,
    kvs.evidence_role
FROM dbo.source_snapshot AS ss
JOIN dbo.source AS s
    ON s.id = ss.source_id
LEFT JOIN dbo.knowledge_version_source AS kvs
    ON kvs.snapshot_id = ss.id
WHERE
    ss.id = 9
    OR s.id = 13
    OR kvs.version_id = 4
ORDER BY ss.id DESC;



USE [GocDanSinh];
GO

SELECT
    kvs.version_id,
    ss.id AS snapshot_id,
    ss.source_id,
    s.title,
    kvs.evidence_role
FROM dbo.knowledge_version_source AS kvs
JOIN dbo.source_snapshot AS ss
    ON ss.id = kvs.snapshot_id
JOIN dbo.source AS s
    ON s.id = ss.source_id
WHERE kvs.version_id = 4;


USE [GocDanSinh];
GO

SELECT
    id,
    title,
    editorial_status,
    effective_from,
    created_by,
    approved_by,
    approved_at,
    published_at
FROM dbo.knowledge_version
WHERE id = 4;


--Kiểm tra gmail--
USE [GocDanSinh];
GO

SELECT
    u.id AS UserID,
    u.display_name AS HoTen,
    u.email AS Email,
    u.account_status AS TrangThai,
    r.role_code AS VaiTro
FROM dbo.app_user AS u
JOIN dbo.user_role AS ur
    ON ur.user_id = u.id
JOIN dbo.[role] AS r
    ON r.id = ur.role_id

ORDER BY u.id;



USE [GocDanSinh];
GO

SELECT
    v.id AS VersionID,
    v.title AS TieuDe,
    v.editorial_status AS TrangThai,
    v.effective_from AS NgayApDung,

    COUNT(DISTINCT kvs.snapshot_id) AS SoChungCu,

    COUNT(DISTINCT CASE
        WHEN sv.decision = N'accepted'
         AND (sv.valid_until IS NULL
              OR sv.valid_until >= SYSUTCDATETIME())
        THEN kvs.snapshot_id
    END) AS ChungCuHopLe,

    CASE
        WHEN v.effective_from IS NULL
            THEN N'THIEU NGAY AP DUNG'

        WHEN COUNT(DISTINCT kvs.snapshot_id) = 0
            THEN N'THIEU CHUNG CU'

        WHEN COUNT(DISTINCT CASE
            WHEN sv.decision = N'accepted'
             AND (sv.valid_until IS NULL
                  OR sv.valid_until >= SYSUTCDATETIME())
            THEN kvs.snapshot_id
        END) = 0
            THEN N'CAN XAC MINH CHUNG CU'

        WHEN v.editorial_status = N'published'
            THEN N'DA CONG BO'

        ELSE N'CAN KIEM TRA VA KIEM DUYET'
    END AS DanhGiaTuDong

FROM dbo.knowledge_version v

LEFT JOIN dbo.knowledge_version_source kvs
    ON kvs.version_id = v.id

LEFT JOIN dbo.source_verification sv
    ON sv.id = (
        SELECT TOP (1) sv2.id
        FROM dbo.source_verification sv2
        WHERE sv2.source_snapshot_id = kvs.snapshot_id
        ORDER BY sv2.verified_at DESC, sv2.id DESC
    )

GROUP BY
    v.id,
    v.title,
    v.editorial_status,
    v.effective_from

ORDER BY v.id;
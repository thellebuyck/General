use master
go
if not exists(select 1 from sys.procedures p where p.name ='GetTableIndexInformation')
begin
	exec ('Create procedure dbo.GetTableIndexInformation as select 1')
	print 'procedure GetTableIndexInformation created'
end
go

alter procedure dbo.GetTableIndexInformation

  @objname NVARCHAR(776)

AS
/*
  2015-10-08  MMS   Created
	2017-03-10	MMS		Fixed issue with pulling index usage from other DBs with same index id
*/
SET NOCOUNT ON;

DECLARE @objid INT
SELECT @objid = OBJECT_ID(@objname)
IF @objid IS NULL
BEGIN
  RAISERROR('Invalid object name %s', 16, 1, @objname)
  SET NOEXEC ON
END

DECLARE @defaultFillFactor TINYINT
SELECT @defaultFillFactor = CONVERT(TINYINT, value)
FROM sys.configurations AS c WITH (NOLOCK)
WHERE name = 'fill factor (%)'

SELECT
  STUFF((
    SELECT
      ', '
        + CASE WHEN is_descending_key = 1 THEN '(-)' ELSE '' END
        + c.name
    FROM sys.index_columns AS ic
    JOIN sys.columns AS c
      ON c.object_id = ic.object_id
      AND c.column_id = ic.column_id
    WHERE ic.object_id = i.object_id
      AND ic.index_id = i.index_id
      AND ic.is_included_column = 0
    ORDER BY ic.index_column_id
    FOR XML PATH('')
  ),1,2,'') AS 'index_columns',
  STUFF((
    SELECT
      ', '
        + CASE WHEN is_descending_key = 1 THEN '(-)' ELSE '' END
        + c.name
    FROM sys.index_columns AS ic
    JOIN sys.columns AS c
      ON c.object_id = ic.object_id
      AND c.column_id = ic.column_id
    WHERE ic.object_id = i.object_id
      AND ic.index_id = i.index_id
      AND ic.is_included_column = 1
    ORDER BY ic.index_column_id
    FOR XML PATH('')
  ),1,2,'') AS 'included_columns',
  i.filter_definition,
  (
    CASE WHEN i.is_disabled = 1 THEN '[DISABLED] ' ELSE '' END
    + i.[type_desc] 
    + CASE WHEN i.[ignore_dup_key] = 1 THEN ', IGNORE_DUP_KEY' ELSE '' END
    + CASE WHEN i.is_primary_key = 1 THEN ', PRIMARY_KEY' ELSE '' END
    + CASE WHEN i.is_unique_constraint = 1 OR i.is_unique = 1 THEN ', UNIQUE' ELSE '' END
    + CASE WHEN i.fill_factor <> @defaultFillFactor THEN ', FILL_FACTOR=' + CONVERT(VARCHAR(MAX), i.fill_factor) + '%' ELSE '' END
    + CASE WHEN i.is_padded = 1 THEN ', PADDED' ELSE '' END
    + CASE WHEN i.is_hypothetical = 1 THEN ', HYPOTHETICAL' ELSE '' END
    + CASE WHEN i.allow_row_locks = 0 THEN ', NO ROW LOCKS' ELSE '' END
    + CASE WHEN i.allow_page_locks = 0 THEN ', NO PAGE LOCKS' ELSE '' END
  ) AS 'options',
  (
    SELECT
      CONVERT(VARCHAR(MAX), COUNT(*)) + '-' + p.data_compression_desc + ' '
    FROM sys.partitions AS p
    WHERE p.object_id = i.object_id
      AND p.index_id = i.index_id
    GROUP BY p.data_compression_desc
    FOR XML PATH('')
  ) AS 'partition_compression',
  CASE
    WHEN fg.data_space_id IS NOT NULL THEN
      fg.name + ' (' + fg.type_desc + CASE WHEN fg.is_read_only = 1 THEN '-READONLY' ELSE '' END + ')'
    ELSE
      ps.name COLLATE Latin1_General_CI_AS_KS_WS + ': ' + pf.name + ' (' + pf.type_desc + ') fanout=' + CONVERT(VARCHAR(MAX), pf.fanout) + ', boundary_value_on_right=' + CONVERT(VARCHAR(MAX), pf.boundary_value_on_right)
  END AS 'storage',
  STATS_DATE(i.object_id, i.index_id) AS 'stats_date',
  i.name,
  i.index_id,
  dm_ius.user_seeks AS UserSeek,
  dm_ius.user_scans AS UserScans,
  dm_ius.user_lookups AS UserLookups,
  dm_ius.user_updates AS UserUpdates
	
FROM sys.indexes AS i
JOIN sys.stats AS s
  ON i.object_id = s.object_id
  AND i.index_id = s.stats_id
LEFT JOIN sys.filegroups AS fg
  ON fg.data_space_id = i.data_space_id
LEFT JOIN sys.partition_schemes AS ps
  ON ps.data_space_id = i.data_space_id
LEFT JOIN sys.partition_functions AS pf
  ON pf.function_id = ps.function_id
LEFT JOIN sys.dm_db_index_usage_stats dm_ius
	ON dm_ius.index_id = i.index_id
	AND dm_ius.OBJECT_ID = i.OBJECT_ID
	AND dm_ius.database_id = DB_ID()
WHERE i.object_id = @objid


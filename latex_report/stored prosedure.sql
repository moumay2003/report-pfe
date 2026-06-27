CREATE OR REPLACE PROCEDURE PLATFORM_CONFIG_DB.OPS.SYNC_SHARED_SCHEMA_TO_TARGET("SOURCE_SCHEMA" VARCHAR, "TARGET_SCHEMA" VARCHAR, "EXCLUDE_TABLES" VARCHAR DEFAULT '')
RETURNS TABLE ("TABLE_NAME" VARCHAR, "ACTION" VARCHAR, "COLUMN_NAME" VARCHAR, "SOURCE_DATA_TYPE" VARCHAR, "TARGET_DATA_TYPE" VARCHAR, "SOURCE_NULLABLE" VARCHAR, "TARGET_NULLABLE" VARCHAR, "STATUS" VARCHAR)
LANGUAGE SQL
EXECUTE AS OWNER
AS 'DECLARE
    SRC_DB VARCHAR;
    SRC_SCH VARCHAR;
    TGT_DB VARCHAR;
    TGT_SCH VARCHAR;
    SQL_TEXT VARCHAR;
    TBL_NAME VARCHAR;
    MISMATCH_COUNT INTEGER;
    RES RESULTSET;
    RES2 RESULTSET;
    FINAL_RES RESULTSET;
BEGIN
    SRC_DB := SPLIT_PART(:SOURCE_SCHEMA, ''.'', 1);
    SRC_SCH := SPLIT_PART(:SOURCE_SCHEMA, ''.'', 2);
    TGT_DB := SPLIT_PART(:TARGET_SCHEMA, ''.'', 1);
    TGT_SCH := SPLIT_PART(:TARGET_SCHEMA, ''.'', 2);

    LET EXCLUDE_FILTER VARCHAR := '''';
    LET EXCLUDE_FILTER_ALIASED VARCHAR := '''';
    IF (:EXCLUDE_TABLES IS NOT NULL AND :EXCLUDE_TABLES != '''') THEN
        EXCLUDE_FILTER := '' AND TABLE_NAME NOT IN (SELECT UPPER(TRIM(VALUE)) FROM TABLE(SPLIT_TO_TABLE('''''' || :EXCLUDE_TABLES || '''''', '''','''')))'';        
        EXCLUDE_FILTER_ALIASED := '' AND s.TABLE_NAME NOT IN (SELECT UPPER(TRIM(VALUE)) FROM TABLE(SPLIT_TO_TABLE('''''' || :EXCLUDE_TABLES || '''''', '''','''')))'';
    END IF;

    EXECUTE IMMEDIATE ''CREATE OR REPLACE TEMPORARY TABLE PLATFORM_CONFIG_DB.OPS.TMP__SYNC_SCHEMA_LOG (
        TABLE_NAME VARCHAR,
        ACTION VARCHAR,
        COLUMN_NAME VARCHAR,
        SOURCE_DATA_TYPE VARCHAR,
        TARGET_DATA_TYPE VARCHAR,
        SOURCE_NULLABLE VARCHAR,
        TARGET_NULLABLE VARCHAR,
        STATUS VARCHAR
    )'';

    -- Step 1: Clone missing tables
    SQL_TEXT := ''
        SELECT TABLE_NAME
        FROM '' || :SRC_DB || ''.INFORMATION_SCHEMA.TABLES
        WHERE TABLE_SCHEMA = '''''' || :SRC_SCH || ''''''
          AND TABLE_TYPE = ''''BASE TABLE''''
          AND TABLE_NAME NOT IN (
              SELECT TABLE_NAME
              FROM '' || :TGT_DB || ''.INFORMATION_SCHEMA.TABLES
              WHERE TABLE_SCHEMA = '''''' || :TGT_SCH || ''''''
          )'' || :EXCLUDE_FILTER;

    RES := (EXECUTE IMMEDIATE :SQL_TEXT);
    LET CUR_CLONE CURSOR FOR RES;
    OPEN CUR_CLONE;

    FOR ROW_VAR IN CUR_CLONE DO
        TBL_NAME := ROW_VAR.TABLE_NAME;
        BEGIN
            EXECUTE IMMEDIATE ''CREATE TABLE '' || :TARGET_SCHEMA || ''.'' || :TBL_NAME || '' CLONE '' || :SOURCE_SCHEMA || ''.'' || :TBL_NAME;
            EXECUTE IMMEDIATE ''INSERT INTO PLATFORM_CONFIG_DB.OPS.TMP__SYNC_SCHEMA_LOG VALUES ('''''' || :TBL_NAME || '''''', ''''CLONED'''', NULL, NULL, NULL, NULL, NULL, ''''Table cloned from source'''')'';
        EXCEPTION
            WHEN OTHER THEN
                BEGIN
                    EXECUTE IMMEDIATE ''CREATE TABLE '' || :TARGET_SCHEMA || ''.'' || :TBL_NAME || '' AS SELECT * FROM '' || :SOURCE_SCHEMA || ''.'' || :TBL_NAME;
                    EXECUTE IMMEDIATE ''INSERT INTO PLATFORM_CONFIG_DB.OPS.TMP__SYNC_SCHEMA_LOG VALUES ('''''' || :TBL_NAME || '''''', ''''CTAS CREATED'''', NULL, NULL, NULL, NULL, NULL, ''''Clone failed - created via CTAS'''')'';
                EXCEPTION
                    WHEN OTHER THEN
                        EXECUTE IMMEDIATE ''INSERT INTO PLATFORM_CONFIG_DB.OPS.TMP__SYNC_SCHEMA_LOG VALUES ('''''' || :TBL_NAME || '''''', ''''ERROR'''', NULL, NULL, NULL, NULL, NULL, '''''' || REPLACE(SQLERRM, '''''''', '''''''''''') || '''''')'';
                END;
        END;
    END FOR;
    CLOSE CUR_CLONE;

    -- Step 2: For all common tables, compare structure and copy data or log differences
    SQL_TEXT := ''
        SELECT s.TABLE_NAME
        FROM '' || :SRC_DB || ''.INFORMATION_SCHEMA.TABLES s
        INNER JOIN '' || :TGT_DB || ''.INFORMATION_SCHEMA.TABLES t
            ON s.TABLE_NAME = t.TABLE_NAME
        WHERE s.TABLE_SCHEMA = '''''' || :SRC_SCH || ''''''
          AND t.TABLE_SCHEMA = '''''' || :TGT_SCH || ''''''
          AND s.TABLE_TYPE = ''''BASE TABLE''''
          AND t.TABLE_TYPE = ''''BASE TABLE'''''' || :EXCLUDE_FILTER_ALIASED;

    RES := (EXECUTE IMMEDIATE :SQL_TEXT);
    LET CUR_COMMON CURSOR FOR RES;
    OPEN CUR_COMMON;

    FOR ROW_VAR IN CUR_COMMON DO
        TBL_NAME := ROW_VAR.TABLE_NAME;

        -- Check mismatch count
        SQL_TEXT := ''
            SELECT COUNT(*) AS CNT
            FROM (
                SELECT COLUMN_NAME, DATA_TYPE
                FROM '' || :SRC_DB || ''.INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = '''''' || :SRC_SCH || '''''' AND TABLE_NAME = '''''' || :TBL_NAME || ''''''
            ) t1
            FULL OUTER JOIN (
                SELECT COLUMN_NAME, DATA_TYPE
                FROM '' || :TGT_DB || ''.INFORMATION_SCHEMA.COLUMNS
                WHERE TABLE_SCHEMA = '''''' || :TGT_SCH || '''''' AND TABLE_NAME = '''''' || :TBL_NAME || ''''''
            ) t2
            ON t1.COLUMN_NAME = t2.COLUMN_NAME
                AND t1.DATA_TYPE = t2.DATA_TYPE
            WHERE t1.COLUMN_NAME IS NULL OR t2.COLUMN_NAME IS NULL'';

        RES2 := (EXECUTE IMMEDIATE :SQL_TEXT);
        LET CUR_CNT CURSOR FOR RES2;
        OPEN CUR_CNT;
        FETCH CUR_CNT INTO MISMATCH_COUNT;
        CLOSE CUR_CNT;

        IF (:MISMATCH_COUNT = 0) THEN
            -- Same structure: clone replace
            BEGIN
                EXECUTE IMMEDIATE ''CREATE OR REPLACE TABLE '' || :TARGET_SCHEMA || ''.'' || :TBL_NAME || '' CLONE '' || :SOURCE_SCHEMA || ''.'' || :TBL_NAME;
                EXECUTE IMMEDIATE ''INSERT INTO PLATFORM_CONFIG_DB.OPS.TMP__SYNC_SCHEMA_LOG VALUES ('''''' || :TBL_NAME || '''''', ''''CLONE REPLACED'''', NULL, NULL, NULL, NULL, NULL, ''''Structure matches - table cloned'''')'';
            EXCEPTION
                WHEN OTHER THEN
                    BEGIN
                        EXECUTE IMMEDIATE ''CREATE OR REPLACE TABLE '' || :TARGET_SCHEMA || ''.'' || :TBL_NAME || '' AS SELECT * FROM '' || :SOURCE_SCHEMA || ''.'' || :TBL_NAME;
                        EXECUTE IMMEDIATE ''INSERT INTO PLATFORM_CONFIG_DB.OPS.TMP__SYNC_SCHEMA_LOG VALUES ('''''' || :TBL_NAME || '''''', ''''CTAS REPLACED'''', NULL, NULL, NULL, NULL, NULL, ''''Clone failed (shared table?) - recreated via CTAS'''')'';
                    EXCEPTION
                        WHEN OTHER THEN
                            EXECUTE IMMEDIATE ''INSERT INTO PLATFORM_CONFIG_DB.OPS.TMP__SYNC_SCHEMA_LOG VALUES ('''''' || :TBL_NAME || '''''', ''''ERROR'''', NULL, NULL, NULL, NULL, NULL, '''''' || REPLACE(SQLERRM, '''''''', '''''''''''') || '''''')'';
                    END;
            END;
        ELSE
            -- Different structure: log column differences
            SQL_TEXT := ''
                INSERT INTO PLATFORM_CONFIG_DB.OPS.TMP__SYNC_SCHEMA_LOG
                SELECT
                    '''''' || :TBL_NAME || '''''',
                    ''''STRUCTURE MISMATCH'''',
                    COALESCE(t1.COLUMN_NAME, t2.COLUMN_NAME),
                    t1.DATA_TYPE,
                    t2.DATA_TYPE,
                    NULL,
                    NULL,
                    CASE
                        WHEN t1.COLUMN_NAME IS NULL THEN ''''ONLY IN TARGET''''
                        WHEN t2.COLUMN_NAME IS NULL THEN ''''ONLY IN SOURCE''''
                        WHEN t1.DATA_TYPE <> t2.DATA_TYPE THEN ''''DATA TYPE MISMATCH''''
                    END
                FROM (
                    SELECT COLUMN_NAME, DATA_TYPE
                    FROM '' || :SRC_DB || ''.INFORMATION_SCHEMA.COLUMNS
                    WHERE TABLE_SCHEMA = '''''' || :SRC_SCH || '''''' AND TABLE_NAME = '''''' || :TBL_NAME || ''''''
                ) t1
                FULL OUTER JOIN (
                    SELECT COLUMN_NAME, DATA_TYPE
                    FROM '' || :TGT_DB || ''.INFORMATION_SCHEMA.COLUMNS
                    WHERE TABLE_SCHEMA = '''''' || :TGT_SCH || '''''' AND TABLE_NAME = '''''' || :TBL_NAME || ''''''
                ) t2
                ON t1.COLUMN_NAME = t2.COLUMN_NAME
                WHERE t1.COLUMN_NAME IS NULL OR t2.COLUMN_NAME IS NULL
                   OR t1.DATA_TYPE <> t2.DATA_TYPE'';

            EXECUTE IMMEDIATE :SQL_TEXT;
        END IF;
    END FOR;
    CLOSE CUR_COMMON;

    FINAL_RES := (EXECUTE IMMEDIATE ''SELECT * FROM PLATFORM_CONFIG_DB.OPS.TMP__SYNC_SCHEMA_LOG ORDER BY TABLE_NAME, ACTION'');
    RETURN TABLE(FINAL_RES);
END';
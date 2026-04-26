-- =============================================================
-- Script  : bronze_load.sql
-- Layer   : Bronze
-- Author  : ttwange
-- Date    : 2026-04-25
-- =============================================================
-- Purpose:
--   Stored procedure that truncates and reloads all 6 bronze
--   tables from source CSV files mounted at /datasets.
--
--   Follows full load pattern — truncate then reload every run.
--   All columns are VARCHAR to accept raw dirty source data.
--   Types are enforced in the Silver layer only.
--
-- Usage:
--   CALL bronze.load_bronze();
--
-- Dependencies:
--   - Docker volume mount: /datasets must be visible to server
--   - Run init_database.sql first (schemas must exist)
-- =============================================================


-- -------------------------------------------------------------
-- DROP AND RECREATE TABLES
-- Ensures clean DDL every time this script is run fresh.
-- All date/numeric columns are VARCHAR in Bronze intentionally.
-- -------------------------------------------------------------

DROP TABLE IF EXISTS bronze.crm_cust_info;
CREATE TABLE bronze.crm_cust_info (
    cst_id              VARCHAR(50),   -- customer id, validate as INT in Silver
    cst_key             VARCHAR(50),   -- natural business key
    cst_firstname       VARCHAR(50),
    cst_lastname        VARCHAR(50),
    cst_marital_status  VARCHAR(50),   -- raw: 'M','S','n/a' — normalise in Silver
    cst_gndr            VARCHAR(50),   -- raw: 'M','F','n/a' — normalise in Silver
    cst_create_date     VARCHAR(20),   -- raw date string — cast in Silver
    dwh_create_date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS bronze.crm_prd_info;
CREATE TABLE bronze.crm_prd_info (
    prd_id          VARCHAR(50),   -- product id, validate as INT in Silver
    prd_key         VARCHAR(50),   -- e.g. BK-R93R-62
    prd_nm          VARCHAR(50),   -- product name
    prd_cost        VARCHAR(20),   -- numeric but raw — cast in Silver
    prd_line        VARCHAR(50),   -- product line code
    prd_start_dt    VARCHAR(20),   -- raw date string — cast in Silver
    prd_end_dt      VARCHAR(20),   -- raw date string, can be NULL/0 — cast in Silver
    dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS bronze.crm_sales_details;
CREATE TABLE bronze.crm_sales_details (
    sls_ord_num     VARCHAR(50),   -- e.g. SO43697 — order code, not a number
    sls_prd_key     VARCHAR(50),   -- e.g. BK-R93R-62 — product code
    sls_cust_id     VARCHAR(50),   -- raw id — validate in Silver
    sls_order_dt    VARCHAR(20),   -- arrives as 20101229 or 0 — cast in Silver
    sls_ship_dt     VARCHAR(20),   -- same — raw date string
    sls_due_dt      VARCHAR(20),   -- same — raw date string
    sls_sales       VARCHAR(20),   -- numeric but can be null/empty/0
    sls_quantity    VARCHAR(20),   -- same
    sls_price       VARCHAR(20),   -- same
    dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS bronze.erp_cust_az12;
CREATE TABLE bronze.erp_cust_az12 (
    cid             VARCHAR(50),   -- customer id, may have prefix e.g. 'NAS12345'
    bdate           VARCHAR(20),   -- birth date raw string — cast in Silver
    gen             VARCHAR(50),   -- raw gender code — normalise in Silver
    dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS bronze.erp_loc_a101;
CREATE TABLE bronze.erp_loc_a101 (
    cid             VARCHAR(50),
    cntry           VARCHAR(50),   -- raw country — standardise in Silver
    dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

DROP TABLE IF EXISTS bronze.erp_px_cat_g1v2;
CREATE TABLE bronze.erp_px_cat_g1v2 (
    id              VARCHAR(50),
    cat             VARCHAR(50),   -- category
    subcat          VARCHAR(50),   -- sub category
    maintenance     VARCHAR(50),   -- raw flag — normalise in Silver
    dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


-- =============================================================
-- STORED PROCEDURE: bronze.load_bronze
-- =============================================================
-- Purpose:
--   Single entry point to reload the entire Bronze layer.
--   Truncates each table then bulk loads from CSV.
--   Logs start time, end time and duration for each table.
--   On any error, raises a notice with the table name so you
--   know exactly where the pipeline failed.
-- =============================================================

CREATE OR REPLACE PROCEDURE bronze.load_bronze()
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_time    TIMESTAMP;
    v_end_time      TIMESTAMP;
    v_batch_start   TIMESTAMP;
BEGIN
    v_batch_start := clock_timestamp();

    RAISE NOTICE '==============================================';
    RAISE NOTICE 'BRONZE LAYER LOAD STARTED: %', v_batch_start;
    RAISE NOTICE '==============================================';

    -- ----------------------------------------------------------
    -- TABLE 1: bronze.crm_cust_info
    -- Source  : /datasets/source_crm/cust_info.csv
    -- ----------------------------------------------------------
    BEGIN
        RAISE NOTICE '----------------------------------------------';
        RAISE NOTICE 'Loading: bronze.crm_cust_info';
        v_start_time := clock_timestamp();

        TRUNCATE TABLE bronze.crm_cust_info;

        COPY bronze.crm_cust_info (
            cst_id,
            cst_key,
            cst_firstname,
            cst_lastname,
            cst_marital_status,
            cst_gndr,
            cst_create_date
        )
        FROM '/datasets/source_crm/cust_info.csv'
        WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', NULL '');

        v_end_time := clock_timestamp();
        RAISE NOTICE 'Completed: bronze.crm_cust_info | Duration: % ms',
            EXTRACT(MILLISECOND FROM (v_end_time - v_start_time))::INT;

    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAILED: bronze.crm_cust_info | Error: %', SQLERRM;
    END;

    -- ----------------------------------------------------------
    -- TABLE 2: bronze.crm_prd_info
    -- Source  : /datasets/source_crm/prd_info.csv
    -- ----------------------------------------------------------
    BEGIN
        RAISE NOTICE '----------------------------------------------';
        RAISE NOTICE 'Loading: bronze.crm_prd_info';
        v_start_time := clock_timestamp();

        TRUNCATE TABLE bronze.crm_prd_info;

        COPY bronze.crm_prd_info (
            prd_id,
            prd_key,
            prd_nm,
            prd_cost,
            prd_line,
            prd_start_dt,
            prd_end_dt
        )
        FROM '/datasets/source_crm/prd_info.csv'
        WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', NULL '');

        v_end_time := clock_timestamp();
        RAISE NOTICE 'Completed: bronze.crm_prd_info | Duration: % ms',
            EXTRACT(MILLISECOND FROM (v_end_time - v_start_time))::INT;

    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAILED: bronze.crm_prd_info | Error: %', SQLERRM;
    END;

    -- ----------------------------------------------------------
    -- TABLE 3: bronze.crm_sales_details
    -- Source  : /datasets/source_crm/sales_details.csv
    -- ----------------------------------------------------------
    BEGIN
        RAISE NOTICE '----------------------------------------------';
        RAISE NOTICE 'Loading: bronze.crm_sales_details';
        v_start_time := clock_timestamp();

        TRUNCATE TABLE bronze.crm_sales_details;

        COPY bronze.crm_sales_details (
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            sls_order_dt,
            sls_ship_dt,
            sls_due_dt,
            sls_sales,
            sls_quantity,
            sls_price
        )
        FROM '/datasets/source_crm/sales_details.csv'
        WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', NULL '');

        v_end_time := clock_timestamp();
        RAISE NOTICE 'Completed: bronze.crm_sales_details | Duration: % ms',
            EXTRACT(MILLISECOND FROM (v_end_time - v_start_time))::INT;

    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAILED: bronze.crm_sales_details | Error: %', SQLERRM;
    END;

    -- ----------------------------------------------------------
    -- TABLE 4: bronze.erp_cust_az12
    -- Source  : /datasets/source_erp/cust_az12.csv
    -- ----------------------------------------------------------
    BEGIN
        RAISE NOTICE '----------------------------------------------';
        RAISE NOTICE 'Loading: bronze.erp_cust_az12';
        v_start_time := clock_timestamp();

        TRUNCATE TABLE bronze.erp_cust_az12;

        COPY bronze.erp_cust_az12 (
            cid,
            bdate,
            gen
        )
        FROM '/datasets/source_erp/cust_az12.csv'
        WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', NULL '');

        v_end_time := clock_timestamp();
        RAISE NOTICE 'Completed: bronze.erp_cust_az12 | Duration: % ms',
            EXTRACT(MILLISECOND FROM (v_end_time - v_start_time))::INT;

    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAILED: bronze.erp_cust_az12 | Error: %', SQLERRM;
    END;

    -- ----------------------------------------------------------
    -- TABLE 5: bronze.erp_loc_a101
    -- Source  : /datasets/source_erp/loc_a101.csv
    -- ----------------------------------------------------------
    BEGIN
        RAISE NOTICE '----------------------------------------------';
        RAISE NOTICE 'Loading: bronze.erp_loc_a101';
        v_start_time := clock_timestamp();

        TRUNCATE TABLE bronze.erp_loc_a101;

        COPY bronze.erp_loc_a101 (
            cid,
            cntry
        )
        FROM '/datasets/source_erp/loc_a101.csv'
        WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', NULL '');

        v_end_time := clock_timestamp();
        RAISE NOTICE 'Completed: bronze.erp_loc_a101 | Duration: % ms',
            EXTRACT(MILLISECOND FROM (v_end_time - v_start_time))::INT;

    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAILED: bronze.erp_loc_a101 | Error: %', SQLERRM;
    END;

    -- ----------------------------------------------------------
    -- TABLE 6: bronze.erp_px_cat_g1v2
    -- Source  : /datasets/source_erp/px_cat_g1v2.csv
    -- ----------------------------------------------------------
    BEGIN
        RAISE NOTICE '----------------------------------------------';
        RAISE NOTICE 'Loading: bronze.erp_px_cat_g1v2';
        v_start_time := clock_timestamp();

        TRUNCATE TABLE bronze.erp_px_cat_g1v2;

        COPY bronze.erp_px_cat_g1v2 (
            id,
            cat,
            subcat,
            maintenance
        )
        FROM '/datasets/source_erp/px_cat_g1v2.csv'
        WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',', NULL '');

        v_end_time := clock_timestamp();
        RAISE NOTICE 'Completed: bronze.erp_px_cat_g1v2 | Duration: % ms',
            EXTRACT(MILLISECOND FROM (v_end_time - v_start_time))::INT;

    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAILED: bronze.erp_px_cat_g1v2 | Error: %', SQLERRM;
    END;

    -- ----------------------------------------------------------
    -- BATCH SUMMARY
    -- ----------------------------------------------------------
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'BRONZE LAYER LOAD COMPLETED';
    RAISE NOTICE 'Total duration: % seconds',
        EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start))::INT;
    RAISE NOTICE '==============================================';

END;
$$;
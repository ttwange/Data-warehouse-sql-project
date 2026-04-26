-- =============================================================
-- Script  : silver_load.sql
-- Layer   : Silver
-- Author  : thonne
-- Date    : 2026-04-26
-- =============================================================
-- Purpose:
--   Creates all Silver tables and loads cleaned, typed data
--   from Bronze. Wraps all 6 tables into a single stored
--   procedure following the same pattern as bronze.load_bronze().
--
--   Key transformations applied:
--     - All VARCHAR types cast to proper INT, DATE, TIMESTAMP
--     - NULL/empty/invalid values handled with CASE and COALESCE
--     - Duplicates removed via ROW_NUMBER() window function
--     - Gender and marital status decoded to readable labels
--     - Sales/price/quantity cross-validated for consistency
--     - Date strings parsed from YYYYMMDD format
--     - Future birth dates nulled out
--     - Country codes standardised to full names
--     - NAS prefix stripped from ERP customer ids
--
-- Usage:
--   CALL silver.load_silver();
--
-- Dependencies:
--   - Run init_database.sql first   (schemas must exist)
--   - Run bronze/bronze_load.sql    (bronze tables must be loaded)
-- =============================================================


-- -------------------------------------------------------------
-- SILVER TABLE DDL
-- Dropped and recreated on every run to ensure clean structure.
-- Types reflect cleaned output — not raw Bronze types.
-- -------------------------------------------------------------

CREATE OR REPLACE PROCEDURE silver.load_silver()
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_time  TIMESTAMP;
    v_end_time    TIMESTAMP;
    v_batch_start TIMESTAMP;
BEGIN
    v_batch_start := clock_timestamp();

    RAISE NOTICE '==============================================';
    RAISE NOTICE 'SILVER LAYER LOAD STARTED: %', v_batch_start;
    RAISE NOTICE '==============================================';

    -- ----------------------------------------------------------
    -- TABLE 1: silver.crm_cust_info
    -- ----------------------------------------------------------
    BEGIN
        RAISE NOTICE '----------------------------------------------';
        RAISE NOTICE 'Loading: silver.crm_cust_info';
        v_start_time := clock_timestamp();

        DROP TABLE IF EXISTS silver.crm_cust_info;
        CREATE TABLE silver.crm_cust_info (
            cst_id              INT,
            cst_key             VARCHAR(50),
            cst_firstname       VARCHAR(50),
            cst_lastname        VARCHAR(50),
            cst_marital_status  VARCHAR(20),
            cst_gndr            VARCHAR(20),
            cst_create_date     DATE,
            dwh_create_date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        INSERT INTO silver.crm_cust_info (
            cst_id, cst_key, cst_firstname, cst_lastname,
            cst_marital_status, cst_gndr, cst_create_date, dwh_create_date
        )
        SELECT
            cst_id::INT,
            cst_key,
            TRIM(cst_firstname),
            TRIM(cst_lastname),
            CASE
                WHEN TRIM(UPPER(cst_marital_status)) = 'S' THEN 'SINGLE'
                WHEN TRIM(UPPER(cst_marital_status)) = 'M' THEN 'MARRIED'
                ELSE 'UNKNOWN'
            END,
            CASE
                WHEN TRIM(UPPER(cst_gndr)) = 'M' THEN 'MALE'
                WHEN TRIM(UPPER(cst_gndr)) = 'F' THEN 'FEMALE'
                ELSE 'UNKNOWN'
            END,
            cst_create_date::DATE,
            CURRENT_TIMESTAMP
        FROM (
            SELECT *,
                ROW_NUMBER() OVER (
                    PARTITION BY cst_id
                    ORDER BY cst_create_date DESC
                ) AS flag_date
            FROM bronze.crm_cust_info
            WHERE cst_id IS NOT NULL
        ) AS t
        WHERE t.flag_date = 1;

        v_end_time := clock_timestamp();
        RAISE NOTICE 'Completed: silver.crm_cust_info | Duration: % ms',
            EXTRACT(MILLISECOND FROM (v_end_time - v_start_time))::INT;

    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAILED: silver.crm_cust_info | Error: %', SQLERRM;
    END;

    -- ----------------------------------------------------------
    -- TABLE 2: silver.crm_prd_info
    -- ----------------------------------------------------------
    BEGIN
        RAISE NOTICE '----------------------------------------------';
        RAISE NOTICE 'Loading: silver.crm_prd_info';
        v_start_time := clock_timestamp();

        DROP TABLE IF EXISTS silver.crm_prd_info;
        CREATE TABLE silver.crm_prd_info (
            prd_id          INT,
            cat_id          VARCHAR(50),
            prd_key         VARCHAR(50),
            prd_nm          VARCHAR(50),
            prd_cost        INT,
            prd_line        VARCHAR(50),
            prd_start_dt    DATE,
            prd_end_dt      DATE,
            dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        INSERT INTO silver.crm_prd_info (
            prd_id, cat_id, prd_key, prd_nm,
            prd_cost, prd_line, prd_start_dt, prd_end_dt, dwh_create_date
        )
        SELECT
            prd_id::INT,
            REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_')    AS cat_id,
            SUBSTRING(prd_key, 7, LENGTH(prd_key))          AS prd_key,
            TRIM(prd_nm),
            COALESCE(NULLIF(TRIM(prd_cost), ''), '0')::INT,
            CASE UPPER(TRIM(prd_line))
                WHEN 'M' THEN 'MOUNTAIN'
                WHEN 'R' THEN 'ROADS'
                WHEN 'S' THEN 'OTHER SALES'
                WHEN 'T' THEN 'TOURING'
                ELSE          'UNKNOWN'
            END,
            prd_start_dt::DATE,
            COALESCE(
                LEAD(prd_start_dt::DATE)
                    OVER (PARTITION BY prd_key ORDER BY prd_start_dt::DATE)
                    - INTERVAL '1 day',
                '9999-12-31'::DATE
            ),
            CURRENT_TIMESTAMP
        FROM bronze.crm_prd_info
        WHERE prd_start_dt IS NOT NULL
          AND TRIM(prd_start_dt) != '';

        v_end_time := clock_timestamp();
        RAISE NOTICE 'Completed: silver.crm_prd_info | Duration: % ms',
            EXTRACT(MILLISECOND FROM (v_end_time - v_start_time))::INT;

    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAILED: silver.crm_prd_info | Error: %', SQLERRM;
    END;

    -- ----------------------------------------------------------
    -- TABLE 3: silver.crm_sales_details
    -- ----------------------------------------------------------
    BEGIN
        RAISE NOTICE '----------------------------------------------';
        RAISE NOTICE 'Loading: silver.crm_sales_details';
        v_start_time := clock_timestamp();

        DROP TABLE IF EXISTS silver.crm_sales_details;
        CREATE TABLE silver.crm_sales_details (
            sls_ord_num     VARCHAR(50),
            sls_prd_key     VARCHAR(50),
            sls_cust_id     INT,
            sls_order_dt    DATE,
            sls_ship_dt     DATE,
            sls_due_dt      DATE,
            sls_sales       INT,
            sls_quantity    INT,
            sls_price       INT,
            dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        INSERT INTO silver.crm_sales_details (
            sls_ord_num, sls_prd_key, sls_cust_id,
            sls_order_dt, sls_ship_dt, sls_due_dt,
            sls_sales, sls_quantity, sls_price, dwh_create_date
        )
        SELECT
            sls_ord_num,
            sls_prd_key,
            sls_cust_id::INT,
            CASE
                WHEN sls_order_dt = '0' OR LENGTH(sls_order_dt) != 8 THEN NULL
                ELSE TO_DATE(sls_order_dt, 'YYYYMMDD')
            END,
            CASE
                WHEN sls_ship_dt = '0' OR LENGTH(sls_ship_dt) != 8 THEN NULL
                ELSE TO_DATE(sls_ship_dt, 'YYYYMMDD')
            END,
            CASE
                WHEN sls_due_dt = '0' OR LENGTH(sls_due_dt) != 8 THEN NULL
                ELSE TO_DATE(sls_due_dt, 'YYYYMMDD')
            END,
            CASE
                WHEN sls_sales::INT IS NULL
                  OR sls_sales::INT <= 0
                  OR sls_sales::INT != sls_quantity::INT * ABS(sls_price::INT)
                    THEN sls_quantity::INT * ABS(sls_price::INT)
                ELSE sls_sales::INT
            END,
            sls_quantity::INT,
            CASE
                WHEN sls_price::INT IS NULL OR sls_price::INT <= 0
                    THEN sls_sales::INT / NULLIF(sls_quantity::INT, 0)
                ELSE sls_price::INT
            END,
            CURRENT_TIMESTAMP
        FROM bronze.crm_sales_details
        WHERE sls_ord_num IS NOT NULL;

        v_end_time := clock_timestamp();
        RAISE NOTICE 'Completed: silver.crm_sales_details | Duration: % ms',
            EXTRACT(MILLISECOND FROM (v_end_time - v_start_time))::INT;

    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAILED: silver.crm_sales_details | Error: %', SQLERRM;
    END;

    -- ----------------------------------------------------------
    -- TABLE 4: silver.erp_cust_az12
    -- ----------------------------------------------------------
    BEGIN
        RAISE NOTICE '----------------------------------------------';
        RAISE NOTICE 'Loading: silver.erp_cust_az12';
        v_start_time := clock_timestamp();

        DROP TABLE IF EXISTS silver.erp_cust_az12;
        CREATE TABLE silver.erp_cust_az12 (
            cid             VARCHAR(50),
            bdate           DATE,
            gen             VARCHAR(50),
            dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        INSERT INTO silver.erp_cust_az12 (cid, bdate, gen, dwh_create_date)
        SELECT
            CASE
                WHEN cid LIKE '%NAS%' THEN SUBSTRING(cid, 4, LENGTH(cid))
                ELSE cid
            END,
            CASE
                WHEN bdate IS NULL OR TRIM(bdate) = '' THEN NULL
                WHEN TRIM(bdate)::DATE > NOW()         THEN NULL
                ELSE TRIM(bdate)::DATE
            END,
            CASE
                WHEN TRIM(UPPER(gen)) IN ('M', 'MALE')   THEN 'MALE'
                WHEN TRIM(UPPER(gen)) IN ('F', 'FEMALE') THEN 'FEMALE'
                ELSE 'UNKNOWN'
            END,
            CURRENT_TIMESTAMP
        FROM bronze.erp_cust_az12;

        v_end_time := clock_timestamp();
        RAISE NOTICE 'Completed: silver.erp_cust_az12 | Duration: % ms',
            EXTRACT(MILLISECOND FROM (v_end_time - v_start_time))::INT;

    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAILED: silver.erp_cust_az12 | Error: %', SQLERRM;
    END;

    -- ----------------------------------------------------------
    -- TABLE 5: silver.erp_loc_a101
    -- ----------------------------------------------------------
    BEGIN
        RAISE NOTICE '----------------------------------------------';
        RAISE NOTICE 'Loading: silver.erp_loc_a101';
        v_start_time := clock_timestamp();

        DROP TABLE IF EXISTS silver.erp_loc_a101;
        CREATE TABLE silver.erp_loc_a101 (
            cid             VARCHAR(50),
            cntry           VARCHAR(50),
            dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        INSERT INTO silver.erp_loc_a101 (cid, cntry, dwh_create_date)
        SELECT
            REPLACE(cid, '-', ''),
            CASE
                WHEN TRIM(UPPER(cntry)) IN ('US', 'USA', 'UNITED STATES') THEN 'USA'
                WHEN TRIM(UPPER(cntry)) = 'DE'                             THEN 'GERMANY'
                WHEN TRIM(UPPER(cntry)) = '' OR cntry IS NULL              THEN 'UNKNOWN'
                ELSE TRIM(UPPER(cntry))
            END,
            CURRENT_TIMESTAMP
        FROM bronze.erp_loc_a101;

        v_end_time := clock_timestamp();
        RAISE NOTICE 'Completed: silver.erp_loc_a101 | Duration: % ms',
            EXTRACT(MILLISECOND FROM (v_end_time - v_start_time))::INT;

    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAILED: silver.erp_loc_a101 | Error: %', SQLERRM;
    END;

    -- ----------------------------------------------------------
    -- TABLE 6: silver.erp_px_cat_g1v2
    -- ----------------------------------------------------------
    BEGIN
        RAISE NOTICE '----------------------------------------------';
        RAISE NOTICE 'Loading: silver.erp_px_cat_g1v2';
        v_start_time := clock_timestamp();

        DROP TABLE IF EXISTS silver.erp_px_cat_g1v2;
        CREATE TABLE silver.erp_px_cat_g1v2 (
            id              VARCHAR(50),
            cat             VARCHAR(50),
            subcat          VARCHAR(50),
            maintenance     VARCHAR(50),
            dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        INSERT INTO silver.erp_px_cat_g1v2 (
            id, cat, subcat, maintenance, dwh_create_date
        )
        SELECT
            id, cat, subcat, maintenance,
            CURRENT_TIMESTAMP
        FROM bronze.erp_px_cat_g1v2;

        v_end_time := clock_timestamp();
        RAISE NOTICE 'Completed: silver.erp_px_cat_g1v2 | Duration: % ms',
            EXTRACT(MILLISECOND FROM (v_end_time - v_start_time))::INT;

    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'FAILED: silver.erp_px_cat_g1v2 | Error: %', SQLERRM;
    END;

    -- ----------------------------------------------------------
    -- BATCH SUMMARY
    -- ----------------------------------------------------------
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'SILVER LAYER LOAD COMPLETED';
    RAISE NOTICE 'Total duration: % seconds',
        EXTRACT(EPOCH FROM (clock_timestamp() - v_batch_start))::INT;
    RAISE NOTICE '==============================================';

END;
$$;
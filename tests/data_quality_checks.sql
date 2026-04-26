-- =============================================================
-- Script  : bronze_quality_checks.sql
-- Layer   : Bronze
-- Author  : thonne
-- Date    : 2026-04-26
-- =============================================================
-- Purpose:
--   Data quality checks run against Bronze tables before
--   promoting data to Silver. Covers:
--     - Null and duplicate checks on primary keys
--     - Whitespace checks on string fields
--     - Data consistency and value distribution checks
--     - Business rule validation on numeric fields
--     - Date range and ordering checks
--
-- Usage:
--   Run each section independently in DBeaver to inspect
--   results before running silver.load_silver().
--   None of these queries modify data — read only.
-- =============================================================


-- =============================================================
-- TABLE 1: bronze.crm_cust_info
-- =============================================================

-- -------------------------------------------------------------
-- 1.1 Row count overview
-- Compares total rows vs non-null id count vs distinct id count
-- Any difference between the three signals nulls or duplicates
-- -------------------------------------------------------------
SELECT COUNT(*)             AS all_rows    FROM bronze.crm_cust_info
UNION ALL
SELECT COUNT(cst_id)        AS id_count    FROM bronze.crm_cust_info
UNION ALL
SELECT COUNT(DISTINCT cst_id) AS distinct_count FROM bronze.crm_cust_info;


-- -------------------------------------------------------------
-- 1.2 Null and duplicate check on primary key cst_id
-- Returns rows where cst_id is null or appears more than once
-- Expect: zero rows returned for clean data
-- -------------------------------------------------------------
SELECT cst_id, COUNT(*) AS id_count
FROM bronze.crm_cust_info
GROUP BY cst_id
HAVING COUNT(*) > 1 OR cst_id IS NULL;


-- -------------------------------------------------------------
-- 1.3 Identify which duplicate rows would be removed
-- Shows all rows that are NOT the most recent per customer
-- These are the rows Silver discards via ROW_NUMBER()
-- -------------------------------------------------------------
SELECT * FROM (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY cst_id
            ORDER BY cst_create_date DESC
        ) AS flag_date_count
    FROM bronze.crm_cust_info
) AS row_cst_info
WHERE flag_date_count != 1;


-- -------------------------------------------------------------
-- 1.4 Whitespace check on firstname and lastname
-- Returns rows where leading/trailing spaces exist
-- Expect: zero rows — Silver applies TRIM() to fix these
-- -------------------------------------------------------------
SELECT cst_firstname
FROM bronze.crm_cust_info
WHERE cst_firstname != TRIM(cst_firstname);

SELECT cst_lastname
FROM bronze.crm_cust_info
WHERE cst_lastname != TRIM(cst_lastname);


-- -------------------------------------------------------------
-- 1.5 Gender value distribution
-- Shows all raw values in cst_gndr and their counts
-- Expect: only 'M', 'F', nulls or known variants
-- -------------------------------------------------------------
SELECT cst_gndr, COUNT(*) AS total
FROM bronze.crm_cust_info
GROUP BY cst_gndr
ORDER BY total DESC;


-- -------------------------------------------------------------
-- 1.6 Gender consistency check
-- Shows rows that will map to UNKNOWN after Silver CASE logic
-- Investigate these to see if new codes need to be handled
-- -------------------------------------------------------------
SELECT * FROM (
    SELECT cst_gndr,
        CASE
            WHEN cst_gndr = 'M' THEN 'MALE'
            WHEN cst_gndr = 'F' THEN 'FEMALE'
            ELSE 'UNKNOWN'
        END AS cst_gndr_clean
    FROM bronze.crm_cust_info
) AS cleaned_gender
WHERE cst_gndr_clean = 'UNKNOWN';


-- -------------------------------------------------------------
-- 1.7 Marital status distinct values
-- Check what raw codes exist before writing CASE logic
-- -------------------------------------------------------------
SELECT DISTINCT cst_marital_status
FROM bronze.crm_cust_info;


-- =============================================================
-- TABLE 2: bronze.crm_prd_info
-- =============================================================

-- -------------------------------------------------------------
-- 2.1 Duplicate check on prd_id
-- -------------------------------------------------------------
SELECT prd_id, COUNT(*) AS distinct_count
FROM bronze.crm_prd_info
GROUP BY prd_id
HAVING COUNT(*) != 1;


-- -------------------------------------------------------------
-- 2.2 Duplicate check on prd_key
-- prd_key can legitimately repeat for SCD2 versioned products
-- but flag any unexpected patterns
-- -------------------------------------------------------------
SELECT prd_key, COUNT(*) AS distinct_count
FROM bronze.crm_prd_info
GROUP BY prd_key
HAVING COUNT(*) != 1;


-- -------------------------------------------------------------
-- 2.3 Negative or null cost check
-- Costs should never be negative — investigate any that are
-- -------------------------------------------------------------
SELECT prd_cost
FROM bronze.crm_prd_info
WHERE prd_cost < '0' OR prd_cost IS NULL;


-- -------------------------------------------------------------
-- 2.4 Product line distinct values
-- Check all raw codes before writing CASE decode logic
-- Expect: M, R, S, T only — anything else maps to UNKNOWN
-- -------------------------------------------------------------
SELECT DISTINCT prd_line
FROM bronze.crm_prd_info;


-- -------------------------------------------------------------
-- 2.5 Start date distribution
-- Check for unexpected date patterns or NULLs
-- -------------------------------------------------------------
SELECT prd_start_dt, COUNT(*)
FROM bronze.crm_prd_info
GROUP BY prd_start_dt
ORDER BY prd_start_dt;


-- -------------------------------------------------------------
-- 2.6 End date distribution
-- -------------------------------------------------------------
SELECT prd_end_dt, COUNT(*)
FROM bronze.crm_prd_info
GROUP BY prd_end_dt
ORDER BY prd_end_dt;


-- -------------------------------------------------------------
-- 2.7 Date ordering check
-- End date should never be before start date
-- Expect: zero rows returned
-- -------------------------------------------------------------
SELECT *
FROM bronze.crm_prd_info
WHERE prd_end_dt::DATE < prd_start_dt::DATE;


-- =============================================================
-- TABLE 3: bronze.crm_sales_details
-- =============================================================

-- -------------------------------------------------------------
-- 3.1 Invalid date checks — '0' and wrong length values
-- Shows how many rows have bad date values per date column
-- These will be NULLed out in Silver
-- -------------------------------------------------------------
SELECT COUNT(*) AS bad_order_dt FROM bronze.crm_sales_details WHERE sls_order_dt = '0';
SELECT COUNT(*) AS bad_ship_dt  FROM bronze.crm_sales_details WHERE sls_ship_dt  = '0';
SELECT COUNT(*) AS bad_due_dt   FROM bronze.crm_sales_details WHERE sls_due_dt   = '0';


-- -------------------------------------------------------------
-- 3.2 Date ordering check
-- Order date should never be after ship or due date
-- Expect: zero rows returned
-- -------------------------------------------------------------
SELECT *
FROM bronze.crm_sales_details
WHERE sls_order_dt > sls_ship_dt
   OR sls_order_dt > sls_due_dt;


-- -------------------------------------------------------------
-- 3.3 Business rule validation: sales = quantity * price
-- Returns rows where the three values are inconsistent
-- or any of them are null or negative
-- Silver repairs these using CASE logic
-- -------------------------------------------------------------
SELECT
    sls_cust_id,
    sls_sales::INT,
    sls_price::INT,
    sls_quantity::INT,
    sls_price::INT * sls_quantity::INT AS sale_check
FROM bronze.crm_sales_details
WHERE sls_price::INT * sls_quantity::INT != sls_sales::INT
   OR sls_quantity IS NULL
   OR sls_price    IS NULL
   OR sls_sales    IS NULL
   OR sls_quantity < '0'
   OR sls_price    < '0'
   OR sls_sales    < '0'
ORDER BY sls_sales, sls_quantity, sls_price;


-- =============================================================
-- TABLE 4: bronze.erp_cust_az12
-- =============================================================

-- -------------------------------------------------------------
-- 4.1 Full table inspection
-- Small table — review all rows to understand shape
-- -------------------------------------------------------------
SELECT * FROM bronze.erp_cust_az12;


-- -------------------------------------------------------------
-- 4.2 Customer id prefix check
-- Identify rows with NAS prefix that need stripping in Silver
-- -------------------------------------------------------------
SELECT DISTINCT cid FROM bronze.erp_cust_az12
WHERE cid LIKE '%NAS%';


-- -------------------------------------------------------------
-- 4.3 Future birth date check
-- Any bdate after today is invalid — Silver nulls these out
-- -------------------------------------------------------------
SELECT cid, bdate
FROM bronze.erp_cust_az12
WHERE bdate::DATE > NOW();


-- -------------------------------------------------------------
-- 4.4 Gender distinct values
-- Check all raw codes before writing CASE decode logic
-- -------------------------------------------------------------
SELECT DISTINCT gen FROM bronze.erp_cust_az12;


-- =============================================================
-- TABLE 5: bronze.erp_loc_a101
-- =============================================================

-- -------------------------------------------------------------
-- 5.1 Country distinct values
-- Check all raw country codes before writing CASE logic
-- Expect to find: US, USA, United States, DE, blanks, nulls
-- -------------------------------------------------------------
SELECT DISTINCT cntry
FROM bronze.erp_loc_a101
ORDER BY cntry;


-- -------------------------------------------------------------
-- 5.2 Null or blank country check
-- These will map to UNKNOWN in Silver
-- -------------------------------------------------------------
SELECT COUNT(*) AS missing_country
FROM bronze.erp_loc_a101
WHERE cntry IS NULL OR TRIM(cntry) = '';


-- =============================================================
-- TABLE 6: bronze.erp_px_cat_g1v2
-- =============================================================

-- -------------------------------------------------------------
-- 6.1 Subcategory distinct values
-- Verify subcategory data is clean — no transforms needed
-- -------------------------------------------------------------
SELECT DISTINCT subcat
FROM bronze.erp_px_cat_g1v2
ORDER BY subcat;


-- -------------------------------------------------------------
-- 6.2 Full table inspection
-- Small lookup table — review all rows directly
-- -------------------------------------------------------------
SELECT * FROM bronze.erp_px_cat_g1v2;
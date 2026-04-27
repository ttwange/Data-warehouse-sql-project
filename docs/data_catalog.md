# Data Catalog — Data Warehouse SQL Project

## Overview

| Property | Detail |
|---|---|
| **Project** | Data Warehouse SQL Project |
| **Author** | thonne |
| **Database** | PostgreSQL 16 |
| **Architecture** | Medallion (Bronze → Silver → Gold) |
| **Last Updated** | 2026-04-26 |
| **Repository** | https://github.com/ttwange/Data-warehouse-sql-project |

This catalog documents every table and view in the warehouse across all three layers. It is the single reference point for understanding what data exists, where it came from, what transformations were applied, and how to use it.

---

## Architecture Overview

| Layer | Purpose | Load Method | Script |
|---|---|---|---|
| **Bronze** | Raw ingestion — exact copy of source | Full load, truncate + COPY | `bronze/bronze_load.sql` |
| **Silver** | Cleaned, typed, deduplicated | Full load, truncate + INSERT | `silver/silver_load.sql` |
| **Gold** | Star schema for analytics | Views — live on Silver | `gold/gold_layer.sql` |

**Data flow:**

| Source | Bronze | Silver | Gold |
|---|---|---|---|
| CRM System | `crm_cust_info` | `crm_cust_info` | `dim_customers` |
| CRM System | `crm_prd_info` | `crm_prd_info` | `dim_products` |
| CRM System | `crm_sales_details` | `crm_sales_details` | `fact_sales` |
| ERP System | `erp_cust_az12` | `erp_cust_az12` | into `dim_customers` |
| ERP System | `erp_loc_a101` | `erp_loc_a101` | into `dim_customers` |
| ERP System | `erp_px_cat_g1v2` | `erp_px_cat_g1v2` | into `dim_products` |

---

## Bronze Layer

> Raw data exactly as it arrives from source systems.
> No transformations applied. All columns stored as VARCHAR.
> Reload with: `CALL bronze.load_bronze();`

---

### bronze.crm_cust_info

**Source file:** `datasets/source_crm/cust_info.csv`

**Description:** Raw customer records from the CRM system. Contains duplicates by design — Silver handles deduplication.

| Column | Type | Description | Notes |
|---|---|---|---|
| `cst_id` | VARCHAR(50) | Customer identifier | May contain duplicates — deduplicated in Silver |
| `cst_key` | VARCHAR(50) | Customer business key | Natural key used for ERP joins |
| `cst_firstname` | VARCHAR(50) | First name | May have leading/trailing spaces |
| `cst_lastname` | VARCHAR(50) | Last name | May have leading/trailing spaces |
| `cst_marital_status` | VARCHAR(50) | Marital status code | Raw values: M, S, n/a, NULL |
| `cst_gndr` | VARCHAR(50) | Gender code | Raw values: M, F, n/a, NULL |
| `cst_create_date` | VARCHAR(20) | Account creation date | Stored as string — cast to DATE in Silver |
| `dwh_create_date` | TIMESTAMP | Warehouse load timestamp | Set by warehouse, not from source |

**Known quality issues:**
- Duplicate `cst_id` values exist — keep most recent by `cst_create_date`
- Leading/trailing whitespace on name fields
- `cst_gndr` and `cst_marital_status` use single-letter codes

---

### bronze.crm_prd_info

**Source file:** `datasets/source_crm/prd_info.csv`

**Description:** Raw product catalogue from the CRM system. Contains versioned product records — one row per product version following the SCD2 pattern.

| Column | Type | Description | Notes |
|---|---|---|---|
| `prd_id` | VARCHAR(50) | Product identifier | Cast to INT in Silver |
| `prd_key` | VARCHAR(50) | Full product key | First 5 chars = category id, chars 7+ = product key |
| `prd_nm` | VARCHAR(50) | Product name | |
| `prd_cost` | VARCHAR(20) | Product cost | May be NULL or empty — defaulted to 0 in Silver |
| `prd_line` | VARCHAR(50) | Product line code | Raw values: M, R, S, T |
| `prd_start_dt` | VARCHAR(20) | Version start date | Stored as string — cast to DATE in Silver |
| `prd_end_dt` | VARCHAR(20) | Version end date | Not in source — derived in Silver via LEAD |
| `dwh_create_date` | TIMESTAMP | Warehouse load timestamp | Set by warehouse |

**Known quality issues:**
- `prd_end_dt` is not in source — derived in Silver
- `prd_cost` can be NULL or empty string
- `prd_key` encodes two pieces of information that are split in Silver

---

### bronze.crm_sales_details

**Source file:** `datasets/source_crm/sales_details.csv`

**Description:** Raw sales transaction records. Approximately 64,000 rows. One row per order line.

| Column | Type | Description | Notes |
|---|---|---|---|
| `sls_ord_num` | VARCHAR(50) | Order number | e.g. SO43697 — alphanumeric, not an integer |
| `sls_prd_key` | VARCHAR(50) | Product key | Links to crm_prd_info.prd_key after Silver split |
| `sls_cust_id` | VARCHAR(50) | Customer identifier | Links to crm_cust_info.cst_id |
| `sls_order_dt` | VARCHAR(20) | Order date | Raw format YYYYMMDD — value 0 means unknown |
| `sls_ship_dt` | VARCHAR(20) | Ship date | Same format and issues as sls_order_dt |
| `sls_due_dt` | VARCHAR(20) | Due date | Same format and issues as sls_order_dt |
| `sls_sales` | VARCHAR(20) | Sales amount | May be inconsistent with quantity x price |
| `sls_quantity` | VARCHAR(20) | Quantity sold | |
| `sls_price` | VARCHAR(20) | Unit price | May be negative in source — ABS applied in Silver |
| `dwh_create_date` | TIMESTAMP | Warehouse load timestamp | Set by warehouse |

**Known quality issues:**
- Date columns contain 0 for unknown dates — NULLed in Silver
- `sls_sales` is sometimes inconsistent with quantity x price — recalculated in Silver
- Negative prices exist — ABS() applied in Silver

---

### bronze.erp_cust_az12

**Source file:** `datasets/source_erp/cust_az12.csv`

**Description:** ERP customer supplement containing birth dates and gender. Joins to CRM customers via cst_key.

| Column | Type | Description | Notes |
|---|---|---|---|
| `cid` | VARCHAR(50) | Customer identifier | May have NAS prefix — stripped in Silver |
| `bdate` | VARCHAR(20) | Birth date | Stored as string — future dates NULLed in Silver |
| `gen` | VARCHAR(50) | Gender | Raw values: M, F, Male, Female, NULL |
| `dwh_create_date` | TIMESTAMP | Warehouse load timestamp | Set by warehouse |

**Known quality issues:**
- `cid` has NAS prefix on some rows — stripped in Silver to match CRM key
- Some `bdate` values are in the future — treated as NULL in Silver

---

### bronze.erp_loc_a101

**Source file:** `datasets/source_erp/loc_a101.csv`

**Description:** ERP location data mapping customers to countries.

| Column | Type | Description | Notes |
|---|---|---|---|
| `cid` | VARCHAR(50) | Customer identifier | May have hyphens — stripped in Silver |
| `cntry` | VARCHAR(50) | Country code or name | Raw values: US, USA, United States, DE, blank |
| `dwh_create_date` | TIMESTAMP | Warehouse load timestamp | Set by warehouse |

**Known quality issues:**
- `cid` contains hyphens — removed in Silver for join compatibility
- Country values are inconsistent — standardised to full names in Silver

---

### bronze.erp_px_cat_g1v2

**Source file:** `datasets/source_erp/px_cat_g1v2.csv`

**Description:** ERP product category lookup table. Maps category ids to category, subcategory, and maintenance flag.

| Column | Type | Description | Notes |
|---|---|---|---|
| `id` | VARCHAR(50) | Category identifier | Matches cat_id in Silver crm_prd_info |
| `cat` | VARCHAR(50) | Category name | e.g. Bikes, Components |
| `subcat` | VARCHAR(50) | Subcategory name | e.g. Mountain Bikes, Road Bikes |
| `maintenance` | VARCHAR(50) | Maintenance flag | |
| `dwh_create_date` | TIMESTAMP | Warehouse load timestamp | Set by warehouse |

**Known quality issues:** None — passes through to Silver unchanged.

---

## Silver Layer

> Cleaned, typed, and deduplicated data. Source of truth for data scientists and engineers.
> All columns have correct data types. Business rules applied.
> Reload with: `CALL silver.load_silver();`

---

### silver.crm_cust_info

**Source:** `bronze.crm_cust_info`

**Description:** Deduplicated, cleaned customer records. One row per customer — most recent version kept.

| Column | Type | Description | Transformation |
|---|---|---|---|
| `cst_id` | INT | Customer identifier (PK) | Cast from VARCHAR. Deduplicated via ROW_NUMBER() |
| `cst_key` | VARCHAR(50) | Customer business key | No change |
| `cst_firstname` | VARCHAR(50) | First name | TRIM applied |
| `cst_lastname` | VARCHAR(50) | Last name | TRIM applied |
| `cst_marital_status` | VARCHAR(20) | Marital status | Decoded: S to SINGLE, M to MARRIED, else UNKNOWN |
| `cst_gndr` | VARCHAR(20) | Gender | Decoded: M to MALE, F to FEMALE, else UNKNOWN |
| `cst_create_date` | DATE | Account creation date | Cast from VARCHAR |
| `dwh_create_date` | TIMESTAMP | Silver load timestamp | Set by Silver procedure |

**Business rules applied:**
- Keep only the most recent record per `cst_id` ordered by `cst_create_date DESC`
- Exclude rows where `cst_id` is NULL

---

### silver.crm_prd_info

**Source:** `bronze.crm_prd_info`

**Description:** Cleaned product catalogue with SCD2 versioning. Each row represents one version of a product. A `prd_end_dt` of 9999-12-31 indicates the currently active version.

| Column | Type | Description | Transformation |
|---|---|---|---|
| `prd_id` | INT | Product identifier | Cast from VARCHAR |
| `cat_id` | VARCHAR(50) | Category identifier | Extracted from chars 1-5 of prd_key, hyphen replaced with underscore |
| `prd_key` | VARCHAR(50) | Product business key | Extracted from char 7 onward of raw prd_key |
| `prd_nm` | VARCHAR(50) | Product name | TRIM applied |
| `prd_cost` | INT | Product cost | NULL or empty defaults to 0, cast from VARCHAR |
| `prd_line` | VARCHAR(50) | Product line | Decoded: M to MOUNTAIN, R to ROADS, S to OTHER SALES, T to TOURING |
| `prd_start_dt` | DATE | Version start date | Cast from VARCHAR |
| `prd_end_dt` | DATE | Version end date | Derived via LEAD() minus 1 day. NULL becomes 9999-12-31 |
| `dwh_create_date` | TIMESTAMP | Silver load timestamp | Set by Silver procedure |

**Business rules applied:**
- `prd_end_dt` derived as one day before the next version's `prd_start_dt`
- `prd_end_dt` of 9999-12-31 means this is the currently active version
- Rows with NULL or empty `prd_start_dt` excluded

---

### silver.crm_sales_details

**Source:** `bronze.crm_sales_details`

**Description:** Cleaned and validated sales transactions. One row per order line. Approximately 64,000 rows.

| Column | Type | Description | Transformation |
|---|---|---|---|
| `sls_ord_num` | VARCHAR(50) | Order number | No change |
| `sls_prd_key` | VARCHAR(50) | Product key | No change — links to silver.crm_prd_info.prd_key |
| `sls_cust_id` | INT | Customer identifier | Cast from VARCHAR |
| `sls_order_dt` | DATE | Order date | Parsed from YYYYMMDD. Value 0 or length not 8 becomes NULL |
| `sls_ship_dt` | DATE | Ship date | Same as sls_order_dt |
| `sls_due_dt` | DATE | Due date | Same as sls_order_dt |
| `sls_sales` | INT | Sales amount | Recalculated as quantity x ABS(price) when NULL, zero, or inconsistent |
| `sls_quantity` | INT | Quantity sold | Cast from VARCHAR |
| `sls_price` | INT | Unit price | Derived as sales divided by quantity when NULL or less than or equal to 0 |
| `dwh_create_date` | TIMESTAMP | Silver load timestamp | Set by Silver procedure |

**Business rules applied:**
- sales = quantity x price enforced — recalculated when violated
- Negative prices corrected using ABS()
- Division by zero on price derivation protected with NULLIF(quantity, 0)
- Rows where `sls_ord_num` is NULL excluded

---

### silver.erp_cust_az12

**Source:** `bronze.erp_cust_az12`

**Description:** Cleaned ERP customer supplement. Birth dates validated. Gender decoded.

| Column | Type | Description | Transformation |
|---|---|---|---|
| `cid` | VARCHAR(50) | Customer identifier | NAS prefix stripped for CRM join compatibility |
| `bdate` | DATE | Birth date | Cast from VARCHAR. Future dates become NULL |
| `gen` | VARCHAR(50) | Gender | Decoded: M or Male to MALE, F or Female to FEMALE, else UNKNOWN |
| `dwh_create_date` | TIMESTAMP | Silver load timestamp | Set by Silver procedure |

---

### silver.erp_loc_a101

**Source:** `bronze.erp_loc_a101`

**Description:** Cleaned customer location data. Country codes standardised to full names.

| Column | Type | Description | Transformation |
|---|---|---|---|
| `cid` | VARCHAR(50) | Customer identifier | Hyphens stripped for CRM join compatibility |
| `cntry` | VARCHAR(50) | Country | Standardised: US, USA, United States all become USA. DE becomes GERMANY. Blank or NULL becomes UNKNOWN |
| `dwh_create_date` | TIMESTAMP | Silver load timestamp | Set by Silver procedure |

---

### silver.erp_px_cat_g1v2

**Source:** `bronze.erp_px_cat_g1v2`

**Description:** Product category lookup. No transformations required — data passes through from Bronze unchanged.

| Column | Type | Description | Transformation |
|---|---|---|---|
| `id` | VARCHAR(50) | Category identifier | No change — matches cat_id in silver.crm_prd_info |
| `cat` | VARCHAR(50) | Category name | No change |
| `subcat` | VARCHAR(50) | Subcategory name | No change |
| `maintenance` | VARCHAR(50) | Maintenance flag | No change |
| `dwh_create_date` | TIMESTAMP | Silver load timestamp | Set by Silver procedure |

---

## Gold Layer

> Business-ready star schema. Optimised for BI tools, dashboards, and SQL analytics.
> All objects are views — they reflect Silver data in real time.
> No load step required — Gold updates automatically when Silver is reloaded.

**Star schema:**

| Object | Type | Grain | Role |
|---|---|---|---|
| `gold.dim_customers` | View | One row per customer | Dimension |
| `gold.dim_products` | View | One row per active product | Dimension |
| `gold.fact_sales` | View | One row per order line | Fact |

---

### gold.dim_customers

**Type:** View

**Source tables:** `silver.crm_cust_info`, `silver.erp_loc_a101`, `silver.erp_cust_az12`

**Description:** Conformed customer dimension. Integrates CRM and ERP data into one flat denormalised table. One row per customer — current state only.

**Join logic:**

| Join | On | Purpose |
|---|---|---|
| silver.crm_cust_info LEFT JOIN silver.erp_loc_a101 | cst_key = cid | Add country |
| silver.crm_cust_info LEFT JOIN silver.erp_cust_az12 | cst_key = cid | Add birthdate and gender |

| Column | Type | Description | Source |
|---|---|---|---|
| `customer_key` | INT | Surrogate key (PK) | ROW_NUMBER() ordered by customer_id |
| `customer_id` | INT | Natural key from CRM | silver.crm_cust_info.cst_id |
| `customer_number` | VARCHAR(50) | Business key from CRM | silver.crm_cust_info.cst_key |
| `first_name` | VARCHAR(50) | First name | silver.crm_cust_info.cst_firstname |
| `last_name` | VARCHAR(50) | Last name | silver.crm_cust_info.cst_lastname |
| `country` | VARCHAR(50) | Country | silver.erp_loc_a101.cntry |
| `marital_status` | VARCHAR(20) | Marital status | silver.crm_cust_info.cst_marital_status |
| `gender` | VARCHAR(20) | Gender | CRM primary, ERP fallback when CRM is UNKNOWN |
| `birthdate` | DATE | Birth date | silver.erp_cust_az12.bdate |
| `create_date` | DATE | CRM account creation date | silver.crm_cust_info.cst_create_date |

**Sample query:**
```sql
SELECT country, COUNT(*) AS customers
FROM gold.dim_customers
GROUP BY country
ORDER BY customers DESC;
```

---

### gold.dim_products

**Type:** View

**Source tables:** `silver.crm_prd_info`, `silver.erp_px_cat_g1v2`

**Description:** Product dimension containing currently active products only. Historical versions filtered out. Category and subcategory enriched from ERP.

**Filter:** WHERE prd_end_dt = '9999-12-31' — current products only.

**Join logic:**

| Join | On | Purpose |
|---|---|---|
| silver.crm_prd_info LEFT JOIN silver.erp_px_cat_g1v2 | cat_id = id | Add category and subcategory |

| Column | Type | Description | Source |
|---|---|---|---|
| `product_key` | INT | Surrogate key (PK) | ROW_NUMBER() ordered by start_date, product_number |
| `product_id` | INT | Natural key from CRM | silver.crm_prd_info.prd_id |
| `product_number` | VARCHAR(50) | Business key from CRM | silver.crm_prd_info.prd_key |
| `category_id` | VARCHAR(50) | Category identifier | silver.crm_prd_info.cat_id |
| `product_name` | VARCHAR(50) | Product name | silver.crm_prd_info.prd_nm |
| `cost` | INT | Product cost | silver.crm_prd_info.prd_cost |
| `product_line` | VARCHAR(50) | Product line | silver.crm_prd_info.prd_line |
| `start_date` | DATE | Active since | silver.crm_prd_info.prd_start_dt |
| `category` | VARCHAR(50) | Category name | silver.erp_px_cat_g1v2.cat |
| `subcategory` | VARCHAR(50) | Subcategory name | silver.erp_px_cat_g1v2.subcat |
| `maintenance` | VARCHAR(50) | Maintenance flag | silver.erp_px_cat_g1v2.maintenance |

**Sample query:**
```sql
SELECT category, subcategory, COUNT(*) AS products
FROM gold.dim_products
GROUP BY category, subcategory
ORDER BY category, subcategory;
```

---

### gold.fact_sales

**Type:** View

**Source tables:** `silver.crm_sales_details`, `gold.dim_products`, `gold.dim_customers`

**Description:** Central fact table. One row per sales order line. Contains foreign keys to both dimensions and three additive numeric measures.

**Grain:** One row = one sales order line item.

**Join logic:**

| Join | On | Purpose |
|---|---|---|
| silver.crm_sales_details LEFT JOIN gold.dim_products | sls_prd_key = product_number | Resolve product surrogate key |
| silver.crm_sales_details LEFT JOIN gold.dim_customers | sls_cust_id = customer_id | Resolve customer surrogate key |

| Column | Type | Description | Source |
|---|---|---|---|
| `order_number` | VARCHAR(50) | Order identifier — degenerate dimension | silver.crm_sales_details.sls_ord_num |
| `product_key` | INT | FK to gold.dim_products | Resolved via sls_prd_key = product_number |
| `customer_key` | INT | FK to gold.dim_customers | Resolved via sls_cust_id = customer_id |
| `order_date` | DATE | Date order was placed | silver.crm_sales_details.sls_order_dt |
| `shipping_date` | DATE | Date order was shipped | silver.crm_sales_details.sls_ship_dt |
| `due_date` | DATE | Date order was due | silver.crm_sales_details.sls_due_dt |
| `sales_amount` | INT | Total sales value — additive | silver.crm_sales_details.sls_sales |
| `quantity` | INT | Units sold — additive | silver.crm_sales_details.sls_quantity |
| `price` | INT | Unit price — additive | silver.crm_sales_details.sls_price |

**Sample queries:**
```sql
-- total sales by country
SELECT dc.country, SUM(fs.sales_amount) AS total_sales
FROM gold.fact_sales fs
LEFT JOIN gold.dim_customers dc ON fs.customer_key = dc.customer_key
GROUP BY dc.country
ORDER BY total_sales DESC;

-- total sales by product category and year
SELECT
    dp.category,
    EXTRACT(YEAR FROM fs.order_date) AS year,
    SUM(fs.sales_amount) AS total_sales
FROM gold.fact_sales fs
LEFT JOIN gold.dim_products dp ON fs.product_key = dp.product_key
GROUP BY dp.category, year
ORDER BY year, total_sales DESC;

-- referential integrity check
SELECT COUNT(*) AS missing_customer FROM gold.fact_sales WHERE customer_key IS NULL;
SELECT COUNT(*) AS missing_product  FROM gold.fact_sales WHERE product_key  IS NULL;
```

---

## Pipeline Execution Order
```sql
-- Step 1: run once on a new environment
-- execute init_database.sql in DBeaver

-- Step 2: load Bronze
CALL bronze.load_bronze();

-- Step 3: load Silver
CALL silver.load_silver();

-- Step 4: Gold is live automatically
SELECT * FROM gold.fact_sales LIMIT 10;
```

---

## Data Quality Checks

Full check queries are in `tests/bronze_quality_checks.sql`.

| Check | Pattern | Expected result |
|---|---|---|
| No NULL primary keys | WHERE cst_id IS NULL | 0 rows |
| No duplicate keys | GROUP BY key HAVING COUNT(*) > 1 | 0 rows |
| No orphaned fact rows | LEFT JOIN dim WHERE key IS NULL | 0 rows |
| Sales rule: sales = qty x price | WHERE sales != qty * price | 0 rows |
| No future birth dates | WHERE bdate > CURRENT_DATE | 0 rows |
| Pipeline ran today | WHERE dwh_create_date::DATE = CURRENT_DATE | more than 0 rows |

---

## Glossary

| Term | Definition |
|---|---|
| **Bronze** | Raw ingestion layer — data stored exactly as received from source |
| **Silver** | Cleaned and typed layer — business rules applied, types enforced |
| **Gold** | Business-ready layer — star schema optimised for analytics |
| **Surrogate key** | Warehouse-generated integer PK with no business meaning |
| **Natural key** | Business identifier from the source system |
| **SCD2** | Slowly Changing Dimension Type 2 — new row per change, history preserved |
| **Conformed dimension** | Dimension shared identically across multiple fact tables |
| **Grain** | The level of detail represented by one row in a fact table |
| **Degenerate dimension** | A dimension attribute stored directly on the fact table with no dimension table |
| **Additive measure** | A numeric measure safe to SUM across any dimension |
| **Watermark** | Timestamp marking the last successfully loaded record |
| **dwh_create_date** | Warehouse audit column recording when a row was loaded into that layer |
| **9999-12-31** | Sentinel date used to indicate a currently active SCD2 record |
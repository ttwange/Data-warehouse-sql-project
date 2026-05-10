# Data Warehouse SQL Project

A modern data warehouse built with PostgreSQL 16 following the Medallion Architecture
(Bronze → Silver → Gold), consolidating sales data from CRM and ERP source systems
to enable analytical reporting and informed decision-making.
# Notion project live project:https://motley-revolve-f1e.notion.site/Data-Warehouse-Project-34cb4b2fedf280dca8fbe6cb9d34be7f

---

## Table of Contents

- [Data Warehouse SQL Project](#data-warehouse-sql-project)
  - [Table of Contents](#table-of-contents)
  - [Project Overview](#project-overview)
    - [What this project delivers](#what-this-project-delivers)
  - [Architecture](#architecture)
  - [](#)
  - [Data Sources](#data-sources)
    - [CRM Source — `datasets/source_crm/`](#crm-source--datasetssource_crm)
    - [ERP Source — `datasets/source_erp/`](#erp-source--datasetssource_erp)
  - [](#-1)
  - [Data Flow](#data-flow)
  - [](#-2)
  - [Data Model](#data-model)
  - [](#-3)
  - [Quick Start](#quick-start)
    - [Prerequisites](#prerequisites)
    - [Step 1 — Clone the repository](#step-1--clone-the-repository)
    - [Step 2 — Configure and start the Docker container](#step-2--configure-and-start-the-docker-container)
    - [Step 3 — Initialise the database](#step-3--initialise-the-database)
    - [Step 4 — Load Bronze](#step-4--load-bronze)
    - [Step 5 — Load Silver](#step-5--load-silver)
    - [Step 6 — Query Gold](#step-6--query-gold)
  - [Layer Details](#layer-details)
    - [Bronze — Raw Ingestion](#bronze--raw-ingestion)
    - [Silver — Cleansed and Typed](#silver--cleansed-and-typed)
    - [Gold — Star Schema](#gold--star-schema)
  - [Analytics and Reporting](#analytics-and-reporting)
    - [Customer Behaviour](#customer-behaviour)
    - [Product Performance](#product-performance)
    - [Sales Trends](#sales-trends)
  - [Data Quality](#data-quality)
    - [Quality dimensions checked](#quality-dimensions-checked)
    - [Key checks](#key-checks)
  - [Documentation and Resources](#documentation-and-resources)
  - [Contributing](#contributing)

---

## Project Overview

| Property | Detail |
|---|---|
| **Author** | thonne |
| **Database** | PostgreSQL 16 |
| **Architecture** | Medallion — Bronze, Silver, Gold |
| **Source systems** | CRM and ERP (CSV files) |
| **Scope** | Latest dataset only — historization not required for dimension tables |
| **Goal** | Consolidate sales data into a single analytical model |

### What this project delivers

This project builds a full end-to-end data warehouse pipeline covering three areas.

**Data Engineering** — a modern warehouse that ingests raw CRM and ERP data, cleanses
and resolves quality issues, integrates both sources into a single conformed model,
and serves business-ready tables for analytical queries.

**Data Quality** — every layer validates completeness, uniqueness, consistency,
and referential integrity before data is promoted to the next layer.

**Analytics and Reporting** — SQL-based views and queries that deliver insights
into customer behaviour, product performance, and sales trends to support
strategic decision-making.

---

## Architecture

This project follows the **Medallion Architecture** — a three-layer pattern
where data is progressively refined from raw to business-ready.

![alt text](<Data Warehouse_ Sales.drawio-1.png>)
---

## Data Sources

Two source systems are integrated — a CRM system and an ERP system.
Both are provided as CSV files and loaded into the Bronze layer as-is.

### CRM Source — `datasets/source_crm/`

| File | Description | Approx rows |
|---|---|---|
| `cust_info.csv` | Customer records — names, gender, marital status, create date | 18,000+ |
| `prd_info.csv` | Product catalogue — product key, cost, line, versioned dates | 300+ |
| `sales_details.csv` | Sales transactions — order number, product, customer, dates, amounts | 64,000+ |

### ERP Source — `datasets/source_erp/`

| File | Description | Approx rows |
|---|---|---|
| `cust_az12.csv` | Customer supplement — birth date and gender | 18,000+ |
| `loc_a101.csv` | Customer location — country mapping | 18,000+ |
| `px_cat_g1v2.csv` | Product category lookup — category, subcategory, maintenance | 40+ |

> **Data integration mapping:** See `data integration mapping.drawio` for the full
> source-to-target column mapping across all six files.
![alt text](<Data Integration mapping.jpg>)
---

## Data Flow
> **Full data flow diagram:** See `data flow diagram.drawio` in the project diagrams folder.
![alt text](<Data Flow Diagram.jpg>)
---

## Data Model

The Gold layer implements a **star schema** — the industry standard for analytical
data warehouses. A central fact table holds measurable business events and connects
to flat dimension tables through surrogate keys.

**Grain:** One row in `fact_sales` = one sales order line item.

**Measures:** `sales_amount`, `quantity`, and `price` are fully additive —
safe to SUM across any combination of dimensions.

> **Full data model diagram:** See `data model.drawio` in the project diagrams folder.
> **Column-level detail:** See `docs/data_catalog.md`.

![alt text](<data model.jpg>)
---

## Quick Start

### Prerequisites

- Docker installed and running
- DBeaver or any PostgreSQL client
- Git

### Step 1 — Clone the repository

```bash
git clone https://github.com/ttwange/Data-warehouse-sql-project.git
cd Data-warehouse-sql-project
```

### Step 2 — Configure and start the Docker container

Open `infrastructure/docker_setup.sh` and set your credentials in the CONFIG section,
then run:

```bash
bash infrastructure/docker_setup.sh
```

This creates a PostgreSQL 16 container with two volume mounts:
- `pgdata` — persists your database across container restarts
- `/datasets` — makes your CSV files visible to the server for COPY commands

Verify the container is running:

```bash
docker ps
docker exec -it pg_warehouse ls /datasets
```

### Step 3 — Initialise the database

Connect to `data_warehouse` in DBeaver and run:

```sql
-- creates the database and Bronze, Silver, Gold schemas
-- run init_database.sql
```

### Step 4 — Load Bronze

```sql
CALL bronze.load_bronze();
```

Expected output:

### Step 5 — Load Silver

```sql
CALL silver.load_silver();
```

Expected output:

### Step 6 — Query Gold

Gold views are live automatically after Silver loads. No additional step needed.

```sql
-- verify the star schema
SELECT COUNT(*) FROM gold.dim_customers;
SELECT COUNT(*) FROM gold.dim_products;
SELECT COUNT(*) FROM gold.fact_sales;

-- first analytical query
SELECT
    dc.country,
    SUM(fs.sales_amount) AS total_sales,
    COUNT(fs.order_number) AS total_orders
FROM gold.fact_sales fs
LEFT JOIN gold.dim_customers dc ON fs.customer_key = dc.customer_key
GROUP BY dc.country
ORDER BY total_sales DESC;
```

---

## Layer Details

### Bronze — Raw Ingestion

**Philosophy:** Accept everything, reject nothing, store as text.

- All columns stored as VARCHAR regardless of source type
- No transformations applied — data lands exactly as received
- Append-only audit column `dwh_create_date` records when each row was loaded
- Full load pattern — truncate and reload on every run
- If Silver or Gold logic is wrong, Bronze is the source of truth for reprocessing

**Tables:** `crm_cust_info`, `crm_prd_info`, `crm_sales_details`,
`erp_cust_az12`, `erp_loc_a101`, `erp_px_cat_g1v2`

### Silver — Cleansed and Typed

**Philosophy:** Question everything, clean and cast with explicit logic.

Key transformations applied across Silver tables:

| Transformation | Example |
|---|---|
| Cast VARCHAR to INT | `cst_id::INT` |
| Cast VARCHAR to DATE | `TO_DATE(sls_order_dt, 'YYYYMMDD')` |
| Trim whitespace | `TRIM(cst_firstname)` |
| Decode single-letter codes | `M` to `MALE`, `S` to `SINGLE` |
| Handle sentinel values | `0` in date columns becomes NULL |
| Cross-validate business rules | `sales = quantity x price` enforced |
| Deduplicate with ROW_NUMBER | Keep most recent record per customer |
| Derive SCD2 end dates | `LEAD(prd_start_dt) - INTERVAL '1 day'` |
| Strip source prefixes | NAS prefix removed from ERP customer ids |
| Standardise country codes | `US`, `USA`, `United States` all become `USA` |
| Gender source priority | CRM is primary, ERP fills gap when CRM is UNKNOWN |

**Tables:** `crm_cust_info`, `crm_prd_info`, `crm_sales_details`,
`erp_cust_az12`, `erp_loc_a101`, `erp_px_cat_g1v2`

### Gold — Star Schema

**Philosophy:** Trust everything, optimise for queries.

- Fully denormalised star schema — no joins needed within a dimension
- Surrogate keys generated by `ROW_NUMBER()` — integer joins are faster than strings
- Natural keys preserved alongside surrogate keys for traceability
- `dim_customers` integrates three Silver sources into one flat table
- `dim_products` filters to current active products only (`prd_end_dt = '9999-12-31'`)
- `fact_sales` resolves surrogate keys from both dimensions via LEFT JOIN

**Views:** `dim_customers`, `dim_products`, `fact_sales`

---

## Analytics and Reporting

The Gold layer is designed to answer three categories of business questions.

### Customer Behaviour

```sql
-- customers by country
SELECT country, COUNT(*) AS customers
FROM gold.dim_customers
GROUP BY country
ORDER BY customers DESC;

-- customers by gender and marital status
SELECT gender, marital_status, COUNT(*) AS customers
FROM gold.dim_customers
GROUP BY gender, marital_status
ORDER BY customers DESC;

-- average order value per customer segment
SELECT
    dc.country,
    dc.gender,
    ROUND(AVG(fs.sales_amount), 2) AS avg_order_value
FROM gold.fact_sales fs
LEFT JOIN gold.dim_customers dc ON fs.customer_key = dc.customer_key
GROUP BY dc.country, dc.gender
ORDER BY avg_order_value DESC;
```

### Product Performance

```sql
-- revenue by product category
SELECT
    dp.category,
    dp.subcategory,
    SUM(fs.sales_amount) AS total_revenue,
    SUM(fs.quantity) AS units_sold
FROM gold.fact_sales fs
LEFT JOIN gold.dim_products dp ON fs.product_key = dp.product_key
GROUP BY dp.category, dp.subcategory
ORDER BY total_revenue DESC;

-- top 10 products by revenue
SELECT
    dp.product_name,
    dp.category,
    SUM(fs.sales_amount) AS total_revenue
FROM gold.fact_sales fs
LEFT JOIN gold.dim_products dp ON fs.product_key = dp.product_key
GROUP BY dp.product_name, dp.category
ORDER BY total_revenue DESC
LIMIT 10;
```

### Sales Trends

```sql
-- monthly sales trend
SELECT
    EXTRACT(YEAR FROM fs.order_date) AS year,
    EXTRACT(MONTH FROM fs.order_date) AS month,
    SUM(fs.sales_amount) AS monthly_sales,
    COUNT(DISTINCT fs.order_number) AS orders
FROM gold.fact_sales fs
GROUP BY year, month
ORDER BY year, month;

-- year over year comparison
SELECT
    EXTRACT(YEAR FROM order_date) AS year,
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT order_number) AS total_orders,
    ROUND(AVG(sales_amount), 2) AS avg_order_value
FROM gold.fact_sales
GROUP BY year
ORDER BY year;
```

---

## Data Quality

Quality checks are applied at each layer before promotion to the next.

### Quality dimensions checked

| Dimension | What is checked | Where |
|---|---|---|
| **Completeness** | No NULL values in required fields | Bronze and Silver |
| **Uniqueness** | No duplicate primary or business keys | Bronze and Silver |
| **Validity** | Values within expected domains | Silver |
| **Consistency** | Business rules hold across columns | Silver |
| **Timeliness** | Pipeline ran and data is current | All layers |
| **Referential integrity** | FK values exist in parent dimension | Gold |

### Key checks

| Check | Expected result |
|---|---|
| No NULL cst_id in silver.crm_cust_info | 0 rows |
| No duplicate cst_id after dedup | 0 rows |
| sales = quantity x price in silver.crm_sales_details | 0 rows violated |
| No future birth dates in silver.erp_cust_az12 | 0 rows |
| No orphaned rows in gold.fact_sales | 0 NULL customer_key or product_key |
| Pipeline ran today | dwh_create_date = CURRENT_DATE in all tables |

Full check scripts: `tests/bronze_quality_checks.sql`

---

## Documentation and Resources

| Resource | Location | Description |
|---|---|---|
| Data catalog | `docs/data_catalog.md` | Column-level documentation for all 15 objects |
| Architecture diagram | `data warehouse:sales.drawio` | End-to-end Medallion architecture |
| Data flow diagram | `data flow diagram.drawio` | Source to Gold data movement |
| Integration mapping | `data integration mapping.drawio` | Source column to target column mapping |
| Data model diagram | `data model.drawio` | Star schema ERD |
| Project notion page | https://motley-revolve-f1e.notion.site/Data-Warehouse-Project-34cb4b2fedf280dca8fbe6cb9d34be7f | Project planning and notes |

---

## Contributing

This is a learning project. To extend it:

1. Pull the latest version before starting

```bash
git pull origin main
```

2. Make changes to the relevant SQL scripts

3. Test by rerunning the stored procedures

```sql
CALL bronze.load_bronze();
CALL silver.load_silver();
SELECT COUNT(*) FROM gold.fact_sales;
```

4. Commit with a descriptive prefix

```bash
git add .
git commit -m "silver: add validation for duplicate order numbers"
git push origin main
```

**Commit prefix conventions:**

| Prefix | Use for |
|---|---|
| `init:` | Database and schema setup |
| `infra:` | Docker and infrastructure changes |
| `bronze:` | Bronze layer changes |
| `silver:` | Silver layer changes |
| `gold:` | Gold layer changes |
| `tests:` | Quality check scripts |
| `docs:` | Documentation updates |
| `fix:` | Bug fixes |
| `chore:` | Maintenance — gitignore, formatting |

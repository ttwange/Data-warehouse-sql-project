-- row counts across all three Gold objects
SELECT 'dim_customers' AS object_name, COUNT(*) AS rows FROM gold.dim_customers
UNION ALL
SELECT 'dim_products',                 COUNT(*) FROM gold.dim_products
UNION ALL
SELECT 'fact_sales',                   COUNT(*) FROM gold.fact_sales;

-- referential integrity — sales with no matching customer
SELECT COUNT(*) AS orphaned_customers
FROM gold.fact_sales
WHERE customer_key IS NULL;

-- referential integrity — sales with no matching product
SELECT COUNT(*) AS orphaned_products
FROM gold.fact_sales
WHERE product_key IS NULL;

-- first analytical query on the star schema
-- total sales by country
SELECT
    dc.country,
    SUM(fs.sales_amount)    AS total_sales,
    COUNT(fs.order_number)  AS total_orders,
    SUM(fs.quantity)        AS total_quantity
FROM gold.fact_sales fs
LEFT JOIN gold.dim_customers dc ON fs.customer_key = dc.customer_key
GROUP BY dc.country
ORDER BY total_sales DESC;

-- total sales by product category
SELECT
    dp.category,
    dp.subcategory,
    SUM(fs.sales_amount)    AS total_sales,
    COUNT(fs.order_number)  AS total_orders
FROM gold.fact_sales fs
LEFT JOIN gold.dim_products dp ON fs.product_key = dp.product_key
GROUP BY dp.category, dp.subcategory
ORDER BY total_sales DESC;
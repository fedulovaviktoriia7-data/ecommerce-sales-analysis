--01_data_quality_checks.sql
-- 1. order_id in Fact_Sales must be unique (expecting 0 rows)
SELECT order_id, COUNT(*)
FROM fact_sales
GROUP BY order_id
HAVING COUNT(*) > 1;

-- 2. Order lines without a matching order in fact_sales (expect 0)
SELECT COUNT(*)
FROM order_items oi
LEFT JOIN fact_sales fs ON fs.order_id = oi.order_id
WHERE fs.order_id IS NULL;

-- 3. Order lines with a product missing from dim_products (expect 0)
SELECT COUNT(*)
FROM order_items oi
LEFT JOIN dim_products p ON p.product_id = oi.product_id
WHERE p.product_id IS NULL;

-- 4. Orders with a customer missing from dim_customers (expect 0)
SELECT COUNT(*)
FROM fact_sales fs
LEFT JOIN dim_customers c ON c.customer_id = fs.customer_id
WHERE c.customer_id IS NULL;

-- 5. Does net_sales follow the formula? (expect 0 rows)
SELECT order_id, net_sales,
       gross_sales - discount_amount + tax_amount + shipping_cost AS calc
FROM fact_sales
WHERE ABS(net_sales - (gross_sales - discount_amount + tax_amount + shipping_cost)) > 0.05;

-- 6. Do quantities match between fact_sales and order_items? (expect 0 rows)
SELECT fs.order_id, fs.quantity, SUM(oi.quantity) AS items_qty
FROM fact_sales fs
JOIN order_items oi ON oi.order_id = fs.order_id
GROUP BY fs.order_id, fs.quantity
HAVING fs.quantity <> SUM(oi.quantity);

-- 7. Average gross_sales by currency (are amounts comparable?)
SELECT currency, COUNT(*) AS orders, ROUND(AVG(gross_sales), 2) AS avg_gross
FROM fact_sales
GROUP BY currency

-- A. How many orders mismatch out of all orders?
SELECT COUNT(*) FILTER (WHERE fs.quantity <> oi.items_qty) AS mismatched,
       COUNT(*) AS total_orders
FROM fact_sales fs
JOIN (SELECT order_id, SUM(quantity) AS items_qty
      FROM order_items
      GROUP BY order_id) oi ON oi.order_id = fs.order_id;

-- B. How many rows per order are in order_items?
SELECT rows_per_order, COUNT(*) AS orders
FROM (SELECT order_id, COUNT(*) AS rows_per_order
      FROM order_items
      GROUP BY order_id) t
GROUP BY rows_per_order
ORDER BY rows_per_order;

-- C. Exact duplicate lines in order_items
SELECT order_id, product_id, quantity, unit_price, COUNT(*) AS copies
FROM order_items
GROUP BY order_id, product_id, quantity, unit_price
HAVING COUNT(*) > 1
LIMIT 20;

-- D. Look at one mismatched order in both tables
SELECT * FROM order_items WHERE order_id = 'ORD-990295';
SELECT order_id, quantity, gross_sales, discount_amount FROM fact_sales WHERE order_id = 'ORD-990295';

-- E. For orders where quantity matches, does the line total match gross_sales?
WITH oi AS (
    SELECT order_id,
           SUM(quantity) AS items_qty,
           SUM(quantity * unit_price) AS items_total
    FROM order_items
    GROUP BY order_id
)
SELECT COUNT(*) AS qty_matched_orders,
       COUNT(*) FILTER (WHERE ABS(fs.gross_sales - oi.items_total) <= 1) AS also_amount_matched
FROM fact_sales fs
JOIN oi ON oi.order_id = fs.order_id
WHERE fs.quantity = oi.items_qty;

-- profit = net_sales - product_cost - shipping_cost ? (expect 0 violations)
SELECT COUNT(*) AS total_orders,
       COUNT(*) FILTER (
           WHERE ABS(profit - (net_sales - product_cost - shipping_cost)) > 0.05
       ) AS profit_violations
FROM fact_sales;

CREATE VIEW order_items_clean AS
WITH oi AS (
    SELECT order_id, SUM(quantity) AS items_qty
    FROM order_items
    GROUP BY order_id
)
SELECT o.*
FROM order_items o
JOIN oi ON oi.order_id = o.order_id
JOIN fact_sales fs ON fs.order_id = o.order_id
                  AND fs.quantity = oi.items_qty;

SELECT COUNT(DISTINCT order_id) FROM order_items_clean;
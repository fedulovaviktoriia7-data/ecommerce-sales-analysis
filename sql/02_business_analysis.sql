02_business_analysis.sql
-- Q1. Monthly revenue and month-over-month growth.
-- Q1.  Finding: Monthly revenue is volatile; yearly revenue is flat (~25.5M, within ±2.1%).
WITH monthly AS (
    SELECT DATE_TRUNC('month', order_date) AS month,
           SUM(gross_sales - discount_amount) AS revenue
    FROM fact_sales
    WHERE order_status = 'Completed'
    GROUP BY 1
)
SELECT month,
       ROUND(revenue, 2) AS revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month))
             / LAG(revenue) OVER (ORDER BY month), 1) AS mom_growth_pct
FROM monthly
ORDER BY month;

-- Q1b. Yearly revenue and year-over-year growth.
-- Q1b. Finding: No long-term growth: revenue stays around 25.5M per year in 2021-2025.
WITH yearly AS (
    SELECT EXTRACT(YEAR FROM order_date)::int AS year,
           SUM(gross_sales - discount_amount) AS revenue
    FROM fact_sales
    WHERE order_status = 'Completed'
    GROUP BY 1
)
SELECT year,
       ROUND(revenue, 2) AS revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY year))
             / LAG(revenue) OVER (ORDER BY year), 1) AS yoy_growth_pct
FROM yearly
ORDER BY year;

-- Q2. Revenue, profit and margin by sales channel
-- Q2.  Finding: Mobile App and Website bring ~75% of revenue; margin is ~36% in every channel.
SELECT sales_channel,
       COUNT(*) AS orders,
       ROUND(SUM(gross_sales - discount_amount), 2) AS revenue,
       ROUND(SUM(gross_sales - discount_amount - product_cost), 2) AS profit,
       ROUND(100.0 * SUM(gross_sales - discount_amount - product_cost)
             / SUM(gross_sales - discount_amount), 1) AS margin_pct
FROM fact_sales
WHERE order_status = 'Completed'
GROUP BY sales_channel
ORDER BY revenue DESC;

-- Q3. Top 10 product categories (reconciled orders only)
-- Q3.  Finding: Electronics leads (31.5M before discounts); Sports & Outdoors sells most units but is 5th by revenue.
SELECT p.product_category,
       SUM(oi.quantity) AS units_sold,
       ROUND(SUM(oi.quantity * oi.unit_price), 2) AS gross_revenue
FROM order_items_clean oi
JOIN dim_products p ON p.product_id = oi.product_id
JOIN fact_sales fs ON fs.order_id = oi.order_id
WHERE fs.order_status = 'Completed'
GROUP BY p.product_category
ORDER BY gross_revenue DESC
LIMIT 10;

-- Q4. Top 3 products inside each category
-- Q4.  Finding: The top product in each category brings only ~2-3% of its category revenue.
WITH product_rev AS (
    SELECT p.product_category, p.product_name,
           SUM(oi.quantity * oi.unit_price) AS gross_revenue
    FROM order_items_clean oi
    JOIN dim_products p ON p.product_id = oi.product_id
    JOIN fact_sales fs ON fs.order_id = oi.order_id
    WHERE fs.order_status = 'Completed'
    GROUP BY p.product_category, p.product_name
)
SELECT product_category, product_name, ROUND(gross_revenue, 2) AS gross_revenue, rnk
FROM (
    SELECT *,
           RANK() OVER (PARTITION BY product_category ORDER BY gross_revenue DESC) AS rnk
    FROM product_rev
) t
WHERE rnk <= 3
ORDER BY product_category, rnk;

-- Q5. Top 10 customers and their share of total revenue
-- Q5.  Finding: Top 10 customers bring only ~0.2% of revenue; no dependence on big customers.
SELECT c.customer_id, c.customer_name,
       ROUND(SUM(fs.gross_sales - fs.discount_amount), 2) AS revenue,
       ROUND(100.0 * SUM(fs.gross_sales - fs.discount_amount)
             / SUM(SUM(fs.gross_sales - fs.discount_amount)) OVER (), 2) AS revenue_share_pct
FROM fact_sales fs
JOIN dim_customers c ON c.customer_id = fs.customer_id
WHERE fs.order_status = 'Completed'
GROUP BY c.customer_id, c.customer_name
ORDER BY revenue DESC
LIMIT 10;

-- Q6. Revenue and average order value by customer country
-- Q6.  Finding: US ~60% of revenue, UK ~15%, Germany ~8%; average order value is similar everywhere.
SELECT c.customer_country,
       COUNT(*) AS orders,
       ROUND(SUM(fs.gross_sales - fs.discount_amount), 2) AS revenue,
       ROUND(AVG(fs.gross_sales - fs.discount_amount), 2) AS avg_order_value
FROM fact_sales fs
JOIN dim_customers c ON c.customer_id = fs.customer_id
WHERE fs.order_status = 'Completed'
GROUP BY c.customer_country
ORDER BY revenue DESC;

-- Q7. Do bigger discounts reduce margin?
-- Q7.  Finding: Margin drops with bigger discounts: 45% (under 10%), 39% (10-25%), 19% (over 25%).
SELECT CASE
           WHEN discount_amount = 0 THEN '1. No discount'
           WHEN discount_amount / gross_sales < 0.10 THEN '2. Under 10%'
           WHEN discount_amount / gross_sales < 0.25 THEN '3. 10-25%'
           ELSE '4. Over 25%'
       END AS discount_band,
       COUNT(*) AS orders,
       ROUND(100.0 * SUM(gross_sales - discount_amount - product_cost)
             / SUM(gross_sales - discount_amount), 1) AS margin_pct
FROM fact_sales
WHERE order_status = 'Completed' AND gross_sales > 0
GROUP BY 1
ORDER BY 1;

-- Q8. Marketing channels: revenue, profit and margin
-- Q8.  Finding: Organic Search is the largest channel (20%); margin ~36% everywhere; no cost data for ROI.
SELECT marketing_channel,
       COUNT(*) AS orders,
       ROUND(SUM(gross_sales - discount_amount), 2) AS revenue,
       ROUND(SUM(gross_sales - discount_amount - product_cost), 2) AS profit,
       ROUND(100.0 * SUM(gross_sales - discount_amount - product_cost)
             / SUM(gross_sales - discount_amount), 1) AS margin_pct
FROM fact_sales
WHERE order_status = 'Completed'
GROUP BY marketing_channel
ORDER BY profit DESC;

-- Q9. Cancellation and payment failure rates by payment method (all orders)
-- Q9.  Finding: Cancellations (~6%) and failed payments (~7.5%) are similar for all payment methods.
SELECT payment_method,
       COUNT(*) AS orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE order_status = 'Cancelled') / COUNT(*), 1) AS cancelled_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE payment_status = 'Failed') / COUNT(*), 1) AS failed_pct
FROM fact_sales
GROUP BY payment_method
ORDER BY cancelled_pct DESC;

-- Q10. Repeat customers: share of customers with more than one completed order
-- Q10. Finding: 95% of customers ordered more than once (likely a synthetic dataset).
WITH cust AS (
    SELECT customer_id, COUNT(*) AS orders
    FROM fact_sales
    WHERE order_status = 'Completed'
    GROUP BY customer_id
)
SELECT COUNT(*) AS customers,
       COUNT(*) FILTER (WHERE orders > 1) AS repeat_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE orders > 1) / COUNT(*), 1) AS repeat_customer_pct
FROM cust;

-- Q11. Top 10 months by revenue growth and the marketing channel that drove it
-- Q11. Finding: Biggest growth months are every November (+40-56% vs. October), driven by all channels.
WITH channel_monthly AS (
    SELECT DATE_TRUNC('month', order_date) AS sales_month,
           marketing_channel,
           SUM(gross_sales - discount_amount) AS channel_rev
    FROM fact_sales
    WHERE order_status = 'Completed'
    GROUP BY 1, 2
),
channel_growth AS (
    -- growth of each channel vs. its own previous month
    SELECT sales_month, marketing_channel, channel_rev,
           channel_rev - LAG(channel_rev) OVER (
               PARTITION BY marketing_channel ORDER BY sales_month
           ) AS channel_growth
    FROM channel_monthly
),
monthly AS (
    SELECT sales_month, SUM(channel_rev) AS total_revenue
    FROM channel_monthly
    GROUP BY 1
),
monthly_growth AS (
    SELECT sales_month, total_revenue,
           total_revenue - LAG(total_revenue) OVER (ORDER BY sales_month) AS absolute_growth,
           100.0 * (total_revenue - LAG(total_revenue) OVER (ORDER BY sales_month))
                 / NULLIF(LAG(total_revenue) OVER (ORDER BY sales_month), 0) AS growth_pct
    FROM monthly
),
top_months AS (
    SELECT *
    FROM monthly_growth
    WHERE absolute_growth > 0
    ORDER BY absolute_growth DESC
    LIMIT 10
),
ranked AS (
    SELECT t.*, g.marketing_channel, g.channel_growth,
           ROW_NUMBER() OVER (
               PARTITION BY t.sales_month ORDER BY g.channel_growth DESC
           ) AS rn
    FROM top_months t
    JOIN channel_growth g ON g.sales_month = t.sales_month
    WHERE g.channel_growth IS NOT NULL
)
SELECT TO_CHAR(sales_month, 'YYYY-MM') AS month,
       ROUND(total_revenue, 2) AS revenue,
       ROUND(absolute_growth, 2) AS growth_amount,
       ROUND(growth_pct, 1) AS growth_pct,
       marketing_channel AS channel_driving_growth,
       ROUND(channel_growth, 2) AS channel_growth_amount
FROM ranked
WHERE rn = 1
ORDER BY absolute_growth DESC;

-- Q12. Seasonality: average revenue by calendar month
-- Q12. Finding: November (index 148) and December (158) are the peak; February is the weakest (68).
WITH monthly AS (
    SELECT DATE_TRUNC('month', order_date) AS month,
           SUM(gross_sales - discount_amount) AS revenue
    FROM fact_sales
    WHERE order_status = 'Completed'
    GROUP BY 1
)
SELECT EXTRACT(MONTH FROM month)::int AS month_number,
       ROUND(AVG(revenue), 0) AS avg_revenue,
       ROUND(100.0 * AVG(revenue) / AVG(AVG(revenue)) OVER (), 0) AS index_vs_average
FROM monthly
GROUP BY 1
ORDER BY 1;
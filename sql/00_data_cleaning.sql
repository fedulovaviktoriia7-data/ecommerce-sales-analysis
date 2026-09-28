-- 00_data_cleaning.sql
-- Source: Kaggle e-commerce dataset, imported via Excel into PostgreSQL as text columns.
-- Goal: convert text columns to proper data types (decimal commas, Russian month names, empty values).
-- Run ONCE, top to bottom (after the first run the columns are no longer text).

-- 1. Numeric columns: replace decimal comma with a dot
alter table order_items
alter column unit_price type numeric using replace(unit_price, ',', '.') :: numeric;

alter table fact_sales
alter column gross_sales type numeric using replace(gross_sales, ',', '.') :: numeric,
alter column discount_amount type numeric using replace(discount_amount, ',', '.') :: numeric,
alter column tax_amount type numeric using replace(tax_amount, ',', '.') :: numeric,
alter column shipping_cost type numeric using replace(shipping_cost, ',', '.') :: numeric,
alter column net_sales type numeric using replace(net_sales, ',', '.') :: numeric,
alter column product_cost type numeric using replace(product_cost, ',', '.') :: numeric,
alter column profit type numeric using replace(profit, ',', '.') :: numeric,
alter column profit_margin_percentage type numeric using replace(profit_margin_percentage, ',', '.') :: numeric,
alter column customer_rating type numeric using replace(customer_rating, ',', '.') :: numeric;

-- 2. Dates: month names are in Russian in the source data (they are values, keep them as is)
update fact_sales
set order_date = split_part(order_date, '-', 1) ||'-'||
(case lower(split_part(order_date, '-', 2))
when 'января' then '01' when 'февраля' then '02' when 'марта' then '03' when 'апреля' then '04'
when 'мая' then '05' when 'июня' then '06' when 'июля' then '07' when 'августа' then '08'
when 'сентября' then '09' when 'октября' then '10' when 'ноября' then '11' when 'декабря' then '12'
else split_part(order_date, '-', 2)end)
||'-'|| split_part(order_date, '-', 3);

-- 3. Check BEFORE converting: every month part must have 2 digits (expect 0 rows)
select order_id, order_date
from fact_sales
where length(split_part(order_date, '-', 2)) <>2
or order_date is null;

-- 4. Convert date and time columns
alter table fact_sales
alter column order_date type date using to_date(order_date, 'DD-MM-YYYY');
alter table fact_sales
alter column order_time type time without time zone using order_time::time;

-- 5. dim_customers: empty values are replaced with 0 / False (assumption)
alter table dim_customers
alter column loyalty_points_earned type integer using coalesce(nullif(loyalty_points_earned, ''), '0')::integer,
alter column loyalty_points_redeemed type integer using coalesce(nullif(loyalty_points_redeemed, ''), '0')::integer;

alter table dim_customers
alter column customer_lifetime_value type numeric(10,2)
using coalesce(nullif(replace(customer_lifetime_value, ',', '.'), ''), '0')::numeric(10,2),
alter column is_repeat_customer type boolean
using coalesce(nullif(is_repeat_customer, ''), 'False')::boolean,
alter column customer_order_count type integer
using coalesce(nullif(customer_order_count, ''), '0')::integer;

-- 6. dim_products: empty prices and costs are replaced with 0 (assumption)
alter table dim_products
alter column unit_price type numeric(10,2)
using coalesce(nullif(replace(unit_price, ',', '.'), ''), '0')::numeric(10,2),
alter column product_cost type numeric(10,2)
using coalesce(nullif(replace(product_cost, ',', '.'), ''), '0')::numeric(10,2);
/*
Customer & Revenue Intelligence — FINAL SQL (MySQL 8+)
Dataset: Superstore Orders, expected 9,994 rows.

IMPORTANT IMPORT NOTES
1. Import the Orders sheet only into a table named `superstore`.
2. Dates in `superstore` should be either DATE/DATETIME values or text in DD/MM/YYYY format.
3. Sales, Profit, Discount, and Quantity must be numeric. If import converted them incorrectly, re-import the source before relying on results.
4. This script uses a drop-and-recreate clean table. Back up any table named `superstore_clean` first.
5. Standard dataset checks: 9,994 rows, 5,009 distinct orders, 793 distinct customers,
   Sales = 2,297,200.86, Profit = 286,397.02, profit margin = 12.47%.
*/

-- 01. Source data quality
SELECT COUNT(*) AS source_rows,
       COUNT(DISTINCT `Row ID`) AS distinct_row_ids,
       COUNT(DISTINCT `Order ID`) AS distinct_orders,
       COUNT(DISTINCT `Customer ID`) AS distinct_customers
FROM superstore;

SELECT
  SUM(`Row ID` IS NULL) AS null_row_ids,
  SUM(`Order ID` IS NULL) AS null_order_ids,
  SUM(`Customer ID` IS NULL) AS null_customer_ids,
  SUM(Sales IS NULL) AS null_sales,
  SUM(Profit IS NULL) AS null_profit
FROM superstore;

-- 02. Create a clean table. This preserves every source row; invalid dates remain NULL and are reported below.
DROP TABLE IF EXISTS superstore_clean;
CREATE TABLE superstore_clean AS
SELECT
  `Row ID`, `Order ID`,
  CASE
    WHEN `Order Date` IS NULL THEN NULL
    WHEN CAST(`Order Date` AS CHAR) REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}' THEN DATE(`Order Date`)
    ELSE STR_TO_DATE(CAST(`Order Date` AS CHAR), '%d/%m/%Y')
  END AS `Order Date`,
  CASE
    WHEN `Ship Date` IS NULL THEN NULL
    WHEN CAST(`Ship Date` AS CHAR) REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}' THEN DATE(`Ship Date`)
    ELSE STR_TO_DATE(CAST(`Ship Date` AS CHAR), '%d/%m/%Y')
  END AS `Ship Date`,
  `Ship Mode`, `Customer ID`, `Customer Name`, `Segment`, `Country`, `City`, `State`,
  `Postal Code`, `Region`, `Product ID`, `Category`, `Sub-Category`, `Product Name`,
  CAST(Sales AS DECIMAL(12,2)) AS Sales,
  CAST(Quantity AS SIGNED) AS Quantity,
  CAST(Discount AS DECIMAL(5,4)) AS Discount,
  CAST(Profit AS DECIMAL(12,4)) AS Profit
FROM superstore;

-- Validate clean-table row count and invalid dates. Do not silently ignore discrepancies.
SELECT COUNT(*) AS clean_rows,
       COUNT(DISTINCT `Row ID`) AS distinct_row_ids,
       SUM(`Order Date` IS NULL) AS invalid_order_dates,
       SUM(`Ship Date` IS NULL) AS invalid_ship_dates,
       SUM(Sales IS NULL) AS null_sales,
       SUM(Profit IS NULL) AS null_profit
FROM superstore_clean;

-- 03. Core KPIs (expected to match the standard Superstore Orders table)
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT `Order ID`) AS total_orders,
  COUNT(DISTINCT `Customer ID`) AS total_customers,
  ROUND(SUM(Sales), 2) AS total_sales,
  ROUND(SUM(Profit), 2) AS total_profit,
  ROUND(100 * SUM(Profit) / NULLIF(SUM(Sales), 0), 2) AS profit_margin_pct,
  ROUND(SUM(Sales) / NULLIF(COUNT(DISTINCT `Order ID`), 0), 2) AS average_order_value,
  ROUND(SUM(Sales) / NULLIF(COUNT(DISTINCT `Customer ID`), 0), 2) AS average_customer_sales,
  ROUND(SUM(Profit) / NULLIF(COUNT(DISTINCT `Order ID`), 0), 2) AS average_profit_per_order
FROM superstore_clean;

-- 04. Repeat customers: one customer counts as repeat if they placed >1 distinct order.
WITH customer_orders AS (
  SELECT `Customer ID`, COUNT(DISTINCT `Order ID`) AS total_orders
  FROM superstore_clean
  GROUP BY `Customer ID`
)
SELECT COUNT(*) AS total_customers,
       SUM(total_orders > 1) AS repeat_customers,
       SUM(total_orders = 1) AS one_time_customers,
       ROUND(100 * SUM(total_orders > 1) / COUNT(*), 2) AS repeat_customer_pct
FROM customer_orders;

-- 05. Top 10 customers' share of total sales
WITH customer_sales AS (
  SELECT `Customer ID`, MAX(`Customer Name`) AS customer_name, SUM(Sales) AS total_sales
  FROM superstore_clean
  GROUP BY `Customer ID`
), ranked_customers AS (
  SELECT *, ROW_NUMBER() OVER (ORDER BY total_sales DESC, `Customer ID`) AS rn
  FROM customer_sales
)
SELECT ROUND(SUM(CASE WHEN rn <= 10 THEN total_sales ELSE 0 END), 2) AS top_10_sales,
       ROUND(SUM(total_sales), 2) AS total_sales,
       ROUND(100 * SUM(CASE WHEN rn <= 10 THEN total_sales ELSE 0 END) / NULLIF(SUM(total_sales),0), 2) AS top_10_sales_share_pct
FROM ranked_customers;

-- 06. Yearly sales, profit, margin, and year-over-year sales growth
WITH yearly AS (
  SELECT YEAR(`Order Date`) AS order_year, SUM(Sales) AS sales, SUM(Profit) AS profit
  FROM superstore_clean
  WHERE `Order Date` IS NOT NULL
  GROUP BY YEAR(`Order Date`)
), yearly_lag AS (
  SELECT *, LAG(sales) OVER (ORDER BY order_year) AS previous_year_sales
  FROM yearly
)
SELECT order_year, ROUND(sales,2) AS total_sales, ROUND(profit,2) AS total_profit,
       ROUND(100 * profit / NULLIF(sales,0),2) AS profit_margin_pct,
       ROUND(100 * (sales - previous_year_sales) / NULLIF(previous_year_sales,0),2) AS sales_yoy_growth_pct
FROM yearly_lag
ORDER BY order_year;

-- 07. Category and sub-category profitability
SELECT Category, ROUND(SUM(Sales),2) AS total_sales, ROUND(SUM(Profit),2) AS total_profit,
       ROUND(100 * SUM(Profit) / NULLIF(SUM(Sales),0),2) AS profit_margin_pct
FROM superstore_clean
GROUP BY Category
ORDER BY total_profit DESC;

SELECT `Sub-Category`, ROUND(SUM(Sales),2) AS total_sales, ROUND(SUM(Profit),2) AS total_profit,
       ROUND(AVG(Discount)*100,2) AS average_discount_pct,
       ROUND(100 * SUM(Profit) / NULLIF(SUM(Sales),0),2) AS profit_margin_pct
FROM superstore_clean
GROUP BY `Sub-Category`
ORDER BY total_profit ASC;

-- 08. Profitability by discount level
SELECT Discount, COUNT(*) AS order_lines, ROUND(SUM(Sales),2) AS total_sales,
       ROUND(SUM(Profit),2) AS total_profit,
       ROUND(100 * SUM(Profit) / NULLIF(SUM(Sales),0),2) AS profit_margin_pct
FROM superstore_clean
GROUP BY Discount
ORDER BY Discount;

-- 09. Regional analysis
SELECT Region, ROUND(SUM(Sales),2) AS total_sales, ROUND(SUM(Profit),2) AS total_profit,
       ROUND(100 * SUM(Profit) / NULLIF(SUM(Sales),0),2) AS profit_margin_pct
FROM superstore_clean
GROUP BY Region
ORDER BY total_sales DESC;

-- 10. Top 10 customers by profit
SELECT `Customer ID`, MAX(`Customer Name`) AS customer_name,
       COUNT(DISTINCT `Order ID`) AS total_orders,
       ROUND(SUM(Sales),2) AS total_sales, ROUND(SUM(Profit),2) AS total_profit
FROM superstore_clean
GROUP BY `Customer ID`
ORDER BY total_profit DESC
LIMIT 10;

-- 11. RFM segmentation: same six rule-based segments used in the Tableau dashboard and fixed Python notebook.
WITH customer_rfm AS (
  SELECT `Customer ID`, MAX(`Customer Name`) AS customer_name,
         DATEDIFF((SELECT MAX(`Order Date`) FROM superstore_clean), MAX(`Order Date`)) AS recency_days,
         COUNT(DISTINCT `Order ID`) AS frequency_orders,
         SUM(Sales) AS monetary_sales,
         SUM(Profit) AS total_profit
  FROM superstore_clean
  GROUP BY `Customer ID`
), segmented AS (
  SELECT *,
    CASE
      WHEN recency_days <= 90 AND frequency_orders >= 5 AND monetary_sales >= 1000 THEN 'Champions'
      WHEN recency_days <= 30 AND frequency_orders = 1 THEN 'New Customers'
      WHEN recency_days <= 90 AND frequency_orders <= 2 THEN 'Potential Loyalists'
      WHEN recency_days <= 180 AND frequency_orders >= 3 THEN 'Loyal Customers'
      WHEN recency_days > 180 AND frequency_orders >= 3 THEN 'At Risk'
      ELSE 'Lost Customers'
    END AS rfm_segment
  FROM customer_rfm
)
SELECT rfm_segment, COUNT(*) AS customers,
       ROUND(100 * COUNT(*) / (SELECT COUNT(*) FROM segmented),2) AS customer_share_pct,
       ROUND(SUM(monetary_sales),2) AS total_sales,
       ROUND(SUM(total_profit),2) AS total_profit,
       ROUND(100 * SUM(total_profit) / NULLIF(SUM(monetary_sales),0),2) AS profit_margin_pct
FROM segmented
GROUP BY rfm_segment
ORDER BY customers DESC;

-- 12. Final reconciliation. Compare these values with Python and Tableau.
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT `Order ID`) AS total_orders,
  COUNT(DISTINCT `Customer ID`) AS total_customers,
  ROUND(SUM(Sales),2) AS total_sales,
  ROUND(SUM(Profit),2) AS total_profit,
  ROUND(100 * SUM(Profit) / NULLIF(SUM(Sales),0),2) AS profit_margin_pct
FROM superstore_clean;

/* Expected baseline for the standard Superstore Orders data:
   Rows: 9,994 | Orders: 5,009 | Customers: 793
   Sales: 2,297,200.86 | Profit: 286,397.02 | Margin: 12.47%
   Repeat customers: 781 | Repeat-customer rate: 98.49%
   Top-10 sales share: 6.70%
   Average customer sales: 2,896.85 | Average order value: 458.61

   If the results differ, check import types/locale and the selected worksheet.
   SQL not executed against the user's live MySQL server in this environment.
*/

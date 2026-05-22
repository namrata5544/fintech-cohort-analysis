-- FinTech User Retention & Cohort Analysis SQL Queries
-- Note: Replace "transactions" with your actual table name if different.

-- Query 1: Create cohort assignments
-- Finds the very first transaction date and month for every user.
WITH cohort_base AS (
  SELECT 
    "User",
    MIN(DATE("Year" || '-' || LPAD("Month"::text, 2, '0') || '-' || LPAD("Day"::text, 2, '0'))) as cohort_date,
    DATE_TRUNC('month', MIN(DATE("Year" || '-' || LPAD("Month"::text, 2, '0') || '-' || LPAD("Day"::text, 2, '0')))) as cohort_month
  FROM transactions
  GROUP BY "User"
),

-- Query 2: Month over month retention
-- Computes the engagement month for every user relative to their cohort month (cohort_index).
retention_data AS (
  SELECT 
    c."User",
    c.cohort_month,
    DATE_TRUNC('month', DATE(t."Year" || '-' || LPAD(t."Month"::text, 2, '0') || '-' || LPAD(t."Day"::text, 2, '0'))) as transaction_month,
    (EXTRACT(year FROM AGE(
      DATE_TRUNC('month', DATE(t."Year" || '-' || LPAD(t."Month"::text, 2, '0') || '-' || LPAD(t."Day"::text, 2, '0'))), 
      c.cohort_month
    )) * 12 + EXTRACT(month FROM AGE(
      DATE_TRUNC('month', DATE(t."Year" || '-' || LPAD(t."Month"::text, 2, '0') || '-' || LPAD(t."Day"::text, 2, '0'))), 
      c.cohort_month
    )))::int as cohort_index
  FROM transactions t
  JOIN cohort_base c ON t."User" = c."User"
)
SELECT 
  cohort_month, 
  cohort_index, 
  COUNT(DISTINCT "User") as retained_users 
FROM retention_data 
GROUP BY cohort_month, cohort_index 
ORDER BY cohort_month, cohort_index;

-- Query 3: CLTV calculation segmented by MCC category
-- Calculates customer lifetime value based on total clean transactions per merchant category.
WITH clean_amounts AS (
  SELECT 
    "User",
    "MCC",
    CAST(REPLACE(REPLACE("Amount", '$', ''), ',', '') AS NUMERIC) as amount_num
  FROM transactions
  WHERE "Is Fraud" = 'No'
)
SELECT 
  "MCC",
  COUNT(DISTINCT "User") as total_users,
  SUM(amount_num) as total_revenue,
  SUM(amount_num) / NULLIF(COUNT(DISTINCT "User"), 0) as cltv
FROM clean_amounts
GROUP BY "MCC"
ORDER BY cltv DESC;

-- Query 4: Churn rate by acquisition month
-- Identifies users who failed to make any transaction in their second month (cohort_index = 1).
WITH user_months AS (
  SELECT 
    c."User",
    c.cohort_month,
    MAX(
      CASE WHEN 
        (EXTRACT(year FROM AGE(
          DATE_TRUNC('month', DATE(t."Year" || '-' || LPAD(t."Month"::text, 2, '0') || '-' || LPAD(t."Day"::text, 2, '0'))), 
          c.cohort_month
        )) * 12 + EXTRACT(month FROM AGE(
          DATE_TRUNC('month', DATE(t."Year" || '-' || LPAD(t."Month"::text, 2, '0') || '-' || LPAD(t."Day"::text, 2, '0'))), 
          c.cohort_month
        ))) = 1 THEN 1 ELSE 0 END
    ) as active_month_2
  FROM (
    SELECT "User", DATE_TRUNC('month', MIN(DATE("Year" || '-' || LPAD("Month"::text, 2, '0') || '-' || LPAD("Day"::text, 2, '0')))) as cohort_month
    FROM transactions GROUP BY "User"
  ) c
  LEFT JOIN transactions t ON c."User" = t."User"
  GROUP BY c."User", c.cohort_month
)
SELECT 
  cohort_month,
  COUNT(*) as total_users,
  SUM(CASE WHEN active_month_2 = 0 THEN 1 ELSE 0 END) as churned_month_2,
  ROUND(SUM(CASE WHEN active_month_2 = 0 THEN 1 ELSE 0 END)::numeric / COUNT(*), 4) as churn_rate_month_2
FROM user_months
GROUP BY cohort_month
ORDER BY cohort_month;

-- Query 5: Fraud impact on user retention
-- Compares retention for users who have ever experienced fraud vs those who have not.
WITH user_fraud_status AS (
  SELECT 
    "User",
    MAX(CASE WHEN "Is Fraud" = 'Yes' THEN 1 ELSE 0 END) as has_experienced_fraud,
    DATE_TRUNC('month', MIN(DATE("Year" || '-' || LPAD("Month"::text, 2, '0') || '-' || LPAD("Day"::text, 2, '0')))) as cohort_month
  FROM transactions
  GROUP BY "User"
),
user_lifespan AS (
  SELECT 
    "User",
    DATE_TRUNC('month', MAX(DATE("Year" || '-' || LPAD("Month"::text, 2, '0') || '-' || LPAD("Day"::text, 2, '0')))) as last_activity_month
  FROM transactions
  GROUP BY "User"
)
SELECT 
  f.has_experienced_fraud,
  COUNT(f."User") as num_users,
  AVG(
    EXTRACT(year FROM AGE(l.last_activity_month, f.cohort_month)) * 12 + 
    EXTRACT(month FROM AGE(l.last_activity_month, f.cohort_month))
  ) as avg_lifetime_months
FROM user_fraud_status f
JOIN user_lifespan l ON f."User" = l."User"
GROUP BY f.has_experienced_fraud;

-- Query 6: Average transaction value by cohort month
WITH cohort_base AS (
  SELECT 
    "User",
    DATE_TRUNC('month', MIN(DATE("Year" || '-' || LPAD("Month"::text, 2, '0') || '-' || LPAD("Day"::text, 2, '0')))) as cohort_month
  FROM transactions
  GROUP BY "User"
)
SELECT 
  c.cohort_month,
  AVG(CAST(REPLACE(REPLACE(t."Amount", '$', ''), ',', '') AS NUMERIC)) as avg_transaction_value
FROM transactions t
JOIN cohort_base c ON t."User" = c."User"
WHERE t."Is Fraud" = 'No'
GROUP BY c.cohort_month
ORDER BY c.cohort_month;

-- Query 7: Top merchant categories by retained users
-- Looks at users active beyond month 6 and their favorite MCCs.
WITH cohort_base AS (
  SELECT "User", DATE_TRUNC('month', MIN(DATE("Year" || '-' || LPAD("Month"::text, 2, '0') || '-' || LPAD("Day"::text, 2, '0')))) as cohort_month FROM transactions GROUP BY "User"
),
retained_users AS (
  SELECT DISTINCT c."User"
  FROM transactions t
  JOIN cohort_base c ON t."User" = c."User"
  WHERE (EXTRACT(year FROM AGE(DATE_TRUNC('month', DATE(t."Year" || '-' || LPAD(t."Month"::text, 2, '0') || '-' || LPAD(t."Day"::text, 2, '0'))), c.cohort_month)) * 12 + 
         EXTRACT(month FROM AGE(DATE_TRUNC('month', DATE(t."Year" || '-' || LPAD(t."Month"::text, 2, '0') || '-' || LPAD(t."Day"::text, 2, '0'))), c.cohort_month))) > 6
)
SELECT 
  t."MCC",
  COUNT(DISTINCT t."User") as retained_user_count
FROM transactions t
JOIN retained_users r ON t."User" = r."User"
WHERE t."Is Fraud" = 'No'
GROUP BY t."MCC"
ORDER BY retained_user_count DESC
LIMIT 10;

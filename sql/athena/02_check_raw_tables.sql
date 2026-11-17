-- =====================================================================
-- 02_check_raw_tables.sql
-- Confirms every raw table loaded. Run the row-count query first, then
-- peek at a few rows from each table.
-- =====================================================================

-- Row counts: expected numbers are in the comments
SELECT 'crm_accounts'          AS table_name, COUNT(*) AS row_count FROM loopwise_raw.crm_accounts           -- 64
UNION ALL SELECT 'crm_contacts',          COUNT(*) FROM loopwise_raw.crm_contacts          -- 156
UNION ALL SELECT 'crm_opportunities',     COUNT(*) FROM loopwise_raw.crm_opportunities     -- 126
UNION ALL SELECT 'usage_monthly',         COUNT(*) FROM loopwise_raw.usage_monthly         -- 575 (includes July twice)
UNION ALL SELECT 'billing_customers',     COUNT(*) FROM loopwise_raw.billing_customers     -- 56
UNION ALL SELECT 'billing_subscriptions', COUNT(*) FROM loopwise_raw.billing_subscriptions -- 54
UNION ALL SELECT 'billing_invoices',      COUNT(*) FROM loopwise_raw.billing_invoices      -- 582
ORDER BY table_name;

-- Peek at the mess: notice the mixed segment spellings and website formats
SELECT * FROM loopwise_raw.crm_accounts LIMIT 10;

-- "$path" is a hidden Athena column with the S3 file each row came from.
-- This is how we'll spot July being sent twice.
SELECT "$path" AS source_file, COUNT(*) AS rows_in_file
FROM loopwise_raw.usage_monthly
GROUP BY "$path"
ORDER BY source_file;

-- Nested JSON: pull the plan name and seat count out of a subscription
SELECT
  id,
  status,
  items.data[1].price.nickname           AS plan_nickname,
  items.data[1].price.recurring['interval'] AS billing_interval,
  items.data[1].quantity                 AS seats
FROM loopwise_raw.billing_subscriptions
LIMIT 10;

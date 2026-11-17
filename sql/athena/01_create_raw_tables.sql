-- =====================================================================
-- 01_create_raw_tables.sql
-- Registers the raw S3 files as tables in the Glue Data Catalog so
-- Athena can query them. Nothing is cleaned here: every CSV column is
-- read as a string on purpose. Cleaning and typing happen in dbt.
--
-- Run each statement ONE AT A TIME in the Athena query editor
-- (Athena runs a single statement per query).
-- =====================================================================


-- 1. Database for the raw layer ---------------------------------------
CREATE DATABASE IF NOT EXISTS loopwise_raw
COMMENT 'Raw landing tables for the Loopwise Customer 360 project';


-- 2. CRM: accounts ------------------------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS loopwise_raw.crm_accounts (
  `id`               string,
  `name`             string,
  `website`          string,
  `type`             string,
  `customer_segment` string,
  `industry`         string,
  `billing_country`  string,
  `owner_name`       string,
  `created_date`     string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"')
LOCATION 's3://loopwise-customer360-julianne/raw/crm/accounts/'
TBLPROPERTIES ('skip.header.line.count' = '1');


-- 3. CRM: contacts ------------------------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS loopwise_raw.crm_contacts (
  `id`                  string,
  `account_id`          string,
  `first_name`          string,
  `last_name`           string,
  `email`               string,
  `title`               string,
  `is_billing_contact`  string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"')
LOCATION 's3://loopwise-customer360-julianne/raw/crm/contacts/'
TBLPROPERTIES ('skip.header.line.count' = '1');


-- 4. CRM: opportunities -------------------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS loopwise_raw.crm_opportunities (
  `id`             string,
  `account_id`     string,
  `name`           string,
  `stage_name`     string,
  `amount`         string,
  `close_date`     string,
  `currency_code`  string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"')
LOCATION 's3://loopwise-customer360-julianne/raw/crm/opportunities/'
TBLPROPERTIES ('skip.header.line.count' = '1');


-- 5. Usage: all monthly files in one table ------------------------------
-- The column NAMES changed in May, but the column ORDER did not, so one
-- table reads every file. api_calls is empty for Jan-Apr (older format).
CREATE EXTERNAL TABLE IF NOT EXISTS loopwise_raw.usage_monthly (
  `customer_domain`   string,
  `usage_month`       string,
  `active_users`      string,
  `projects_created`  string,
  `api_calls`         string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES ('separatorChar' = ',', 'quoteChar' = '"')
LOCATION 's3://loopwise-customer360-julianne/raw/usage/'
TBLPROPERTIES ('skip.header.line.count' = '1');


-- 6. Billing: customers (JSON, one record per line) ---------------------
CREATE EXTERNAL TABLE IF NOT EXISTS loopwise_raw.billing_customers (
  `id`        string,
  `object`    string,
  `name`      string,
  `email`     string,
  `currency`  string,
  `created`   bigint,
  `metadata`  map<string, string>
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://loopwise-customer360-julianne/raw/billing/customers/';


-- 7. Billing: subscriptions (nested JSON) -------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS loopwise_raw.billing_subscriptions (
  `id`           string,
  `object`       string,
  `customer`     string,
  `status`       string,
  `start_date`   bigint,
  `canceled_at`  bigint,
  `currency`     string,
  `items`        struct<data: array<struct<
                   price: struct<nickname: string, unit_amount: bigint,
                                 recurring: map<string, string>>,
                   quantity: int>>>
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://loopwise-customer360-julianne/raw/billing/subscriptions/';


-- 8. Billing: invoices (nested JSON) ------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS loopwise_raw.billing_invoices (
  `id`            string,
  `object`        string,
  `customer`      string,
  `subscription`  string,
  `currency`      string,
  `amount_due`    bigint,
  `amount_paid`   bigint,
  `status`        string,
  `created`       bigint,
  `period_start`  bigint,
  `lines`         struct<data: array<struct<description: string, quantity: int>>>
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://loopwise-customer360-julianne/raw/billing/invoices/';

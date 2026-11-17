-- =============================================================================
-- dim_account
-- -----------------------------------------------------------------------------
-- Grain:   one row per real company (60 rows: customers and prospects).
-- Input:   int_crm__accounts_deduped
-- Purpose: the PARENT table of the star schema. Every fact table (subscriptions,
--          invoices, usage) links here through account_id.
--
-- Saved as a real table (Parquet files in S3), not a view, because marts are read
-- often by dashboards and the AI. See dbt_project.yml.
-- Tests and column descriptions live in _marts.yml.
-- =============================================================================

with accounts as (

    select * from {{ ref('int_crm__accounts_deduped') }}

)

select
    account_id,                                         -- primary key
    account_name,
    account_domain,

    -- A comparison returns true or false on its own:
    -- 'Customer' -> true, 'Prospect' -> false.
    account_type = 'Customer'                           as is_customer,

    segment,
    industry,
    country_code,

    -- Group countries into sales regions so the AI can answer "MRR by region".
    -- Each WHEN checks a list of country codes; the first match wins.
    case
        when country_code in ('US', 'CA')               then 'NA'
        when country_code in ('GB', 'DE', 'FR')         then 'EMEA'
        when country_code in ('AU', 'SG', 'JP')         then 'APAC'
    end                                                 as region,

    account_owner,
    created_date

from accounts

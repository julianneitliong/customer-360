-- =============================================================================
-- int_usage__mapped
-- -----------------------------------------------------------------------------
-- Grain:   one row per customer domain per month (524 rows).
-- Inputs:  stg_usage__monthly, int_crm__accounts_deduped
-- Purpose: give every usage row an account_id. Usage exports only identify a
--          company by its domain, so the domain is the only possible match.
--
-- Result: 504 rows matched; 20 rows (2 trial workspaces x 10 months) unmatched.
-- Unmatched rows stay here with is_matched = false; fct_usage_monthly keeps only
-- matched rows, and int_unmatched_records lists the rest.
-- =============================================================================

with usage as (

    select * from {{ ref('stg_usage__monthly') }}

),

accounts as (

    select * from {{ ref('int_crm__accounts_deduped') }}

),

matched as (

    select
        usage.*,

        -- Only ONE join, so only one possible account_id: select it directly.
        -- (coalesce is only needed when there are fallbacks, like in
        -- int_billing__customers_mapped.) NULL when the domain had no match.
        domain_match.account_id                         as account_id,

        -- "x is not null" already returns true or false, so no CASE is needed.
        domain_match.account_id is not null             as is_matched

    from usage

    -- LEFT JOIN keeps every usage row (child), matched to an account (parent) or not.
    -- Column names differ by system (customer_domain vs account_domain), but both
    -- were cleaned the same way in staging, so the values line up.
    left join accounts as domain_match
        on domain_match.account_domain = usage.customer_domain

)

select * from matched

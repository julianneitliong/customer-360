-- =============================================================================
-- int_crm__accounts_deduped
-- -----------------------------------------------------------------------------
-- Grain:   one row per real company (60 rows, down from 64 in staging).
-- Input:   stg_crm__accounts
-- Purpose: merge the 4 duplicate CRM accounts, created twice by different sales
--          reps (same company, new ID, slightly different name, missing fields).
--
-- Approach: the classic "keep one row per group" pattern with row_number().
--   1. Decide what makes two rows the SAME thing   -> partition by account_domain
--   2. Decide which row of each group WINS          -> order by created_date asc
--   3. Keep the winner                              -> where row_num = 1
--
-- Example (one duplicate pair):
--   account_id  account_domain  segment  created_date  row_num
--   001...AAA   acmelabs.com    SMB      2024-03-01    1   <- kept (original, complete)
--   001...ZZZ   acmelabs.com    (blank)  2024-09-15    2   <- dropped (later duplicate)
--
-- Why domain and not name: names vary ('Acme Labs' vs 'ACME LABS INC.'), but the
-- cleaned website domain is the same for both records of a company.
-- Why oldest: the original record was created first, and it's the one with
-- segment and industry filled in. Nothing references the duplicate IDs downstream.
-- =============================================================================

-- CTE 1: everything from staging.
-- A CTE (WITH name AS (...)) is a named step inside one query. It is not saved
-- in Athena; only this model's final result is saved, as a view named after the file.
with accounts as (

    -- ref() points to another dbt model, which tells dbt to build staging first.
    select * from {{ ref('stg_crm__accounts') }}

),

-- CTE 2: rank the rows inside each company.
ranked as (

    select
        *,
        -- row_number() is a WINDOW function (you can tell by OVER). Unlike GROUP BY,
        -- it keeps every row and just adds a rank within each group (the "window").
        -- A company with no duplicate is a group of one, so it simply gets 1.
        row_number() over (
            partition by account_domain     -- group rows that are the same company
            order by created_date asc       -- oldest first = the original record
        )                                   as row_num
    from accounts

)

-- Final select: keep only the winner in each group. Columns are listed by name so
-- the helper column row_num is left out of the result.
select
    account_id,
    account_id_18,
    account_name,
    account_domain,
    account_type,
    segment,
    industry,
    country_code,
    account_owner,
    created_date
from ranked
where row_num = 1

-- CHILD TABLE: one row per account per month of product usage.
-- Only matched usage is kept here; unmatched trial domains live in int_unmatched_records.

select
    account_id,                              -- link to the parent (dim_account)
    usage_month,
    active_users,
    projects_created,
    api_calls
from {{ ref('int_usage__mapped') }}
where is_matched

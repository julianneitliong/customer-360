-- Singular test: returns any subscription with negative MRR.
-- dbt treats any returned row as a failure, so this passes when the query returns nothing.
select subscription_id, mrr_usd
from {{ ref('fct_subscriptions') }}
where mrr_usd < 0

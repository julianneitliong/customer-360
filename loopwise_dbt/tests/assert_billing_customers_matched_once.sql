-- Singular test: every billing customer appears exactly once after mapping
-- (the two left joins must not create duplicates).
select billing_customer_id, count(*) as row_count
from {{ ref('int_billing__customers_mapped') }}
group by billing_customer_id
having count(*) > 1

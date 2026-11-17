-- Every record from billing or usage that could not be matched to a CRM account.
-- Nothing is silently dropped: this table is the to-do list for the business
-- (add these companies to the CRM, or confirm they are trials).

with unmatched_billing as (

    select
        'billing'                                   as source_system,
        billing_customer_id                         as record_id,
        customer_name                               as record_label,
        'No CRM ID in billing, and email domain ' || email_domain || ' is not in the CRM'
                                                    as unmatched_reason,
        cast(1 as bigint)                           as rows_affected
    from {{ ref('int_billing__customers_mapped') }}
    where match_method = 'unmatched'

),

unmatched_usage as (

    -- one row per domain, counting how many monthly usage rows it affects
    select
        'usage'                                     as source_system,
        customer_domain                             as record_id,
        customer_domain                             as record_label,
        'Usage domain is not in the CRM'            as unmatched_reason,
        count(*)                                    as rows_affected
    from {{ ref('int_usage__mapped') }}
    where not is_matched
    group by customer_domain

)

-- UNION ALL stacks the two lists on top of each other.
-- Both sides must have the same columns, in the same order, with the same types.
select * from unmatched_billing
union all
select * from unmatched_usage

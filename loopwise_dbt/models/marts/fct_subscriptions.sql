-- CHILD TABLE: one row per subscription, linked to dim_account, with MRR in USD.

with subscriptions as (

    select * from {{ ref('stg_billing__subscriptions') }}

),

customer_map as (

    select billing_customer_id, account_id
    from {{ ref('int_billing__customers_mapped') }}

),

fx as (

    select * from {{ ref('fx_rates_to_usd') }}

)

select
    subscriptions.subscription_id,
    customer_map.account_id,                 -- link to the parent (dim_account)
    subscriptions.billing_customer_id,
    subscriptions.plan_name,
    subscriptions.billing_interval,
    subscriptions.seats,
    subscriptions.subscription_status,
    subscriptions.subscription_status = 'active'             as is_active,
    subscriptions.started_at,
    subscriptions.canceled_at,

    -- MRR = seats x price, spread evenly per month.
    -- Annual plans are billed once a year, so divide by 12.
    cast(
        subscriptions.seats * subscriptions.unit_price
        / case subscriptions.billing_interval when 'year' then 12 else 1 end
        * fx.rate_to_usd
    as decimal(12, 2))                                       as mrr_usd

from subscriptions
left join customer_map
    on subscriptions.billing_customer_id = customer_map.billing_customer_id
left join fx
    on subscriptions.currency = fx.currency_code

-- =============================================================================
-- stg_billing__subscriptions
-- -----------------------------------------------------------------------------
-- Grain:   one row per billing subscription.
-- Source:  loopwise_raw.billing_subscriptions (Stripe-style API, nested JSON).
-- Purpose: flatten the nested JSON into plain columns that MRR can be calculated from.
--
-- The nested structure of the "items" column looks like this:
--
--   items
--    └─ data              <- a LIST (array) of line items
--        └─ [1]           <- the first item. Athena lists start at 1, not 0.
--            ├─ price
--            │   ├─ nickname      'Pro Monthly'
--            │   ├─ unit_amount   1500   (cents, per seat, per billing period)
--            │   └─ recurring     a map: {'interval': 'month'}
--            └─ quantity          25     (seats)
--
-- How to read a path:  a dot (.) opens a box (struct); [1] picks an item from a
-- list; ['key'] reads a value from a map.
--
-- Keys:
--   subscription_id     = primary key
--   billing_customer_id = foreign key to stg_billing__customers
-- =============================================================================

with source as (

    select * from {{ source('raw', 'billing_subscriptions') }}

),

cleaned as (

    select
        id                                              as subscription_id,
        customer                                        as billing_customer_id,
        status                                          as subscription_status,

        -- The nickname holds two facts in one string: 'Pro Monthly' = plan + period.
        -- Keep only the plan: split at the space and take piece 1 -> 'Pro'.
        -- The billing period has its own column below, so nothing is lost.
        -- (The plan was called 'Team' before July 2026; subscriptions already show
        -- the new name 'Pro'. Older invoices are fixed in stg_billing__invoices.)
        split_part(items.data[1].price.nickname, ' ', 1)
                                                        as plan_name,

        -- 'month' or 'year'. Critical for MRR: annual prices cover 12 months,
        -- so they are divided by 12 later (see fct_subscriptions).
        items.data[1].price.recurring['interval']       as billing_interval,

        -- Number of paid seats (licenses).
        items.data[1].quantity                          as seats,

        -- Price per seat per billing period. The API sends cents, so divide by 100.0.
        -- The .0 matters: it forces decimal math so 1550 becomes 15.50, not 15.
        items.data[1].price.unit_amount / 100.0         as unit_price,

        upper(currency)                                 as currency,

        -- Unix timestamps -> dates. canceled_at is NULL for active subscriptions,
        -- and from_unixtime(NULL) safely returns NULL.
        date(from_unixtime(start_date))                 as started_at,
        date(from_unixtime(canceled_at))                as canceled_at

    from source

)

select * from cleaned

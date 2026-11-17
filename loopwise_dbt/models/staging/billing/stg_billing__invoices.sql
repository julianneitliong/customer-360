-- One row per invoice, in dollars, with the plan name standardized.

with source as (

    select * from {{ source('raw', 'billing_invoices') }}

),

fx as (

    select * from {{ ref('fx_rates_to_usd') }}

),

cleaned as (

    select
        id                                              as invoice_id,
        customer                                        as billing_customer_id,
        subscription                                    as subscription_id,
        status                                          as invoice_status,

        -- amounts arrive in cents
        amount_due  / 100.0                             as amount_due_local,
        amount_paid / 100.0                             as amount_paid_local,
        upper(currency)                                 as currency_code,

        date(from_unixtime(created))                    as invoiced_at,
        date(from_unixtime(period_start))               as period_start,

        -- line description looks like "25 x Team (Monthly)"
        lines.data[1].description                       as line_description,
        lines.data[1].quantity                          as seats,

        -- the Team plan was renamed Pro on 2026-07-01; older invoices still say Team
        case regexp_extract(lines.data[1].description, '\d+ x (\w+) \(', 1)
            when 'Team' then 'Pro'
            else regexp_extract(lines.data[1].description, '\d+ x (\w+) \(', 1)
        end                                             as plan_name

    from source

),

converted as (

    -- each invoice (child) looks up its currency's rate (parent)
    select
        cleaned.*,
        cast(cleaned.amount_due_local  * fx.rate_to_usd as decimal(12, 2)) as amount_due_usd,
        cast(cleaned.amount_paid_local * fx.rate_to_usd as decimal(12, 2)) as amount_paid_usd
    from cleaned
    left join fx
        on cleaned.currency_code = fx.currency_code

)

select * from converted

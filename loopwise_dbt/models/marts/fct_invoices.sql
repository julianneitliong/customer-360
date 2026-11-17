-- CHILD TABLE: one row per invoice, linked to dim_account, in USD.

with invoices as (

    select * from {{ ref('stg_billing__invoices') }}

),

customer_map as (

    select billing_customer_id, account_id
    from {{ ref('int_billing__customers_mapped') }}

)

select
    invoices.invoice_id,
    customer_map.account_id,                 -- link to the parent (dim_account)
    invoices.subscription_id,
    invoices.plan_name,
    invoices.seats,
    invoices.invoice_status,
    invoices.invoiced_at,
    invoices.period_start,
    invoices.amount_due_usd,
    invoices.amount_paid_usd

from invoices
left join customer_map
    on invoices.billing_customer_id = customer_map.billing_customer_id

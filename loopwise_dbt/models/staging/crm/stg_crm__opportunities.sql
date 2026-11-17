-- One row per CRM opportunity (deal), cleaned and converted to USD.

with source as (

    select * from {{ source('raw', 'crm_opportunities') }}

),

fx as (

    select * from {{ ref('fx_rates_to_usd') }}

),

cleaned as (

    select
        id                                              as opportunity_id,

        -- normalize 15/18-char IDs to 15 so they match stg_crm__accounts
        substr(account_id, 1, 15)                       as account_id,

        trim(name)                                      as opportunity_name,
        trim(stage_name)                                as stage_name,

        -- stage flags make questions like "how many deals did we win?" simple
        trim(stage_name) = 'Closed Won'                 as is_won,
        trim(stage_name) in ('Closed Won', 'Closed Lost') as is_closed,

        -- "12,500" -> 12500.00 (some exports added thousands separators)
        cast(replace(trim(amount), ',', '') as decimal(12, 2))
                                                        as amount_local,

        upper(trim(currency_code))                      as currency_code,

        -- two date formats arrive: 2026-03-01 and 03/01/2026
        case
            when close_date like '%/%' then date(date_parse(trim(close_date), '%m/%d/%Y'))
            else date(trim(close_date))
        end                                             as close_date

    from source

),

converted as (

    -- parent/child: each opportunity (child) looks up its currency's rate (parent)
    select
        cleaned.*,
        cast(cleaned.amount_local * fx.rate_to_usd as decimal(12, 2)) as amount_usd
    from cleaned
    left join fx
        on cleaned.currency_code = fx.currency_code

)

select * from converted

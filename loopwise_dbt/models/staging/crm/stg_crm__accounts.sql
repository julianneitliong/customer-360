-- One row per CRM account, cleaned and standardized.
-- Duplicates are NOT removed here (that happens in intermediate),
-- so this model still has 64 rows.

with source as (

    select * from {{ source('raw', 'crm_accounts') }}

),

cleaned as (

    select
        -- IDs: keep the first 15 characters as the join key.
        -- Other exports use 15-char IDs, so this lets every table match.
        substr(id, 1, 15)                                   as account_id,
        id                                                  as account_id_18,

        trim(name)                                          as account_name,

        -- "https://www.Acme.com/" -> "acme.com"
        lower(regexp_replace(trim(website), '^(https?://)?(www\.)?|/$', ''))
                                                            as account_domain,

        trim(type)                                          as account_type,

        case
            when lower(trim(customer_segment)) in ('smb', 'small business')    then 'SMB'
            when lower(trim(customer_segment)) in ('mid-market', 'mid market', 'mm') then 'Mid-Market'
            when lower(trim(customer_segment)) in ('enterprise', 'ent')        then 'Enterprise'
        end                                                 as segment,

        nullif(trim(industry), '')                          as industry,

        case trim(billing_country)
            when 'United States'  then 'US'
            when 'USA'            then 'US'
            when 'US'             then 'US'
            when 'Canada'         then 'CA'
            when 'United Kingdom' then 'GB'
            when 'UK'             then 'GB'
            when 'Germany'        then 'DE'
            when 'France'         then 'FR'
            when 'Australia'      then 'AU'
            when 'Singapore'      then 'SG'
            when 'Japan'          then 'JP'
        end                                                 as country_code,

        nullif(trim(owner_name), '')                        as account_owner,

        -- "2025-01-13T00:00:00.000+0000" -> 2025-01-13
        date(substr(created_date, 1, 10))                   as created_date

    from source

)

select * from cleaned

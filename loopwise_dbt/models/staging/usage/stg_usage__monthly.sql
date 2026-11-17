-- One row per customer domain per month of product usage.
-- Fixes: two export formats, mixed date styles, messy domains, and July sent twice.

with source as (

    -- "$path" is Athena's hidden column holding the S3 file each row came from
    select
        *,
        "$path" as source_file
    from {{ source('raw', 'usage_monthly') }}

),

cleaned as (

    select
        -- " WWW.AcmeLabs.com" -> "acmelabs.com"
        lower(regexp_replace(trim(customer_domain), '^(https?://)?(www\.)?', ''))
                                                        as customer_domain,

        -- Jan-Apr files say "01/2026"; May onward say "2026-05-01"
        case
            when usage_month like '%/%' then date(date_parse(trim(usage_month), '%m/%Y'))
            else date(trim(usage_month))
        end                                             as usage_month,

        cast(active_users     as integer)               as active_users,
        cast(projects_created as integer)               as projects_created,

        -- api_calls only exists in the new format (May onward); blank before that
        try_cast(nullif(trim(api_calls), '') as integer) as api_calls,

        source_file

    from source

),

deduplicated as (

    -- July was sent twice ("usage_2026_07.csv" and "usage_2026_07 (1).csv").
    -- Keep one row per domain per month, preferring the original file over the "(1)" copy.
    select
        *,
        row_number() over (
            partition by customer_domain, usage_month
            order by case when source_file like '% (1)%' then 1 else 0 end, source_file
        ) as row_num
    from cleaned

)

select
    customer_domain,
    usage_month,
    active_users,
    projects_created,
    api_calls,
    source_file
from deduplicated
where row_num = 1

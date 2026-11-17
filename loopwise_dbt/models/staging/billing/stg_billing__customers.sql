-- =============================================================================
-- stg_billing__customers
-- -----------------------------------------------------------------------------
-- Grain:   one row per billing customer (a paying company in the billing tool).
-- Source:  loopwise_raw.billing_customers (Stripe-style API, one JSON record per line).
-- Purpose: clean the fields and prepare the two "clues" used later to match each
--          billing customer to a CRM account. The matching itself happens in
--          int_billing__customers_mapped; staging only prepares.
--
-- Problems fixed:
--   1. The CRM account ID is nested inside a JSON "metadata" box, exists for only
--      38 of 56 customers, and is a mix of 15 and 18 characters.
--   2. Dates arrive as Unix timestamps (seconds since 1970-01-01, UTC).
--   3. Currency codes are lowercase ('usd'); the CRM uses uppercase ('USD').
--   4. The column called "name" is ambiguous; it holds the COMPANY name, not a person.
--
-- Keys:
--   billing_customer_id = primary key (the billing tool's own ID, 'cus_...')
-- =============================================================================

with source as (

    select * from {{ source('raw', 'billing_customers') }}

),

cleaned as (

    select
        -- Primary key from the billing system. It has no relationship to the CRM ID.
        id                                              as billing_customer_id,

        -- In the billing tool, a "customer" is the paying company, so "name" is the
        -- company name (e.g. 'Ember Foods, Inc.'). Renamed so nobody downstream,
        -- including the AI, mistakes it for a person's name.
        trim(name)                                      as customer_name,

        -- Same email pattern as stg_crm__contacts: trim, lowercase, then take the
        -- part after the @. The domain is match clue #2 (used when there is no CRM ID).
        lower(trim(email))                              as email,
        split_part(lower(trim(email)), '@', 2)          as email_domain,

        -- Match clue #1: the CRM account ID stored in the billing tool.
        -- metadata is a map (a box of key/value pairs). element_at(map, 'key') opens
        -- the box and returns the value, or NULL if the key isn't there. That's safer
        -- than metadata['key'], which errors when the key is missing.
        -- Then substr(..., 1, 15) standardizes 15/18-character IDs, the same rule as
        -- the CRM models. Customers with no CRM ID come out NULL on purpose.
        substr(element_at(metadata, 'crm_account_id'), 1, 15)
                                                        as crm_account_id,

        -- Uppercase so it joins to the exchange-rate seed and matches the CRM.
        upper(currency)                                 as currency,

        -- from_unixtime() turns seconds-since-1970 into a timestamp;
        -- date() keeps just the day.
        date(from_unixtime(created))                    as created_at

    from source

)

select * from cleaned

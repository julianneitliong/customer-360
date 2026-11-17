-- =============================================================================
-- stg_crm__contacts
-- -----------------------------------------------------------------------------
-- Grain:   one row per CRM contact (a person at a customer or prospect company).
-- Source:  loopwise_raw.crm_contacts (Salesforce-style Contact export, all strings).
-- Purpose: clean each column so contacts can be joined to accounts and used
--          downstream. No rows are removed here; staging only cleans.
--
-- Problems fixed:
--   1. account_id arrives as a mix of 15- and 18-character Salesforce IDs.
--   2. Text fields may carry stray spaces; emails may arrive in mixed case.
--   3. The billing-contact checkbox arrives as 'true', 'TRUE', '1', 'false' or ''.
--
-- Keys:
--   contact_id  = primary key (unique, one per contact)
--   account_id  = foreign key to stg_crm__accounts (repeats: one account has many contacts)
-- =============================================================================

with source as (

    -- Pull the raw table through dbt's source() so dbt knows this model depends on it.
    select * from {{ source('raw', 'crm_contacts') }}

),

cleaned as (

    select
        -- Primary key. Salesforce Contact IDs are already consistent, so no change.
        id                                              as contact_id,

        -- Foreign key to the parent account.
        -- An 18-character Salesforce ID is the 15-character ID plus a 3-character
        -- checksum, so the first 15 characters are the "real" ID. Trimming every ID
        -- to 15 makes contacts match stg_crm__accounts, which uses the same rule.
        -- Verified in Athena: 91 distinct raw IDs became 60 real accounts, and
        -- 0 contacts pointed to an account that doesn't exist.
        -- Never lower() or upper() a 15-character ID: Salesforce treats 'abc' and
        -- 'ABC' as different records.
        substr(account_id, 1, 15)                       as account_id,

        -- trim() removes leading and trailing spaces so " Alex" and "Alex" match.
        trim(first_name)                                as first_name,
        trim(last_name)                                 as last_name,
        trim(title)                                     as title,

        -- Emails are compared case-insensitively, so store them in one case.
        -- Functions run inside-out: trim the spaces first, then lowercase.
        lower(trim(email))                              as email,

        -- Domain = everything after the @.
        -- split_part(text, '@', 2) cuts the text at '@' and keeps piece 2:
        --   'alex.kim@acmelabs.com'  ->  ['alex.kim', 'acmelabs.com']  ->  'acmelabs.com'
        -- Built from the cleaned email so the domain is lowercase too. Used later to
        -- match records from other systems that only know a company by its domain.
        split_part(lower(trim(email)), '@', 2)          as email_domain,

        -- Turn five spellings of yes/no into a real boolean (true/false, no quotes).
        -- lower() first, so 'TRUE' and 'true' are handled by one rule.
        -- Values inside in (...) are quoted because the raw column is text.
        -- Decision: a blank ('') means false, because an empty Salesforce checkbox
        -- means unchecked.
        case
            when lower(trim(is_billing_contact)) in ('1', 'true')  then true
            when lower(trim(is_billing_contact)) in ('false', '')  then false
        end                                             as is_billing_contact

    from source

)

select * from cleaned

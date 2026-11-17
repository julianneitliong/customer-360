-- =============================================================================
-- int_billing__customers_mapped
-- -----------------------------------------------------------------------------
-- Grain:   one row per billing customer (56 rows), each with the CRM account it
--          belongs to.
-- Inputs:  stg_billing__customers, int_crm__accounts_deduped
-- Purpose: give every billing customer an account_id, the "conformed key" that
--          lets billing data hang off dim_account as a child.
--
-- The billing tool and the CRM don't share an ID, so matching uses two clues,
-- tried in order of how trustworthy they are:
--   1. CRM ID stored in billing metadata   -> 38 customers matched ('crm_id')
--   2. Billing email domain = CRM domain   -> 16 more matched      ('email_domain')
--   3. Neither worked                      ->  2 flagged           ('unmatched')
-- (Checked in Athena against data/answer_key/account_truth.csv.)
--
-- Why not match on company name: billing has 'Ember Foods, Inc.' where the CRM has
-- 'Ember Foods'. Names need fuzzy matching and are easy to get wrong.
-- =============================================================================

with billing_customers as (

    select * from {{ ref('stg_billing__customers') }}

),

accounts as (

    select * from {{ ref('int_crm__accounts_deduped') }}

),

matched as (

    select
        billing_customers.*,

        -- coalesce(a, b) returns the first value that isn't NULL:
        -- use the ID match when there is one, otherwise the domain match.
        -- Both choices are account IDs. The domain is only used in the join to FIND
        -- the account; the value we keep is that account's ID.
        coalesce(id_match.account_id, domain_match.account_id)
                                                        as account_id,

        -- Record HOW each customer was matched, so the matching can be audited later
        -- and unmatched customers are easy to find (where match_method = 'unmatched').
        -- The order of the WHEN lines matters: the stronger clue (ID) is checked first.
        case
            when id_match.account_id     is not null then 'crm_id'
            when domain_match.account_id is not null then 'email_domain'
            else 'unmatched'
        end                                             as match_method

    from billing_customers

    -- Parent/child: each billing customer (child) looks for its account (parent).
    -- A LEFT JOIN keeps every child even when no parent is found; the account
    -- columns just come back NULL. Nothing is silently dropped.
    --
    -- The accounts table is joined TWICE under two nicknames (aliases), because we
    -- look for the parent two different ways. Inside each ON, use that join's own
    -- nickname.

    -- Match 1: the CRM ID stored in the billing tool.
    left join accounts as id_match
        on id_match.account_id = billing_customers.crm_account_id

    -- Match 2: the billing email's domain. The two sides can have different column
    -- names (account_domain vs email_domain) as long as the values mean the same thing.
    left join accounts as domain_match
        on domain_match.account_domain = billing_customers.email_domain

)

select * from matched

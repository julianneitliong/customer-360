-- ONE ROW PER ACCOUNT: the table the AI analytics product reads first.
-- Combines who the customer is (dim_account), what they pay (fct_subscriptions)
-- and how much they use the product (fct_usage_monthly).

with accounts as (

    select * from {{ ref('dim_account') }}

),

-- What each account pays today
billing as (

    select
        account_id,
        sum(case when is_active then mrr_usd else 0 end)    as mrr_usd,
        sum(case when is_active then seats   else 0 end)    as seats_paid,
        max(plan_name)                                       as plan_name,
        bool_or(is_active)                                   as has_active_subscription,
        max(canceled_at)                                     as canceled_at
    from {{ ref('fct_subscriptions') }}
    where account_id is not null
    group by account_id

),

usage as (

    select * from {{ ref('fct_usage_monthly') }}

),

latest_month as (

    select max(usage_month) as usage_month from usage

),

-- Active users in the latest month, and three months before it
usage_trend as (

    select
        usage.account_id,
        max(case when usage.usage_month = latest_month.usage_month
                 then usage.active_users end)                           as active_users_latest,
        max(case when usage.usage_month = date_add('month', -3, latest_month.usage_month)
                 then usage.active_users end)                           as active_users_3_months_ago
    from usage
    cross join latest_month
    group by usage.account_id

),

combined as (

    select
        accounts.account_id,
        accounts.account_name,
        accounts.segment,
        accounts.region,
        accounts.industry,
        accounts.account_owner,
        accounts.is_customer,

        billing.plan_name,
        coalesce(billing.has_active_subscription, false)                as has_active_subscription,
        coalesce(billing.mrr_usd, 0)                                    as mrr_usd,
        coalesce(billing.seats_paid, 0)                                 as seats_paid,
        billing.canceled_at,

        usage_trend.active_users_latest,
        usage_trend.active_users_3_months_ago,

        -- share of paid seats actually used last month (0.25 = 25%)
        case
            when billing.seats_paid > 0
            then round(cast(usage_trend.active_users_latest as double) / billing.seats_paid, 2)
        end                                                             as seat_utilization,

        -- change in active users over the last three months (-0.40 = down 40%)
        case
            when usage_trend.active_users_3_months_ago > 0
            then round(cast(usage_trend.active_users_latest as double)
                       / usage_trend.active_users_3_months_ago - 1, 2)
        end                                                             as usage_change_3_months

    from accounts
    left join billing     on accounts.account_id = billing.account_id
    left join usage_trend on accounts.account_id = usage_trend.account_id

)

select
    *,
    -- Simple, explainable rules. Documented in the README so the AI (and people) know what "risk" means.
    case
        when not is_customer                                    then 'Prospect'
        when not has_active_subscription                        then 'Churned'
        when seat_utilization < 0.35                            then 'High'
        when usage_change_3_months <= -0.30                     then 'High'
        when seat_utilization < 0.60                            then 'Medium'
        else 'Low'
    end                                                         as churn_risk
from combined

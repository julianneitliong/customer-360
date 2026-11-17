"""
generate_data.py
----------------
Creates synthetic, intentionally messy source data for the Loopwise Customer 360 project.

Loopwise is a fictional B2B SaaS project-management tool. Its customer data lives in
three systems that don't agree with each other:

  1. CRM export (Salesforce-style CSVs)   -> data/landing/crm/
  2. Billing tool (Stripe-style paginated API, saved as JSON pages)
                                           -> mock_api/billing/
  3. Product usage exports (monthly CSV + Excel files in a folder)
                                           -> data/landing/usage/

The mess is built in ON PURPOSE so the pipeline has real problems to solve.
See data/DATA_ISSUES.md (written by this script) for the full list.

Run:  python scripts/generate_data.py
Everything is seeded, so the output is identical every run.
"""

import csv
import json
import random
import string
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import pandas as pd  # only used to write the Excel usage files

random.seed(42)

ROOT = Path(__file__).resolve().parents[1]
CRM_DIR = ROOT / "data" / "landing" / "crm"
USAGE_DIR = ROOT / "data" / "landing" / "usage"
API_DIR = ROOT / "mock_api" / "billing"
for d in (CRM_DIR, USAGE_DIR, API_DIR):
    d.mkdir(parents=True, exist_ok=True)

NUM_ACCOUNTS = 60
USAGE_MONTHS = [date(2026, m, 1) for m in range(1, 11)]  # Jan - Oct 2026
PLAN_RENAME_DATE = date(2026, 7, 1)  # "Team" plan renamed to "Pro" on this date


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def salesforce_id_15(prefix: str) -> str:
    """A 15-character, case-sensitive Salesforce-style ID, e.g. 001Hs00002AbCdE."""
    chars = string.ascii_letters + string.digits
    return prefix + "".join(random.choice(chars) for _ in range(15 - len(prefix)))


def salesforce_id_18(id15: str) -> str:
    """Convert a 15-char ID to the 18-char case-insensitive version (real Salesforce algorithm)."""
    lookup = "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345"
    suffix = ""
    for chunk_start in (0, 5, 10):
        chunk = id15[chunk_start:chunk_start + 5]
        bits = sum(1 << i for i, ch in enumerate(chunk) if ch.isupper())
        suffix += lookup[bits]
    return id15 + suffix


def maybe_15(id15: str, pct_15: float = 0.35) -> str:
    """Mess: some exports use the 15-char ID, others the 18-char ID."""
    return id15 if random.random() < pct_15 else salesforce_id_18(id15)


def unix_ts(d: date) -> int:
    """Billing API returns Unix timestamps in UTC (seconds)."""
    return int(datetime(d.year, d.month, d.day, random.randint(0, 23), random.randint(0, 59),
                        tzinfo=timezone.utc).timestamp())


def write_csv(path: Path, rows: list[dict]) -> None:
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


# ---------------------------------------------------------------------------
# 1. Company master list (the "truth" -- never exported as-is)
# ---------------------------------------------------------------------------

PREFIXES = ["Acme", "Bluefin", "Cedar", "Driftwood", "Ember", "Fable", "Granite", "Harbor",
            "Ironleaf", "Juniper", "Keystone", "Lumen", "Maple", "Northstar", "Orchid", "Pinecrest",
            "Quill", "Redwood", "Summit", "Tidewater", "Umbra", "Vantage", "Willow", "Xenon",
            "Yellowtail", "Zephyr", "Aurora", "Beacon", "Copper", "Delta"]
SUFFIXES = ["Labs", "Logistics", "Health", "Studios", "Analytics", "Foods", "Robotics",
            "Financial", "Media", "Energy"]
INDUSTRIES = ["Software", "Logistics", "Healthcare", "Media", "Financial Services",
              "Manufacturing", "Retail", "Energy"]
REGIONS = ["NA", "EMEA", "APAC"]
OWNERS = ["Priya Shah", "Marcus Lee", "Dana Ortiz", "Sam Whitfield"]

# Segment drives seat counts and plan choice
SEGMENTS = {
    "SMB":        {"seats": (5, 25),    "plans": ["Starter", "Team"]},
    "Mid-Market": {"seats": (25, 150),  "plans": ["Team", "Business"]},
    "Enterprise": {"seats": (150, 800), "plans": ["Business"]},
}
# Mess: the CRM has no picklist validation, so segment values are inconsistent
SEGMENT_VARIANTS = {
    "SMB": ["SMB", "smb", "Small Business", "SMB "],
    "Mid-Market": ["Mid-Market", "Mid Market", "mid-market", "MM"],
    "Enterprise": ["Enterprise", "ENT", "enterprise", "Enterprise "],
}

names_used = set()
companies = []
for i in range(NUM_ACCOUNTS):
    while True:
        name = f"{random.choice(PREFIXES)} {random.choice(SUFFIXES)}"
        if name not in names_used:
            names_used.add(name)
            break
    segment = random.choices(list(SEGMENTS), weights=[50, 35, 15])[0]
    currency = random.choices(["usd", "eur", "gbp"], weights=[70, 20, 10])[0]
    region = "EMEA" if currency in ("eur", "gbp") else random.choice(["NA", "NA", "APAC"])
    created = date(2024, 1, 1) + timedelta(days=random.randint(0, 600))

    # Customer "story" -- what kind of account is this?
    #   healthy   : steady/growing usage, stays subscribed
    #   underused : pays for far more seats than it uses
    #   churning  : usage declines, then subscription is canceled mid-2026
    #   prospect  : in CRM only (never bought)
    story = random.choices(["healthy", "underused", "churning", "prospect"],
                           weights=[55, 15, 15, 15])[0]
    companies.append({
        "id15": salesforce_id_15("001Hs0000"),
        "name": name,
        "domain": name.lower().replace(" ", "") + ".com",
        "segment": segment,
        "industry": random.choice(INDUSTRIES),
        "region": region,
        "currency": currency,
        "created": created,
        "owner": random.choice(OWNERS),
        "story": story,
        "seats": random.randint(*SEGMENTS[segment]["seats"]),
        "plan": random.choice(SEGMENTS[segment]["plans"]),
        "billing_period": random.choices(["month", "year"], weights=[60, 40])[0],
    })

customers = [c for c in companies if c["story"] != "prospect"]


# ---------------------------------------------------------------------------
# 2. CRM export (Salesforce-style CSVs)
# ---------------------------------------------------------------------------

crm_accounts = []
for c in companies:
    crm_accounts.append({
        "Id": maybe_15(c["id15"], pct_15=0.0),  # Account export itself uses 18-char IDs
        "Name": c["name"],
        "Website": random.choice([c["domain"], "www." + c["domain"], "https://" + c["domain"],
                                  "https://www." + c["domain"] + "/"]),
        "Type": "Prospect" if c["story"] == "prospect" else "Customer",
        "Customer_Segment__c": random.choice(SEGMENT_VARIANTS[c["segment"]]),
        "Industry": c["industry"],
        "BillingCountry": {"NA": random.choice(["United States", "USA", "US", "Canada"]),
                           "EMEA": random.choice(["United Kingdom", "Germany", "France", "UK"]),
                           "APAC": random.choice(["Australia", "Singapore", "Japan"])}[c["region"]],
        "OwnerName": c["owner"],
        "CreatedDate": c["created"].strftime("%Y-%m-%dT%H:%M:%S.000+0000"),
    })

# Mess: duplicate accounts created by different reps (same company, new ID, slightly different name)
dupe_sources = random.sample(customers, 4)
dupe_ids = {}
for c in dupe_sources:
    dupe_id15 = salesforce_id_15("001Hs0000")
    dupe_ids[c["name"]] = dupe_id15
    crm_accounts.append({
        "Id": salesforce_id_18(dupe_id15),
        "Name": random.choice([c["name"] + " Inc.", c["name"].upper(), c["name"] + ", LLC"]),
        "Website": c["domain"].upper(),
        "Type": "Customer",
        "Customer_Segment__c": "",
        "Industry": "",
        "BillingCountry": "",
        "OwnerName": random.choice(OWNERS),
        "CreatedDate": (c["created"] + timedelta(days=random.randint(30, 300)))
        .strftime("%Y-%m-%dT%H:%M:%S.000+0000"),
    })
random.shuffle(crm_accounts)
write_csv(CRM_DIR / "accounts.csv", crm_accounts)

# Contacts -- AccountId uses a MIX of 15- and 18-char IDs (exported from a different report)
FIRST = ["Alex", "Jordan", "Taylor", "Morgan", "Casey", "Riley", "Jamie", "Avery", "Quinn",
         "Drew", "Reese", "Skyler", "Rowan", "Emerson", "Hayden"]
LAST = ["Nguyen", "Garcia", "Patel", "Kim", "Johnson", "Okafor", "Silva", "Chen", "Brown",
        "Martin", "Rossi", "Haddad", "Cohen", "Novak", "Reyes"]
TITLES = ["VP Operations", "Director of PMO", "IT Manager", "Head of Product", "COO",
          "Program Manager", "Finance Manager"]
crm_contacts = []
for c in companies:
    for _ in range(random.randint(1, 4)):
        fn, ln = random.choice(FIRST), random.choice(LAST)
        crm_contacts.append({
            "Id": salesforce_id_18(salesforce_id_15("003Hs0000")),
            "AccountId": maybe_15(c["id15"]),
            "FirstName": fn,
            "LastName": ln,
            "Email": f"{fn.lower()}.{ln.lower()}@{c['domain']}",
            "Title": random.choice(TITLES),
            "Is_Billing_Contact__c": random.choice(["true", "false", "TRUE", "1", ""]),
        })
write_csv(CRM_DIR / "contacts.csv", crm_contacts)

# Opportunities -- Amount is in the account's currency but the column doesn't say so
crm_opps = []
for c in companies:
    stages = (["Closed Lost", "Prospecting", "Negotiation"] if c["story"] == "prospect"
              else ["Closed Won"] + random.sample(["Closed Won", "Closed Lost", "Negotiation"], 1))
    for stage in stages:
        close = c["created"] + timedelta(days=random.randint(10, 400))
        crm_opps.append({
            "Id": salesforce_id_18(salesforce_id_15("006Hs0000")),
            "AccountId": maybe_15(c["id15"]),
            "Name": f"{c['name']} - {random.choice(['New Business', 'Expansion', 'Renewal'])}",
            "StageName": stage,
            "Amount": f"{random.randint(2, 200) * 500:,}" if random.random() < 0.3
                      else str(random.randint(2, 200) * 500),  # mess: some amounts have commas
            "CloseDate": random.choice([close.strftime("%Y-%m-%d"), close.strftime("%m/%d/%Y")]),
            "CurrencyIsoCode": c["currency"].upper(),
        })
write_csv(CRM_DIR / "opportunities.csv", crm_opps)


# ---------------------------------------------------------------------------
# 3. Billing tool (Stripe-style API responses, paginated)
# ---------------------------------------------------------------------------

# Monthly list price per seat, in the customer's currency (cents)
PRICE_PER_SEAT_CENTS = {"Starter": 800, "Team": 1500, "Pro": 1500, "Business": 2500}

billing_customers, billing_subs, billing_invoices = [], [], []
for n, c in enumerate(customers, start=1):
    cus_id = f"cus_{''.join(random.choices(string.ascii_letters + string.digits, k=14))}"
    c["cus_id"] = cus_id

    # Mess: billing name doesn't match CRM name exactly
    billing_name = random.choice([c["name"], c["name"] + ", Inc.", c["name"].upper(),
                                  c["name"] + " Ltd" if c["region"] == "EMEA" else c["name"]])
    # Mess: only ~70% of billing customers have the CRM ID in metadata, and it's 15 OR 18 chars
    metadata = {}
    if random.random() < 0.7:
        metadata["crm_account_id"] = maybe_15(c["id15"], pct_15=0.5)
    # Mess: a few billing emails are personal addresses, so the domain can't be used to match
    email_domain = c["domain"] if random.random() < 0.9 else random.choice(["gmail.com", "outlook.com"])
    billing_customers.append({
        "id": cus_id,
        "object": "customer",
        "name": billing_name,
        "email": f"billing@{email_domain}" if "gmail" not in email_domain and "outlook" not in email_domain
                 else f"{random.choice(FIRST).lower()}{random.randint(10, 99)}@{email_domain}",
        "currency": c["currency"],
        "created": unix_ts(c["created"] + timedelta(days=random.randint(5, 40))),
        "metadata": metadata,
    })

    # Subscription
    sub_start = max(c["created"] + timedelta(days=30), date(2025, 1, 1)) \
        if random.random() < 0.8 else date(2026, random.randint(1, 3), random.randint(1, 28))
    canceled_at = None
    if c["story"] == "churning":
        canceled_at = date(2026, random.randint(6, 9), random.randint(1, 28))
    plan_name = c["plan"]
    sub_items_price_cents = PRICE_PER_SEAT_CENTS[plan_name] * (10 if c["billing_period"] == "year" else 1)
    sub_id = f"sub_{''.join(random.choices(string.ascii_letters + string.digits, k=14))}"
    billing_subs.append({
        "id": sub_id,
        "object": "subscription",
        "customer": cus_id,
        "status": "canceled" if canceled_at else "active",
        "start_date": unix_ts(sub_start),
        "canceled_at": unix_ts(canceled_at) if canceled_at else None,
        "currency": c["currency"],
        "items": {"data": [{
            "price": {
                # Mess: plan nickname changes mid-year (Team -> Pro) for the SAME plan
                # (the subscription shows today's name; older invoices still say "Team")
                "nickname": f"{'Pro' if plan_name == 'Team' else plan_name} "
                            f"{'Annual' if c['billing_period'] == 'year' else 'Monthly'}",
                "unit_amount": sub_items_price_cents,  # cents, per seat, per billing period
                "recurring": {"interval": c["billing_period"]},
            },
            "quantity": c["seats"],
        }]},
    })

    # Invoices: one per billing period from start to cancel/now
    cursor = sub_start
    end = canceled_at or date(2026, 11, 1)
    while cursor < end:
        nickname_plan = "Pro" if (plan_name == "Team" and cursor >= PLAN_RENAME_DATE) else plan_name
        amount = sub_items_price_cents * c["seats"]
        billing_invoices.append({
            "id": f"in_{''.join(random.choices(string.ascii_letters + string.digits, k=14))}",
            "object": "invoice",
            "customer": cus_id,
            "subscription": sub_id,
            "currency": c["currency"],
            "amount_due": amount,
            "amount_paid": amount if random.random() < 0.95 else 0,
            "status": random.choices(["paid", "open", "void"], weights=[93, 5, 2])[0],
            "created": unix_ts(cursor),
            "period_start": unix_ts(cursor),
            "lines": {"data": [{"description": f"{c['seats']} x {nickname_plan} "
                                               f"({'Annual' if c['billing_period'] == 'year' else 'Monthly'})",
                                "quantity": c["seats"]}]},
        })
        cursor = (cursor.replace(year=cursor.year + 1) if c["billing_period"] == "year"
                  else (cursor.replace(day=1) + timedelta(days=32)).replace(day=min(cursor.day, 28)))

# Mess: the billing tool has 2 customers that never made it into the CRM (self-serve signups)
for i in range(2):
    cus_id = f"cus_{''.join(random.choices(string.ascii_letters + string.digits, k=14))}"
    billing_customers.append({
        "id": cus_id, "object": "customer",
        "name": random.choice(["Pixel Pantry", "Orbit Outfitters"]) if i == 0 else "Moss & Co",
        "email": f"owner@selfserve{i}.io", "currency": "usd",
        "created": unix_ts(date(2026, 4, 2 + i)), "metadata": {},
    })


def write_api_pages(resource: str, records: list[dict], page_size: int = 25) -> None:
    """Save records as paginated API responses: page_001.json, page_002.json, ...
    Each page links to the next one, like a real cursor-paginated API."""
    out = API_DIR / resource
    out.mkdir(parents=True, exist_ok=True)
    pages = [records[i:i + page_size] for i in range(0, len(records), page_size)]
    for i, page in enumerate(pages, start=1):
        has_more = i < len(pages)
        body = {
            "object": "list",
            "url": f"/v1/{resource}",
            "has_more": has_more,
            "next_page": f"page_{i + 1:03d}.json" if has_more else None,
            "data": page,
        }
        (out / f"page_{i:03d}.json").write_text(json.dumps(body, indent=2))


write_api_pages("customers", billing_customers)
write_api_pages("subscriptions", billing_subs)
write_api_pages("invoices", billing_invoices)


# ---------------------------------------------------------------------------
# 4. Product usage exports (one file per month, format drifts over time)
# ---------------------------------------------------------------------------

def usage_row(c: dict, month: date) -> dict | None:
    """Active users for one account in one month, shaped by the account's story."""
    start = date(2026, 1, 1)
    months_in = (month.year - start.year) * 12 + month.month - start.month
    if c["story"] == "healthy":
        util = min(0.95, random.uniform(0.6, 0.8) + 0.01 * months_in)
    elif c["story"] == "underused":
        util = random.uniform(0.10, 0.30)
    else:  # churning: declines, then stops after cancellation
        util = max(0.05, 0.7 - 0.12 * months_in)
    active = max(1, int(c["seats"] * util))
    return {"domain": c["domain"], "active_users": active,
            "projects_created": int(active * random.uniform(0.3, 1.5)),
            "api_calls": int(active * random.uniform(50, 400))}


for month in USAGE_MONTHS:
    rows = []
    for c in customers:
        cancel = next((s["canceled_at"] for s in billing_subs if s["customer"] == c["cus_id"]), None)
        if cancel and datetime.fromtimestamp(cancel, tz=timezone.utc).date() < month:
            continue  # no usage after churn
        r = usage_row(c, month)
        # Mess: domains come in different shapes
        r["domain"] = random.choice([r["domain"], r["domain"].upper(), "www." + r["domain"],
                                     " " + r["domain"]])
        rows.append(r)
    # Mess: two trial workspaces not tied to any CRM account
    rows.append({"domain": "trial-workspace-88.loopwise.app", "active_users": 3,
                 "projects_created": 1, "api_calls": 40})
    rows.append({"domain": "freelancer-jess.com", "active_users": 1,
                 "projects_created": 2, "api_calls": 12})

    if month < date(2026, 5, 1):
        # Jan-Apr: old export format
        out_rows = [{"Domain": r["domain"], "Month": month.strftime("%m/%Y"),
                     "Active Users": r["active_users"], "Projects Created": r["projects_created"]}
                    for r in rows]
    else:
        # May onward: new export format -- renamed columns, ISO dates, new api_calls column
        out_rows = [{"customer_domain": r["domain"], "report_date": month.strftime("%Y-%m-%d"),
                     "active_user_count": r["active_users"],
                     "projects_created": r["projects_created"], "api_calls": r["api_calls"]}
                    for r in rows]

    name = f"usage_{month:%Y_%m}"
    if month.month in (3, 8):
        # Mess: someone exported these two months from Excel instead of CSV
        pd.DataFrame(out_rows).to_excel(USAGE_DIR / f"{name}.xlsx", index=False)
    else:
        write_csv(USAGE_DIR / f"{name}.csv", out_rows)
    if month.month == 7:
        # Mess: July was sent twice
        write_csv(USAGE_DIR / f"{name} (1).csv", out_rows)


# ---------------------------------------------------------------------------
# 5. Answer key + issues list (for you, not for the pipeline)
# ---------------------------------------------------------------------------

answer_key = [{"account_id_15": c["id15"], "account_id_18": salesforce_id_18(c["id15"]),
               "name": c["name"], "domain": c["domain"], "segment": c["segment"],
               "story": c["story"], "billing_customer_id": c.get("cus_id", ""),
               "seats": c["seats"] if c["story"] != "prospect" else "",
               "duplicate_crm_id_18": salesforce_id_18(dupe_ids[c["name"]]) if c["name"] in dupe_ids else ""}
              for c in companies]
(ROOT / "data" / "answer_key").mkdir(parents=True, exist_ok=True)
write_csv(ROOT / "data" / "answer_key" / "account_truth.csv", answer_key)

print(f"CRM: {len(crm_accounts)} accounts, {len(crm_contacts)} contacts, {len(crm_opps)} opportunities")
print(f"Billing: {len(billing_customers)} customers, {len(billing_subs)} subscriptions, "
      f"{len(billing_invoices)} invoices")
print(f"Usage: {len(list(USAGE_DIR.iterdir()))} files")
print("Stories:", {s: sum(c['story'] == s for c in companies)
                   for s in ['healthy', 'underused', 'churning', 'prospect']})

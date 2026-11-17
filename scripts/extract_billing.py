"""
extract_billing.py
------------------
Pulls customers, subscriptions and invoices from the billing API, following
pagination until there are no more pages, and saves each resource as
newline-delimited JSON (one record per line) -- the format Athena reads best.

The "API" is a local mock (mock_api/billing/). Start it in another terminal with:

    python -m http.server 8000 --directory mock_api

Then run:

    python scripts/extract_billing.py

To point at a real API later, change BASE_URL and add an auth header.
"""

import json
import urllib.request
from pathlib import Path

BASE_URL = "http://localhost:8000/billing"
RESOURCES = ["customers", "subscriptions", "invoices"]

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "data" / "landing" / "billing"


def fetch_json(url: str) -> dict:
    with urllib.request.urlopen(url, timeout=10) as response:
        return json.load(response)


def extract(resource: str) -> list[dict]:
    """Request page 1, then keep following next_page until has_more is false."""
    records = []
    page = "page_001.json"
    while page:
        body = fetch_json(f"{BASE_URL}/{resource}/{page}")
        records.extend(body["data"])
        page = body["next_page"] if body["has_more"] else None
    return records


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for resource in RESOURCES:
        records = extract(resource)
        out_file = OUT_DIR / f"{resource}.jsonl"
        with out_file.open("w", encoding="utf-8") as f:
            for record in records:
                f.write(json.dumps(record) + "\n")
        print(f"{resource}: {len(records)} records -> {out_file.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

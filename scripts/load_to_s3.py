"""
load_to_s3.py
-------------
Uploads everything in data/landing/ to the S3 raw zone, one folder per table
(Athena treats each folder as one table).

    data/landing/crm/accounts.csv        -> s3://<bucket>/raw/crm/accounts/accounts.csv
    data/landing/billing/invoices.jsonl  -> s3://<bucket>/raw/billing/invoices/invoices.jsonl
    data/landing/usage/usage_2026_03.xlsx-> s3://<bucket>/raw/usage/usage_2026_03.csv

Athena can't read Excel, so .xlsx usage files are converted to .csv on the way up.
Nothing else is changed: cleaning happens later, in dbt.

Setup (once):
    pip install -r requirements.txt
    aws configure            # your access key, secret, and region

Run:
    python scripts/load_to_s3.py --bucket your-bucket-name
"""

import argparse
import io
from pathlib import Path

import boto3
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
LANDING = ROOT / "data" / "landing"


def s3_key_for(path: Path) -> str:
    """Decide where a landing file goes in S3."""
    source = path.parent.name  # crm, billing or usage
    if source == "usage":
        # all monthly usage files share one table folder
        return f"raw/usage/{path.stem}.csv"
    # one folder per table for crm and billing
    return f"raw/{source}/{path.stem}/{path.stem}{path.suffix}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", required=True, help="S3 bucket name")
    args = parser.parse_args()

    s3 = boto3.client("s3")
    files = sorted(p for p in LANDING.rglob("*") if p.is_file())
    if not files:
        raise SystemExit("No files in data/landing/. Run generate_data.py and extract_billing.py first.")

    for path in files:
        key = s3_key_for(path)
        if path.suffix == ".xlsx":
            buffer = io.StringIO()
            pd.read_excel(path).to_csv(buffer, index=False)
            s3.put_object(Bucket=args.bucket, Key=key, Body=buffer.getvalue().encode("utf-8"))
        else:
            s3.upload_file(str(path), args.bucket, key)
        print(f"uploaded {path.relative_to(ROOT)} -> s3://{args.bucket}/{key}")


if __name__ == "__main__":
    main()

"""
ai_analyst.py
-------------
The "AI analytics product" demo. For each business question it:

  1. Gives an AI model (Claude on Amazon Bedrock) the data dictionary from dbt
     -- the table and column descriptions you wrote in _marts.yml.
  2. Asks the model to write ONE Athena SQL query that answers the question.
  3. Checks the SQL is read-only (a guardrail: the AI may only SELECT).
  4. Runs it on Athena against the loopwise_marts tables.
  5. Asks the model to explain the result in one or two plain-English sentences,
     using only the numbers that came back.
  6. Saves everything to docs/data/results.json, which the GitHub Pages site displays.

Setup (once):
    - Bedrock access for a Claude model in your region (see README)
    - From the loopwise_dbt folder: dbt docs generate   (creates target/manifest.json)

Run (from the customer-360 folder, with .venv active):
    python scripts/ai_analyst.py --bucket loopwise-customer360-julianne --model-id <inference profile ID>
"""

import argparse
import json
import re
import time
from datetime import datetime, timezone
from pathlib import Path

import boto3

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "loopwise_dbt" / "target" / "manifest.json"
OUTPUT = ROOT / "docs" / "data" / "results.json"
DATABASE = "loopwise_marts"

QUESTIONS = [
    "What is our total current MRR, and how is it split by customer segment?",
    "What is current MRR by region?",
    "Which 10 customers have the most unused paid seats?",
    "How many customers are at each churn risk level, and how much current MRR does each level represent?",
    "How much MRR did we lose to cancellations in 2026, by month of cancellation?",
    "How have total monthly active users trended across 2026?",
]

SYSTEM_PROMPT = """You are a careful data analyst. You write SQL for Amazon Athena (Trino SQL dialect).

Rules:
- Use ONLY the tables and columns in the data dictionary below. Never invent a column.
- Always write fully qualified table names, for example loopwise_marts.mart_account_health.
- Write exactly one read-only query (SELECT or WITH). Never modify data.
- Read the column descriptions carefully: they define business rules (for example, which rows count toward current MRR).
- Round money to 2 decimals and give columns readable names.

Respond with JSON only, no other text, in this shape:
{"sql": "...", "chart": {"type": "bar" | "line" | "table", "x": "<column for labels>", "y": "<numeric column>"}, "approach": "<one sentence on how the query answers the question>"}

DATA DICTIONARY
"""

ANSWER_PROMPT = """Question: {question}

Query result (columns and rows):
{result}

In one or two plain-English sentences, answer the question using ONLY these numbers.
Do not add numbers that are not in the result. Respond with the sentences only."""


# ---------------------------------------------------------------------------
# 1. Build the data dictionary from dbt
# ---------------------------------------------------------------------------

def load_data_dictionary() -> str:
    """Turn the descriptions in dbt's manifest.json into plain text for the AI."""
    if not MANIFEST.exists():
        raise SystemExit("target/manifest.json not found. Run `dbt docs generate` in loopwise_dbt first.")
    manifest = json.loads(MANIFEST.read_text())
    lines = []
    for node in manifest["nodes"].values():
        if node["resource_type"] != "model" or not node["original_file_path"].startswith("models/marts/"):
            continue
        lines.append(f"\nTABLE {DATABASE}.{node['name']}")
        lines.append(f"  {' '.join(node.get('description', '').split())}")
        for column in node.get("columns", {}).values():
            lines.append(f"  - {column['name']}: {' '.join(column.get('description', '').split())}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# 2. Talk to the AI model on Bedrock
# ---------------------------------------------------------------------------

def ask_model(bedrock, model_id: str, system: str, prompt: str) -> str:
    response = bedrock.converse(
        modelId=model_id,
        system=[{"text": system}],
        messages=[{"role": "user", "content": [{"text": prompt}]}],
        inferenceConfig={"maxTokens": 1500, "temperature": 0},
    )
    return response["output"]["message"]["content"][0]["text"].strip()


def parse_json(text: str) -> dict:
    """Models sometimes wrap JSON in ```json fences; take the part between the outer braces."""
    start, end = text.find("{"), text.rfind("}")
    if start == -1 or end == -1:
        raise ValueError(f"No JSON in model response: {text[:200]}")
    return json.loads(text[start:end + 1])


# ---------------------------------------------------------------------------
# 3. Guardrail: the AI may only read data
# ---------------------------------------------------------------------------

BLOCKED = re.compile(r"\b(insert|update|delete|drop|create|alter|merge|grant|unload|msck)\b", re.IGNORECASE)


def check_read_only(sql: str) -> None:
    cleaned = sql.strip().rstrip(";")
    if not re.match(r"^\s*(select|with)\b", cleaned, re.IGNORECASE):
        raise ValueError("Blocked: query must start with SELECT or WITH.")
    if ";" in cleaned:
        raise ValueError("Blocked: only one statement is allowed.")
    if BLOCKED.search(cleaned):
        raise ValueError("Blocked: query contains a data-changing keyword.")


# ---------------------------------------------------------------------------
# 4. Run SQL on Athena
# ---------------------------------------------------------------------------

def run_athena(athena, sql: str, bucket: str) -> tuple[list[str], list[list[str]]]:
    execution = athena.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={"Catalog": "AwsDataCatalog", "Database": DATABASE},
        ResultConfiguration={"OutputLocation": f"s3://{bucket}/athena-results/"},
        WorkGroup="primary",
    )
    query_id = execution["QueryExecutionId"]
    while True:
        status = athena.get_query_execution(QueryExecutionId=query_id)["QueryExecution"]["Status"]
        if status["State"] in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break
        time.sleep(1)
    if status["State"] != "SUCCEEDED":
        raise RuntimeError(status.get("StateChangeReason", status["State"]))

    rows = []
    for page in athena.get_paginator("get_query_results").paginate(QueryExecutionId=query_id):
        for row in page["ResultSet"]["Rows"]:
            rows.append([cell.get("VarCharValue") for cell in row["Data"]])
    return rows[0], rows[1:]  # first row is the header


# ---------------------------------------------------------------------------
# 5. Main loop
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bucket", required=True)
    parser.add_argument("--model-id", required=True, help="Bedrock model or inference profile ID")
    args = parser.parse_args()

    system = SYSTEM_PROMPT + load_data_dictionary()
    bedrock = boto3.client("bedrock-runtime")
    athena = boto3.client("athena")

    results = []
    for question in QUESTIONS:
        print(f"\nQ: {question}")
        record = {"question": question}
        prompt = question
        for attempt in (1, 2):  # if the first query fails, show the AI the error and let it fix it once
            try:
                plan = parse_json(ask_model(bedrock, args.model_id, system, prompt))
                check_read_only(plan["sql"])
                columns, rows = run_athena(athena, plan["sql"].strip().rstrip(";"), args.bucket)
                record.update(sql=plan["sql"].strip(), approach=plan.get("approach", ""),
                              chart=plan.get("chart", {"type": "table"}),
                              columns=columns, rows=rows, attempts=attempt, status="ok")
                record.pop("error", None)
                break
            except Exception as error:  # noqa: BLE001 -- record any failure on the page
                print(f"   attempt {attempt} failed: {error}")
                record.update(status="error", error=str(error), sql=locals().get("plan", {}).get("sql", ""))
                prompt = (f"{question}\n\nYour previous query failed with this error:\n{error}\n"
                          f"Previous query:\n{record['sql']}\nWrite a corrected query.")

        if record["status"] == "ok":
            table_text = json.dumps({"columns": record["columns"], "rows": record["rows"][:50]})
            record["answer"] = ask_model(bedrock, args.model_id,
                                         "You explain data results clearly and accurately.",
                                         ANSWER_PROMPT.format(question=question, result=table_text))
            print(f"A: {record['answer']}")
        results.append(record)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps({
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC"),
        "model_id": args.model_id,
        "results": results,
    }, indent=2))
    print(f"\nSaved {len(results)} answers to {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

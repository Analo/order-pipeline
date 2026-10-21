#!/usr/bin/env python3
"""
Seed the pipeline with a controlled mix of orders to generate evidence artifacts.

Sends three batches:
  1. Valid orders  → expect 202, land in DynamoDB
  2. Malformed orders → expect 400, rejected at API Gateway (never touch SQS)
  3. Duplicate orders → same orderId as batch 1; expect 202 from API, but
                        DynamoDB conditional write is skipped (idempotency hit)

Usage:
    pip install requests
    python scripts/seed_orders.py --endpoint https://<api-id>.execute-api.eu-west-1.amazonaws.com/dev

Save output to docs/evidence/seed_orders.log for the portfolio README.
"""

import argparse
import json
import time
import uuid
from typing import Any

import requests


def build_valid_order(customer_id: str, amount: float, items: list) -> dict:
    return {
        "orderId": str(uuid.uuid4()),
        "customerId": customer_id,
        "items": items,
        "totalAmount": amount,
    }


VALID_ORDERS = [
    build_valid_order("cust-001", 149.97, [{"sku": "WIDGET-A", "qty": 3, "price": 49.99}]),
    build_valid_order("cust-002", 29.99,  [{"sku": "GADGET-B", "qty": 1, "price": 29.99}]),
    build_valid_order("cust-003", 89.98,  [{"sku": "WIDGET-A", "qty": 1, "price": 49.99}, {"sku": "GADGET-B", "qty": 1, "price": 39.99}]),
    build_valid_order("cust-001", 59.98,  [{"sku": "ACCESSORY-C", "qty": 2, "price": 29.99}]),
    build_valid_order("cust-004", 199.95, [{"sku": "PREMIUM-D", "qty": 5, "price": 39.99}]),
]

MALFORMED_ORDERS: list[dict[str, Any]] = [
    # Missing orderId
    {"customerId": "cust-bad", "items": [{"sku": "X"}], "totalAmount": 10.00},
    # Empty items list
    {"orderId": str(uuid.uuid4()), "customerId": "cust-bad", "items": [], "totalAmount": 5.00},
    # Negative amount
    {"orderId": str(uuid.uuid4()), "customerId": "cust-bad", "items": [{"sku": "X"}], "totalAmount": -1.00},
    # Missing totalAmount and items
    {"orderId": str(uuid.uuid4()), "customerId": "cust-bad"},
]


def post_order(url: str, payload: dict, label: str, delay: float) -> None:
    try:
        resp = requests.post(url, json=payload, timeout=15)
        order_id = payload.get("orderId", "N/A")[:16]
        print(f"  [{resp.status_code}] {label:<30} orderId={order_id}…  {resp.text[:60]}")
    except requests.RequestException as exc:
        print(f"  [ERR] {label:<30} {exc}")
    time.sleep(delay)


def main() -> None:
    parser = argparse.ArgumentParser(description="Seed the order pipeline with test data.")
    parser.add_argument("--endpoint", required=True, help="API Gateway base URL")
    parser.add_argument("--delay", type=float, default=0.3, help="Seconds between requests (default: 0.3)")
    args = parser.parse_args()

    url = args.endpoint.rstrip("/") + "/orders"
    print(f"Target: {url}\n")

    print("=== Batch 1: Valid orders (expect 202) ===")
    for order in VALID_ORDERS:
        post_order(url, order, "valid", args.delay)

    print("\n=== Batch 2: Malformed orders (expect 400) ===")
    for order in MALFORMED_ORDERS:
        post_order(url, order, "malformed", args.delay)

    print("\n=== Batch 3: Duplicate orders — idempotency test (expect 202, DynamoDB skips) ===")
    for order in VALID_ORDERS[:3]:
        post_order(url, order, "duplicate", args.delay)

    print(
        "\nDone.\n"
        "  - DynamoDB should have 5 unique orders (duplicates skipped)\n"
        "  - DLQ should be empty (malformed orders rejected before SQS)\n"
        "  - CloudWatch Logs should show IDEMPOTENCY_HIT for 3 entries"
    )


if __name__ == "__main__":
    main()
